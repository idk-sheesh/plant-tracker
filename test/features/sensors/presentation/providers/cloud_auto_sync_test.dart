import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:garden_journal/core/database/database_helper.dart';
import 'package:garden_journal/features/sensors/data/repositories/cloud_sensor_repository.dart';
import 'package:garden_journal/features/sensors/data/repositories/sensor_data_repository.dart';
import 'package:garden_journal/features/sensors/domain/entities/sensor_device.dart';
import 'package:garden_journal/features/sensors/presentation/providers/cloud_provider.dart';

import '../../../../support/database_test_utils.dart';

void main() {
  for (final failJournal in [false, true]) {
    test('connexion lance la synchro, journal en échec : $failJournal',
        () async {
      final db = await openMemoryDatabase();
      addTearDown(db.close);
      await DatabaseHelper.instance.createSchemaForTesting(db);
      final data = SensorDataRepository(database: db);
      final now = DateTime.utc(2026, 10, 6);
      await data.upsertDevice(SensorDevice(
          id: 'local',
          uid: 'node',
          name: 'Serre',
          zoneId: null,
          baseUrl: 'http://192.168.1.10',
          cloudDeviceId: 'remote',
          createdAt: now,
          updatedAt: now));
      var publications = 0;
      var downloads = 0;
      var offline = true;
      final provider = CloudProvider(
        dataRepository: data,
        buildSnapshot: () async => {'plants': [], 'actions': []},
        remoteFactory: (uri, token) => CloudSensorRepository(
            baseUri: uri,
            accessToken: token,
            client: MockClient((request) async {
              if (request.url.path == '/api/v1/me') {
                return http.Response(
                    jsonEncode({'id': 'account', 'username': 'user'}), 200);
              }
              if (request.url.path == '/api/v1/devices') {
                return http.Response(
                    jsonEncode({
                      'devices': [
                        {'id': 'remote'}
                      ]
                    }),
                    200);
              }
              if (request.url.path == '/api/v1/sync/snapshot') {
                publications++;
                if (failJournal) return http.Response('{}', 503);
                return http.Response(
                    jsonEncode({'publishedAt': now.toIso8601String()}), 200);
              }
              downloads++;
              if (offline)
                throw http.ClientException(
                    'Failed host lookup: private-host?token=secret');
              return http.Response(
                  jsonEncode({
                    'deviceId': 'remote',
                    'readings': [],
                    'nextCursor': null
                  }),
                  200);
            })),
      );
      addTearDown(provider.dispose);
      expect(
          await provider.connect(
              baseUrl: 'https://hub.example.ts.net', accessToken: 'test-token'),
          isTrue);
      expect(publications, 1);
      expect(downloads, 1);
      expect(provider.error, contains('connexion Internet'));
      expect(provider.error, isNot(contains('Tailscale')));
      expect(provider.error, isNot(contains('secret')));
      if (failJournal) expect(provider.error, contains('Journal'));
      offline = false;
      expect(await provider.synchronizeMyData(), {'local'});
      expect(publications, 2);
      expect(downloads, 2);
      expect(provider.error, failJournal ? contains('Journal') : isNull);
    });
  }

  test('deux demandes concurrentes ne doublent pas la publication', () async {
    final db = await openMemoryDatabase();
    addTearDown(db.close);
    await DatabaseHelper.instance.createSchemaForTesting(db);
    Completer<void>? gate;
    var publications = 0;
    final provider = CloudProvider(
      dataRepository: SensorDataRepository(database: db),
      buildSnapshot: () async => {'plants': [], 'actions': []},
      remoteFactory: (uri, token) => CloudSensorRepository(
          baseUri: uri,
          accessToken: token,
          client: MockClient((request) async {
            if (request.url.path == '/api/v1/me')
              return http.Response('{"id":"a","username":"u"}', 200);
            if (request.url.path == '/api/v1/devices')
              return http.Response('{"devices":[]}', 200);
            publications++;
            if (gate != null) await gate.future;
            return http.Response('{"publishedAt":"2026-10-06T12:00:00Z"}', 200);
          })),
    );
    addTearDown(provider.dispose);
    await provider.connect(
        baseUrl: 'https://hub.example.test', accessToken: 'test-token');
    gate = Completer<void>();
    final first = provider.synchronizeMyData();
    expect(await provider.synchronizeMyData(), isEmpty);
    gate.complete();
    await first;
    expect(publications, 2);
  });
}
