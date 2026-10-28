import 'dart:convert';
import 'dart:developer' as developer;

import 'package:http/http.dart' as http;

import '../../domain/entities/sensor_reading.dart';

class SensorRepository {
  // The ESP32 scans its LittleFS history before streaming /readings. A full
  // 48-hour recovery took about 37 seconds on the real device.
  static const historyRequestTimeout = Duration(seconds: 90);

  final http.Client _client;
  final bool _ownsClient;
  Uri? _baseUri;
  SensorBatchDiagnostics? _lastBatchDiagnostics;

  SensorRepository({http.Client? client})
      : _client = client ?? http.Client(),
        _ownsClient = client == null;

  void configure(String ip, {int port = 80}) {
    final host = ip.trim();
    if (!_isValidHostInput(host) ||
        !_isAllowedLocalHost(host) ||
        port < 1 ||
        port > 65535) {
      _baseUri = null;
      return;
    }
    _baseUri = Uri.http(port == 80 ? host : '$host:$port', '');
  }

  bool get isConfigured => _baseUri != null;
  String? get baseUrl => _baseUri?.toString();
  SensorBatchDiagnostics? get lastBatchDiagnostics => _lastBatchDiagnostics;

  void clearConfiguration() {
    _baseUri = null;
    _lastBatchDiagnostics = null;
  }

  bool configureBaseUrl(String value) {
    final raw = value.trim();
    final withScheme = raw.contains('://') ? raw : 'http://$raw';
    final uri = Uri.tryParse(withScheme);
    if (uri == null ||
        !const {'http', 'https'}.contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        (uri.path.isNotEmpty && uri.path != '/') ||
        uri.hasQuery ||
        uri.hasFragment ||
        !_isAllowedLocalHost(uri.host) ||
        (uri.hasPort && (uri.port < 1 || uri.port > 65535))) {
      _baseUri = null;
      return false;
    }
    _baseUri = Uri(
      scheme: uri.scheme,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
    );
    return true;
  }

  bool _isValidHostInput(String host) {
    if (host.isEmpty) return false;
    if (host.contains('/') ||
        host.contains('?') ||
        host.contains('#') ||
        host.contains('@') ||
        host.contains(':')) {
      return false;
    }
    final parsedHost = Uri.tryParse('http://$host')?.host;
    return parsedHost != null && parsedHost.toLowerCase() == host.toLowerCase();
  }

  bool _isAllowedLocalHost(String host) {
    final normalized = host.toLowerCase();
    if (normalized == 'localhost' || normalized == '127.0.0.1') return true;
    if (normalized.endsWith('.local')) return true;
    final parts = normalized.split('.');
    if (parts.length != 4) return false;
    final octets = parts.map(int.tryParse).toList();
    if (octets.any((o) => o == null || o < 0 || o > 255)) return false;
    final a = octets[0]!;
    final b = octets[1]!;
    return a == 10 ||
        (a == 172 && b >= 16 && b <= 31) ||
        (a == 192 && b == 168);
  }

  Future<SensorReading> fetchStatus() async {
    final uri = _requireUri('/status');
    final response = await _client.get(
      uri,
      headers: const {'Accept': 'application/json'},
    ).timeout(const Duration(seconds: 5));
    if (response.statusCode != 200) {
      throw SensorApiException('/status', response.statusCode);
    }
    _ensureResponseSize(response, 256 * 1024, '/status');
    final body = jsonDecode(utf8.decode(response.bodyBytes));
    if (body is! Map) {
      throw const FormatException('La réponse /status doit être un objet JSON');
    }
    return SensorReading.fromJson(Map<String, dynamic>.from(body));
  }

  Future<List<SensorReading>> fetchReadings({required int since}) async {
    final uri = _requireUri(
      '/readings',
      queryParameters: {'since': since.toString()},
    );
    final response = await _client.get(
      uri,
      headers: const {'Accept': 'application/json'},
    ).timeout(historyRequestTimeout);
    if (response.statusCode == 404 || response.statusCode == 501) {
      throw const SensorHistoryUnavailableException();
    }
    if (response.statusCode != 200) {
      throw SensorApiException('/readings', response.statusCode);
    }
    _ensureResponseSize(response, 5 * 1024 * 1024, '/readings');

    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    final rawReadings = switch (decoded) {
      List<dynamic> values => values,
      Map<dynamic, dynamic> values when values['readings'] is List =>
        values['readings'] as List<dynamic>,
      Map<dynamic, dynamic> values => <dynamic>[values],
      _ => throw const FormatException(
          'La réponse /readings doit être une liste JSON',
        ),
    };

    final readings = <SensorReading>[];
    final reasons = <String, int>{};
    for (final raw in rawReadings) {
      if (raw is! Map) {
        reasons.update('entrée non objet', (count) => count + 1,
            ifAbsent: () => 1);
        continue;
      }
      try {
        readings.add(SensorReading.fromJson(Map<String, dynamic>.from(raw)));
      } catch (error) {
        final reason = error is FormatException
            ? error.message.toString()
            : error.runtimeType.toString();
        reasons.update(reason, (count) => count + 1, ifAbsent: () => 1);
      }
    }
    final rejected = reasons.values.fold<int>(0, (sum, count) => sum + count);
    _lastBatchDiagnostics = rejected == 0
        ? null
        : SensorBatchDiagnostics(
            accepted: readings.length,
            rejected: rejected,
            reasons: reasons,
          );
    if (_lastBatchDiagnostics case final diagnostics?) {
      developer.log(
        'Mesures ESP32 rejetées: ${diagnostics.rejected}; '
        'acceptées: ${diagnostics.accepted}',
        name: 'gardenjournal.sensors',
      );
      if (readings.isEmpty) throw SensorBatchFormatException(diagnostics);
    }
    readings.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return readings;
  }

