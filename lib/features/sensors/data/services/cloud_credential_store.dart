import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class CloudCredentials {
  final String baseUrl;
  final String username;
  final String password;

  const CloudCredentials({
    required this.baseUrl,
    required this.username,
    required this.password,
  });
}

abstract interface class CloudCredentialStore {
  Future<CloudCredentials?> read();
  Future<void> write(CloudCredentials credentials);
  Future<void> delete();
}

/// Opt-in credentials stay in the platform keystore, outside SQLite and exports.
class SecureCloudCredentialStore implements CloudCredentialStore {
  static const _key = 'gardenjournal-cloud-credentials-v1';
  final FlutterSecureStorage _storage;

  SecureCloudCredentialStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  @override
  Future<CloudCredentials?> read() async {
    final encoded = await _storage.read(key: _key);
    if (encoded == null) return null;
    final decoded = jsonDecode(encoded);
    if (decoded is! Map<String, dynamic> ||
        decoded['baseUrl'] is! String ||
        decoded['username'] is! String ||
        decoded['password'] is! String) {
      throw const FormatException('Identifiants cloud mémorisés invalides');
    }
    final credentials = CloudCredentials(
      baseUrl: decoded['baseUrl'] as String,
      username: decoded['username'] as String,
      password: decoded['password'] as String,
    );
    _validate(credentials);
    return credentials;
  }

  @override
  Future<void> write(CloudCredentials credentials) async {
    _validate(credentials);
    await _storage.write(
      key: _key,
      value: jsonEncode({
        'baseUrl': credentials.baseUrl.trim(),
        'username': credentials.username.trim(),
        'password': credentials.password,
      }),
    );
  }

  @override
  Future<void> delete() => _storage.delete(key: _key);

  static void _validate(CloudCredentials credentials) {
    final url = credentials.baseUrl.trim();
    final uri = Uri.tryParse(url);
    if (url.length > 2048 ||
        uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.path.isNotEmpty && uri.path != '/') ||
        credentials.username.trim().isEmpty ||
        credentials.username.length > 80 ||
        credentials.password.isEmpty ||
        credentials.password.length > 4096) {
      throw const FormatException('Identifiants cloud invalides');
    }
  }
}
