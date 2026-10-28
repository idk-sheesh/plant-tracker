import 'dart:convert';

import 'package:http/http.dart' as http;

import 'cloud_sensor_repository.dart';

class CloudAuthRepository {
  final http.Client _client;
  final bool _ownsClient;
  final Uri _baseUri;

  CloudAuthRepository({
    required Uri baseUri,
    http.Client? client,
  })  : _client = client ?? http.Client(),
        _ownsClient = client == null,
        _baseUri = _validateBaseUri(baseUri);

  Future<void> register({
    required String username,
    required String password,
  }) async {
    await _postJson(
      '/api/v1/auth/register',
      {'username': username.trim(), 'password': password},
    );
  }

  Future<CloudSession> login({
    required String username,
    required String password,
  }) async {
    final decoded = await _postJson(
      '/api/v1/auth/login',
      {'username': username.trim(), 'password': password},
    );
    if (decoded is! Map || decoded['sessionToken'] is! String) {
      throw const FormatException('Session cloud invalide');
    }
    final token = (decoded['sessionToken'] as String).trim();
    if (token.isEmpty || token.length > 4096) {
      throw const FormatException('Token de session cloud invalide');
    }
    final expiresAt = decoded['expiresAt'] is String
        ? DateTime.tryParse(decoded['expiresAt'] as String)
        : null;
    return CloudSession(sessionToken: token, expiresAt: expiresAt);
  }

  Future<void> logout(String sessionToken) async {
    final response = await _client.post(
      _endpoint('/api/v1/auth/logout'),
      headers: {
        'Accept': 'application/json',
        'Authorization': 'Bearer ${sessionToken.trim()}',
      },
    ).timeout(const Duration(seconds: 10));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw CloudApiException('/api/v1/auth/logout', response.statusCode);
    }
  }

  Future<Object?> _postJson(String path, Map<String, dynamic> payload) async {
    final response = await _client
        .post(
          _endpoint(path),
          headers: const {
            'Accept': 'application/json',
            'Content-Type': 'application/json; charset=utf-8',
          },
          body: jsonEncode(payload),
        )
        .timeout(const Duration(seconds: 10));
    if (response.bodyBytes.length > 1024 * 1024) {
      throw FormatException('RÃ©ponse $path trop volumineuse');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw CloudApiException(path, response.statusCode);
    }
    try {
      return jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      throw FormatException('JSON cloud invalide sur $path');
    }
  }

  Uri _endpoint(String path) {
    final basePath = _baseUri.path.endsWith('/')
        ? _baseUri.path.substring(0, _baseUri.path.length - 1)
        : _baseUri.path;
    return _baseUri.replace(path: '$basePath$path');
  }

  static Uri _validateBaseUri(Uri uri) {
    if (uri.scheme != 'https' || uri.host.isEmpty || uri.userInfo.isNotEmpty) {
      throw ArgumentError.value(
        uri,
        'baseUri',
        'Lâ€™API cloud doit utiliser HTTPS sans identifiants embarquÃ©s',
      );
    }
    return uri.replace(query: null, fragment: null);
  }

  void close() {
    if (_ownsClient) _client.close();
  }
}

class CloudSession {
  final String sessionToken;
  final DateTime? expiresAt;

  const CloudSession({required this.sessionToken, this.expiresAt});
}
