import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:garden_journal/core/database/database_helper.dart';
import 'package:garden_journal/features/cameras/data/repositories/camera_data_repository.dart';
import 'package:garden_journal/features/cameras/data/repositories/camera_gateway_repository.dart';
import 'package:garden_journal/features/cameras/data/repositories/private_camera_gateway_repository.dart';
import 'package:garden_journal/features/cameras/data/services/camera_credential_store.dart';
import 'package:garden_journal/features/cameras/domain/entities/camera_snapshot.dart';
import 'package:garden_journal/features/cameras/domain/entities/camera_status.dart';
import 'package:garden_journal/features/cameras/presentation/providers/camera_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../../support/database_test_utils.dart';

class _MemoryCredentialStore implements CameraCredentialStore {
  final Map<String, String> _tokens = {};

  String _key(String cameraId, String baseUrl) => '$cameraId|$baseUrl';

  @override
  Future<String?> readToken({
    required String cameraId,
    required String baseUrl,
  }) async =>
      _tokens[_key(cameraId, baseUrl)];

  @override
  Future<void> writeToken({
    required String cameraId,
    required String baseUrl,
    required String token,
  }) async {
    _tokens[_key(cameraId, baseUrl)] = token.trim();
  }

  @override
  Future<void> deleteToken({
    required String cameraId,
    required String baseUrl,
  }) async {
    _tokens.remove(_key(cameraId, baseUrl));
  }
}

class _FailingCredentialStore extends _MemoryCredentialStore {
  @override
  Future<void> writeToken({
    required String cameraId,
    required String baseUrl,
    required String token,
  }) =>
      throw StateError('secure storage unavailable');
}

CameraStatus _statusFor({
  required String cameraId,
  required String zoneId,
  String status = 'online',
}) =>
    CameraStatus(
      cameraId: cameraId,
      name: cameraId,
      zoneId: zoneId,
      status: status,
      lastSeenAt: null,
      firmwareVersion: null,
      rssi: null,
      freeHeapBytes: null,
      uptimeSeconds: null,
      lastError: null,
      latestSnapshot: null,
    );

class _DeferredStatusClient implements CameraGatewayClient {
  @override
  final String cameraId;
  final String zoneId;
  CameraStatus status;
  Completer<CameraStatus>? nextStatus;

  _DeferredStatusClient({
    required this.cameraId,
    required this.zoneId,
  }) : status = _statusFor(cameraId: cameraId, zoneId: zoneId);

  @override
  String get baseUrl => 'http://192.168.0.21:8443';

  @override
  Future<CameraStatus> fetchStatus() async {
    final pending = nextStatus;
    if (pending != null) {
      nextStatus = null;
      status = await pending.future;
    }
    return status;
  }

  @override
  Future<Uint8List> fetchLatestPhoto(CameraSnapshot snapshot) async =>
      Uint8List(0);

  @override
  Future<int> requestCapture() async => 1;

  @override
  void close() {}
}

class _FakeCameraClient implements CameraGatewayClient {
  final List<CameraStatus> statuses;
  int _statusIndex = 0;

  _FakeCameraClient(this.statuses);

  @override
  String get baseUrl => 'http://192.168.0.21:8443';

  @override
  String get cameraId => 'cam-01';

  @override
  Future<CameraStatus> fetchStatus() async {
    final index = _statusIndex.clamp(0, statuses.length - 1).toInt();
    _statusIndex++;
    return statuses[index];
  }

  @override
  Future<Uint8List> fetchLatestPhoto(CameraSnapshot snapshot) async =>
      Uint8List.fromList([0xff, 0xd8, 0xff, 0xff, 0xd9]);

  @override
  Future<int> requestCapture() async => 7;

