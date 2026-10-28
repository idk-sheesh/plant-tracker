import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../repositories/private_camera_gateway_repository.dart';

abstract interface class CameraCredentialStore {
  Future<String?> readToken({
    required String cameraId,
    required String baseUrl,
  });

  Future<void> writeToken({
    required String cameraId,
    required String baseUrl,
    required String token,
  });

  Future<void> deleteToken({
    required String cameraId,
    required String baseUrl,
  });
}

class SecureCameraCredentialStore implements CameraCredentialStore {
  final FlutterSecureStorage _storage;

  SecureCameraCredentialStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  @override
  Future<String?> readToken({
    required String cameraId,
    required String baseUrl,
  }) async {
    final token = await _storage.read(key: _key(cameraId, baseUrl));
    return token == null || token.isEmpty ? null : token;
  }

  @override
  Future<void> writeToken({
    required String cameraId,
    required String baseUrl,
    required String token,
  }) async {
    final normalized = token.trim();
    if (normalized.length < 32 ||
        normalized.length > 512 ||
        RegExp(r'[\r\n]').hasMatch(normalized)) {
      throw const FormatException('Jeton caméra invalide');
    }
    await _storage.write(
      key: _key(cameraId, baseUrl),
      value: normalized,
    );
  }

  @override
  Future<void> deleteToken({
    required String cameraId,
    required String baseUrl,
  }) =>
      _storage.delete(key: _key(cameraId, baseUrl));

  String _key(String cameraId, String baseUrl) {
    final id = cameraId.trim();
    if (!RegExp(r'^cam-[A-Za-z0-9][A-Za-z0-9_-]{0,63}$').hasMatch(id)) {
      throw const FormatException('Identifiant caméra privée invalide');
    }
    final url = PrivateCameraGatewayRepository.validateUrl(baseUrl).toString();
    final digest = sha256.convert(utf8.encode('$url|$id'));
    return 'private-camera-token-$digest';
  }
}
