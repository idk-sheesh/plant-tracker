import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garden_journal/features/cameras/data/repositories/camera_data_repository.dart';
import 'package:garden_journal/features/cameras/data/repositories/camera_gateway_repository.dart';
import 'package:garden_journal/features/cameras/data/repositories/private_camera_gateway_repository.dart';
import 'package:garden_journal/features/cameras/domain/entities/camera_snapshot.dart';
import 'package:garden_journal/features/cameras/domain/entities/camera_status.dart';
import 'package:garden_journal/features/cameras/presentation/providers/camera_provider.dart';
import 'package:garden_journal/features/cameras/presentation/widgets/zone_camera_card.dart';
import 'package:garden_journal/features/sensors/domain/entities/sensor_device.dart';
import 'package:provider/provider.dart';

class _MemoryCameraDataRepository extends CameraDataRepository {
  final List<SensorDevice> _cameras = [];
  final List<CameraSnapshot> _snapshots = [];

  @override
  Future<List<SensorDevice>> getCameras() async => List.of(_cameras);

  @override
  Future<void> upsertCamera(SensorDevice camera) async {
    final index = _cameras.indexWhere((item) => item.uid == camera.uid);
    if (index == -1) {
      _cameras.add(camera);
    } else {
      _cameras[index] = camera;
    }
  }

  @override
  Future<bool> saveSnapshot(CameraSnapshot snapshot) async {
    if (_snapshots.any((item) => item.id == snapshot.id)) return false;
    _snapshots.add(snapshot);
    return true;
  }

  @override
  Future<List<CameraSnapshot>> getSavedSnapshots() async => List.of(_snapshots);

  @override
  Future<bool> deleteSnapshot(String snapshotId) async {
    final before = _snapshots.length;
    _snapshots.removeWhere((item) => item.id == snapshotId);
    return _snapshots.length != before;
  }

  void seedSnapshot(CameraSnapshot snapshot) => _snapshots.add(snapshot);
}

class _WidgetCameraClient implements EphemeralCameraClient {
  @override
  final String cameraId;
  final String zoneId;
  final bool offline;
  final bool captureFails;
  CameraSnapshot? _snapshot;
  final Uint8List _image = base64Decode(
    'R0lGODlhAQABAIAAAAAAAP///ywAAAAAAQABAAACAUwAOw==',
  );

  _WidgetCameraClient({
    required this.cameraId,
    required this.zoneId,
    this.offline = false,
    this.captureFails = false,
  });

  @override
  String get baseUrl => 'https://hub.example.ts.net:8443';

  @override
  Future<CameraStatus> fetchStatus() async => CameraStatus(
        cameraId: cameraId,
        name: cameraId,
        zoneId: zoneId,
        status: offline ? 'offline' : 'online',
        lastSeenAt: null,
        firmwareVersion: null,
        rssi: null,
        freeHeapBytes: null,
        uptimeSeconds: null,
        lastError: null,
        latestSnapshot: _snapshot,
      );

  @override
  Future<Uint8List> fetchLatestPhoto(CameraSnapshot snapshot) async =>
      Uint8List.fromList(_image);

  @override
  Future<int> requestCapture() async {
    if (captureFails) throw CameraGatewayException('/capture', 503);
    final now = DateTime.now();
    _snapshot = CameraSnapshot(
      id: 'private-widget',
      deviceId: cameraId,
      zoneId: zoneId,
      capturedAt: now,
      sha256: sha256.convert(_image).toString(),
      sizeBytes: _image.length,
      createdAt: now,
    );
    return 1;
  }

  @override
  void clearPhoto() => _snapshot = null;

  @override
  void close() => clearPhoto();
}

Future<CameraProvider> _connectedProvider(
  _WidgetCameraClient client,
) async {
  final provider = CameraProvider(
    dataRepository: _MemoryCameraDataRepository(),
    clientFactory: ({
      required baseUrl,
      required cameraId,
      required appToken,
    }) =>
        client,
  );
  final connected = await provider.connect(
    cameraId: client.cameraId,
    name: 'Caméra de test',
    zoneId: client.zoneId,
    baseUrl: client.baseUrl,
    appToken: 'x' * 40,
  );
  expect(connected, isTrue);
  addTearDown(provider.dispose);
  return provider;
}

