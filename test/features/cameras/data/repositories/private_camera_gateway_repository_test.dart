import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:garden_journal/features/cameras/data/repositories/camera_gateway_repository.dart';
import 'package:garden_journal/features/cameras/data/repositories/private_camera_gateway_repository.dart';

void main() {
  const url = 'https://hub.example.ts.net:8443';
  final jpeg = <int>[255, 216, 1, 2, 255, 217];
  PrivateCameraGatewayRepository repository(http.Client client) =>
      PrivateCameraGatewayRepository(
          baseUrl: url,
          cameraId: 'cam-01',
          zoneId: 'test-zone',
          appToken: 'x' * 40,
          client: client);
  http.Response status() => http.Response(
      jsonEncode({
        'status': 'offline',
        'checked_at': null,
        'image_retention_seconds': 0,
      }),
      200);

  test('expiration automatique après 60 secondes', () async {
    final repo = repository(MockClient((request) async =>
        request.method == 'POST'
            ? http.Response.bytes(jpeg, 200,
                headers: {'content-type': 'image/jpeg'})
            : status()));
    addTearDown(repo.close);
    await repo.requestCapture();
    final snapshot = (await repo.fetchStatus()).latestSnapshot!;
    await Future<void>.delayed(const Duration(seconds: 61));
    expect((await repo.fetchStatus()).latestSnapshot, isNull);
    await expectLater(repo.fetchLatestPhoto(snapshot), throwsFormatException);
  }, timeout: const Timeout(Duration(seconds: 90)));

  test('adresse HTTPS centrale sans identifiants ni chemin', () {
    for (final value in [
      'http://hub.example.ts.net',
      'https://127.0.0.1',
      'https://example.com:8443',
      'https://user:password@hub.example.ts.net',
      '$url/path',
      '$url?token=x'
    ]) {
      expect(() => PrivateCameraGatewayRepository.validateUrl(value),
          throwsFormatException);
    }
    expect(PrivateCameraGatewayRepository.validateUrl(url).port, 8443);
    expect(
        PrivateCameraGatewayRepository.validateUrl('https://grow.example.com')
            .port,
        443);
    expect(
        PrivateCameraGatewayRepository.isPrivateHubUrl(
            'https://grow.example.com'),
        isTrue);
    expect(
        PrivateCameraGatewayRepository.isPrivateHubUrl(
            'https://example.com:8443'),
        isFalse);
    final nextCamera = PrivateCameraGatewayRepository(
      baseUrl: 'https://grow.example.com',
      cameraId: 'cam-03',
      zoneId: 'test-zone',
      appToken: 'x' * 40,
    );
    addTearDown(nextCamera.close);
  });

  test('photo en mémoire, statut hors ligne accepté et effacement explicite',
      () async {
    var captures = 0;
    final repo = repository(MockClient((request) async {
      expect(request.followRedirects, isFalse);
      expect(request.headers['authorization'], 'Bearer ${'x' * 40}');
      if (request.method == 'POST') {
        captures++;
        expect(request.bodyBytes, isEmpty);
        return http.Response.bytes(jpeg, 200,
            headers: {'content-type': 'image/jpeg'});
      }
      return status();
    }));
    addTearDown(repo.close);
    expect((await repo.fetchStatus()).isOnline, isFalse);
    await repo.requestCapture();
    final snapshot = (await repo.fetchStatus()).latestSnapshot!;
    expect(await repo.fetchLatestPhoto(snapshot), jpeg);
    expect(captures, 1);
    repo.clearPhoto();
    expect((await repo.fetchStatus()).latestSnapshot, isNull);
    await expectLater(repo.fetchLatestPhoto(snapshot), throwsFormatException);
  });

  test('refuse redirection, clé refusée, photo invalide et réponse trop grande',
      () async {
    for (final response in [
      http.Response('', 302),
      http.Response('', 401),
      http.Response('not jpeg', 200),
      http.Response.bytes(List.filled(2 * 1024 * 1024 + 1, 0), 200)
    ]) {
      final repo = repository(MockClient((_) async => response));
      addTearDown(repo.close);
      await expectLater(
          repo.requestCapture(),
          throwsA(
              anyOf(isA<CameraGatewayException>(), isA<FormatException>())));
    }
  });

  test('une capture terminée après effacement ne recrée pas la photo',
      () async {
    final pending = Completer<http.Response>();
    final repo = repository(MockClient((_) => pending.future));
    addTearDown(repo.close);
    final result = repo.requestCapture();
    final check = expectLater(result, throwsStateError);
    repo.clearPhoto();
    pending.complete(http.Response.bytes(jpeg, 200,
        headers: {'content-type': 'image/jpeg'}));
    await check;
  });

  test('refuse un serveur qui annonce conserver les photos', () async {
    final repo = repository(MockClient((_) async => http.Response(
        '{"status":"ok","checked_at":null,"image_retention_seconds":60}',
        200)));
    addTearDown(repo.close);
    await expectLater(repo.fetchStatus(), throwsFormatException);
  });
}
