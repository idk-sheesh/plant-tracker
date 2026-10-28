import 'device_capability.dart';

class SensorMeasurement {
  final String? id;
  final String deviceId;
  final String? zoneId;
  final String capabilityKey;
  final SensorValueType valueType;
  final double? numericValue;
  final String? textValue;
  final bool? booleanValue;
  final String? unit;
  final String? quality;
  final DateTime timestamp;
  final DateTime createdAt;

  const SensorMeasurement({
    this.id,
    required this.deviceId,
    this.zoneId,
    required this.capabilityKey,
    required this.valueType,
    this.numericValue,
    this.textValue,
    this.booleanValue,
    this.unit,
    this.quality,
    required this.timestamp,
    required this.createdAt,
  });

  int get timestampSeconds => timestamp.toUtc().millisecondsSinceEpoch ~/ 1000;
  String get persistenceId =>
      id ?? '$deviceId-$timestampSeconds-$capabilityKey';

  Object get value => switch (valueType) {
        SensorValueType.number => numericValue!,
        SensorValueType.boolean => booleanValue!,
        SensorValueType.text => textValue!,
      };

  String get displayValue {
    final formatted = switch (valueType) {
      SensorValueType.number => _formatNumber(numericValue!),
      SensorValueType.boolean => booleanValue! ? 'Oui' : 'Non',
      SensorValueType.text => textValue!,
    };
    return unit == null ? formatted : '$formatted $unit';
  }

  SensorMeasurement copyWith({
    String? id,
    String? deviceId,
    String? zoneId,
    String? capabilityKey,
    SensorValueType? valueType,
    double? numericValue,
    String? textValue,
    bool? booleanValue,
    String? unit,
    String? quality,
    DateTime? timestamp,
    DateTime? createdAt,
  }) {
    return SensorMeasurement(
      id: id ?? this.id,
      deviceId: deviceId ?? this.deviceId,
      zoneId: zoneId ?? this.zoneId,
      capabilityKey: capabilityKey ?? this.capabilityKey,
      valueType: valueType ?? this.valueType,
      numericValue: numericValue ?? this.numericValue,
      textValue: textValue ?? this.textValue,
      booleanValue: booleanValue ?? this.booleanValue,
      unit: unit ?? this.unit,
      quality: quality ?? this.quality,
      timestamp: timestamp ?? this.timestamp,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, Object?> toMap() => {
        'id': persistenceId,
        'device_id': deviceId,
        'zone_id': zoneId,
        'capability_key': capabilityKey,
        'measured_at': timestampSeconds,
        'value_type': valueType.wireValue,
        'numeric_value': numericValue,
        'text_value': textValue,
        'boolean_value': booleanValue == null ? null : (booleanValue! ? 1 : 0),
        'unit': unit,
        'quality': quality,
        'created_at': createdAt.toUtc().toIso8601String(),
      };

  factory SensorMeasurement.fromMap(Map<String, dynamic> map) {
    final valueType = SensorValueType.parse(map['value_type']);
    return SensorMeasurement(
      id: map['id'] as String,
      deviceId: map['device_id'] as String,
      zoneId: map['zone_id'] as String?,
      capabilityKey: map['capability_key'] as String,
      valueType: valueType,
      numericValue: (map['numeric_value'] as num?)?.toDouble(),
      textValue: map['text_value'] as String?,
      booleanValue:
          map['boolean_value'] == null ? null : map['boolean_value'] == 1,
      unit: map['unit'] as String?,
      quality: map['quality'] as String?,
      timestamp: DateTime.fromMillisecondsSinceEpoch(
        (map['measured_at'] as int) * 1000,
        isUtc: true,
      ).toLocal(),
      createdAt: DateTime.parse(map['created_at'] as String).toLocal(),
    );
  }

  factory SensorMeasurement.fromValue({
    required String deviceId,
    String? zoneId,
    required String key,
    required Object value,
    String? unit,
    String? quality,
    required DateTime timestamp,
    DateTime? createdAt,
  }) {
    final capabilityKey = validateCapabilityKey(key);
    final valueType = SensorValueType.infer(value);
    if (value is String && value.length > 500) {
      throw FormatException('Mesure texte trop longue: $capabilityKey');
    }
    final normalizedUnit = _optionalText(unit, 32, 'unit');
    final normalizedQuality = _optionalText(quality, 32, 'quality');
    return SensorMeasurement(
      deviceId: deviceId,
      zoneId: zoneId,
      capabilityKey: capabilityKey,
      valueType: valueType,
      numericValue: valueType == SensorValueType.number
          ? (value as num).toDouble()
          : null,
      textValue: valueType == SensorValueType.text ? value as String : null,
      booleanValue: valueType == SensorValueType.boolean ? value as bool : null,
      unit: normalizedUnit,
      quality: normalizedQuality,
      timestamp: timestamp,
      createdAt: createdAt ?? DateTime.now(),
    );
  }

  static List<SensorMeasurement> parseCollection(
    Object? raw, {
    required String deviceId,
    String? zoneId,
    required DateTime timestamp,
    DateTime? now,
  }) {
    if (raw == null) return const [];
    if (raw is! Map) {
      throw const FormatException('measurements doit être un objet');
    }
    if (raw.length > 200) {
      throw const FormatException('Trop de mesures génériques');
    }
    final result = <SensorMeasurement>[];
    for (final entry in raw.entries) {
      final key = entry.key.toString();
      var value = entry.value;
      String? unit;
      String? quality;
      if (value is Map) {
        final details = Map<String, dynamic>.from(value);
        value = details['value'];
        unit = _optionalTextValue(details['unit'], 32, 'unit');
        quality = _optionalTextValue(details['quality'], 32, 'quality');
      }
      if (value == null) continue;
      result.add(SensorMeasurement.fromValue(
        deviceId: deviceId,
        zoneId: zoneId,
        key: key,
        value: value,
        unit: unit,
        quality: quality,
        timestamp: timestamp,
        createdAt: now,
      ));
    }
    return result;
  }

  static String _formatNumber(double value) {
    if (value == value.roundToDouble()) return value.toStringAsFixed(0);
    return value
        .toStringAsFixed(2)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(
          RegExp(r'\.$'),
          '',
        );
  }
}

String? _optionalText(String? value, int maximumLength, String key) {
  if (value == null) return null;
  final normalized = value.trim();
  if (normalized.length > maximumLength) {
    throw FormatException('$key trop long');
  }
  return normalized.isEmpty ? null : normalized;
}

String? _optionalTextValue(Object? value, int maximumLength, String key) {
  if (value == null) return null;
  if (value is! String) throw FormatException('$key doit être du texte');
  return _optionalText(value, maximumLength, key);
}
