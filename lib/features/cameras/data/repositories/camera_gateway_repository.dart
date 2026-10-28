import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../domain/entities/camera_snapshot.dart';
import '../../domain/entities/camera_status.dart';

abstract interface class CameraGatewayClient {
  String get baseUrl;
  String get cameraId;

  Future<CameraStatus> fetchStatus();
  Future<int> requestCapture();
  Future<Uint8List> fetchLatestPhoto(CameraSnapshot snapshot);
  void close();
}

class CameraGatewayRepository implements CameraGatewayClient {
  final http.Client _client;
  final bool _ownsClient;
  final Uri _baseUri;
  final String _appToken;

  @override
  final String cameraId;

  CameraGatewayRepository({
    required String baseUrl,
    required this.cameraId,
    required String appToken,
    http.Client? client,
    bool? allowHttpForTesting,
  })  : _client = client ?? http.Client(),
        _ownsClient = client == null,
        _baseUri = _validatedBaseUri(
          baseUrl,
          allowHttp: allowHttpForTesting ?? !kReleaseMode,
        ),
        _appToken = _validatedToken(appToken) {
    if (!RegExp(r'^[a-zA-Z0-9][a-zA-Z0-9_.:-]{0,79}$').hasMatch(cameraId)) {
      throw const FormatException('Identifiant caméra invalide');
    }
  }

  @override
  String get baseUrl => _baseUri.toString();

  @override
  Future<CameraStatus> fetchStatus() async {
    final response = await _client
        .get(
          _uri('/api/v1/cameras/$cameraId/status'),
          headers: _headers,
        )
        .timeout(const Duration(seconds: 8));
    _requireSuccess(response, '/status', maximumBytes: 256 * 1024);
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map || decoded['camera'] is! Map) {
      throw const FormatException('Réponse caméra invalide');
    }
    return CameraStatus.fromJson(
      Map<String, dynamic>.from(decoded['camera'] as Map),
    );
  }

  @override
  Future<int> requestCapture() async {
    final response = await _client
        .post(
          _uri('/api/v1/cameras/$cameraId/captures'),
          headers: _headers,
        )
        .timeout(const Duration(seconds: 8));
    _requireSuccess(response, '/captures', maximumBytes: 256 * 1024);
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    final command = decoded is Map ? decoded['command'] : null;
    final id = command is Map ? command['id'] : null;
    if (id is! int || id <= 0) {
      throw const FormatException('Accusé de capture invalide');
    }
    return id;
  }

  @override
  Future<Uint8List> fetchLatestPhoto(CameraSnapshot snapshot) async {
    final response = await _client.get(
      _uri('/api/v1/cameras/$cameraId/snapshots/latest'),
      headers: {
        ..._headers,
        'Accept': 'image/jpeg',
      },
    ).timeout(const Duration(seconds: 20));
    _requireSuccess(
      response,
      '/snapshots/latest',
      maximumBytes: 16 * 1024 * 1024,
    );
    final bytes = response.bodyBytes;
    if (bytes.length < 4 ||
        bytes[0] != 0xff ||
        bytes[1] != 0xd8 ||
        bytes[2] != 0xff ||
        bytes[bytes.length - 2] != 0xff ||
        bytes[bytes.length - 1] != 0xd9 ||
        bytes.length != snapshot.sizeBytes ||
        sha256.convert(bytes).toString() != snapshot.sha256) {
      throw const FormatException('Photo caméra corrompue ou inattendue');
    }
    return Uint8List.fromList(bytes);
  }

  Map<String, String> get _headers => {
        'Authorization': 'Bearer $_appToken',
        'Accept': 'application/json',
      };

  Uri _uri(String path) => _baseUri.replace(path: path);

  static Uri _validatedBaseUri(String value, {required bool allowHttp}) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null ||
        !const {'http', 'https'}.contains(uri.scheme) ||
        (!allowHttp && uri.scheme != 'https') ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        (uri.path.isNotEmpty && uri.path != '/') ||
        uri.hasQuery ||
        uri.hasFragment ||
        !_isAllowedLocalHost(uri.host) ||
        (uri.hasPort && (uri.port < 1 || uri.port > 65535))) {
      throw const FormatException('URL locale de passerelle caméra invalide');
    }
    return Uri(
      scheme: uri.scheme,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
    );
  }

  static bool _isAllowedLocalHost(String host) {
    final normalized = host.toLowerCase();
    if (normalized == 'localhost' || normalized == '127.0.0.1') return true;
    if (normalized.endsWith('.local')) return true;
    final parts = normalized.split('.');
    if (parts.length != 4) return false;
    final octets = parts.map(int.tryParse).toList();
    if (octets.any((value) => value == null || value < 0 || value > 255)) {
      return false;
    }
    final first = octets[0]!;
    final second = octets[1]!;
    return first == 10 ||
        (first == 172 && second >= 16 && second <= 31) ||
        (first == 192 && second == 168);
  }

  static String _validatedToken(String value) {
    final token = value.trim();
    if (token.length < 32 || token.length > 512) {
      throw const FormatException('Jeton de passerelle caméra invalide');
    }
    return token;
  }

  static void _requireSuccess(
    http.Response response,
    String endpoint, {
    required int maximumBytes,
  }) {
    if (response.bodyBytes.length > maximumBytes) {
      throw FormatException('Réponse $endpoint trop volumineuse');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw CameraGatewayException(endpoint, response.statusCode);
    }
  }

  @override
  void close() {
    if (_ownsClient) _client.close();
  }
}

class CameraGatewayException implements Exception {
  final String endpoint;
  final int statusCode;

  const CameraGatewayException(this.endpoint, this.statusCode);

  @override
  String toString() => 'HTTP $statusCode sur $endpoint';
}
