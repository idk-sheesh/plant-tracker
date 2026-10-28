import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart' as cryptography;
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import '../../domain/entities/ota_update.dart';
import '../../domain/entities/sensor_device.dart';
import '../repositories/gateway_repository.dart';
import '../repositories/lora_repository.dart';
import '../repositories/ota_repository.dart';
import '../repositories/sensor_repository.dart';

class OtaHttpClient {
  final http.Client _client;
  final bool _ownsClient;

  OtaHttpClient({http.Client? client})
      : _client = client ?? http.Client(),
        _ownsClient = client == null;

  Future<Object?> fetchManifest(Uri uri) async {
    _requireHttps(uri, 'manifest');
    final response = await _client.get(
      uri,
      headers: const {'Accept': 'application/json'},
    ).timeout(const Duration(seconds: 12));
    if (response.statusCode != 200) {
      throw OtaException('Manifest HTTP ${response.statusCode}');
    }
    if (response.bodyBytes.length > 256 * 1024) {
      throw const OtaException('Manifest trop volumineux');
    }
    return jsonDecode(utf8.decode(response.bodyBytes));
  }

  Future<void> verifyFirmware(OtaManifest manifest) async {
    _requireHttps(manifest.firmwareUri, 'firmware');
    final response = await _client.get(manifest.firmwareUri).timeout(
          const Duration(minutes: 2),
        );
    if (response.statusCode != 200) {
      throw OtaException('Firmware HTTP ${response.statusCode}');
    }
    final bytes = response.bodyBytes;
    if (bytes.length != manifest.sizeBytes || bytes.length > 32 * 1024 * 1024) {
      throw const OtaException('Taille du firmware incohérente');
    }
    final digest = sha256.convert(bytes).toString();
    if (digest != manifest.firmwareSha256) {
      throw const OtaException('SHA-256 du firmware incohérent');
    }
  }

  static void _requireHttps(Uri uri, String label) {
    if (uri.scheme != 'https' || uri.host.isEmpty || uri.userInfo.isNotEmpty) {
      throw OtaException('URL $label HTTPS invalide');
    }
  }

  void close() {
    if (_ownsClient) _client.close();
  }
}

class OtaUpdateService {
  final OtaRepository repository;
  final SensorRepository remote;
  final OtaHttpClient httpClient;
  final GatewayRepository gatewayRepository;
  final LoRaRepository loraRepository;
  final cryptography.SignatureAlgorithm signatureAlgorithm;
  final Uuid _uuid;
  final DateTime Function() _clock;

  OtaUpdateService({
    OtaRepository? repository,
    SensorRepository? remote,
    OtaHttpClient? httpClient,
    GatewayRepository? gatewayRepository,
    LoRaRepository? loraRepository,
    cryptography.SignatureAlgorithm? signatureAlgorithm,
    Uuid uuid = const Uuid(),
    DateTime Function()? clock,
  })  : repository = repository ?? OtaRepository(),
        remote = remote ?? SensorRepository(),
        httpClient = httpClient ?? OtaHttpClient(),
        gatewayRepository = gatewayRepository ?? GatewayRepository(),
        loraRepository = loraRepository ?? LoRaRepository(),
        signatureAlgorithm = signatureAlgorithm ?? cryptography.Ed25519(),
        _uuid = uuid,
        _clock = clock ?? DateTime.now;

  Future<OtaDeviceState> synchronizeDeviceState(SensorDevice device) async {
    final targetNodeId = await _configureTarget(device);
    final response = await remote.fetchOtaCapabilities(nodeId: targetNodeId);
    final build = response['currentBuild'];
    final rollback = response['rollbackSupported'];
    if (build is! int || build < 0 || rollback is! bool) {
      throw const OtaException('Capacités OTA du nœud invalides');
    }
    final existing = await repository.getDeviceState(device.id);
    final highest = existing == null
        ? build
        : (existing.highestAcceptedBuild > build
            ? existing.highestAcceptedBuild
            : build);
    final state = OtaDeviceState(
      deviceId: device.id,
      currentVersion: _optionalText(response['currentVersion'], 40),
      currentBuild: build,
      highestAcceptedBuild: highest,
      lastKnownGoodBuild: build,
      hardwareModel:
          _optionalText(response['hardwareModel'], 80) ?? device.model,
      bootloaderVersion: _optionalText(response['bootloaderVersion'], 40),
      rollbackSupported: rollback,
      lastUpdateAt: existing?.lastUpdateAt,
      updatedAt: _clock(),
    );
    await repository.saveDeviceState(state);
    return state;
  }

