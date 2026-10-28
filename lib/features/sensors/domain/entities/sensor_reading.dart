import 'dart:math' as math;

import 'device_capability.dart';
import 'sensor_measurement.dart';

class SensorReading {
  final String? id;
  final String? remoteEventId;
  final int? sourceSequence;
  final String deviceId;
  final String? zoneId;
  final double temperature;
  final double humidity;
  final double vpd;
  final DateTime timestamp;
  final bool mistOn;
  final double? dewPoint;
  final double? fanPercent;
  final bool? lightOn;
  final String? stageName;
  final double? vpdTarget;
  final String? heure;
  final bool? waterLow;
  final int? rssi;
  final String? firmwareVersion;
  final DateTime? createdAt;
  final List<HistoryPoint> historique;
  final List<DeviceCapability> capabilities;
  final List<SensorMeasurement> measurements;

  const SensorReading({
    this.id,
    this.remoteEventId,
    this.sourceSequence,
    this.deviceId = '',
    this.zoneId,
    required this.temperature,
    required this.humidity,
    required this.vpd,
    required this.timestamp,
    required this.mistOn,
    this.dewPoint,
    this.fanPercent,
    this.lightOn,
    this.stageName,
    this.vpdTarget,
    this.heure,
    this.waterLow,
    this.rssi,
    this.firmwareVersion,
    this.createdAt,
    this.historique = const [],
    this.capabilities = const [],
    this.measurements = const [],
  });

  int get timestampSeconds => timestamp.toUtc().millisecondsSinceEpoch ~/ 1000;

  String get persistenceId =>
      id ?? remoteEventId ?? '$deviceId-$timestampSeconds';

  static double calculateVpd(double t, double h) {
    // FAO-56, saturation over liquid water at air temperature; result in kPa.
    final svp = 0.6108 * math.exp(17.27 * t / (t + 237.3));
    return svp * (1.0 - h / 100.0);
  }

  static double calculateDewPoint(double temperature, double humidity) {
    final safeHumidity = humidity.clamp(0.1, 100.0);
    final gamma = math.log(safeHumidity / 100) +
        (17.62 * temperature) / (243.12 + temperature);
    return 243.12 * gamma / (17.62 - gamma);
  }