Future<void> _pumpCard(WidgetTester tester, CameraProvider provider) =>
    tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: provider,
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ZoneCameraCard(
                zoneId: 'zone-main',
                zoneName: 'Serre de tomates',
              ),
            ),
          ),
        ),
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final size in [const Size(360, 640), const Size(1280, 800)]) {
    testWidgets('affiche l’état vide et le formulaire sans débordement mobile',
        (tester) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final provider = CameraProvider();
      addTearDown(provider.dispose);

      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: provider,
          child: const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: ZoneCameraCard(
                  zoneId: 'zone-main',
                  zoneName: 'Serre de tomates avec un nom très long',
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.text('Aucune caméra n’est associée à cet espace.'),
          findsOneWidget);
      await tester.tap(find.text('Connecter'));
      await tester.pumpAndSettle();

      expect(find.text('Connecter la caméra'), findsOneWidget);
      expect(find.text('Jeton application du Pi'), findsOneWidget);
      await tester.enterText(
        find.byType(TextFormField).at(2),
        'https://hub.example.ts.net:8443',
      );
      await tester.pump();
      expect(find.text('Mémoriser le jeton'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('affiche les états hors ligne et erreur du hub', (tester) async {
    final previousErrorHandler = FlutterError.onError;
    FlutterError.onError = (_) {};
    addTearDown(() => FlutterError.onError = previousErrorHandler);
    final provider = await _connectedProvider(_WidgetCameraClient(
      cameraId: 'cam-01',
      zoneId: 'zone-main',
      offline: true,
      captureFails: true,
    ));
    await _pumpCard(tester, provider);

    expect(find.text('Hors ligne'), findsOneWidget);
    expect(find.text('Aucune photo téléchargée pour cette session.'),
        findsOneWidget);
    await tester.tap(find.text('Prendre une photo'));
    await tester.pump();
    await tester.pump();

    expect(
      find.text(
        'Caméra hors ligne ou occupée. Réessayez dans quelques secondes.',
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('affiche puis retire un aperçu privé à la déconnexion',
      (tester) async {
    final provider = await _connectedProvider(_WidgetCameraClient(
      cameraId: 'cam-01',
      zoneId: 'zone-main',
    ));
    await _pumpCard(tester, provider);

    final capture = provider.capture('zone-main');
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(await capture, isTrue);
    await tester.pump();

    expect(find.byType(Image), findsOneWidget);
    expect(
      find.text(
        'Aperçu temporaire · effacé après 60 secondes ou en arrière-plan.',
      ),
      findsOneWidget,
    );

    await tester.ensureVisible(find.text('Déconnecter'));
    await tester.pump();
    await tester.tap(find.text('Déconnecter'));
    await tester.pump();
    expect(find.text('Connexion requise'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('propose de conserver une photo privée', (tester) async {
    final provider = await _connectedProvider(_WidgetCameraClient(
      cameraId: 'cam-01',
      zoneId: 'zone-main',
    ));
    await _pumpCard(tester, provider);

    final capture = provider.capture('zone-main');
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(await capture, isTrue);
    await tester.pump();

    expect(find.text('Conserver cette photo'), findsOneWidget);
    expect(tester.takeException(), isNull);

    provider.disconnect('zone-main');
    await tester.pump();
  });

  testWidgets('affiche l’historique des photos conservées', (tester) async {
    final now = DateTime(2026, 9, 10, 12);
    final data = _MemoryCameraDataRepository()
      ..seedSnapshot(CameraSnapshot(
        id: 'saved-widget',
        deviceId: 'cam-01',
        zoneId: 'zone-main',
        capturedAt: now,
        sha256: 'a' * 64,
        sizeBytes: 100,
        createdAt: now,
        photoPath: 'missing-test-photo.jpg',
      ));
    final provider = CameraProvider(dataRepository: data);
    addTearDown(provider.dispose);
    await provider.initialize();
    await _pumpCard(tester, provider);

    expect(find.text('Photos conservées (1)'), findsOneWidget);
    expect(find.byTooltip('Supprimer cette photo'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
