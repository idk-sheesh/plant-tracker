import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../domain/entities/cloud_telemetry.dart';
import '../../domain/entities/sensor_reading.dart';

class CloudSensorRepository {
  final http.Client _client;
  final bool _ownsClient;
  final Uri _baseUri;
  final String _accessToken;

  CloudSensorRepository({
    required Uri baseUri,
    required String accessToken,
    http.Client? client,
  })  : _client = client ?? http.Client(),
        _ownsClient = client == null,
        _baseUri = _validateBaseUri(baseUri),
        _accessToken = _validateToken(accessToken);

  Future<List<CloudDeviceSummary>> fetchDevices() async {
    final decoded = await _getJson('/api/v1/devices');
    final rawDevices = decoded is List
        ? decoded
        : decoded is Map && decoded['devices'] is List
            ? decoded['devices'] as List
            : throw const FormatException('Réponse /api/v1/devices invalide');
    return rawDevices
        .whereType<Map>()
        .map((item) => CloudDeviceSummary.fromJson(
              Map<String, dynamic>.from(item),
            ))
        .toList(growable: false);
  }

  Future<CloudAccount> fetchAccount() async {
    final decoded = await _getJson('/api/v1/me');
    if (decoded is! Map ||
        decoded['id'] is! String ||
        decoded['username'] is! String) {
      throw const FormatException('Identité du compte cloud invalide');
    }
    return CloudAccount(
      id: decoded['id'] as String,
      username: decoded['username'] as String,
    );
  }

  Future<void> logout() async {
    await _postJson('/api/v1/auth/logout', const {});
  }

  Future<DateTime> publishBusinessSnapshot(
      Map<String, dynamic> snapshot) async {
    final encoded = utf8.encode(jsonEncode(snapshot));
    if (encoded.length > 2 * 1024 * 1024) {
      throw const FormatException(
          'Journal trop volumineux pour cette version de l’API');
    }
    final decoded = await _postJson('/api/v1/sync/snapshot', snapshot);
    if (decoded is! Map || decoded['publishedAt'] is! String) {
      throw const FormatException('Accusé de publication invalide');
    }
    final publishedAt = DateTime.tryParse(decoded['publishedAt'] as String);
    if (publishedAt == null) {
      throw const FormatException('Date de publication invalide');
    }
    return publishedAt;
  }

  Future<CloudProvisionedDevice> createDevice({
    String? name,
    String? firmwareVersion,
  }) async {
    final decoded = await _postJson('/api/v1/devices', {
      if (name != null && name.trim().isNotEmpty) 'name': name.trim(),
      if (firmwareVersion != null && firmwareVersion.trim().isNotEmpty)
        'firmwareVersion': firmwareVersion.trim(),
    });
    if (decoded is! Map || decoded['deviceToken'] is! String) {
      throw const FormatException('Provisionnement cloud invalide');
    }
    final rawDevice = decoded['device'];
    if (rawDevice is! Map) {
      throw const FormatException('Appareil cloud absent');
    }
    return CloudProvisionedDevice(
      device: CloudDeviceSummary.fromJson(
        Map<String, dynamic>.from(rawDevice),
      ),
      deviceToken: (decoded['deviceToken'] as String).trim(),
    );
  }

  Future<CloudProvisionedDevice> rotateDeviceToken(String deviceId) async {
    final decoded = await _postJson(
      '/api/v1/devices/${_encodePathSegment(deviceId)}/rotate-token',
      const {},
    );
    if (decoded is! Map || decoded['deviceToken'] is! String) {
      throw const FormatException('Rotation du token cloud invalide');
    }
    final devices = await fetchDevices();
    final device = devices.where((item) => item.id == deviceId);
    if (device.isEmpty) throw const FormatException('Appareil cloud absent');
    return CloudProvisionedDevice(
      device: device.first,
      deviceToken: (decoded['deviceToken'] as String).trim(),
    );
  }

  Future<void> revokeDevice(String deviceId) async {
    await _postJson(
      '/api/v1/devices/${_encodePathSegment(deviceId)}/revoke',
      const {},
    );
  }

  Future<CloudTelemetryPage> fetchReadings(
    String deviceId, {
    int since = 0,
    String? cursor,
  }) async {
    final decoded = await _getJson(
      '/api/v1/devices/${_encodePathSegment(deviceId)}/readings',
      queryParameters: {
        if ((cursor == null || cursor.isEmpty) && since > 0)
          'since': since.toString(),
        if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
      },
    );
    return _parseTelemetryPage(decoded, expectedDeviceId: deviceId);
  }

