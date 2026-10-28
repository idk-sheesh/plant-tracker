class SensorAlertRule {
  final String id;
  final String name;
  final String? zoneId;
  final String? deviceId;
  final String metricKey;
  final String comparison;
  final double? thresholdMin;
  final double? thresholdMax;
  final int durationSeconds;
  final double hysteresis;
  final int cooldownSeconds;
  final String severity;
  final bool isEnabled;
  final DateTime createdAt;
  final DateTime updatedAt;

  const SensorAlertRule({
    required this.id,
    required this.name,
    this.zoneId,
    this.deviceId,
    required this.metricKey,
    required this.comparison,
    this.thresholdMin,
    this.thresholdMax,
    this.durationSeconds = 0,
    this.hysteresis = 0,
    this.cooldownSeconds = 900,
    this.severity = 'warning',
    this.isEnabled = true,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'zone_id': zoneId,
        'device_id': deviceId,
        'metric_key': metricKey,
        'comparison': comparison,
        'threshold_min': thresholdMin,
        'threshold_max': thresholdMax,
        'duration_seconds': durationSeconds,
        'hysteresis': hysteresis,
        'cooldown_seconds': cooldownSeconds,
        'severity': severity,
        'is_enabled': isEnabled ? 1 : 0,
        'created_at': createdAt.toUtc().toIso8601String(),
        'updated_at': updatedAt.toUtc().toIso8601String(),
      };

  factory SensorAlertRule.fromMap(Map<String, dynamic> map) => SensorAlertRule(
        id: map['id'] as String,
        name: map['name'] as String,
        zoneId: map['zone_id'] as String?,
        deviceId: map['device_id'] as String?,
        metricKey: map['metric_key'] as String,
        comparison: map['comparison'] as String,
        thresholdMin: (map['threshold_min'] as num?)?.toDouble(),
        thresholdMax: (map['threshold_max'] as num?)?.toDouble(),
        durationSeconds: (map['duration_seconds'] as num?)?.toInt() ?? 0,
        hysteresis: (map['hysteresis'] as num?)?.toDouble() ?? 0,
        cooldownSeconds: (map['cooldown_seconds'] as num?)?.toInt() ?? 900,
        severity: map['severity'] as String? ?? 'warning',
        isEnabled: map['is_enabled'] == 1,
        createdAt: DateTime.parse(map['created_at'] as String).toLocal(),
        updatedAt: DateTime.parse(map['updated_at'] as String).toLocal(),
      );
}

class SensorAlertEvent {
  final String id;
  final String ruleId;
  final String? deviceId;
  final String? zoneId;
  final String metricKey;
  final String severity;
  final String message;
  final double? observedValue;
  final DateTime startedAt;
  final DateTime lastObservedAt;
  final DateTime? resolvedAt;
  final DateTime? acknowledgedAt;
  final DateTime? notificationSentAt;
  final DateTime createdAt;

  const SensorAlertEvent({
    required this.id,
    required this.ruleId,
    this.deviceId,
    this.zoneId,
    required this.metricKey,
    required this.severity,
    required this.message,
    this.observedValue,
    required this.startedAt,
    required this.lastObservedAt,
    this.resolvedAt,
    this.acknowledgedAt,
    this.notificationSentAt,
    required this.createdAt,
  });

  bool get isActive => resolvedAt == null;
  bool get isAcknowledged => acknowledgedAt != null;

  Map<String, Object?> toMap() => {
        'id': id,
        'rule_id': ruleId,
        'device_id': deviceId,
        'zone_id': zoneId,
        'metric_key': metricKey,
        'severity': severity,
        'message': message,
        'observed_value': observedValue,
        'started_at': _seconds(startedAt),
        'last_observed_at': _seconds(lastObservedAt),
        'resolved_at': resolvedAt == null ? null : _seconds(resolvedAt!),
        'acknowledged_at':
            acknowledgedAt == null ? null : _seconds(acknowledgedAt!),
        'notification_sent_at':
            notificationSentAt == null ? null : _seconds(notificationSentAt!),
        'created_at': createdAt.toUtc().toIso8601String(),
      };

  factory SensorAlertEvent.fromMap(Map<String, dynamic> map) {
    DateTime? date(Object? value) => value == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(
            (value as int) * 1000,
            isUtc: true,
          ).toLocal();
    return SensorAlertEvent(
      id: map['id'] as String,
      ruleId: map['rule_id'] as String,
      deviceId: map['device_id'] as String?,
      zoneId: map['zone_id'] as String?,
      metricKey: map['metric_key'] as String,
      severity: map['severity'] as String,
      message: map['message'] as String,
      observedValue: (map['observed_value'] as num?)?.toDouble(),
      startedAt: date(map['started_at'])!,
      lastObservedAt: date(map['last_observed_at'])!,
      resolvedAt: date(map['resolved_at']),
      acknowledgedAt: date(map['acknowledged_at']),
      notificationSentAt: date(map['notification_sent_at']),
      createdAt: DateTime.parse(map['created_at'] as String).toLocal(),
    );
  }

  static int _seconds(DateTime value) =>
      value.toUtc().millisecondsSinceEpoch ~/ 1000;
}