  SensorReading copyWith({
    String? id,
    String? remoteEventId,
    int? sourceSequence,
    String? deviceId,
    String? zoneId,
    double? temperature,
    double? humidity,
    double? vpd,
    DateTime? timestamp,
    bool? mistOn,
    double? dewPoint,
    double? fanPercent,
    bool? lightOn,
    String? stageName,
    double? vpdTarget,
    String? heure,
    bool? waterLow,
    int? rssi,
    String? firmwareVersion,
    DateTime? createdAt,
    List<HistoryPoint>? historique,
    List<DeviceCapability>? capabilities,
    List<SensorMeasurement>? measurements,
  }) {
    return SensorReading(
      id: id ?? this.id,
      remoteEventId: remoteEventId ?? this.remoteEventId,
      sourceSequence: sourceSequence ?? this.sourceSequence,
      deviceId: deviceId ?? this.deviceId,
      zoneId: zoneId ?? this.zoneId,
      temperature: temperature ?? this.temperature,
      humidity: humidity ?? this.humidity,
      vpd: vpd ?? this.vpd,
      timestamp: timestamp ?? this.timestamp,
      mistOn: mistOn ?? this.mistOn,
      dewPoint: dewPoint ?? this.dewPoint,
      fanPercent: fanPercent ?? this.fanPercent,
      lightOn: lightOn ?? this.lightOn,
      stageName: stageName ?? this.stageName,
      vpdTarget: vpdTarget ?? this.vpdTarget,
      heure: heure ?? this.heure,
      waterLow: waterLow ?? this.waterLow,
      rssi: rssi ?? this.rssi,
      firmwareVersion: firmwareVersion ?? this.firmwareVersion,
      createdAt: createdAt ?? this.createdAt,
      historique: historique ?? this.historique,
      capabilities: capabilities ?? this.capabilities,
      measurements: measurements ?? this.measurements,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': persistenceId,
        'remote_event_id': remoteEventId,
        'source_sequence': sourceSequence,
        'device_id': deviceId,
        'zone_id': zoneId,
        'measured_at': timestampSeconds,
        'temperature_c': temperature,
        'humidity_percent': humidity,
        'vpd_kpa': vpd,
        'dew_point_c': dewPoint,
        'mist_on': mistOn ? 1 : 0,
        'fan_percent': fanPercent,
        'light_on': lightOn == null ? null : (lightOn! ? 1 : 0),
        'water_low': waterLow == null ? null : (waterLow! ? 1 : 0),
        'rssi': rssi,
        'created_at': (createdAt ?? DateTime.now()).toUtc().toIso8601String(),
      };

  factory SensorReading.fromMap(Map<String, dynamic> map) {
    final timestampSeconds = map['measured_at'] as int;
    return SensorReading(
      id: map['id'] as String,
      remoteEventId: map['remote_event_id'] as String?,
      sourceSequence: (map['source_sequence'] as num?)?.toInt(),
      deviceId: map['device_id'] as String,
      zoneId: map['zone_id'] as String?,
      temperature:
          ((map['temperature_c'] ?? map['temperature']) as num).toDouble(),
      humidity:
          ((map['humidity_percent'] ?? map['humidity']) as num).toDouble(),
      vpd: ((map['vpd_kpa'] ?? map['vpd']) as num).toDouble(),
      timestamp: DateTime.fromMillisecondsSinceEpoch(
        timestampSeconds * 1000,
        isUtc: true,
      ).toLocal(),
      mistOn: (map['mist_on'] as int? ?? 0) == 1,
      dewPoint: (map['dew_point_c'] as num?)?.toDouble(),
      fanPercent: (map['fan_percent'] as num?)?.toDouble(),
      lightOn: map['light_on'] == null ? null : map['light_on'] == 1,
      waterLow: map['water_low'] == null ? null : map['water_low'] == 1,
      rssi: (map['rssi'] as num?)?.toInt(),
      createdAt: map['created_at'] == null
          ? null
          : DateTime.parse(map['created_at'] as String).toLocal(),
    );
  }

  factory SensorReading.fromJson(
    Map<String, dynamic> json, {
    SensorValidationLimits limits = const SensorValidationLimits(),
    DateTime? now,
  }) {
    final temp = _requiredNumber(json, 'temperature');
    final hum = _requiredNumber(json, 'humidity');
    final receivedVpd =
        json['vpd'] != null ? _requiredNumber(json, 'vpd') : null;
    final vpd = calculateVpd(temp, hum);
    _validateRange(
        temp, 'temperature', limits.temperatureMin, limits.temperatureMax);
    _validateRange(hum, 'humidity', limits.humidityMin, limits.humidityMax);
    _validateRange(vpd, 'vpd', limits.vpdMin, limits.vpdMax);
    if (receivedVpd != null) {
      _validateRange(receivedVpd, 'vpd', limits.vpdMin, limits.vpdMax);
      if ((receivedVpd - vpd).abs() > 0.25) {
        throw const FormatException('VPD reçu incohérent avec température/HR');
      }
    }
    final deviceId = _requiredString(
      json['deviceId'] ?? json['device_id'],
      'deviceId',
      limits.maximumIdentifierLength,
    );
    final timestamp = _parseTimestamp(
      json['timestamp'],
      limits: limits,
      now: now ?? DateTime.now(),
    );
    final zoneId = _optionalString(
      json['zoneId'] ?? json['zone_id'],
      'zoneId',
      limits.maximumIdentifierLength,
    );
    final parsedAt = DateTime.now();
    final capabilities = DeviceCapability.parseCollection(
      json['capabilities'],
      deviceId: deviceId,
      now: parsedAt,
    );
    final measurements = SensorMeasurement.parseCollection(
      json['measurements'] ?? json['metrics'],
      deviceId: deviceId,
      zoneId: zoneId,
      timestamp: timestamp,
      now: parsedAt,
    ).toList();
    // /readings omits capability metadata to keep the ESP32 payload small.
    // Preserve its raw ADC sample in the existing generic measurement table.
    if (!measurements.any((item) => item.capabilityKey == 'light_adc_raw') &&
        json['lightRaw'] != null) {
      final raw = _requiredNumber(json, 'lightRaw');
      _validateRange(raw, 'lightRaw', 0, 4095);
      if (raw != raw.roundToDouble()) {
        throw const FormatException('lightRaw doit être entier');
      }
      measurements.add(SensorMeasurement.fromValue(
        deviceId: deviceId,
        zoneId: zoneId,
        key: 'light_adc_raw',
        value: raw,
        unit: 'ADC',
        quality: 'uncalibrated',
        timestamp: timestamp,
        createdAt: parsedAt,
      ));
    }
    final mist = _optionalBool(
      json['mistOn'] ?? json['mist'] ?? json['mist_on'],
      'mistOn',
    );
    // Firmware 0.3.3 always sent mistOn:false despite having no mist output.
    if (mist != null &&
        json['firmwareVersion'] != '0.3.3-sht40-light-wifi-diagnostics' &&
        !measurements.any((item) => item.capabilityKey == 'mist_state')) {
      measurements.add(SensorMeasurement.fromValue(
        deviceId: deviceId,
        zoneId: zoneId,
        key: 'mist_state',
        value: mist,
        timestamp: timestamp,
        createdAt: parsedAt,
      ));
    }
    final declaredTypes = {
      for (final capability in capabilities)
        capability.key: capability.valueType,
    };
    for (final measurement in measurements) {
      final declaredType = declaredTypes[measurement.capabilityKey];
      if (declaredType != null && declaredType != measurement.valueType) {
        throw FormatException(
          'Type incohérent pour ${measurement.capabilityKey}',
        );
      }
    }
    final hist = <HistoryPoint>[];
    final rawHistory = json['historique'];
    if (rawHistory is List) {
      for (final item in rawHistory) {
        if (item is! Map) {
          throw const FormatException('Point historique invalide');
        }
        final point = Map<String, dynamic>.from(item);
        final historyVpd = _requiredNumber(point, 'vpd');
        final historyTemp = _requiredNumber(point, 'temp');
        final historyHumidity = _requiredNumber(point, 'hum');
        _validateRange(
          historyVpd,
          'historique.vpd',
          limits.vpdMin,
          limits.vpdMax,
        );
        _validateRange(
          historyTemp,
          'historique.temp',
          limits.temperatureMin,
          limits.temperatureMax,
        );
        _validateRange(
          historyHumidity,
          'historique.hum',
          limits.humidityMin,
          limits.humidityMax,
        );
        hist.add(HistoryPoint(
          heure: _optionalString(point['t'], 'historique.t', 32) ?? '',
          vpd: historyVpd,
          temp: historyTemp,
          hum: historyHumidity,
        ));
      }
    }
    final dewPoint = json['dewPoint'] == null
        ? calculateDewPoint(temp, hum)
        : _requiredNumber(json, 'dewPoint');
    final fanPercent = _optionalNumber(json, 'fanPercent');
    final vpdTarget = _optionalNumber(json, 'vpdTarget');
    final rssiValue = _optionalNumber(json, 'rssi');
    _validateRange(
      dewPoint,
      'dewPoint',
      limits.dewPointMin,
      limits.dewPointMax,
    );
    if (fanPercent != null) {
      _validateRange(fanPercent, 'fanPercent', 0, 100);
    }
    if (vpdTarget != null) {
      _validateRange(vpdTarget, 'vpdTarget', limits.vpdMin, limits.vpdMax);
    }
    if (rssiValue != null) {
      _validateRange(rssiValue, 'rssi', limits.rssiMin, limits.rssiMax);
    }
    return SensorReading(
      id: _optionalString(json['id'], 'id', limits.maximumIdentifierLength),
      remoteEventId: _optionalString(
        json['eventId'] ?? json['remoteEventId'] ?? json['remote_event_id'],
        'eventId',
        limits.maximumIdentifierLength,
      ),
      sourceSequence: _optionalInteger(
        json['sequence'] ?? json['sourceSequence'] ?? json['source_sequence'],
        'sequence',
      ),
      deviceId: deviceId,
      zoneId: zoneId,
      temperature: temp,
      humidity: hum,
      vpd: vpd,
      timestamp: timestamp,
      mistOn: mist ?? false,
      dewPoint: dewPoint,
      fanPercent: fanPercent,
      lightOn: _optionalBool(json['lightOn'], 'lightOn') ??
          measurements
              .where((item) => item.capabilityKey == 'light_detected')
              .firstOrNull
              ?.booleanValue,
      stageName: _optionalString(json['mode'] ?? json['stage'], 'mode', 32),
      vpdTarget: vpdTarget,
      heure: _optionalString(json['heure'], 'heure', 32),
      waterLow: _optionalBool(json['waterLow'], 'waterLow'),
      rssi: rssiValue?.toInt(),
      firmwareVersion:
          _optionalString(json['firmwareVersion'], 'firmwareVersion', 80),
      createdAt: parsedAt,
      historique: hist,
      capabilities: capabilities,
      measurements: measurements,
    );
  }

  static DateTime _parseTimestamp(
    dynamic value, {
    required SensorValidationLimits limits,
    required DateTime now,
  }) {
    DateTime? parsed;
    if (value is num) {
      if (!value.toDouble().isFinite) {
        throw const FormatException('timestamp non fini');
      }
      final raw = value.toInt();
      if (raw <= 0) throw const FormatException('timestamp invalide');
      final milliseconds = raw > 100000000000 ? raw : raw * 1000;
      parsed = DateTime.fromMillisecondsSinceEpoch(
        milliseconds,
        isUtc: true,
      ).toLocal();
    }
    if (parsed == null && value is String && value.length <= 80) {
      final numeric = int.tryParse(value);
      if (numeric != null) {
        parsed = _parseTimestamp(numeric, limits: limits, now: now);
      } else {
        parsed = DateTime.tryParse(value)?.toLocal();
      }
    }
    if (parsed == null) throw const FormatException('timestamp invalide');
    final earliest = DateTime.fromMillisecondsSinceEpoch(
      limits.earliestTimestampSeconds * 1000,
      isUtc: true,
    ).toLocal();
    final latest = now.add(limits.maximumFutureSkew);
    if (parsed.isBefore(earliest) || parsed.isAfter(latest)) {
      throw const FormatException('timestamp hors limites');
    }
    return parsed;
  }

  static double _requiredNumber(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is! num || !value.toDouble().isFinite) {
      throw FormatException('$key doit être un nombre fini');
    }
    return value.toDouble();
  }