  Future<SensorReading> fetchLatest(String deviceId) async {
    final decoded = await _getJson(
      '/api/v1/devices/${_encodePathSegment(deviceId)}/latest',
    );
    final raw = decoded is Map && decoded['reading'] is Map
        ? decoded['reading']
        : decoded;
    if (raw is! Map) throw const FormatException('Réponse latest invalide');
    return SensorReading.fromJson(Map<String, dynamic>.from(raw));
  }

  /// Envoie explicitement l'historique local déjà présent dans l'application.
  ///
  /// L'API limite les lots à 100 mesures. Les séquences générées à partir du
  /// timestamp sont réservées au rattrapage applicatif côté serveur : elles ne
  /// font pas avancer l'acknowledgement de la file ESP32.
  Future<CloudBackfillResult> uploadHistoricalReadings(
    String deviceId,
    Iterable<SensorReading> sourceReadings,
  ) async {
    final readings = sourceReadings.toList(growable: false);
    if (readings.isEmpty) return const CloudBackfillResult.empty();

    var accepted = 0;
    var rejected = 0;
    var batches = 0;
    for (var offset = 0; offset < readings.length; offset += 100) {
      final end =
          offset + 100 < readings.length ? offset + 100 : readings.length;
      final batch = readings.sublist(offset, end);
      final payload = <String, dynamic>{
        'schemaVersion': 1,
        'deviceId': deviceId,
        'readings': [
          for (final reading in batch)
            {
              'deviceId': deviceId,
              'eventId': _backfillEventId(reading),
              'sequence': _backfillSequence(reading),
              'measuredAt': reading.timestamp.toUtc().toIso8601String(),
              'temperatureC': reading.temperature,
              'humidityPercent': reading.humidity,
              'vpdKpa': reading.vpd,
            },
        ],
      };
      final decoded = await _postJson(
        '/api/v1/devices/${_encodePathSegment(deviceId)}/backfill',
        payload,
      );
      if (decoded is! Map) {
        throw const FormatException('RÃ©ponse backfill invalide');
      }
      final acceptedIds = decoded['acceptedEventIds'];
      final rejectedItems = decoded['rejected'];
      accepted += acceptedIds is List ? acceptedIds.length : 0;
      rejected += rejectedItems is List ? rejectedItems.length : 0;
      batches++;
    }
    return CloudBackfillResult(
      accepted: accepted,
      rejected: rejected,
      batches: batches,
    );
  }

  CloudTelemetryPage _parseTelemetryPage(
    Object? decoded, {
    required String expectedDeviceId,
  }) {
    final rawReadings = decoded is List
        ? decoded
        : decoded is Map && decoded['readings'] is List
            ? decoded['readings'] as List
            : decoded is Map
                ? <Object?>[decoded]
                : throw const FormatException('Réponse readings invalide');
    final readings = <SensorReading>[];
    for (final raw in rawReadings) {
      if (raw is! Map) throw const FormatException('Mesure cloud invalide');
      final reading = SensorReading.fromJson(
        Map<String, dynamic>.from(raw),
      );
      if (reading.deviceId != expectedDeviceId) {
        throw FormatException(
          'deviceId cloud inattendu (${reading.deviceId})',
        );
      }
      readings.add(reading);
    }
    final metadata = decoded is Map ? decoded : const <String, dynamic>{};
    return CloudTelemetryPage(
      deviceId: expectedDeviceId,
      readings: readings,
      nextCursor: _optionalString(
        metadata['nextCursor'] ?? metadata['next_cursor'],
      ),
      lastContactAt: _parseDateOrNull(
        metadata['lastContactAt'] ?? metadata['last_contact_at'],
      ),
    );
  }

