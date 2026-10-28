import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:garden_journal/features/sensors/data/repositories/sensor_repository.dart';

void main() {
  group('SensorRepository.configure', () {
    test('accepts private ESP32 hosts and valid ports', () {
      final repo = SensorRepository();

      repo.configure('192.168.1.42', port: 80);
      expect(repo.isConfigured, isTrue);

      repo.configure('10.0.0.12', port: 8080);
      expect(repo.isConfigured, isTrue);

      repo.configure('esp32.local');
      expect(repo.isConfigured, isTrue);
    });

    test('accepte une base URL HTTP ou HTTPS locale sans chemin', () {
      final repo = SensorRepository();

      expect(repo.configureBaseUrl('http://192.168.1.42:8080'), isTrue);
      expect(repo.baseUrl, 'http://192.168.1.42:8080');
      expect(repo.configureBaseUrl('https://192.168.1.42'), isTrue);
      expect(repo.baseUrl, 'https://192.168.1.42');
      expect(repo.configureBaseUrl('https://192.168.1.42:8443'), isTrue);
      expect(repo.baseUrl, 'https://192.168.1.42:8443');
      expect(repo.configureBaseUrl('http://192.168.1.42/api'), isFalse);
      expect(repo.configureBaseUrl('http://user:pass@192.168.1.42'), isFalse);
      expect(repo.configureBaseUrl('http://192.168.1.42?token=x'), isFalse);
    });

    test('rejects public hosts', () {
      final repo = SensorRepository();

      repo.configure('8.8.8.8');

      expect(repo.isConfigured, isFalse);
    });

    test('rejects invalid ports', () {
      final repo = SensorRepository();

      repo.configure('192.168.1.42', port: 0);
      expect(repo.isConfigured, isFalse);

      repo.configure('192.168.1.42', port: 65536);
      expect(repo.isConfigured, isFalse);
    });

    test('efface la configuration réseau après restauration', () {
      final repo = SensorRepository()..configure('192.168.1.42');
      expect(repo.isConfigured, isTrue);

      repo.clearConfiguration();

      expect(repo.isConfigured, isFalse);
      expect(repo.baseUrl, isNull);
    });

    test('rejects host input with paths, queries, credentials or inline ports',
        () {
      final repo = SensorRepository();

      repo.configure('192.168.1.42/api');
      expect(repo.isConfigured, isFalse);

      repo.configure('192.168.1.42?x=1');
      expect(repo.isConfigured, isFalse);

      repo.configure('user@192.168.1.42');
      expect(repo.isConfigured, isFalse);

      repo.configure('192.168.1.42:80');
      expect(repo.isConfigured, isFalse);
    });
  });

  group('SensorRepository API locale', () {
    test('prévoit le délai nécessaire à la reprise LittleFS ESP32', () {
      expect(
        SensorRepository.historyRequestTimeout,
        const Duration(seconds: 90),
      );
    });

    test('utilise /status et conserve le timestamp fourni par l ESP32',
        () async {
      late Uri requestedUri;
      final repo = SensorRepository(
        client: MockClient((request) async {
          requestedUri = request.url;
          return http.Response(
            jsonEncode({
              'deviceId': 'greenhouse-01',
              'timestamp': 1783947600,
              'temperature': 24.6,
              'humidity': 57.2,
              'vpd': 1.28,
              'mistOn': true,
              'mode': 'VEG',
              'waterLow': false,
              'rssi': -58,
              'dewPoint': 15.4,
              'firmwareVersion': '0.1.0',
            }),
            200,
          );
        }),
      )..configure('192.168.1.42');

      final status = await repo.fetchStatus();

      expect(requestedUri.path, '/status');
      expect(status.deviceId, 'greenhouse-01');
      expect(status.timestampSeconds, 1783947600);
      expect(status.stageName, 'VEG');
      expect(status.rssi, -58);
      expect(status.dewPoint, 15.4);
      expect(status.firmwareVersion, '0.1.0');
    });

    test('demande uniquement les mesures depuis la dernière synchro', () async {
      late Uri requestedUri;
      final repo = SensorRepository(
        client: MockClient((request) async {
          requestedUri = request.url;
          return http.Response(
            jsonEncode({
              'readings': [
                {
                  'deviceId': 'greenhouse-01',
                  'timestamp': 1783947660,
                  'temperature': 24.7,
                  'humidity': 57.0,
                  'vpd': 1.29,
                  'mistOn': false,
                  'fanPercent': 40,
                },
              ],
            }),
            200,
          );
        }),
      )..configure('192.168.1.42');

      final readings = await repo.fetchReadings(since: 1783947600);

      expect(requestedUri.path, '/readings');
      expect(requestedUri.queryParameters['since'], '1783947600');
      expect(readings, hasLength(1));
      expect(readings.single.fanPercent, 40);
    });

    test('signale une route /readings non implementee', () async {
      final repo = SensorRepository(
        client: MockClient((request) async => http.Response('{}', 404)),
      )..configure('192.168.1.42');

      expect(
        () => repo.fetchReadings(since: 0),
        throwsA(isA<SensorHistoryUnavailableException>()),
      );
    });

    test('envoie la configuration en JSON avec POST /config', () async {
      late http.Request sentRequest;
      final repo = SensorRepository(
        client: MockClient((request) async {
          sentRequest = request;
          return http.Response('{}', 204);
        }),
      )..configure('192.168.1.42');

      final updated = await repo.updateConfig({'mistOn': true});

      expect(updated, isTrue);
      expect(sentRequest.method, 'POST');
      expect(sentRequest.url.path, '/config');
      expect(jsonDecode(sentRequest.body), {'mistOn': true});
      expect(sentRequest.headers['content-type'], 'application/json');
    });

    test('agrège le diagnostic des mesures invalides', () async {
      final repo = SensorRepository(
        client: MockClient((request) async => http.Response(
              jsonEncode([
                {
                  'deviceId': 'greenhouse-01',
                  'timestamp': 1783947660,
                  'temperature': 24.7,
                  'humidity': 57.0,
                },
                {
                  'deviceId': 'greenhouse-01',
                  'timestamp': 'invalid',
                  'temperature': 24.7,
                  'humidity': 57.0,
                },
                'not-an-object',
              ]),
              200,
            )),
      )..configure('192.168.1.42');

      final readings = await repo.fetchReadings(since: 0);

      expect(readings, hasLength(1));
      expect(repo.lastBatchDiagnostics?.accepted, 1);
      expect(repo.lastBatchDiagnostics?.rejected, 2);
    });

    test('refuse une réponse dépassant la taille maximale', () async {
      final repo = SensorRepository(
        client: MockClient((request) async => http.Response(
              List.filled(256 * 1024 + 1, 'x').join(),
              200,
            )),
      )..configure('192.168.1.42');

      await expectLater(repo.fetchStatus(), throwsFormatException);
    });
  });
}
