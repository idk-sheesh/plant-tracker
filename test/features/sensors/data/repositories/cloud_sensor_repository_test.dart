import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:garden_journal/core/database/database_helper.dart';
import 'package:garden_journal/features/sensors/data/repositories/cloud_auth_repository.dart';
import 'package:garden_journal/features/sensors/data/repositories/cloud_sensor_repository.dart';
import 'package:garden_journal/features/sensors/data/repositories/sensor_data_repository.dart';
import 'package:garden_journal/features/sensors/data/services/cloud_sensor_sync_service.dart';
import 'package:garden_journal/features/sensors/domain/entities/sensor_device.dart';
import 'package:garden_journal/features/sensors/domain/entities/sensor_reading.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  test('crée un compte puis lit une session utilisateur cloud', () async {
    var calls = 0;
    final auth = CloudAuthRepository(
      baseUri: Uri.parse('https://api.example.test'),
      client: MockClient((request) async {
        calls++;
        expect(request.headers['content-type'], contains('application/json'));
        final payload = jsonDecode(request.body) as Map<String, dynamic>;
        expect(payload['password'], isNotEmpty);
        if (request.url.path.endsWith('/register')) {
          return http.Response(jsonEncode({'status': 'created'}), 200);
        }
        return http.Response(
          jsonEncode({
            'sessionToken': 'gt_sess_test',
            'expiresAt': '2026-07-27T00:00:00Z',
          }),
          200,
        );
      }),
    );
    addTearDown(auth.close);

    await auth.register(
      username: 'projet',
      password: 'temporary-test-password',
    );
    final session = await auth.login(
      username: 'projet',
      password: 'temporary-test-password',
    );
    expect(session.sessionToken, 'gt_sess_test');
    expect(calls, 2);
  });

  test('lit une page cloud avec curseur et identifiant distant', () async {
    final repository = CloudSensorRepository(
      baseUri: Uri.parse('https://api.example.test'),
      accessToken: 'user-token',
      client: MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/api/v1/devices/greenhouse-01/readings');
        expect(request.url.queryParameters, isNot(contains('since')));
        expect(request.url.queryParameters['cursor'], 'cursor-1');
        expect(request.headers['authorization'], 'Bearer user-token');
        return http.Response(
          jsonEncode({
            'schema': 1,
            'deviceId': 'greenhouse-01',
            'lastContactAt': 1783947600,
            'nextCursor': 'cursor-2',
            'readings': [
              {
                'deviceId': 'greenhouse-01',
                'eventId': 'greenhouse-01-1842',
                'sequence': 1842,
                'timestamp': 1783947600,
                'temperature': 24.6,
                'humidity': 57.2,
                'vpd': 1.28,
              },
            ],
          }),
          200,
        );
      }),
    );
    addTearDown(repository.close);

    final page = await repository.fetchReadings(
      'greenhouse-01',
      since: 1783947600,
      cursor: 'cursor-1',
    );

    expect(page.nextCursor, 'cursor-2');
    expect(page.readings.single.remoteEventId, 'greenhouse-01-1842');
    expect(page.readings.single.sourceSequence, 1842);
  });

  test('utilise since uniquement pour une première synchronisation', () async {
    final repository = CloudSensorRepository(
      baseUri: Uri.parse('https://api.example.test'),
      accessToken: 'user-token',
      client: MockClient((request) async {
        expect(request.url.queryParameters['since'], '1783947600');
        expect(request.url.queryParameters, isNot(contains('cursor')));
        return http.Response(
          jsonEncode({'deviceId': 'greenhouse-01', 'readings': []}),
          200,
        );
      }),
    );
    addTearDown(repository.close);

    await repository.fetchReadings('greenhouse-01', since: 1783947600);
  });

  test('refuse une API cloud non HTTPS', () {
    expect(
      () => CloudSensorRepository(
        baseUri: Uri.parse('http://api.example.test'),
        accessToken: 'token',
      ),
      throwsArgumentError,
    );
  });

  test('envoie un rattrapage historique par lot avec identite stable',
      () async {
    final timestamp = DateTime.utc(2026, 7, 21, 12);
    final repository = CloudSensorRepository(
      baseUri: Uri.parse('https://api.example.test'),
      accessToken: 'user-token',
      client: MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/api/v1/devices/greenhouse-01/backfill');
        final payload = jsonDecode(request.body) as Map<String, dynamic>;
        final reading = (payload['readings'] as List).single as Map;
        expect(reading['deviceId'], 'greenhouse-01');
        expect(reading['sequence'], timestamp.millisecondsSinceEpoch ~/ 1000);
        expect((reading['eventId'] as String), startsWith('backfill-'));
        return http.Response(
          jsonEncode({
            'status': 'accepted',
            'acceptedEventIds': [reading['eventId']],
            'rejected': [],
          }),
          200,
        );
      }),
    );
    addTearDown(repository.close);

    final result = await repository.uploadHistoricalReadings('greenhouse-01', [
      SensorReading(
        id: 'local-reading-1',
        deviceId: 'local-greenhouse-01',
        timestamp: timestamp,
        temperature: 24.6,
        humidity: 57.2,
        vpd: 1.28,
        mistOn: false,
      ),
    ]);

    expect(result.accepted, 1);
    expect(result.rejected, 0);
    expect(result.batches, 1);
  });

  test('synchronise vers SQLite et conserve le succès cloud', () async {
    final db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    addTearDown(db.close);
    await DatabaseHelper.instance.createSchemaForTesting(db);
    final data = SensorDataRepository(database: db);
    final now = DateTime.utc(2026, 7, 14, 10);
    final device = SensorDevice(
      id: 'local-greenhouse-01',
      uid: 'greenhouse-01',
      name: 'Serre cloud',
      zoneId: 'zone-main',
      baseUrl: 'http://192.168.1.42',
      createdAt: now,
      updatedAt: now,
    );
    await data.upsertDevice(device);
    final remote = CloudSensorRepository(
      baseUri: Uri.parse('https://api.example.test'),
      accessToken: 'user-token',
      client: MockClient((_) async => http.Response(
            jsonEncode({
              'deviceId': 'greenhouse-01',
              'nextCursor': 'cursor-2',
              'lastContactAt': now.millisecondsSinceEpoch ~/ 1000,
              'readings': [
                {
                  'deviceId': 'greenhouse-01',
                  'eventId': 'greenhouse-01-1842',
                  'sequence': 1842,
                  'timestamp': now.millisecondsSinceEpoch ~/ 1000,
                  'temperature': 24.6,
                  'humidity': 57.2,
                  'vpd': 1.28,
                },
              ],
            }),
            200,
          )),
    );
    addTearDown(remote.close);

    final result = await CloudSensorSyncService(
      remote: remote,
      data: data,
    ).synchronize(device);

    expect(result.inserted, 1);
    final reading = (await db.query('sensor_readings')).single;
    expect(reading['remote_event_id'], 'greenhouse-01-1842');
    final savedDevice = (await data.getDevices()).single;
    expect(savedDevice.cloudCursor, 'cursor-2');
    expect(savedDevice.status, 'unknown');
    expect(savedDevice.cloudLastError, isNull);
    expect(savedDevice.cloudLastContactAt, isNotNull);
    expect(
      await data.insertReadings(device, [
        SensorReading(
          deviceId: device.id,
          remoteEventId: 'greenhouse-01-1842',
          sourceSequence: 1842,
          timestamp: now.add(const Duration(minutes: 1)),
          temperature: 24.6,
          humidity: 57.2,
          vpd: 1.28,
          mistOn: false,
        ),
      ]),
      0,
    );
  });

  test('rattrape plusieurs pages de 500 mesures et garde le dernier curseur',
      () async {
    final db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    addTearDown(db.close);
    await DatabaseHelper.instance.createSchemaForTesting(db);
    final data = SensorDataRepository(database: db);
    final now = DateTime.utc(2026, 9, 20, 1);
    final device = SensorDevice(
      id: 'local-greenhouse-01',
      uid: 'greenhouse-01',
      name: 'Serre cloud',
      zoneId: 'zone-main',
      baseUrl: 'http://192.168.1.42',
      cloudDeviceId: 'dev-greenhouse-01',
      createdAt: now,
      updatedAt: now,
    );
    await data.upsertDevice(device);
    var requests = 0;
    final remote = CloudSensorRepository(
      baseUri: Uri.parse('https://api.example.test'),
      accessToken: 'user-token',
      client: MockClient((request) async {
        requests++;
        final secondPage = request.url.queryParameters['cursor'] == 'c500';
        expect(request.url.path, '/api/v1/devices/dev-greenhouse-01/readings');
        return http.Response(
          jsonEncode({
            'deviceId': 'dev-greenhouse-01',
            'nextCursor': secondPage ? 'c501' : 'c500',
            'lastContactAt': now.millisecondsSinceEpoch ~/ 1000,
            'readings': [
              for (var i = secondPage ? 500 : 0;
                  i < (secondPage ? 501 : 500);
                  i++)
                {
                  'deviceId': 'dev-greenhouse-01',
                  'eventId': 'event-$i',
                  'sequence': i + 1,
                  'timestamp':
                      now.add(Duration(seconds: i)).millisecondsSinceEpoch ~/
                          1000,
                  'temperature': 24.0,
                  'humidity': 60.0,
                  'vpd': 1.0,
                },
            ],
          }),
          200,
        );
      }),
    );
    addTearDown(remote.close);

    final result = await CloudSensorSyncService(
      remote: remote,
      data: data,
    ).synchronize(device);

    expect(requests, 2);
    expect(result.received, 501);
    expect(result.inserted, 501);
    expect(result.nextCursor, 'c501');
    expect((await data.getDevices()).single.cloudCursor, 'c501');
    expect(await db.query('sensor_readings'), hasLength(501));
  });
}
