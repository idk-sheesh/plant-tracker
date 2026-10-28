import 'dart:convert';

enum SensorValueType {
  number('number'),
  boolean('boolean'),
  text('text');

  final String wireValue;

  const SensorValueType(this.wireValue);

  static SensorValueType parse(Object? value) {
    return switch (value) {
      'number' || 'numeric' || 'float' || 'integer' => number,
      'boolean' || 'bool' => boolean,
      'text' || 'string' => text,
      _ => throw FormatException('Type de capacité inconnu: $value'),
    };
  }

  static SensorValueType infer(Object? value) {
    if (value is bool) return boolean;
    if (value is num && value.toDouble().isFinite) return number;
    if (value is String) return text;
    throw const FormatException('Valeur de mesure générique invalide');
  }
}

class DeviceCapability {
  final String deviceId;
  final String key;
  final String displayName;
  final SensorValueType valueType;
  final String? unit;
  final double? minimum;
  final double? maximum;
  final bool isWritable;
  final String metadataJson;
  final DateTime updatedAt;

  const DeviceCapability({
    required this.deviceId,
    required this.key,
    required this.displayName,
    required this.valueType,
    this.unit,
    this.minimum,
    this.maximum,
    this.isWritable = false,
    this.metadataJson = '{}',
    required this.updatedAt,
  });

  DeviceCapability copyWith({
    String? deviceId,
    String? key,
    String? displayName,
    SensorValueType? valueType,
    String? unit,
    double? minimum,
    double? maximum,
    bool? isWritable,
    String? metadataJson,
    DateTime? updatedAt,
  }) {
    return DeviceCapability(
      deviceId: deviceId ?? this.deviceId,
      key: key ?? this.key,
      displayName: displayName ?? this.displayName,
      valueType: valueType ?? this.valueType,
      unit: unit ?? this.unit,
      minimum: minimum ?? this.minimum,
      maximum: maximum ?? this.maximum,
      isWritable: isWritable ?? this.isWritable,
      metadataJson: metadataJson ?? this.metadataJson,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toMap() => {
        'device_id': deviceId,
        'capability_key': key,
        'display_name': displayName,
        'value_type': valueType.wireValue,
        'unit': unit,
        'minimum_value': minimum,
        'maximum_value': maximum,
        'is_writable': isWritable ? 1 : 0,
        'metadata_json': metadataJson,
        'updated_at': updatedAt.toUtc().toIso8601String(),
      };

  factory DeviceCapability.fromMap(Map<String, dynamic> map) {
    return DeviceCapability(
      deviceId: map['device_id'] as String,
      key: map['capability_key'] as String,
      displayName: map['display_name'] as String,
      valueType: SensorValueType.parse(map['value_type']),
      unit: map['unit'] as String?,
      minimum: (map['minimum_value'] as num?)?.toDouble(),
      maximum: (map['maximum_value'] as num?)?.toDouble(),
      isWritable: map['is_writable'] == 1,
      metadataJson: map['metadata_json'] as String? ?? '{}',
      updatedAt: DateTime.parse(map['updated_at'] as String).toLocal(),
    );
  }

  factory DeviceCapability.fromJson(
    Map<String, dynamic> json, {
    required String deviceId,
    String? fallbackKey,
    DateTime? now,
  }) {
    final key = validateCapabilityKey(
      json['key'] ?? json['capabilityKey'] ?? fallbackKey,
    );
    final rawType = json['valueType'] ?? json['value_type'] ?? json['type'];
    final valueType = SensorValueType.parse(rawType);
    final minimum = _finiteOptional(json['min'] ?? json['minimum']);
    final maximum = _finiteOptional(json['max'] ?? json['maximum']);
    if (minimum != null && maximum != null && minimum > maximum) {
      throw FormatException('Bornes invalides pour $key');
    }
    final displayName = _shortText(
          json['label'] ?? json['displayName'] ?? json['display_name'],
          maximumLength: 120,
        ) ??
        key;
    final unit = _shortText(json['unit'], maximumLength: 32);
    final writable = json['writable'] ?? json['isWritable'] ?? false;
    if (writable is! bool) {
      throw FormatException('writable doit être booléen pour $key');
    }
    final metadata = json['metadata'];
    final metadataJson = metadata == null ? '{}' : jsonEncode(metadata);
    if (metadataJson.length > 4096) {
      throw FormatException('Métadonnées trop volumineuses pour $key');
    }
    return DeviceCapability(
      deviceId: deviceId,
      key: key,
      displayName: displayName,
      valueType: valueType,
      unit: unit,
      minimum: minimum,
      maximum: maximum,
      isWritable: writable,
      metadataJson: metadataJson,
      updatedAt: now ?? DateTime.now(),
    );
  }

  factory DeviceCapability.inferred({
    required String deviceId,
    required String key,
    required SensorValueType valueType,
    String? unit,
    DateTime? now,
  }) {
    final validatedKey = validateCapabilityKey(key);
    return DeviceCapability(
      deviceId: deviceId,
      key: validatedKey,
      displayName: validatedKey,
      valueType: valueType,
      unit: _shortText(unit, maximumLength: 32),
      updatedAt: now ?? DateTime.now(),
    );
  }

  static List<DeviceCapability> parseCollection(
    Object? raw, {
    required String deviceId,
    DateTime? now,
  }) {
    if (raw == null) return const [];
    final result = <DeviceCapability>[];
    if (raw is List) {
      if (raw.length > 200) {
        throw const FormatException('Trop de capacités déclarées');
      }
      for (final item in raw) {
        if (item is! Map) {
          throw const FormatException('Capacité invalide');
        }
        result.add(DeviceCapability.fromJson(
          Map<String, dynamic>.from(item),
          deviceId: deviceId,
          now: now,
        ));
      }
    } else if (raw is Map) {
      if (raw.length > 200) {
        throw const FormatException('Trop de capacités déclarées');
      }
      for (final entry in raw.entries) {
        if (entry.value is! Map) {
          throw FormatException('Capacité invalide: ${entry.key}');
        }
        result.add(DeviceCapability.fromJson(
          Map<String, dynamic>.from(entry.value as Map),
          deviceId: deviceId,
          fallbackKey: entry.key.toString(),
          now: now,
        ));
      }
    } else {
      throw const FormatException(
          'capabilities doit être une liste ou un objet');
    }
    final keys = <String>{};
    for (final capability in result) {
      if (!keys.add(capability.key)) {
        throw FormatException('Capacité dupliquée: ${capability.key}');
      }
    }
    return result;
  }
}

String validateCapabilityKey(Object? value) {
  if (value is! String) {
    throw const FormatException('Clé de capacité obligatoire');
  }
  final key = value.trim();
  if (!RegExp(r'^[A-Za-z][A-Za-z0-9_.-]{0,79}$').hasMatch(key)) {
    throw FormatException('Clé de capacité invalide: $key');
  }
  return key;
}

double? _finiteOptional(Object? value) {
  if (value == null) return null;
  if (value is! num || !value.toDouble().isFinite) {
    throw const FormatException('Borne de capacité invalide');
  }
  return value.toDouble();
}

String? _shortText(Object? value, {required int maximumLength}) {
  if (value == null) return null;
  if (value is! String) throw const FormatException('Texte attendu');
  final normalized = value.trim();
  if (normalized.length > maximumLength) {
    throw const FormatException('Texte trop long');
  }
  return normalized.isEmpty ? null : normalized;
}
