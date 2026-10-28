import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import '../../domain/entities/camera_snapshot.dart';
import '../../domain/entities/camera_status.dart';
import 'camera_gateway_repository.dart';

/// Optional capability: the client keeps its current snapshot only in memory.
abstract interface class EphemeralCameraClient implements CameraGatewayClient {
  void clearPhoto();
}

/// Private camera service behind the Pi's authenticated HTTPS entry point.
class PrivateCameraGatewayRepository implements EphemeralCameraClient {
  final http.Client _client;
  final bool _ownsClient;
  final Uri _baseUri;
  final String _token;
  final String zoneId;
  @override
  final String cameraId;
  Uint8List? _image;
  CameraSnapshot? _snapshot;
  Timer? _expiry;
  bool _closed = false;
  int _generation = 0;

  PrivateCameraGatewayRepository({
    required String baseUrl,
    required this.cameraId,
    required this.zoneId,
    required String appToken,
    http.Client? client,
  })  : _client = client ?? http.Client(),
        _ownsClient = client == null,
        _baseUri = validateUrl(baseUrl),
        _token = appToken.trim() {
    if (!RegExp(r'^cam-[A-Za-z0-9][A-Za-z0-9_-]{0,63}$').hasMatch(cameraId) ||
        zoneId.isEmpty ||
        _token.length < 32 ||
        _token.length > 512 ||
        RegExp(r'[\r\n]').hasMatch(_token)) {
      throw const FormatException('Configuration caméra privée invalide');
    }
  }

  static bool isPrivateHubUrl(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null || uri.scheme != 'https' || !_isDnsHost(uri.host)) {
      return false;
    }
    return uri.port == 443 || uri.host.toLowerCase().endsWith('.ts.net');
  }

  static bool _isDnsHost(String host) => RegExp(
        r'^[a-z0-9-]+(?:\.[a-z0-9-]+)*\.[a-z]{2,63}$',
      ).hasMatch(host.toLowerCase());

  static Uri validateUrl(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.userInfo.isNotEmpty ||
        !_isDnsHost(uri.host) ||
        (uri.path.isNotEmpty && uri.path != '/') ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.port != 443 &&
            !(uri.host.toLowerCase().endsWith('.ts.net') &&
                uri.port == 8443))) {
      throw const FormatException('Adresse HTTPS centrale invalide');
    }
    return uri.replace(path: '');
  }

  @override
  String get baseUrl => _baseUri.toString();

  Future<http.Response> _request(String method, String action,
      {required int maximumBytes}) async {
    if (_closed) throw StateError('Session caméra fermée');
    final request = http.Request(
        method, _baseUri.replace(path: '/api/private-camera/$cameraId/$action'))
      ..followRedirects = false
      ..headers.addAll({
        'Authorization': 'Bearer $_token',
        'Accept': action == 'capture' ? 'image/jpeg' : 'application/json'
      });
    final timeout = Duration(seconds: action == 'capture' ? 25 : 8);
    final response = await _client.send(request).timeout(timeout);
    if (response.statusCode != 200) {
      await response.stream.listen((_) {}).cancel();
      throw CameraGatewayException('/$action', response.statusCode);
    }
    if ((response.contentLength ?? 0) > maximumBytes) {
      await response.stream.listen((_) {}).cancel();
      throw const FormatException('Réponse caméra trop volumineuse');
    }
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in response.stream.timeout(timeout)) {
      if (_closed || bytes.length + chunk.length > maximumBytes) {
        throw const FormatException(
            'Réponse caméra interrompue ou trop volumineuse');
      }
      bytes.add(chunk);
    }
    return http.Response.bytes(bytes.takeBytes(), response.statusCode,
        headers: response.headers);
  }

  @override
  Future<CameraStatus> fetchStatus() async {
    final response = await _request('GET', 'status', maximumBytes: 4096);
    final data = jsonDecode(utf8.decode(response.bodyBytes));
    if (data is! Map ||
        !const {'ok', 'offline'}.contains(data['status']) ||
        (data['checked_at'] != null && data['checked_at'] is! num) ||
        data['image_retention_seconds'] != 0) {
      throw const FormatException('Réponse du hub privé invalide');
    }
    final seen = data['checked_at'] as num?;
    if (seen != null &&
        (!seen.isFinite ||
            seen < 0 ||
            seen > DateTime.now().millisecondsSinceEpoch / 1000 + 60)) {
      throw const FormatException('Date de contact invalide');
    }
    return CameraStatus(
        cameraId: cameraId,
        name: cameraId,
        zoneId: zoneId,
        status: data['status'] == 'ok' ? 'online' : 'offline',
        lastSeenAt: seen == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch((seen * 1000).round()),
        firmwareVersion: null,
        rssi: null,
        freeHeapBytes: null,
        uptimeSeconds: null,
        lastError: null,
        latestSnapshot: _snapshot);
  }

  @override
  Future<int> requestCapture() async {
    clearPhoto();
    final generation = _generation;
    final response =
        await _request('POST', 'capture', maximumBytes: 2 * 1024 * 1024);
    final bytes = response.bodyBytes;
    if (_closed || generation != _generation)
      throw StateError('Capture annulée');
    if (response.headers['content-type']?.split(';').first.trim() !=
            'image/jpeg' ||
        bytes.length < 4 ||
        bytes[0] != 0xff ||
        bytes[1] != 0xd8 ||
        bytes[bytes.length - 2] != 0xff ||
        bytes.last != 0xd9) {
      throw const FormatException('Photo caméra invalide');
    }
    final now = DateTime.now();
    final id = now.microsecondsSinceEpoch;
    _image = Uint8List.fromList(bytes);
    _snapshot = CameraSnapshot(
        id: 'private_$id',
        deviceId: cameraId,
        zoneId: zoneId,
        capturedAt: now,
        createdAt: now,
        sha256: sha256.convert(bytes).toString(),
        sizeBytes: bytes.length);
    _expiry = Timer(const Duration(seconds: 60), clearPhoto);
    return id;
  }

  @override
  Future<Uint8List> fetchLatestPhoto(CameraSnapshot snapshot) async {
    if (_closed || _image == null || snapshot.id != _snapshot?.id) {
      throw const FormatException(
          'Aperçu expiré : demandez une nouvelle photo');
    }
    return Uint8List.fromList(_image!);
  }

  @override
  void clearPhoto() {
    _generation++;
    _expiry?.cancel();
    _expiry = null;
    _image?.fillRange(0, _image!.length, 0);
    _image = null;
    _snapshot = null;
  }

  @override
  void close() {
    _closed = true;
    clearPhoto();
    if (_ownsClient) _client.close();
  }
}