  Future<OtaUpdateRecord> verifyAndRecord(
    SensorDevice device,
    Uri manifestUri,
  ) async {
    await repository.ensureBuildKey();
    final state = await repository.getDeviceState(device.id);
    if (state == null) {
      throw const OtaException('Synchronise d’abord l’état OTA du nœud');
    }
    final raw = await httpClient.fetchManifest(manifestUri);
    final manifest = OtaManifest.parse(raw, now: _clock());
    final expectedModel = state.hardwareModel ?? device.model;
    if (expectedModel == null || manifest.deviceModel != expectedModel) {
      throw const OtaException('Firmware prévu pour un autre matériel');
    }
    if (manifest.buildNumber <= state.highestAcceptedBuild) {
      throw const OtaException('Anti-rollback : build non supérieur');
    }
    if (manifest.minimumBootloader != null &&
        !_versionAtLeast(
          state.bootloaderVersion,
          manifest.minimumBootloader!,
        )) {
      throw const OtaException('Bootloader trop ancien');
    }
    final key = await repository.getKey(manifest.keyId);
    if (key == null || !key.isValidAt(manifest.issuedAt)) {
      throw const OtaException('Clé de signature absente ou révoquée');
    }
    final publicBytes = _decodeBase64(key.publicKeyBase64, expectedLength: 32);
    final signatureBytes =
        _decodeBase64(manifest.signatureBase64, expectedLength: 64);
    final verified = await signatureAlgorithm.verify(
      manifest.signedBytes(),
      signature: cryptography.Signature(
        signatureBytes,
        publicKey: cryptography.SimplePublicKey(
          publicBytes,
          type: cryptography.KeyPairType.ed25519,
        ),
      ),
    );
    if (!verified) throw const OtaException('Signature Ed25519 invalide');
    await httpClient.verifyFirmware(manifest);
    final now = _clock();
    final update = OtaUpdateRecord(
      id: _uuid.v4(),
      deviceId: device.id,
      manifestId: manifest.manifestId,
      version: manifest.version,
      buildNumber: manifest.buildNumber,
      firmwareUrl: manifest.firmwareUri.toString(),
      sizeBytes: manifest.sizeBytes,
      firmwareSha256: manifest.firmwareSha256,
      signatureBase64: manifest.signatureBase64,
      keyId: manifest.keyId,
      status: 'verified',
      verifiedAt: now,
      manifestJson: canonicalJson(manifest.completeJson),
      createdAt: now,
      updatedAt: now,
    );
    await repository.insertUpdate(update);
    return update;
  }

  Future<OtaUpdateRecord> requestInstall(
    SensorDevice device,
    OtaUpdateRecord update, {
    required bool confirmed,
  }) async {
    if (!confirmed ||
        update.verifiedAt == null ||
        update.requestedAt != null ||
        !const {'verified', 'failed'}.contains(update.status)) {
      throw const OtaException('Confirmation OTA requise');
    }
    final state = await repository.getDeviceState(device.id);
    if (state == null || !state.rollbackSupported) {
      throw const OtaException('Rollback firmware non confirmé par le nœud');
    }
    final targetNodeId = await _configureTarget(device);
    final requestedAt = _clock();
    try {
      final response = await remote.requestOta({
        'version': 1,
        'manifestId': update.manifestId,
        'firmwareUrl': update.firmwareUrl,
        'sizeBytes': update.sizeBytes,
        'sha256': update.firmwareSha256,
        'signature': update.signatureBase64,
        'keyId': update.keyId,
        'buildNumber': update.buildNumber,
        if (targetNodeId != null) 'targetNodeId': targetNodeId,
      });
      if (response['manifestId'] != update.manifestId ||
          response['sha256'] != update.firmwareSha256 ||
          response['status'] != 'accepted' ||
          response['rollbackSupported'] != true) {
        throw const OtaException('Accusé OTA incohérent');
      }
      final ackAt = _safeTime(requestedAt);
      await repository.updateStatus(
        update.id,
        status: 'requested',
        requestedAt: requestedAt,
        nodeAckAt: ackAt,
        updatedAt: ackAt,
      );
      await repository.saveDeviceState(OtaDeviceState(
        deviceId: state.deviceId,
        currentVersion: state.currentVersion,
        currentBuild: state.currentBuild,
        highestAcceptedBuild: update.buildNumber,
        lastKnownGoodBuild: state.lastKnownGoodBuild,
        hardwareModel: state.hardwareModel,
        bootloaderVersion: state.bootloaderVersion,
        rollbackSupported: true,
        lastUpdateAt: state.lastUpdateAt,
        updatedAt: ackAt,
      ));
      return (await repository.getUpdate(update.id))!;
    } catch (error) {
      await repository.updateStatus(
        update.id,
        status: 'failed',
        errorCode: error.runtimeType.toString(),
        updatedAt: _clock(),
      );
      rethrow;
    }
  }