  @override
  void close() {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  test(
      'mode privé sans conservation : arrière-plan et déconnexion effacent la photo',
      () async {
    final db = await openMemoryDatabase();
    addTearDown(db.close);
    await DatabaseHelper.instance.createSchemaForTesting(db);
    final data = CameraDataRepository(database: db);
    final client = PrivateCameraGatewayRepository(
      baseUrl: 'https://hub.example.ts.net:8443',
      cameraId: 'cam-01',
      zoneId: 'zone-main',
      appToken: 'x' * 40,
      client: MockClient((request) async => request.method == 'POST'
          ? http.Response.bytes([255, 216, 1, 2, 255, 217], 200,
              headers: {'content-type': 'image/jpeg'})
          : http.Response(
              jsonEncode({
                'status': 'ok',
                'checked_at': null,
                'image_retention_seconds': 0
              }),
              200)),
    );
    final provider = CameraProvider(
        dataRepository: data,
        clientFactory: (
                {required baseUrl, required cameraId, required appToken}) =>
            client);
    addTearDown(provider.dispose);
    expect(
        await provider.connect(
            cameraId: 'cam-01',
            name: 'Test',
            zoneId: 'zone-main',
            baseUrl: client.baseUrl,
            appToken: 'x' * 40),
        isTrue);
    expect(await provider.capture('zone-main'), isTrue);
    final bytes = provider.imageForZone('zone-main')!;
    expect(bytes, isNotEmpty);
    expect(await data.getLatestSnapshot('cam-01'), isNull);
    provider.didChangeAppLifecycleState(AppLifecycleState.paused);
    expect(provider.imageForZone('zone-main'), isNull);
    expect(provider.statusForZone('zone-main')?.latestSnapshot, isNull);
    expect(bytes.every((value) => value == 0), isTrue);
    expect(await provider.capture('zone-main'), isTrue);
    provider.disconnect('zone-main');
    expect(provider.imageForZone('zone-main'), isNull);
    expect(provider.hasSession('cam-01'), isFalse);
    expect(await data.getLatestSnapshot('cam-01'), isNull);
  });

  test('isole les erreurs et connexions des deux espaces', () async {
    final previousErrorHandler = FlutterError.onError;
    FlutterError.onError = (_) {};
    addTearDown(() => FlutterError.onError = previousErrorHandler);
    final db = await openMemoryDatabase();
    addTearDown(db.close);
    await DatabaseHelper.instance.createSchemaForTesting(db);
    final clients = {
      'cam-01': _DeferredStatusClient(cameraId: 'cam-01', zoneId: 'zone-main'),
      'cam-02':
          _DeferredStatusClient(cameraId: 'cam-02', zoneId: 'zone-cutting'),
    };
    final provider = CameraProvider(
      dataRepository: CameraDataRepository(database: db),
      clientFactory: ({
        required baseUrl,
        required cameraId,
        required appToken,
      }) =>
          clients[cameraId]!,
    );
    addTearDown(provider.dispose);

    for (final entry in clients.entries) {
      expect(
        await provider.connect(
          cameraId: entry.key,
          name: entry.key,
          zoneId: entry.value.zoneId,
          baseUrl: entry.value.baseUrl,
          appToken: 'x' * 40,
        ),
        isTrue,
        reason: '${entry.key}: ${provider.errorForZone(entry.value.zoneId)}',
      );
    }

    final failedStatus = Completer<CameraStatus>();
    clients['cam-01']!.nextStatus = failedStatus;
    final failedRefresh = provider.refresh('zone-main');
    failedStatus.completeError(CameraGatewayException('/status', 503));
    expect(await failedRefresh, isFalse);
    expect(
      provider.errorForZone('zone-main'),
      'Caméra hors ligne ou occupée. Réessayez dans quelques secondes.',
    );
    expect(provider.errorForZone('zone-cutting'), isNull);

    final pending = Completer<CameraStatus>();
    clients['cam-02']!.nextStatus = pending;
    final refresh = provider.refresh('zone-cutting');
    await Future<void>.delayed(Duration.zero);
    provider.disconnect('zone-main');
    pending.complete(_statusFor(
      cameraId: 'cam-02',
      zoneId: 'zone-cutting',
      status: 'offline',
    ));

    expect(await refresh, isTrue);
    expect(provider.statusForZone('zone-cutting')?.status, 'offline');
    expect(provider.hasSession('cam-02'), isTrue);
    expect(provider.isLoading('zone-cutting'), isFalse);
  });

  test(
      'conserve explicitement une photo privée et restaure le jeton hors sauvegarde',
      () async {
    final db = await openMemoryDatabase();
    addTearDown(db.close);
    await DatabaseHelper.instance.createSchemaForTesting(db);
    final photoRoot = await Directory.systemTemp.createTemp('camera-saved-');
    addTearDown(() async {
      if (await photoRoot.exists()) await photoRoot.delete(recursive: true);
    });
    final data = CameraDataRepository(database: db);
    final credentials = _MemoryCredentialStore();
    final jpeg = [255, 216, 255, 1, 2, 255, 217];

    CameraGatewayClient clientFactory({
      required String baseUrl,
      required String cameraId,
      required String appToken,
    }) =>
        PrivateCameraGatewayRepository(
          baseUrl: baseUrl,
          cameraId: cameraId,
          zoneId: 'zone-main',
          appToken: appToken,
          client: MockClient((request) async => request.method == 'POST'
              ? http.Response.bytes(jpeg, 200,
                  headers: {'content-type': 'image/jpeg'})
              : http.Response(
                  jsonEncode({
                    'status': 'ok',
                    'checked_at': null,
                    'image_retention_seconds': 0,
                  }),
                  200)),
        );

    final provider = CameraProvider(
      dataRepository: data,
      credentialStore: credentials,
      photoRootDirectory: photoRoot,
      clientFactory: clientFactory,
    );
    expect(
      await provider.connect(
        cameraId: 'cam-01',
        name: 'Caméra privée',
        zoneId: 'zone-main',
        baseUrl: 'https://hub.example.ts.net:8443',
        appToken: 'x' * 40,
        rememberToken: true,
      ),
      isTrue,
    );
    expect(
      await credentials.readToken(
        cameraId: 'cam-01',
        baseUrl: 'https://hub.example.ts.net:8443',
      ),
      'x' * 40,
    );
    expect(await provider.capture('zone-main'), isTrue);
    expect(await provider.saveCurrentPhoto('zone-main'), isTrue);
    final saved = provider.savedPhotosForZone('zone-main').single;
    expect(await File(saved.photoPath!).readAsBytes(), jpeg);
    provider.didChangeAppLifecycleState(AppLifecycleState.paused);
    expect(provider.imageForZone('zone-main'), isNull);
    expect(provider.savedPhotosForZone('zone-main'), hasLength(1));
    provider.dispose();

    final restored = CameraProvider(
      dataRepository: data,
      credentialStore: credentials,
      photoRootDirectory: photoRoot,
      clientFactory: clientFactory,
    );
    addTearDown(restored.dispose);
    await restored.initialize();
    expect(restored.hasSession('cam-01'), isTrue);
    expect(restored.savedPhotosForZone('zone-main'), hasLength(1));
    expect(await restored.deleteSavedPhoto('zone-main', saved), isTrue);
    expect(await File(saved.photoPath!).exists(), isFalse);
    expect(restored.savedPhotosForZone('zone-main'), isEmpty);
  });

  test('garde la session active si le coffre sécurisé est indisponible',
      () async {
    final previousErrorHandler = FlutterError.onError;
    FlutterError.onError = (_) {};
    addTearDown(() => FlutterError.onError = previousErrorHandler);
    final db = await openMemoryDatabase();
    addTearDown(db.close);
    await DatabaseHelper.instance.createSchemaForTesting(db);
    final provider = CameraProvider(
      dataRepository: CameraDataRepository(database: db),
      credentialStore: _FailingCredentialStore(),
      clientFactory: ({
        required baseUrl,
        required cameraId,
        required appToken,
      }) =>
          PrivateCameraGatewayRepository(
        baseUrl: baseUrl,
        cameraId: cameraId,
        zoneId: 'zone-main',
        appToken: appToken,
        client: MockClient((_) async => http.Response(
              jsonEncode({
                'status': 'ok',
                'checked_at': null,
                'image_retention_seconds': 0,
              }),
              200,
            )),
      ),
    );
    addTearDown(provider.dispose);

    expect(
      await provider.connect(
        cameraId: 'cam-01',
        name: 'Caméra privée',
        zoneId: 'zone-main',
        baseUrl: 'https://hub.example.ts.net:8443',
        appToken: 'x' * 40,
        rememberToken: true,
      ),
      isTrue,
    );
    expect(provider.hasSession('cam-01'), isTrue);
    expect(
      provider.errorForZone('zone-main'),
      'Caméra connectée pour cette session, mais le jeton n’a pas pu être mémorisé.',
    );
  });

  test('retire le jeton de l’ancienne adresse après reconfiguration', () async {
    final db = await openMemoryDatabase();
    addTearDown(db.close);
    await DatabaseHelper.instance.createSchemaForTesting(db);
    final credentials = _MemoryCredentialStore();
    final provider = CameraProvider(
      dataRepository: CameraDataRepository(database: db),
      credentialStore: credentials,
      clientFactory: ({
        required baseUrl,
        required cameraId,
        required appToken,
      }) =>
          PrivateCameraGatewayRepository(
        baseUrl: baseUrl,
        cameraId: cameraId,
        zoneId: 'zone-main',
        appToken: appToken,
        client: MockClient((_) async => http.Response(
              jsonEncode({
                'status': 'ok',
                'checked_at': null,
                'image_retention_seconds': 0,
              }),
              200,
            )),
      ),
    );
    addTearDown(provider.dispose);
    const oldUrl = 'https://old.example.ts.net:8443';
    const newUrl = 'https://new.example.ts.net:8443';

    expect(
      await provider.connect(
        cameraId: 'cam-01',
        name: 'Caméra privée',
        zoneId: 'zone-main',
        baseUrl: oldUrl,
        appToken: 'a' * 40,
        rememberToken: true,
      ),
      isTrue,
    );
    expect(
      await provider.connect(
        cameraId: 'cam-01',
        name: 'Caméra privée',
        zoneId: 'zone-main',
        baseUrl: newUrl,
        appToken: 'b' * 40,
        rememberToken: true,
      ),
      isTrue,
    );

    expect(
      await credentials.readToken(cameraId: 'cam-01', baseUrl: oldUrl),
      isNull,
    );
    expect(
      await credentials.readToken(cameraId: 'cam-01', baseUrl: newUrl),
      'b' * 40,
    );
  });

  test('une capture privée tardive est ignorée après déconnexion', () async {
    final db = await openMemoryDatabase();
    addTearDown(db.close);
    await DatabaseHelper.instance.createSchemaForTesting(db);
    final pendingCapture = Completer<http.Response>();
    final client = PrivateCameraGatewayRepository(
      baseUrl: 'https://hub.example.ts.net:8443',
      cameraId: 'cam-01',
      zoneId: 'zone-main',
      appToken: 'x' * 40,
      client: MockClient((request) async {
        if (request.method == 'POST') return pendingCapture.future;
        return http.Response(
          jsonEncode({
            'status': 'ok',
            'checked_at': null,
            'image_retention_seconds': 0,
          }),
          200,
        );
      }),
    );
    final replacement = PrivateCameraGatewayRepository(
      baseUrl: 'https://hub.example.ts.net:8443',
      cameraId: 'cam-01',
      zoneId: 'zone-main',
      appToken: 'x' * 40,
      client: MockClient((_) async => http.Response(
            jsonEncode({
              'status': 'ok',
              'checked_at': null,
              'image_retention_seconds': 0,
            }),
            200,
          )),
    );
    var connectionCount = 0;
    final provider = CameraProvider(
      dataRepository: CameraDataRepository(database: db),
      clientFactory: ({
        required baseUrl,
        required cameraId,
        required appToken,
      }) =>
          connectionCount++ == 0 ? client : replacement,
    );
    addTearDown(provider.dispose);
    expect(
      await provider.connect(
        cameraId: 'cam-01',
        name: 'Caméra privée',
        zoneId: 'zone-main',
        baseUrl: client.baseUrl,
        appToken: 'x' * 40,
      ),
      isTrue,
    );

    final capture = provider.capture('zone-main');
    await Future<void>.delayed(Duration.zero);
    provider.disconnect('zone-main');
    expect(
      await provider.connect(
        cameraId: 'cam-01',
        name: 'Caméra privée reconnectée',
        zoneId: 'zone-main',
        baseUrl: replacement.baseUrl,
        appToken: 'x' * 40,
      ),
      isTrue,
    );
    pendingCapture.complete(http.Response.bytes(
      [255, 216, 1, 2, 255, 217],
      200,
      headers: {'content-type': 'image/jpeg'},
    ));

    expect(await capture, isFalse);
    expect(provider.errorForZone('zone-main'), isNull);
    expect(provider.imageForZone('zone-main'), isNull);
    expect(provider.statusForZone('zone-main')?.isOnline, isTrue);
    expect(provider.hasSession('cam-01'), isTrue);
    expect(provider.isLoading('zone-main'), isFalse);
  });

  test('connecte la caméra, déclenche une capture et mémorise ses métadonnées',
      () async {
    final db = await openMemoryDatabase();
    addTearDown(db.close);
    await DatabaseHelper.instance.createSchemaForTesting(db);
    final now = DateTime(2026, 8, 20, 12);
    final initial = CameraStatus(
      cameraId: 'cam-01',
      name: 'Caméra',
      zoneId: 'zone-main',
      status: 'online',
      lastSeenAt: now,
      firmwareVersion: '0.1.0',
      rssi: -60,
      freeHeapBytes: 100000,
      uptimeSeconds: 10,
      lastError: null,
      latestSnapshot: null,
    );
    final captured = CameraSnapshot(
      id: 'snap_1',
      deviceId: 'cam-01',
      zoneId: 'zone-main',
      capturedAt: now.add(const Duration(seconds: 1)),
      sha256: List.filled(64, 'a').join(),
      sizeBytes: 5,
      createdAt: now,
    );
    final client = _FakeCameraClient([
      initial,
      CameraStatus(
        cameraId: 'cam-01',
        name: 'Caméra',
        zoneId: 'zone-main',
        status: 'online',
        lastSeenAt: now.add(const Duration(seconds: 1)),
        firmwareVersion: '0.1.0',
        rssi: -59,
        freeHeapBytes: 99000,
        uptimeSeconds: 11,
        lastError: null,
        latestSnapshot: captured,
      ),
    ]);
    final data = CameraDataRepository(database: db);
    final provider = CameraProvider(
      dataRepository: data,
      clientFactory: ({
        required baseUrl,
        required cameraId,
        required appToken,
      }) =>
          client,
    );
    addTearDown(provider.dispose);

    expect(
      await provider.connect(
        cameraId: 'cam-01',
        name: 'Caméra principale',
        zoneId: 'zone-main',
        baseUrl: client.baseUrl,
        appToken: 'app_${List.filled(40, 'a').join()}',
      ),
      isTrue,
    );
    expect(provider.cameraForZone('zone-main')?.deviceKind, 'camera');
    expect(await provider.capture('zone-main'), isTrue);
    expect(provider.statusForZone('zone-main')?.latestSnapshot?.id, 'snap_1');
    expect(provider.imageForZone('zone-main'), isNotEmpty);
    expect((await data.getLatestSnapshot('cam-01'))?.id, 'snap_1');
  });
}
