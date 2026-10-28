import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../../../core/services/photo_storage_service.dart';
import '../../../sensors/domain/entities/sensor_device.dart';
import '../../data/repositories/camera_data_repository.dart';
import '../../data/repositories/camera_gateway_repository.dart';
import '../../data/repositories/private_camera_gateway_repository.dart';
import '../../data/services/camera_credential_store.dart';
import '../../domain/entities/camera_snapshot.dart';
import '../../domain/entities/camera_status.dart';

typedef CameraGatewayClientFactory = CameraGatewayClient Function({
  required String baseUrl,
  required String cameraId,
  required String appToken,
});

class CameraProvider extends ChangeNotifier with WidgetsBindingObserver {
  final CameraDataRepository _dataRepository;
  final CameraGatewayClientFactory? _clientFactory;
  final CameraCredentialStore _credentialStore;
  final Directory? _photoRootDirectory;

  CameraProvider({
    CameraDataRepository? dataRepository,
    CameraGatewayClientFactory? clientFactory,
    CameraCredentialStore? credentialStore,
    Directory? photoRootDirectory,
  })  : _dataRepository = dataRepository ?? CameraDataRepository(),
        _clientFactory = clientFactory,
        _credentialStore = credentialStore ?? SecureCameraCredentialStore(),
        _photoRootDirectory = photoRootDirectory {
    WidgetsBinding.instance.addObserver(this);
  }

  List<SensorDevice> _cameras = [];
  final Map<String, CameraGatewayClient> _sessions = {};
  final Map<String, CameraStatus> _statusByZone = {};
  final Map<String, Uint8List> _imageByZone = {};
  final Map<String, String> _errorByZone = {};
  final Map<String, List<CameraSnapshot>> _savedSnapshotsByZone = {};
  final Set<String> _loadingZones = {};
  Future<void>? _initialization;
  final Map<String, Timer> _imageTimers = {};
  final Map<String, int> _operationEpochByZone = {};
  int _privacyEpoch = 0;
  bool _disposed = false;

  bool privateModeForZone(String zoneId) =>
      PrivateCameraGatewayRepository.isPrivateHubUrl(
          cameraForZone(zoneId)?.baseUrl ?? '');

  void clearPrivatePhotos() {
    _privacyEpoch++;
    for (final camera in _cameras) {
      if (_sessions[camera.id] is EphemeralCameraClient &&
          camera.zoneId != null) {
        _clearPhoto(camera.zoneId!);
      }
    }
    _loadingZones.clear();
    if (!_disposed) notifyListeners();
  }

  void _clearPhoto(String zoneId) {
    _imageTimers.remove(zoneId)?.cancel();
    final bytes = _imageByZone.remove(zoneId);
    if (bytes != null) bytes.fillRange(0, bytes.length, 0);
    final camera = cameraForZone(zoneId);
    final client = camera == null ? null : _sessions[camera.id];
    if (client is EphemeralCameraClient) client.clearPhoto();
    final status = _statusByZone[zoneId];
    if (status != null) {
      _statusByZone[zoneId] = CameraStatus(
          cameraId: status.cameraId,
          name: status.name,
          zoneId: status.zoneId,
          status: status.status,
          lastSeenAt: status.lastSeenAt,
          firmwareVersion: status.firmwareVersion,
          rssi: status.rssi,
          freeHeapBytes: status.freeHeapBytes,
          uptimeSeconds: status.uptimeSeconds,
          lastError: status.lastError,
          latestSnapshot: null);
    }
  }

  void disconnect(String zoneId) {
    _operationEpochByZone[zoneId] = _zoneEpoch(zoneId) + 1;
    _loadingZones.remove(zoneId);
    _clearPhoto(zoneId);
    final camera = cameraForZone(zoneId);
    if (camera != null) _sessions.remove(camera.id)?.close();
    _statusByZone.remove(zoneId);
    _errorByZone.remove(zoneId);
    if (!_disposed) notifyListeners();
  }

  int _zoneEpoch(String zoneId) => _operationEpochByZone[zoneId] ?? 0;

