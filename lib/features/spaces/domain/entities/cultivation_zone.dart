import 'dart:convert';
import 'dart:developer' as developer;

import '../../../sensors/domain/entities/sensor_reading.dart';

enum CultivationZoneType { collection, cutting, nursery, main, storage, custom }

extension CultivationZoneTypeX on CultivationZoneType {
  String get value => name;

  String get label {
    switch (this) {
      case CultivationZoneType.collection:
        return 'Collection d’orchidées';
      case CultivationZoneType.cutting:
        return 'Boutures';
      case CultivationZoneType.nursery:
        return 'Pépinière';
      case CultivationZoneType.main:
        return 'Serre de tomates';
      case CultivationZoneType.storage:
        return 'Conservation';
      case CultivationZoneType.custom:
        return 'Personnalisée';
    }
  }

  static CultivationZoneType parse(String? value) {
    return CultivationZoneType.values.firstWhere(
      (type) => type.name == value,
      orElse: () => CultivationZoneType.custom,
    );
  }
}

class ClimateTargetProfile {
  final double? temperatureMin;
  final double? temperatureMax;
  final double? humidityMin;
  final double? humidityMax;
  final double? vpdMin;
  final double? vpdMax;

  const ClimateTargetProfile({
    this.temperatureMin,
    this.temperatureMax,
    this.humidityMin,
    this.humidityMax,
    this.vpdMin,
    this.vpdMax,
  });

  /// Les anciennes limites indépendantes restent décodées pour préserver les
  /// profils déjà enregistrés, mais la décision climatique suit désormais le
  /// tableau VPD température / humidité de référence.
  bool isOutside({
    required double temperature,
    required double humidity,
  }) {
    return VpdChart.classify(
      temperature: temperature,
      humidity: humidity,
    ).isDanger;
  }

  Map<String, dynamic> toJson() => {
        if (temperatureMin != null) 'temperatureMin': temperatureMin,
        if (temperatureMax != null) 'temperatureMax': temperatureMax,
        if (humidityMin != null) 'humidityMin': humidityMin,
        if (humidityMax != null) 'humidityMax': humidityMax,
        if (vpdMin != null) 'vpdMin': vpdMin,
        if (vpdMax != null) 'vpdMax': vpdMax,
      };

  factory ClimateTargetProfile.fromJson(Map<String, dynamic> json) {
    double? number(String key) => (json[key] as num?)?.toDouble();
    return ClimateTargetProfile(
      temperatureMin: number('temperatureMin'),
      temperatureMax: number('temperatureMax'),
      humidityMin: number('humidityMin'),
      humidityMax: number('humidityMax'),
      vpdMin: number('vpdMin'),
      vpdMax: number('vpdMax'),
    );
  }

  factory ClimateTargetProfile.decode(String? value) {
    if (value == null || value.isEmpty) return const ClimateTargetProfile();
    try {
      final decoded = jsonDecode(value);
      if (decoded is Map) {
        return ClimateTargetProfile.fromJson(
          Map<String, dynamic>.from(decoded),
        );
      }
    } catch (error, stackTrace) {
      developer.log(
        'Profil climatique local invalide, valeurs sûres appliquées',
        name: 'gardenjournal.spaces',
        error: error,
        stackTrace: stackTrace,
      );
    }
    return const ClimateTargetProfile();
  }

  String encode() => jsonEncode(toJson());
}

class CultivationZone {
  final String id;
  final String name;
  final CultivationZoneType type;
  final double? widthCm;
  final double? depthCm;
  final double? heightCm;
  final String? description;
  final ClimateTargetProfile targetProfile;
  final DateTime createdAt;
  final DateTime updatedAt;

  const CultivationZone({
    required this.id,
    required this.name,
    required this.type,
    this.widthCm,
    this.depthCm,
    this.heightCm,
    this.description,
    this.targetProfile = const ClimateTargetProfile(),
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isStorage => type == CultivationZoneType.storage;

  String get dimensionsLabel {
    if (widthCm == null || depthCm == null || heightCm == null) return '—';
    return '${widthCm!.toStringAsFixed(0)} × '
        '${depthCm!.toStringAsFixed(0)} × '
        '${heightCm!.toStringAsFixed(0)} cm';
  }

  CultivationZone copyWith({
    String? id,
    String? name,
    CultivationZoneType? type,
    double? widthCm,
    double? depthCm,
    double? heightCm,
    String? description,
    ClimateTargetProfile? targetProfile,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return CultivationZone(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      widthCm: widthCm ?? this.widthCm,
      depthCm: depthCm ?? this.depthCm,
      heightCm: heightCm ?? this.heightCm,
      description: description ?? this.description,
      targetProfile: targetProfile ?? this.targetProfile,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'type': type.value,
        'width_cm': widthCm,
        'depth_cm': depthCm,
        'height_cm': heightCm,
        'description': description,
        'target_profile': targetProfile.encode(),
        'created_at': createdAt.toUtc().toIso8601String(),
        'updated_at': updatedAt.toUtc().toIso8601String(),
      };

  factory CultivationZone.fromMap(Map<String, dynamic> map) {
    return CultivationZone(
      id: map['id'] as String,
      name: map['name'] as String,
      type: CultivationZoneTypeX.parse(map['type'] as String?),
      widthCm: (map['width_cm'] as num?)?.toDouble(),
      depthCm: (map['depth_cm'] as num?)?.toDouble(),
      heightCm: (map['height_cm'] as num?)?.toDouble(),
      description: map['description'] as String?,
      targetProfile:
          ClimateTargetProfile.decode(map['target_profile'] as String?),
      createdAt: DateTime.parse(map['created_at'] as String).toLocal(),
      updatedAt: DateTime.parse(map['updated_at'] as String).toLocal(),
    );
  }
}