  static double? _optionalNumber(Map<String, dynamic> json, String key) {
    if (json[key] == null) return null;
    return _requiredNumber(json, key);
  }

  static int? _optionalInteger(Object? value, String key) {
    if (value == null) return null;
    if (value is! num || !value.toDouble().isFinite || value % 1 != 0) {
      throw FormatException('$key doit être un entier');
    }
    final result = value.toInt();
    if (result < 0) throw FormatException('$key doit être positif');
    return result;
  }

  static String _requiredString(
    Object? value,
    String key,
    int maximumLength,
  ) {
    final result = _optionalString(value, key, maximumLength);
    if (result == null || result.isEmpty) {
      throw FormatException('$key est obligatoire');
    }
    return result;
  }

  static String? _optionalString(
    Object? value,
    String key,
    int maximumLength,
  ) {
    if (value == null) return null;
    if (value is! String) throw FormatException('$key doit être du texte');
    final normalized = value.trim();
    if (normalized.length > maximumLength) {
      throw FormatException('$key est trop long');
    }
    return normalized;
  }

  static bool? _optionalBool(Object? value, String key) {
    if (value == null) return null;
    if (value is! bool) throw FormatException('$key doit être booléen');
    return value;
  }

  static void _validateRange(
    double value,
    String key,
    double minimum,
    double maximum,
  ) {
    if (!value.isFinite || value < minimum || value > maximum) {
      throw FormatException('$key hors limites [$minimum, $maximum]');
    }
  }
}

