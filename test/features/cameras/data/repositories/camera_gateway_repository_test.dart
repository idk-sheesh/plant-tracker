import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:garden_journal/features/cameras/data/repositories/camera_gateway_repository.dart';

void main() {
  final jpeg = <int>[0xff, 0xd8, 0xff, ...List.filled(1024, 7), 0xff, 0xd9];
  final hash = sha256.convert(jpeg).toString();

  test('valide le statut, la commande et le JPEG du gateway', () async {
    final client = MockClient((request) async {
      expect(request.headers['authorization'], startsWith('Bearer '));
      if (request.url.path.endsWith('/status')) {
        return http.Response(
          jsonEncode({
            'camera': {
              'id': 'cam-01',
              'name': 'Caméra principale',
              'zoneId': 'zone-main',
              'status': 'online',
              'lastSeenAt': '2026-08-20T12:00:00Z',
              'firmwareVersion': 'cam-gateway-0.1.0',
              'rssiDbm': -60,
              'freeHeapBytes': 100000,
              'uptimeSeconds': 42,
              'lastError': null,
              'latestSnapshot': {
                'id': 'snap_1',
                'capturedAt': '2026-08-20T12:00:00Z',
                'sha256': hash,
                'sizeBytes': jpeg.length,
              },
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      if (request.url.path.endsWith('/captures')) {
        return http.Response(
            jsonEncode({
              'command': {'id': 7}
            }),
            202);
      }
      if (request.url.path.endsWith('/snapshots/latest')) {
        return http.Response.bytes(jpeg, 200,
            headers: {'content-type': 'image/jpeg'});
      }
      return http.Response('not found', 404);
    });
    final repository = CameraGatewayRepository(
      baseUrl: 'http://192.168.0.21:8443',
      cameraId: 'cam-01',
      appToken: 'app_${List.filled(40, 'a').join()}',
      client: client,
      allowHttpForTesting: true,
    );

    final status = await repository.fetchStatus();
    expect(status.isOnline, isTrue);
    expect(await repository.requestCapture(), 7);
    expect(
      await repository.fetchLatestPhoto(status.latestSnapshot!),
      jpeg,
    );
  });

  test('refuse les hôtes publics et HTTP quand il n’est pas autorisé', () {
    expect(
      () => CameraGatewayRepository(
        baseUrl: 'https://example.com:8443',
        cameraId: 'cam-01',
        appToken: 'app_${List.filled(40, 'a').join()}',
      ),
      throwsFormatException,
    );
    expect(
      () => CameraGatewayRepository(
        baseUrl: 'http://192.168.0.21:8443',
        cameraId: 'cam-01',
        appToken: 'app_${List.filled(40, 'a').join()}',
        allowHttpForTesting: false,
      ),
      throwsFormatException,
    );
  });
}
