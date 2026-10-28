import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:garden_journal/core/database/database_helper.dart';
import 'package:garden_journal/features/sensors/data/repositories/ota_repository.dart';
import 'package:garden_journal/features/sensors/data/repositories/sensor_repository.dart';
import 'package:garden_journal/features/sensors/data/services/ota_update_service.dart';
import 'package:garden_journal/features/sensors/domain/entities/ota_update.dart';
import 'package:garden_journal/features/sensors/domain/entities/sensor_device.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../../support/database_test_utils.dart';

void main() {
  sqfliteFfiInit();
  final now = DateTime.utc(2026, 7, 19, 12);
  final firmware = utf8.encode('signed-firmware-v11');

  Future<
      ({
        Database db,
        SensorDevice device,
        OtaRepository repository,
        KeyPair keyPair,
        SimplePublicKey publicKey,
      })> setup() async {
    final db = await openMemoryDatabase();
    await DatabaseHelper.instance.createSchemaForTesting(db);
    final device = SensorDevice(
      id: 'node-ota',
      uid: 'node-ota',
      name: 'Nœud OTA',
      zoneId: 'zone-main',
      baseUrl: 'http://192.168.1.42',
      model: 'GT-S3',
      createdAt: now,
      updatedAt: now,
    );
    await db.insert('sensor_devices', device.toMap());
    final repository = OtaRepository(database: db);
    await repository.saveDeviceState(OtaDeviceState(
      deviceId: device.id,
      currentVersion: '1.0.0',
      currentBuild: 10,
      highestAcceptedBuild: 10,
      lastKnownGoodBuild: 10,
      hardwareModel: 'GT-S3',
      bootloaderVersion: '1.2.0',
      rollbackSupported: true,
      updatedAt: now,
    ));
    final algorithm = Ed25519();
    final keyPair = await algorithm.newKeyPair();
    final publicKey = await keyPair.extractPublicKey();
    await repository.storeBuildKey(OtaTrustedKey(
      keyId: 'release-2026',
      publicKeyBase64: base64Encode(publicKey.bytes),
      validFrom: DateTime.utc(2026, 1, 1),
    ));
    return (
      db: db,
      device: device,
      repository: repository,
      keyPair: keyPair,
      publicKey: publicKey,
    );
  }

  Future<Map<String, dynamic>> signedManifest(
    KeyPair keyPair, {
    int build = 11,
    List<int>? signedFirmware,
  }) async {
    final bytes = signedFirmware ?? firmware;
    final unsigned = <String, dynamic>{
      'schemaVersion': 1,
      'manifestId': 'manifest-$build',
      'deviceModel': 'GT-S3',
      'version': '1.1.0',
      'buildNumber': build,
      'firmwareUrl': 'https://firmware.test/node.bin',
      'sizeBytes': bytes.length,
      'sha256': sha256.convert(bytes).toString(),
      'keyId': 'release-2026',
      'issuedAt': now.subtract(const Duration(minutes: 1)).toIso8601String(),
      'expiresAt': now.add(const Duration(days: 1)).toIso8601String(),
      'minimumBootloader': '1.1.0',
    };
    final signature = await Ed25519().sign(
      utf8.encode(canonicalJson(unsigned)),
      keyPair: keyPair,
    );
    return {...unsigned, 'signature': base64Encode(signature.bytes)};
  }

  test('vérifie Ed25519 et SHA-256 avant de journaliser', () async {
    final setupData = await setup();
    addTearDown(setupData.db.close);
    final manifest = await signedManifest(setupData.keyPair);
    final service = OtaUpdateService(
      repository: setupData.repository,
      remote: SensorRepository(
          client: MockClient((_) async => http.Response('{}', 500))),
      httpClient: OtaHttpClient(client: MockClient((request) async {
        if (request.url.path.endsWith('manifest.json')) {
          return http.Response(jsonEncode(manifest), 200);
        }
        return http.Response.bytes(firmware, 200);
      })),
      clock: () => now,
    );

    final update = await service.verifyAndRecord(
      setupData.device,
      Uri.parse('https://firmware.test/manifest.json'),
    );

    expect(update.status, 'verified');
    expect(update.firmwareSha256, sha256.convert(firmware).toString());
    expect(await setupData.repository.getUpdates(setupData.device.id),
        hasLength(1));
  });

  test('refuse anti-rollback et signature altérée sans créer d’update',
      () async {
    final setupData = await setup();
    addTearDown(setupData.db.close);
    final rollback = await signedManifest(setupData.keyPair, build: 10);
    final invalidSignature = await signedManifest(setupData.keyPair, build: 12)
      ..['signature'] = base64Encode(List<int>.filled(64, 0));
    var manifest = rollback;
    final service = OtaUpdateService(
      repository: setupData.repository,
      httpClient: OtaHttpClient(client: MockClient((request) async {
        if (request.url.path.endsWith('manifest.json')) {
          return http.Response(jsonEncode(manifest), 200);
        }
        return http.Response.bytes(firmware, 200);
      })),
      clock: () => now,
    );

    await expectLater(
      service.verifyAndRecord(
        setupData.device,
        Uri.parse('https://firmware.test/manifest.json'),
      ),
      throwsA(isA<OtaException>()),
    );
    manifest = invalidSignature;
    await expectLater(
      service.verifyAndRecord(
        setupData.device,
        Uri.parse('https://firmware.test/manifest.json'),
      ),
      throwsA(isA<OtaException>()),
    );
    expect(await setupData.repository.getUpdates(setupData.device.id), isEmpty);
  });

  test('installe seulement après accusé rollback puis vérifie le build démarré',
      () async {
    final setupData = await setup();
    addTearDown(setupData.db.close);
    final manifest = await signedManifest(setupData.keyPair);
    final remote = SensorRepository(client: MockClient((request) async {
      if (request.url.path == '/ota') {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({
            'manifestId': body['manifestId'],
            'sha256': body['sha256'],
            'status': 'accepted',
            'rollbackSupported': true,
          }),
          200,
        );
      }
      if (request.url.path == '/ota/status') {
        return http.Response(
          jsonEncode({
            'status': 'succeeded',
            'signatureVerified': true,
            'runningBuild': 11,
          }),
          200,
        );
      }
      return http.Response('{}', 404);
    }));
    final service = OtaUpdateService(
      repository: setupData.repository,
      remote: remote,
      httpClient: OtaHttpClient(client: MockClient((request) async {
        if (request.url.path.endsWith('manifest.json')) {
          return http.Response(jsonEncode(manifest), 200);
        }
        return http.Response.bytes(firmware, 200);
      })),
      clock: () => now,
    );
    final verified = await service.verifyAndRecord(
      setupData.device,
      Uri.parse('https://firmware.test/manifest.json'),
    );

    final requested = await service.requestInstall(
      setupData.device,
      verified,
      confirmed: true,
    );
    final succeeded = await service.refreshStatus(setupData.device, requested);

    expect(requested.status, 'requested');
    expect(succeeded.status, 'succeeded');
    final state =
        await setupData.repository.getDeviceState(setupData.device.id);
    expect(state?.currentBuild, 11);
    expect(state?.lastKnownGoodBuild, 11);
  });
}