class SensorValidationLimits {
  final double temperatureMin;
  final double temperatureMax;
  final double humidityMin;
  final double humidityMax;
  final double vpdMin;
  final double vpdMax;
  final double dewPointMin;
  final double dewPointMax;
  final double rssiMin;
  final double rssiMax;
  final int maximumIdentifierLength;
  final int earliestTimestampSeconds;
  final Duration maximumFutureSkew;

  const SensorValidationLimits({
    this.temperatureMin = -50,
    this.temperatureMax = 80,
    this.humidityMin = 0,
    this.humidityMax = 100,
    this.vpdMin = 0,
    this.vpdMax = 10,
    this.dewPointMin = -80,
    this.dewPointMax = 80,
    this.rssiMin = -150,
    this.rssiMax = 0,
    this.maximumIdentifierLength = 80,
    this.earliestTimestampSeconds = 1577836800,
    this.maximumFutureSkew = const Duration(days: 1),
  });
}

class HistoryPoint {
  final String heure;
  final double vpd;
  final double temp;
  final double hum;

  const HistoryPoint({
    required this.heure,
    required this.vpd,
    required this.temp,
    required this.hum,
  });

  factory HistoryPoint.fromReading(SensorReading reading) {
    final local = reading.timestamp.toLocal();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return HistoryPoint(
      heure: '$hour:$minute',
      vpd: reading.vpd,
      temp: reading.temperature,
      hum: reading.humidity,
    );
  }
}

