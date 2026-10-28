import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:garden_journal/core/database/database_helper.dart';
import 'package:garden_journal/features/sensors/data/repositories/sensor_data_repository.dart';
import 'package:garden_journal/features/sensors/data/repositories/sensor_repository.dart';
import 'package:garden_journal/features/sensors/domain/entities/sensor_device.dart';
import 'package:garden_journal/features/sensors/domain/entities/sensor_reading.dart';
import 'package:garden_journal/features/sensors/presentation/providers/sensor_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  Future<(Database, SensorDataRepository, SensorDevice)> setup() async {
    final db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    await db.execute('PRAGMA foreign_keys = ON');
    await DatabaseHelper.instance.createSchemaForTesting(db);
    final data = SensorDataRepository(database: db);
    final now = DateTime.utc(2026, 7, 14, 10);
    final device = SensorDevice(
      id: 'greenhouse-main-01',
      uid: 'greenhouse-main-01',
      name: 'Serre de tomates',
      zoneId: 'zone-main',
      baseUrl: 'http://192.168.1.42',
      createdAt: now,
      updatedAt: now,
    );
    await data.upsertDevice(device);
    await data.insertReadings(device, [
      SensorReading(
        deviceId: device.id,
        temperature: 24,
        humidity: 60,
        vpd: 1.0,
        timestamp: now,
        mistOn: false,
      ),
    ]);
    return (db, data, device);
  }

  test('synchronisation incrémentale reprend au dernier timestamp', () async {
    final (db, data, _) = await setup();
    addTearDown(db.close);
    String? requestedSince;
    final nextTimestamp =
        DateTime.utc(2026, 7, 14, 10, 1).millisecondsSinceEpoch ~/ 1000;
    final remote = SensorRepository(
      client: MockClient((request) async {
        if (request.url.path == '/readings') {
          requestedSince = request.url.queryParameters['since'];
          return http.Response(
            jsonEncode([
              _json(nextTimestamp, temperature: 25, withGenericData: true),
            ]),
            200,
          );
        }
        return http.Response(
          jsonEncode(
            _json(nextTimestamp, temperature: 25, withGenericData: true),
          ),
          200,
        );
      }),
    );
    final provider = SensorProvider(
      remoteRepository: remote,
      dataRepository: data,
    );
    addTearDown(provider.dispose);

    await provider.initialize();
    await provider.fetchNow();

    final cachedTimestamp =
        DateTime.utc(2026, 7, 14, 10).millisecondsSinceEpoch ~/ 1000;
    expect(requestedSince, '$cachedTimestamp');
    expect(await db.query('sensor_readings'), hasLength(2));
    expect(await db.query('sensor_device_capabilities'), hasLength(2));
    expect(await db.query('sensor_measurements'), hasLength(2));
    expect(await db.query('device_health_snapshots'), hasLength(1));
    expect(provider.capabilities.map((item) => item.key),
        containsAll(['water_ph', 'mist_state']));
    expect(
      provider.measurements
          .firstWhere((item) => item.capabilityKey == 'water_ph')
          .numericValue,
      6.2,
    );
    expect(provider.latestForZone('zone-main')?.temperature, 25);
  });

  test('conserve le cache et passe hors ligne si le nœud est inaccessible',
      () async {
    final (db, data, _) = await setup();
    addTearDown(db.close);
    final provider = SensorProvider(
      remoteRepository: SensorRepository(
        client: MockClient((request) async {
          throw http.ClientException('offline', request.url);
        }),
      ),
      dataRepository: data,
    );
    addTearDown(provider.dispose);

    await provider.initialize();
    final cached = provider.latest;
    await provider.fetchNow();

    expect(cached, isNotNull);
    expect(provider.latest, cached);
    expect(provider.error, contains('conservées'));
    expect(await db.query('sensor_readings'), hasLength(1));
    expect((await data.getDevices()).single.status, 'offline');
  });

  test('enregistre le live si /readings n’existe pas encore', () async {
    final (db, data, _) = await setup();
    addTearDown(db.close);
    final nextTimestamp =
        DateTime.utc(2026, 7, 14, 10, 1).millisecondsSinceEpoch ~/ 1000;
    final provider = SensorProvider(
      remoteRepository: SensorRepository(
        client: MockClient((request) async {
          if (request.url.path == '/readings') return http.Response('{}', 404);
          return http.Response(jsonEncode(_json(nextTimestamp)), 200);
        }),
      ),
      dataRepository: data,
    );
    addTearDown(provider.dispose);

    await provider.initialize();
    await provider.fetchNow();

    expect(await db.query('sensor_readings'), hasLength(2));
    expect(provider.error, isNull);
  });

  test('mesure cloud récente reste disponible quand le LAN ESP est hors ligne',
      () async {
    final db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    addTearDown(db.close);
    await db.execute('PRAGMA foreign_keys = ON');
    await DatabaseHelper.instance.createSchemaForTesting(db);
    final data = SensorDataRepository(database: db);
    final now = DateTime.now();
    final device = SensorDevice(
      id: 'local-greenhouse-01',
      uid: 'greenhouse-01',
      name: 'Serre cloud',
      zoneId: 'zone-main',
      baseUrl: 'http://192.168.0.37',
      cloudDeviceId: 'dev-greenhouse-01',
      status: 'offline',
      createdAt: now,
      updatedAt: now,
    );
    await data.upsertDevice(device);
    await data.insertReadings(
        device,
        [
          SensorReading(
            deviceId: device.id,
            timestamp: now,
            temperature: 24,
            humidity: 60,
            vpd: 1.0,
            mistOn: false,
          ),
        ],
        markLocalOnline: false);
    await data.recordCloudSyncSuccess(
      device.id,
      cloudDeviceId: 'dev-greenhouse-01',
      lastContactAt: now,
    );
    var localRequests = 0;
    final provider = SensorProvider(
      remoteRepository: SensorRepository(
        client: MockClient((request) async {
          localRequests++;
          throw http.ClientException('offline', request.url);
        }),
      ),
      dataRepository: data,
    );
    addTearDown(provider.dispose);

    await provider.initialize();
    expect(provider.hasCurrentReadingForZone('zone-main'), isTrue);
    await provider.syncAllDevices(skipDeviceIds: {device.id});
    expect(localRequests, 0);
    expect(provider.hasCurrentReadingForZone('zone-main'), isTrue);

    await data.recordCloudSyncFailure(device.id, 'HTTP 401');
    await provider.refreshFromLocalCache();
    expect(provider.hasCurrentReadingForZone('zone-main'), isFalse);
  });
}

Map<String, Object?> _json(
  int timestamp, {
  double temperature = 24.6,
  bool withGenericData = false,
}) =>
    {
      'deviceId': 'greenhouse-main-01',
      'timestamp': timestamp,
      'temperature': temperature,
      'humidity': 57.2,
      'vpd': 1.28,
      'mistOn': false,
      if (withGenericData) ...{
        'capabilities': {
          'water_ph': {'type': 'number', 'unit': 'pH'},
        },
        'measurements': {'water_ph': 6.2},
      },
    };