  bool _isCurrentOperation(
    String zoneId,
    int privacyEpoch,
    int zoneEpoch, {
    String? cameraId,
    CameraGatewayClient? client,
  }) {
    if (_disposed ||
        privacyEpoch != _privacyEpoch ||
        zoneEpoch != _zoneEpoch(zoneId)) {
      return false;
    }
    return cameraId == null || identical(_sessions[cameraId], client);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) clearPrivatePhotos();
  }

  List<SensorDevice> get cameras => List.unmodifiable(_cameras);
  SensorDevice? cameraForZone(String zoneId) {
    for (final camera in _cameras) {
      if (camera.zoneId == zoneId) return camera;
    }
    return null;
  }

  CameraStatus? statusForZone(String zoneId) => _statusByZone[zoneId];
  Uint8List? imageForZone(String zoneId) => _imageByZone[zoneId];
  String? errorForZone(String zoneId) => _errorByZone[zoneId];
  List<CameraSnapshot> savedPhotosForZone(String zoneId) =>
      List.unmodifiable(_savedSnapshotsByZone[zoneId] ?? const []);
  bool isLoading(String zoneId) => _loadingZones.contains(zoneId);
  bool hasSession(String deviceId) => _sessions.containsKey(deviceId);

  bool isCurrentPhotoSaved(String zoneId) {
    final id = _statusByZone[zoneId]?.latestSnapshot?.id;
    return id != null &&
        (_savedSnapshotsByZone[zoneId] ?? const [])
            .any((snapshot) => snapshot.id == id);
  }

  Future<String?> rememberedToken({
    required String cameraId,
    required String baseUrl,
  }) async {
    if (!PrivateCameraGatewayRepository.isPrivateHubUrl(baseUrl)) return null;
    try {
      return await _credentialStore.readToken(
        cameraId: cameraId,
        baseUrl: baseUrl,
      );
    } catch (error, stackTrace) {
      _report(error, stackTrace, 'lecture du jeton caméra sécurisé');
      return null;
    }
  }

  Future<void> initialize() => _initialization ??= _loadCameras();

  Future<bool> reloadAfterRestore() async {
    clearPrivatePhotos();
    for (final session in _sessions.values) {
      session.close();
    }
    _sessions.clear();
    _statusByZone.clear();
    _imageByZone.clear();
    _errorByZone.clear();
    _loadingZones.clear();
    _operationEpochByZone.clear();
    _initialization = null;
    try {
      await initialize();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> connect({
    required String cameraId,
    required String name,
    required String zoneId,
    required String baseUrl,
    required String appToken,
    bool? rememberToken,
  }) async {
    if (_disposed || isLoading(zoneId)) return false;
    final privacyEpoch = _privacyEpoch;
    final zoneEpoch = _zoneEpoch(zoneId);
    _setLoading(zoneId, true);
    _errorByZone.remove(zoneId);
    CameraGatewayClient? client;
    CameraGatewayClient? installedClient;
    String? installedCameraKey;
    try {
      await initialize();
      if (!_isCurrentOperation(zoneId, privacyEpoch, zoneEpoch)) return false;
      final assigned = cameraForZone(zoneId);
      if (assigned != null && assigned.uid != cameraId.trim()) {
        throw const FormatException(
            'Cet espace possède déjà une autre caméra.');
      }
      final normalizedName = name.trim();
      if (normalizedName.length > 120) {
        throw const FormatException('Nom de caméra trop long');
      }
      client = _createClient(
        baseUrl: baseUrl,
        cameraId: cameraId.trim(),
        zoneId: zoneId,
        appToken: appToken,
      );
      final status = await client.fetchStatus();
      if (!_isCurrentOperation(zoneId, privacyEpoch, zoneEpoch)) return false;
      if (status.cameraId != cameraId.trim() || status.zoneId != zoneId) {
        throw const FormatException(
          'La caméra ou la zone annoncée par le Pi ne correspond pas',
        );
      }
      final existing = _cameras.where((item) => item.uid == status.cameraId);
      final previous = existing.isEmpty ? null : existing.first;
      final now = DateTime.now();
      final camera = SensorDevice(
        id: previous?.id ?? status.cameraId,
        uid: status.cameraId,
        name: normalizedName.isEmpty ? status.name : normalizedName,
        zoneId: zoneId,
        baseUrl: client.baseUrl,
        firmwareVersion: status.firmwareVersion,
        lastSeenAt: status.lastSeenAt,
        lastSyncAt: now,
        status: status.status,
        deviceKind: 'camera',
        transport: Uri.parse(client.baseUrl).scheme,
        model: previous?.model ?? 'AI-Thinker ESP32-CAM',
        createdAt: previous?.createdAt ?? now,
        updatedAt: now,
      );
      await _dataRepository.upsertCamera(camera);
      if (!_isCurrentOperation(zoneId, privacyEpoch, zoneEpoch)) return false;
      final previousZoneId = previous?.zoneId;
      if (previousZoneId != null) {
        if (previousZoneId != zoneId) {
          _operationEpochByZone[previousZoneId] =
              _zoneEpoch(previousZoneId) + 1;
          _loadingZones.remove(previousZoneId);
          _statusByZone.remove(previousZoneId);
          _errorByZone.remove(previousZoneId);
        }
        _clearPhoto(previousZoneId);
      }
      _sessions[camera.id]?.close();
      installedClient = client;
      installedCameraKey = camera.id;
      _sessions[camera.id] = installedClient;
      client = null;
      await _rememberStatus(camera, status, downloadPhoto: true);
      if (!_isCurrentOperation(
        zoneId,
        privacyEpoch,
        zoneEpoch,
        cameraId: camera.id,
        client: installedClient,
      )) {
        if (identical(_sessions[camera.id], installedClient)) {
          _sessions.remove(camera.id)?.close();
        }
        return false;
      }
      await _loadCameras(notify: false);
      String? credentialWarning;
      if (PrivateCameraGatewayRepository.isPrivateHubUrl(camera.baseUrl) &&
          rememberToken != null) {
        credentialWarning = await _updateRememberedToken(
          cameraId: camera.uid,
          baseUrl: camera.baseUrl,
          appToken: appToken,
          remember: rememberToken,
        );
        final previousBaseUrl = previous?.baseUrl;
        if (previousBaseUrl != null &&
            previousBaseUrl != camera.baseUrl &&
            PrivateCameraGatewayRepository.isPrivateHubUrl(previousBaseUrl)) {
          final obsoleteCredentialWarning = await _updateRememberedToken(
            cameraId: camera.uid,
            baseUrl: previousBaseUrl,
            appToken: appToken,
            remember: false,
          );
          credentialWarning ??= obsoleteCredentialWarning;
        }
      }
      if (!_isCurrentOperation(
        zoneId,
        privacyEpoch,
        zoneEpoch,
        cameraId: camera.id,
        client: installedClient,
      )) {
        return false;
      }
      if (credentialWarning != null) {
        _errorByZone[zoneId] = credentialWarning;
      }
      return true;
    } catch (error, stackTrace) {
      if (installedClient != null && installedCameraKey != null) {
        if (identical(_sessions[installedCameraKey], installedClient)) {
          _sessions.remove(installedCameraKey)?.close();
        }
      }
      if (_isCurrentOperation(zoneId, privacyEpoch, zoneEpoch)) {
        _errorByZone[zoneId] = _messageFor(error);
        _report(error, stackTrace, 'connexion à la passerelle caméra');
      }
      return false;
    } finally {
      client?.close();
      if (_isCurrentOperation(zoneId, privacyEpoch, zoneEpoch)) {
        _setLoading(zoneId, false);
      }
    }
  }

  Future<bool> refresh(String zoneId) async {
    if (_disposed || isLoading(zoneId)) return false;
    final privacyEpoch = _privacyEpoch;
    final zoneEpoch = _zoneEpoch(zoneId);
    final camera = cameraForZone(zoneId);
    if (camera == null) return false;
    final client = _sessions[camera.id];
    if (client == null) {
      _errorByZone[zoneId] = 'Saisissez le jeton du Pi pour cette session.';
      notifyListeners();
      return false;
    }
    _setLoading(zoneId, true);
    _errorByZone.remove(zoneId);
    try {
      final status = await client.fetchStatus();
      if (!_isCurrentOperation(
        zoneId,
        privacyEpoch,
        zoneEpoch,
        cameraId: camera.id,
        client: client,
      )) return false;
      await _rememberStatus(camera, status, downloadPhoto: true);
      return _isCurrentOperation(
        zoneId,
        privacyEpoch,
        zoneEpoch,
        cameraId: camera.id,
        client: client,
      );
    } catch (error, stackTrace) {
      if (_isCurrentOperation(
        zoneId,
        privacyEpoch,
        zoneEpoch,
        cameraId: camera.id,
        client: client,
      )) {
        _errorByZone[zoneId] = _messageFor(error);
        _report(error, stackTrace, 'actualisation de la caméra');
      }
      return false;
    } finally {
      if (_isCurrentOperation(
        zoneId,
        privacyEpoch,
        zoneEpoch,
        cameraId: camera.id,
        client: client,
      )) {
        _setLoading(zoneId, false);
      }
    }
  }

  Future<bool> capture(String zoneId) async {
    if (_disposed || isLoading(zoneId)) return false;
    final privacyEpoch = _privacyEpoch;
    final zoneEpoch = _zoneEpoch(zoneId);
    final camera = cameraForZone(zoneId);
    if (camera == null) return false;
    final client = _sessions[camera.id];
    if (client == null) {
      _errorByZone[zoneId] = 'Saisissez le jeton du Pi pour cette session.';
      notifyListeners();
      return false;
    }
    _setLoading(zoneId, true);
    _errorByZone.remove(zoneId);
    try {
      final previousId = _statusByZone[zoneId]?.latestSnapshot?.id;
      if (client is EphemeralCameraClient) _clearPhoto(zoneId);
      await client.requestCapture();
      if (!_isCurrentOperation(
        zoneId,
        privacyEpoch,
        zoneEpoch,
        cameraId: camera.id,
        client: client,
      )) return false;
      final deadline = DateTime.now().add(const Duration(seconds: 40));
      while (DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(seconds: 1));
        final status = await client.fetchStatus();
        if (!_isCurrentOperation(
          zoneId,
          privacyEpoch,
          zoneEpoch,
          cameraId: camera.id,
          client: client,
        )) return false;
        final snapshot = status.latestSnapshot;
        if (snapshot != null && snapshot.id != previousId) {
          await _rememberStatus(camera, status, downloadPhoto: true);
          return _isCurrentOperation(
            zoneId,
            privacyEpoch,
            zoneEpoch,
            cameraId: camera.id,
            client: client,
          );
        }
      }
      _errorByZone[zoneId] = 'La caméra n’a pas répondu avant l’expiration.';
      return false;
    } catch (error, stackTrace) {
      if (_isCurrentOperation(
        zoneId,
        privacyEpoch,
        zoneEpoch,
        cameraId: camera.id,
        client: client,
      )) {
        _errorByZone[zoneId] = _messageFor(error);
        _report(error, stackTrace, 'capture distante');
      }
      return false;
    } finally {
      if (_isCurrentOperation(
        zoneId,
        privacyEpoch,
        zoneEpoch,
        cameraId: camera.id,
        client: client,
      )) {
        _setLoading(zoneId, false);
      }
    }
  }

  Future<bool> saveCurrentPhoto(String zoneId) async {
    if (_disposed || isLoading(zoneId)) return false;
    final image = _imageByZone[zoneId];
    final snapshot = _statusByZone[zoneId]?.latestSnapshot;
    if (image == null || snapshot == null || !privateModeForZone(zoneId)) {
      _errorByZone[zoneId] = 'Aucune photo temporaire à conserver.';
      notifyListeners();
      return false;
    }
    if (isCurrentPhotoSaved(zoneId)) return true;
    final bytes = Uint8List.fromList(image);
    String? storedPath;
    _setLoading(zoneId, true);
    _errorByZone.remove(zoneId);
    try {
      if (bytes.length != snapshot.sizeBytes ||
          sha256.convert(bytes).toString() != snapshot.sha256) {
        throw const FormatException('Photo caméra corrompue ou inattendue');
      }
      storedPath = await PhotoStorageService.persistImageBytes(
        bytes,
        bucket: 'camera_snapshots',
        rootDirectory: _photoRootDirectory,
      );
      final saved = snapshot.copyWith(
        photoPath: storedPath,
        createdAt: DateTime.now(),
      );
      final inserted = await _dataRepository.saveSnapshot(saved);
      if (!inserted) {
        await PhotoStorageService.deleteManagedFile(
          storedPath,
          rootDirectory: _photoRootDirectory,
        );
        await _loadSavedSnapshots();
        return true;
      }
      _savedSnapshotsByZone.putIfAbsent(zoneId, () => []).insert(0, saved);
      return true;
    } catch (error, stackTrace) {
      if (storedPath != null) {
        try {
          await PhotoStorageService.deleteManagedFile(
            storedPath,
            rootDirectory: _photoRootDirectory,
          );
        } catch (cleanupError, cleanupStackTrace) {
          _report(
            cleanupError,
            cleanupStackTrace,
            'nettoyage après échec de conservation caméra',
          );
        }
      }
      _errorByZone[zoneId] = 'Impossible de conserver la photo.';
      _report(error, stackTrace, 'conservation de la photo caméra');
      return false;
    } finally {
      bytes.fillRange(0, bytes.length, 0);
      _setLoading(zoneId, false);
    }
  }

  Future<bool> deleteSavedPhoto(
    String zoneId,
    CameraSnapshot snapshot,
  ) async {
    if (_disposed || isLoading(zoneId) || snapshot.photoPath == null) {
      return false;
    }
    _setLoading(zoneId, true);
    _errorByZone.remove(zoneId);
    try {
      final deleted = await _dataRepository.deleteSnapshot(snapshot.id);
      if (!deleted) return false;
      _savedSnapshotsByZone[zoneId]
          ?.removeWhere((item) => item.id == snapshot.id);
      try {
        await PhotoStorageService.deleteManagedFile(
          snapshot.photoPath!,
          rootDirectory: _photoRootDirectory,
        );
      } catch (error, stackTrace) {
        _errorByZone[zoneId] =
            'Photo retirée de l’historique, nettoyage du fichier incomplet.';
        _report(error, stackTrace, 'suppression du fichier caméra');
      }
      return true;
    } catch (error, stackTrace) {
      _errorByZone[zoneId] = 'Impossible de supprimer la photo conservée.';
      _report(error, stackTrace, 'suppression de la photo caméra');
      return false;
    } finally {
      _setLoading(zoneId, false);
    }
  }

  Future<void> _rememberStatus(
    SensorDevice camera,
    CameraStatus status, {
    required bool downloadPhoto,
  }) async {
    final epoch = _privacyEpoch;
    final client = _sessions[camera.id];
    if (status.cameraId != camera.uid || status.zoneId != camera.zoneId) {
      throw const FormatException('Identité de caméra inattendue');
    }
    if (status.latestSnapshot case final snapshot?) {
      if (client is! EphemeralCameraClient)
        await _dataRepository.saveSnapshot(snapshot);
      if (downloadPhoto && client != null) {
        final bytes = await client.fetchLatestPhoto(snapshot);
        if (_disposed ||
            epoch != _privacyEpoch ||
            !identical(_sessions[camera.id], client)) {
          bytes.fillRange(0, bytes.length, 0);
          return;
        }
        _imageByZone[status.zoneId] = bytes;
        if (client is EphemeralCameraClient) {
          _imageTimers.remove(status.zoneId)?.cancel();
          _imageTimers[status.zoneId] = Timer(const Duration(seconds: 60), () {
            _clearPhoto(status.zoneId);
            if (!_disposed) notifyListeners();
          });
        }
      }
    }
    if (_disposed || epoch != _privacyEpoch) return;
    _statusByZone[status.zoneId] = status;
    await _dataRepository.upsertCamera(
      camera.copyWith(
        firmwareVersion: status.firmwareVersion,
        lastSeenAt: status.lastSeenAt,
        lastSyncAt: DateTime.now(),
        status: status.status,
        updatedAt: DateTime.now(),
      ),
    );
    if (!_disposed && epoch == _privacyEpoch) notifyListeners();
  }

  Future<void> _loadCameras({bool notify = true}) async {
    _cameras = await _dataRepository.getCameras();
    await _loadSavedSnapshots();
    await _restoreRememberedSessions();
    if (notify && !_disposed) notifyListeners();
  }

  Future<void> _loadSavedSnapshots() async {
    final snapshots = await _dataRepository.getSavedSnapshots();
    _savedSnapshotsByZone.clear();
    for (final snapshot in snapshots) {
      final zoneId = snapshot.zoneId;
      if (zoneId != null) {
        _savedSnapshotsByZone.putIfAbsent(zoneId, () => []).add(snapshot);
      }
    }
  }

  Future<void> _restoreRememberedSessions() async {
    for (final camera in _cameras) {
      final zoneId = camera.zoneId;
      if (zoneId == null ||
          _sessions.containsKey(camera.id) ||
          !PrivateCameraGatewayRepository.isPrivateHubUrl(camera.baseUrl)) {
        continue;
      }
      try {
        final token = await _credentialStore.readToken(
          cameraId: camera.uid,
          baseUrl: camera.baseUrl,
        );
        if (token == null) continue;
        _sessions[camera.id] = _createClient(
          baseUrl: camera.baseUrl,
          cameraId: camera.uid,
          zoneId: zoneId,
          appToken: token,
        );
      } catch (error, stackTrace) {
        _errorByZone[zoneId] = 'Impossible de lire le jeton mémorisé.';
        _report(error, stackTrace, 'restauration de la session caméra');
      }
    }
  }

  CameraGatewayClient _createClient({
    required String baseUrl,
    required String cameraId,
    required String zoneId,
    required String appToken,
  }) {
    final factory = _clientFactory;
    if (factory != null) {
      return factory(
        baseUrl: baseUrl,
        cameraId: cameraId,
        appToken: appToken,
      );
    }
    return PrivateCameraGatewayRepository.isPrivateHubUrl(baseUrl)
        ? PrivateCameraGatewayRepository(
            baseUrl: baseUrl,
            cameraId: cameraId,
            zoneId: zoneId,
            appToken: appToken,
          )
        : CameraGatewayRepository(
            baseUrl: baseUrl,
            cameraId: cameraId,
            appToken: appToken,
          );
  }

  Future<String?> _updateRememberedToken({
    required String cameraId,
    required String baseUrl,
    required String appToken,
    required bool remember,
  }) async {
    try {
      if (remember) {
        await _credentialStore.writeToken(
          cameraId: cameraId,
          baseUrl: baseUrl,
          token: appToken,
        );
      } else {
        await _credentialStore.deleteToken(
          cameraId: cameraId,
          baseUrl: baseUrl,
        );
      }
      return null;
    } catch (error, stackTrace) {
      _report(error, stackTrace, 'mise à jour du jeton caméra sécurisé');
      return remember
          ? 'Caméra connectée pour cette session, mais le jeton n’a pas pu être mémorisé.'
          : 'Caméra connectée, mais le jeton mémorisé n’a pas pu être supprimé.';
    }
  }

  void _setLoading(String zoneId, bool value) {
    if (_disposed) return;
    if (value) {
      _loadingZones.add(zoneId);
    } else {
      _loadingZones.remove(zoneId);
    }
    notifyListeners();
  }

  String _messageFor(Object error) {
    if (error is CameraGatewayException && error.statusCode == 401) {
      return 'Jeton du Pi refusé.';
    }
    if (error is CameraGatewayException && error.statusCode == 429) {
      return 'Une photo vient déjà d’être demandée.';
    }
    if (error is CameraGatewayException &&
        const {409, 503, 504}.contains(error.statusCode)) {
      return 'Caméra hors ligne ou occupée. Réessayez dans quelques secondes.';
    }
    if (error is FormatException) return error.message.toString();
    return 'Passerelle caméra inaccessible.';
  }

  void _report(Object error, StackTrace stackTrace, String operation) {
    FlutterError.reportError(FlutterErrorDetails(
      exception: error,
      stack: stackTrace,
      library: 'gardenjournal cameras',
      context: ErrorDescription(operation),
    ));
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    clearPrivatePhotos();
    for (final timer in _imageTimers.values) {
      timer.cancel();
    }
    for (final session in _sessions.values) {
      session.close();
    }
    super.dispose();
  }
}