  Future<Object?> _getJson(
    String path, {
    Map<String, String>? queryParameters,
  }) async {
    final uri = _endpoint(path, queryParameters: queryParameters);
    final response = await _client.get(uri, headers: _headers).timeout(
          const Duration(seconds: 10),
        );
    _ensureResponseSize(response, 5 * 1024 * 1024, path);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw CloudApiException(path, response.statusCode);
    }
    try {
      return jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      throw FormatException('JSON cloud invalide sur $path');
    }
  }

  Future<Object?> _postJson(String path, Map<String, dynamic> payload) async {
    final uri = _endpoint(path);
    final response = await _client
        .post(
          uri,
          headers: {
            ..._headers,
            'Content-Type': 'application/json; charset=utf-8',
          },
          body: jsonEncode(payload),
        )
        .timeout(const Duration(seconds: 15));
    _ensureResponseSize(response, 1024 * 1024, path);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw CloudApiException(path, response.statusCode);
    }
    try {
      return jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      throw FormatException('JSON cloud invalide sur $path');
    }
  }

  Uri _endpoint(
    String path, {
    Map<String, String>? queryParameters,
  }) {
    final basePath = _baseUri.path.endsWith('/')
        ? _baseUri.path.substring(0, _baseUri.path.length - 1)
        : _baseUri.path;
    return _baseUri.replace(
      path: '$basePath$path',
      queryParameters: queryParameters,
    );
  }

  Map<String, String> get _headers => {
        'Accept': 'application/json',
        'Authorization': 'Bearer $_accessToken',
      };

  static Uri _validateBaseUri(Uri uri) {
    if (uri.scheme != 'https' || uri.host.isEmpty || uri.userInfo.isNotEmpty) {
      throw ArgumentError.value(
        uri,
        'baseUri',
        'L’API cloud doit utiliser HTTPS sans identifiants embarqués',
      );
    }
    return uri.replace(query: null, fragment: null);
  }

  static String _validateToken(String token) {
    final normalized = token.trim();
    if (normalized.isEmpty || normalized.length > 4096) {
      throw const FormatException('Token cloud invalide');
    }
    return normalized;
  }

  static String _encodePathSegment(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty || normalized.length > 80) {
      throw ArgumentError.value(
          value, 'deviceId', 'Identifiant cloud invalide');
    }
    return Uri.encodeComponent(normalized);
  }

  static String _backfillEventId(SensorReading reading) {
    final source = reading.remoteEventId ?? 'backfill-${reading.persistenceId}';
    final sanitized = source.replaceAll(RegExp(r'[^A-Za-z0-9_.:-]'), '_');
    final normalized =
        sanitized.isEmpty ? 'backfill-${reading.timestampSeconds}' : sanitized;
    return normalized.length <= 128 ? normalized : normalized.substring(0, 128);
  }

  static int _backfillSequence(SensorReading reading) {
    final sequence = reading.sourceSequence ?? reading.timestampSeconds;
    if (sequence <= 0) {
      throw const FormatException('Séquence historique invalide');
    }
    return sequence;
  }

  static String? _optionalString(Object? value) {
    if (value == null) return null;
    if (value is! String) throw const FormatException('Curseur cloud invalide');
    final normalized = value.trim();
    return normalized.isEmpty ? null : normalized;
  }

  static DateTime? _parseDateOrNull(Object? value) {
    if (value == null) return null;
    if (value is num) {
      final raw = value.toInt();
      if (raw <= 0) throw const FormatException('Date cloud invalide');
      return DateTime.fromMillisecondsSinceEpoch(
        raw > 100000000000 ? raw : raw * 1000,
        isUtc: true,
      ).toLocal();
    }
    if (value is String) {
      final parsed = DateTime.tryParse(value);
      if (parsed != null) return parsed.toLocal();
    }
    throw const FormatException('Date cloud invalide');
  }

  static void _ensureResponseSize(
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

class CloudApiException implements Exception {
  final String endpoint;
  final int statusCode;

  const CloudApiException(this.endpoint, this.statusCode);

  @override
  String toString() => 'HTTP $statusCode sur API cloud $endpoint';
}

class CloudProvisionedDevice {
  final CloudDeviceSummary device;
  final String deviceToken;

  const CloudProvisionedDevice({
    required this.device,
    required this.deviceToken,
  });
}

class CloudAccount {
  final String id;
  final String username;

  const CloudAccount({required this.id, required this.username});
}

class CloudBackfillResult {
  final int accepted;
  final int rejected;
  final int batches;

  const CloudBackfillResult({
    required this.accepted,
    required this.rejected,
    required this.batches,
  });

  const CloudBackfillResult.empty()
      : accepted = 0,
        rejected = 0,
        batches = 0;
}