  Future<OtaUpdateRecord> refreshStatus(
    SensorDevice device,
    OtaUpdateRecord update,
  ) async {
    final targetNodeId = await _configureTarget(device);
    final response = await remote.fetchOtaStatus(
      update.manifestId,
      nodeId: targetNodeId,
    );
    final rawStatus = response['status'];
    const allowed = {'downloading', 'installing', 'succeeded', 'failed'};
    if (rawStatus is! String || !allowed.contains(rawStatus)) {
      throw const OtaException('Statut OTA du nœud invalide');
    }
    if (rawStatus == 'succeeded' &&
        (response['signatureVerified'] != true ||
            response['runningBuild'] != update.buildNumber)) {
      throw const OtaException('Preuve de démarrage OTA incohérente');
    }
    await repository.updateStatus(
      update.id,
      status: rawStatus,
      errorCode: _optionalText(response['errorCode'], 120),
      updatedAt: _clock(),
    );
    if (rawStatus == 'succeeded') {
      final state = await repository.getDeviceState(device.id);
      if (state != null) {
        await repository.saveDeviceState(OtaDeviceState(
          deviceId: state.deviceId,
          currentVersion: update.version,
          currentBuild: update.buildNumber,
          highestAcceptedBuild: state.highestAcceptedBuild,
          lastKnownGoodBuild: update.buildNumber,
          hardwareModel: state.hardwareModel,
          bootloaderVersion: state.bootloaderVersion,
          rollbackSupported: state.rollbackSupported,
          lastUpdateAt: _clock(),
          updatedAt: _clock(),
        ));
      }
    }
    return (await repository.getUpdate(update.id))!;
  }

  static List<int> _decodeBase64(String value, {required int expectedLength}) {
    try {
      final bytes = base64Decode(value);
      if (bytes.length != expectedLength) throw const FormatException();
      return bytes;
    } catch (_) {
      throw const OtaException('Clé ou signature Base64 invalide');
    }
  }

  static bool _versionAtLeast(String? current, String minimum) {
    if (current == null) return false;
    List<int>? parts(String value) {
      final match = RegExp(r'^(\d+)\.(\d+)\.(\d+)').firstMatch(value);
      if (match == null) return null;
      return [
        for (var index = 1; index <= 3; index++) int.parse(match.group(index)!)
      ];
    }

    final a = parts(current);
    final b = parts(minimum);
    if (a == null || b == null) return false;
    for (var index = 0; index < 3; index++) {
      if (a[index] != b[index]) return a[index] > b[index];
    }
    return true;
  }

  static String? _optionalText(Object? value, int max) {
    if (value == null) return null;
    if (value is! String || value.length > max) {
      throw const OtaException('Texte OTA invalide');
    }
    final normalized = value.trim();
    return normalized.isEmpty ? null : normalized;
  }

  DateTime _safeTime(DateTime minimum) {
    final value = _clock();
    return value.isBefore(minimum) ? minimum : value;
  }

  Future<String?> _configureTarget(SensorDevice device) async {
    if (device.transport != 'lora') {
      if (!remote.configureBaseUrl(device.baseUrl)) {
        throw const OtaException('Adresse locale du nœud invalide');
      }
      return null;
    }
    final link = await loraRepository.getLinkForNode(device.id);
    final gateway =
        link == null ? null : await gatewayRepository.getConfig(link.gatewayId);
    if (gateway == null ||
        !gateway.usesHttp ||
        !remote.configureBaseUrl(gateway.httpBaseUrl ?? '')) {
      throw const OtaException(
        'La mise à jour LoRa exige une gateway avec transport HTTP',
      );
    }
    return device.uid;
  }

  void close() {
    remote.close();
    httpClient.close();
  }
}

class OtaException implements Exception {
  final String message;

  const OtaException(this.message);

  @override
  String toString() => message;
}