enum GrowStage { cutting, veg, flower }

extension GrowStageExt on GrowStage {
  String get label {
    switch (this) {
      case GrowStage.cutting:
        return 'Bouture';
      case GrowStage.veg:
        return 'Végétatif';
      case GrowStage.flower:
        return 'Floraison';
    }
  }

  String get apiValue {
    switch (this) {
      case GrowStage.cutting:
        return 'CUTTING';
      case GrowStage.veg:
        return 'VEG';
      case GrowStage.flower:
        return 'FLOWER';
    }
  }

  String get emoji {
    switch (this) {
      case GrowStage.cutting:
        return '🌱';
      case GrowStage.veg:
        return '🍃';
      case GrowStage.flower:
        return '🌸';
    }
  }

  double get vpdMin {
    switch (this) {
      case GrowStage.cutting:
        return 0.4;
      case GrowStage.veg:
        return 0.8;
      case GrowStage.flower:
        return 1.0;
    }
  }

  double get vpdMax {
    switch (this) {
      case GrowStage.cutting:
        return 0.8;
      case GrowStage.veg:
        return 1.2;
      case GrowStage.flower:
        return 1.5;
    }
  }

  double get vpdTarget => (vpdMin + vpdMax) / 2;

  static GrowStage fromEspName(String? name) {
    switch (name?.toUpperCase()) {
      case 'CUTTING':
        return GrowStage.cutting;
      case 'FLOWER':
        return GrowStage.flower;
      default:
        return GrowStage.veg;
    }
  }
}

/// Zone de couleur du tableau VPD de référence.
enum VpdChartBand {
  lowTranspiration,
  healthyTranspiration,
  highTranspiration,
  danger,
}

extension VpdChartBandExt on VpdChartBand {
  String get shortLabel {
    switch (this) {
      case VpdChartBand.lowTranspiration:
        return 'Faible transpiration';
      case VpdChartBand.healthyTranspiration:
        return 'Transpiration saine';
      case VpdChartBand.highTranspiration:
        return 'Forte transpiration';
      case VpdChartBand.danger:
        return 'Zone de danger';
    }
  }

  String get detail {
    switch (this) {
      case VpdChartBand.lowTranspiration:
        return 'Propagation / début végétatif';
      case VpdChartBand.healthyTranspiration:
        return 'Fin végétatif / début floraison';
      case VpdChartBand.highTranspiration:
        return 'Fin floraison';
      case VpdChartBand.danger:
        return 'Hors des zones de culture du tableau';
    }
  }

  bool get isDanger => this == VpdChartBand.danger;