  Future<bool> updateConfig(Map<String, dynamic> config) async {
    final uri = _requireUri('/config');
    final body = jsonEncode(config);
    if (utf8.encode(body).length > 64 * 1024) {
      throw const FormatException('Configuration ESP32 trop volumineuse');
    }
    final response = await _client
        .post(
          uri,
          headers: const {
            'Accept': 'application/json',
            'Content-Type': 'application/json',
          },
          body: body,
        )
        .timeout(const Duration(seconds: 5));
    _ensureResponseSize(response, 256 * 1024, '/config');
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw SensorApiException('/config', response.statusCode);
    }
    return true;
  }

  Future<Map<String, dynamic>> issueCommand(
    Map<String, Object?> command,
  ) {
    return _sendControlPayload('/commands', command);
  }

  Future<Map<String, dynamic>> syncSchedule(
    Map<String, Object?> schedule,
  ) {
    return _sendControlPayload('/schedules', schedule);
  }

  Future<Map<String, dynamic>> requestOta(Map<String, Object?> payload) {
    return _sendControlPayload('/ota', payload);
  }

  Future<Map<String, dynamic>> syncAutomationRule(
    Map<String, Object?> payload,
  ) {
    return _sendControlPayload('/rules', payload);
  }

  Future<Map<String, dynamic>> fetchOtaCapabilities({String? nodeId}) async {
    return _getJsonObject(
      '/ota/capabilities',
      queryParameters: nodeId == null ? null : {'nodeId': nodeId},
    );
  }

  Future<Map<String, dynamic>> fetchOtaStatus(
    String manifestId, {
    String? nodeId,
  }) async {
    return _getJsonObject(
      '/ota/status',
      queryParameters: {
        'manifestId': manifestId,
        if (nodeId != null) 'nodeId': nodeId,
      },
    );
  }

  Future<Map<String, dynamic>> _getJsonObject(
    String path, {
    Map<String, String>? queryParameters,
  }) async {
    final uri = _requireUri(path, queryParameters: queryParameters);
    final response = await _client.get(
      uri,
      headers: const {'Accept': 'application/json'},
    ).timeout(const Duration(seconds: 8));
    _ensureResponseSize(response, 256 * 1024, path);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw SensorApiException(path, response.statusCode);
    }
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map) throw FormatException('Réponse $path invalide');
    return Map<String, dynamic>.from(decoded);
  }

  Future<Map<String, dynamic>> _sendControlPayload(
    String path,
    Map<String, Object?> payload,
  ) async {
    final uri = _requireUri(path);
    final body = jsonEncode(payload);
    if (utf8.encode(body).length > 64 * 1024) {
      throw FormatException('Requête $path trop volumineuse');
    }
    final response = await _client
        .post(
          uri,
          headers: const {
            'Accept': 'application/json',
            'Content-Type': 'application/json',
          },
          body: body,
        )
        .timeout(const Duration(seconds: 8));
    _ensureResponseSize(response, 256 * 1024, path);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw SensorApiException(path, response.statusCode);
    }
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map) {
      throw FormatException('Accusé $path invalide');
    }
    return Map<String, dynamic>.from(decoded);
  }

  Future<bool> testConnection() async {
    try {
      await fetchStatus();
      return true;
    } catch (error, stackTrace) {
      developer.log(
        'Test ESP32 échoué',
        name: 'gardenjournal.sensors',
        error: error,
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  Future<SensorReading?> fetchLatest() async {
    try {
      return await fetchStatus();
    } catch (error, stackTrace) {
      developer.log(
        'Lecture ESP32 échouée',
        name: 'gardenjournal.sensors',
        error: error,
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  Future<bool> sendCommand(
    String cmd, {
    Map<String, dynamic>? params,
  }) {
    if (cmd == 'mist' && params?['state'] is bool) {
      return updateConfig({'mistOn': params!['state']});
    }
    throw const FormatException('Commande historique non autorisée');
  }

  Uri _requireUri(
    String path, {
    Map<String, String>? queryParameters,
  }) {
    final base = _baseUri;
    if (base == null) {
      throw StateError('ESP32 non configuré');
    }
    return base.replace(path: path, queryParameters: queryParameters);
  }

  void _ensureResponseSize(
    http.Response response,
    int maximumBytes,
    String endpoint,
  ) {
    if (response.bodyBytes.length > maximumBytes) {
      throw FormatException('Réponse $endpoint trop volumineuse');
    }
  }

  void close() {
    if (_ownsClient) _client.close();
  }
}

class SensorApiException implements Exception {
  final String endpoint;
  final int statusCode;

  const SensorApiException(this.endpoint, this.statusCode);

  @override
  String toString() => 'HTTP $statusCode sur $endpoint';
}

class SensorHistoryUnavailableException implements Exception {
  const SensorHistoryUnavailableException();

  @override
  String toString() => 'La route /readings n’est pas disponible';
}

class SensorBatchDiagnostics {
  final int accepted;
  final int rejected;
  final Map<String, int> reasons;

  const SensorBatchDiagnostics({
    required this.accepted,
    required this.rejected,
    required this.reasons,
  });
}

class SensorBatchFormatException implements Exception {
  final SensorBatchDiagnostics diagnostics;

  const SensorBatchFormatException(this.diagnostics);

  @override
  String toString() => '${diagnostics.rejected} mesure(s) ESP32 invalide(s)';
}
