import 'sensor_reading.dart';

class CloudDeviceSummary {
  final String id;
  final String? name;
  final String? firmwareVersion;
  final DateTime? lastContactAt;

  const CloudDeviceSummary({
    required this.id,
    this.name,
    this.firmwareVersion,
    this.lastContactAt,
  });

  factory CloudDeviceSummary.fromJson(Map<String, dynamic> json) {
    final id = json['id'] ?? json['deviceId'] ?? json['device_id'];
    if (id is! String || id.trim().isEmpty) {
      throw const FormatException('Identifiant cloud absent');
    }
    return CloudDeviceSummary(
      id: id.trim(),
      name: _optionalString(json['name']),
      firmwareVersion: _optionalString(json['firmwareVersion']),
      lastContactAt:
          _parseDate(json['lastContactAt'] ?? json['last_contact_at']),
    );
  }
}

class CloudTelemetryPage {
  final String deviceId;
  final List<SensorReading> readings;
  final String? nextCursor;
  final DateTime? lastContactAt;

  const CloudTelemetryPage({
    required this.deviceId,
    required this.readings,
    this.nextCursor,
    this.lastContactAt,
  });
}

String? _optionalString(Object? value) {
  if (value == null) return null;
  if (value is! String) throw const FormatException('Texte cloud invalide');
  final normalized = value.trim();
  return normalized.isEmpty ? null : normalized;
}

DateTime? _parseDate(Object? value) {
  if (value == null) return null;
  if (value is num) {
    final raw = value.toInt();
    if (raw <= 0) throw const FormatException('Date cloud invalide');
    return DateTime.fromMillisecondsSinceEpoch(
      (raw > 100000000000 ? raw : raw * 1000),
      isUtc: true,
    ).toLocal();
  }
  if (value is String) {
    final parsed = DateTime.tryParse(value);
    if (parsed != null) return parsed.toLocal();
  }
  throw const FormatException('Date cloud invalide');
}