  int get colorValue {
    switch (this) {
      case VpdChartBand.lowTranspiration:
        return 0xFF1976D2;
      case VpdChartBand.healthyTranspiration:
        return 0xFF7CB342;
      case VpdChartBand.highTranspiration:
        return 0xFFF9A825;
      case VpdChartBand.danger:
        return 0xFFD32F2F;
    }
  }
}

/// Classification historique par cases température / humidité.
/// Elle est indépendante du calcul numérique du VPD de l'air. La provenance
/// scientifique de ces seuils n'est pas établie ; les profils par espèce
/// doivent être validés séparément.
class VpdChart {
  static const _rows = <_VpdChartRow>[
    _VpdChartRow(60, 32, 24, 24),
    _VpdChartRow(62, 36, 24, 24),
    _VpdChartRow(64, 38, 24, 24),
    _VpdChartRow(66, 42, 24, 24),
    _VpdChartRow(66, 44, 24, 24),
    _VpdChartRow(68, 48, 28, 24),
    _VpdChartRow(70, 50, 30, 24),
    _VpdChartRow(70, 52, 34, 24),
    _VpdChartRow(72, 56, 38, 24),
    _VpdChartRow(74, 58, 42, 26),
    _VpdChartRow(74, 60, 44, 28),
    _VpdChartRow(76, 62, 46, 32),
    _VpdChartRow(76, 62, 50, 36),
    _VpdChartRow(78, 64, 50, 40),
    _VpdChartRow(78, 66, 54, 42),
    _VpdChartRow(78, 68, 56, 44),
    _VpdChartRow(80, 68, 58, 48),
    _VpdChartRow(80, 70, 60, 50),
    _VpdChartRow(80, 72, 62, 52),
    _VpdChartRow(82, 72, 64, 54),
    _VpdChartRow(82, 74, 64, 56),
  ];

  /// Classe le couple dans la case du tableau la plus proche.
  ///
  /// Le tableau couvre 15–35 °C, par pas de 1 °C, et 24–84 % HR, par pas de
  /// 2 %. Toute mesure en dehors de cette grille est traitée comme dangereuse
  /// afin de ne pas inventer une valeur absente de la référence.
  static VpdChartBand classify({
    required double temperature,
    required double humidity,
  }) {
    if (!temperature.isFinite ||
        !humidity.isFinite ||
        temperature < 15 ||
        temperature > 35 ||
        humidity < 24 ||
        humidity > 84) {
      return VpdChartBand.danger;
    }

    final row = _rows[temperature.round() - 15];
    final cellHumidity = (humidity / 2).round() * 2;
    if (cellHumidity >= row.lowDangerMinHumidity) {
      return VpdChartBand.danger;
    }
    if (cellHumidity >= row.lowTranspirationMinHumidity) {
      return VpdChartBand.lowTranspiration;
    }
    if (cellHumidity >= row.healthyMinHumidity) {
      return VpdChartBand.healthyTranspiration;
    }
    if (cellHumidity >= row.highTranspirationMinHumidity) {
      return VpdChartBand.highTranspiration;
    }
    return VpdChartBand.danger;
  }
}

class _VpdChartRow {
  final int lowDangerMinHumidity;
  final int lowTranspirationMinHumidity;
  final int healthyMinHumidity;
  final int highTranspirationMinHumidity;

  const _VpdChartRow(
    this.lowDangerMinHumidity,
    this.lowTranspirationMinHumidity,
    this.healthyMinHumidity,
    this.highTranspirationMinHumidity,
  );
}

enum VpdStatus { tooLow, ideal, tooHigh }

extension VpdStatusExt on VpdStatus {
  String get label {
    switch (this) {
      case VpdStatus.tooLow:
        return 'Trop bas';
      case VpdStatus.ideal:
        return 'Idéal ✓';
      case VpdStatus.tooHigh:
        return 'Trop élevé';
    }
  }

  int get colorValue {
    switch (this) {
      case VpdStatus.tooLow:
        return 0xFF1976D2;
      case VpdStatus.ideal:
        return 0xFF2E7D32;
      case VpdStatus.tooHigh:
        return 0xFFD32F2F;
    }
  }
}
