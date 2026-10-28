import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/database/database_helper.dart';
import '../../domain/entities/sensor_alert.dart';

class AlertEvaluationResult {
  final SensorAlertEvent? openedEvent;
  final SensorAlertEvent? resolvedEvent;
  final bool shouldNotify;

  const AlertEvaluationResult({
    this.openedEvent,
    this.resolvedEvent,
    this.shouldNotify = false,
  });
}

class SensorAlertRepository {
  final DatabaseHelper _databaseHelper;
  final Database? _database;
  final Uuid _uuid;

  SensorAlertRepository({
    DatabaseHelper? databaseHelper,
    Database? database,
    Uuid uuid = const Uuid(),
  })  : _databaseHelper = databaseHelper ?? DatabaseHelper.instance,
        _database = database,
        _uuid = uuid;

  Future<Database> get _db async {
    if (_database != null) return _database;
    return _databaseHelper.database;
  }

  Future<void> saveRule(SensorAlertRule rule) async {
    _validateRule(rule);
    final db = await _db;
    await db.insert(
      'alert_rules',
      rule.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> deleteRule(String ruleId) async {
    final db = await _db;
    await db.delete('alert_rules', where: 'id = ?', whereArgs: [ruleId]);
  }

  Future<List<SensorAlertRule>> getRules({bool enabledOnly = false}) async {
    final db = await _db;
    final rows = await db.query(
      'alert_rules',
      where: enabledOnly ? 'is_enabled = 1' : null,
      orderBy: 'severity DESC, name COLLATE NOCASE ASC',
    );
    return rows.map(SensorAlertRule.fromMap).toList();
  }

  Future<List<SensorAlertRule>> getRulesForTarget({
    required String deviceId,
    String? zoneId,
  }) async {
    final db = await _db;
    final rows = await db.query(
      'alert_rules',
      where: zoneId == null
          ? 'is_enabled = 1 AND device_id = ?'
          : 'is_enabled = 1 AND (device_id = ? OR zone_id = ?)',
      whereArgs:
          zoneId == null ? <Object?>[deviceId] : <Object?>[deviceId, zoneId],
      orderBy: 'severity DESC, name COLLATE NOCASE ASC',
    );
    return rows.map(SensorAlertRule.fromMap).toList();
  }

  Future<List<SensorAlertEvent>> getEvents({
    bool activeOnly = false,
    int limit = 200,
  }) async {
    final db = await _db;
    final rows = await db.query(
      'alert_events',
      where: activeOnly ? 'resolved_at IS NULL' : null,
      orderBy: 'started_at DESC',
      limit: limit,
    );
    return rows.map(SensorAlertEvent.fromMap).toList();
  }

  Future<void> acknowledge(String eventId, DateTime at) async {
    final db = await _db;
    await db.update(
      'alert_events',
      {'acknowledged_at': _seconds(at)},
      where: 'id = ? AND acknowledged_at IS NULL',
      whereArgs: [eventId],
    );
  }

  Future<void> markNotificationSent(String eventId, DateTime at) async {
    final db = await _db;
    await db.update(
      'alert_events',
      {'notification_sent_at': _seconds(at)},
      where: 'id = ? AND notification_sent_at IS NULL',
      whereArgs: [eventId],
    );
  }

  /// Evaluates and persists one rule atomically. [conditionOverride] is used
  /// for stale-data rules; numeric rules derive their condition from [value].
  Future<AlertEvaluationResult> evaluate(
    SensorAlertRule rule, {
    double? value,
    bool? conditionOverride,
    required DateTime observedAt,
  }) async {
    _validateRule(rule);
    if (rule.comparison != 'stale' && (value == null || !value.isFinite)) {
      throw const FormatException('Valeur numérique requise pour cette alerte');
    }
    if (rule.comparison == 'stale' && conditionOverride == null) {
      throw const FormatException('État de fraîcheur requis');
    }
    final db = await _db;
    return db.transaction((txn) async {
      final stateRows = await txn.query(
        'alert_evaluation_states',
        where: 'rule_id = ?',
        whereArgs: [rule.id],
        limit: 1,
      );
      final activeRows = await txn.query(
        'alert_events',
        where: 'rule_id = ? AND resolved_at IS NULL',
        whereArgs: [rule.id],
        limit: 1,
      );
      final state = stateRows.isEmpty ? null : stateRows.single;
      final active = activeRows.isEmpty
          ? null
          : SensorAlertEvent.fromMap(activeRows.single);
      final wasViolating = active != null || state?['is_violating'] == 1;
      final violating = conditionOverride ??
          _isNumericViolation(rule, value!, continuing: wasViolating);
      final observedSeconds = _seconds(observedAt);

      if (!violating) {
        await txn.insert(
          'alert_evaluation_states',
          {
            'rule_id': rule.id,
            'first_violation_at': null,
            'last_evaluated_at': observedSeconds,
            'last_value': value,
            'is_violating': 0,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        if (active == null) return const AlertEvaluationResult();
        await txn.update(
          'alert_events',
          {
            'last_observed_at': observedSeconds,
            'observed_value': value,
            'resolved_at': observedSeconds,
          },
          where: 'id = ?',
          whereArgs: [active.id],
        );
        return AlertEvaluationResult(
          resolvedEvent: SensorAlertEvent(
            id: active.id,
            ruleId: active.ruleId,
            deviceId: active.deviceId,
            zoneId: active.zoneId,
            metricKey: active.metricKey,
            severity: active.severity,
            message: active.message,
            observedValue: value,
            startedAt: active.startedAt,
            lastObservedAt: observedAt,
            resolvedAt: observedAt,
            acknowledgedAt: active.acknowledgedAt,
            notificationSentAt: active.notificationSentAt,
            createdAt: active.createdAt,
          ),
        );
      }

      final firstViolationSeconds =
          state?['first_violation_at'] as int? ?? observedSeconds;
      await txn.insert(
        'alert_evaluation_states',
        {
          'rule_id': rule.id,
          'first_violation_at': firstViolationSeconds,
          'last_evaluated_at': observedSeconds,
          'last_value': value,
          'is_violating': 1,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      final message = _message(rule, value);
      if (active != null) {
        await txn.update(
          'alert_events',
          {
            'last_observed_at': observedSeconds,
            'observed_value': value,
            'message': message,
          },
          where: 'id = ?',
          whereArgs: [active.id],
        );
        return const AlertEvaluationResult();
      }
      if (observedSeconds - firstViolationSeconds < rule.durationSeconds) {
        return const AlertEvaluationResult();
      }

      final event = SensorAlertEvent(
        id: _uuid.v4(),
        ruleId: rule.id,
        deviceId: rule.deviceId,
        zoneId: rule.zoneId,
        metricKey: rule.metricKey,
        severity: rule.severity,
        message: message,
        observedValue: value,
        startedAt: DateTime.fromMillisecondsSinceEpoch(
          firstViolationSeconds * 1000,
          isUtc: true,
        ).toLocal(),
        lastObservedAt: observedAt,
        createdAt: observedAt,
      );
      final recentNotifications = await txn.query(
        'alert_events',
        columns: const ['notification_sent_at'],
        where: 'rule_id = ? AND notification_sent_at IS NOT NULL',
        whereArgs: [rule.id],
        orderBy: 'notification_sent_at DESC',
        limit: 1,
      );
      final lastNotification = recentNotifications.isEmpty
          ? null
          : recentNotifications.single['notification_sent_at'] as int?;
      final shouldNotify = lastNotification == null ||
          observedSeconds - lastNotification >= rule.cooldownSeconds;
      await txn.insert('alert_events', event.toMap());
      return AlertEvaluationResult(
        openedEvent: event,
        shouldNotify: shouldNotify,
      );
    });
  }

  static bool _isNumericViolation(
    SensorAlertRule rule,
    double value, {
    required bool continuing,
  }) {
    final hysteresis = continuing ? rule.hysteresis : 0.0;
    return switch (rule.comparison) {
      'gt' => value > rule.thresholdMax! - hysteresis,
      'lt' => value < rule.thresholdMin! + hysteresis,
      'outside' => value < rule.thresholdMin! + hysteresis ||
          value > rule.thresholdMax! - hysteresis,
      _ => throw const FormatException('Comparaison numérique invalide'),
    };
  }

  static String _message(SensorAlertRule rule, double? value) {
    if (rule.comparison == 'stale') return '${rule.name} : données absentes';
    return '${rule.name} : ${value!.toStringAsFixed(2)}';
  }

  static void _validateRule(SensorAlertRule rule) {
    if (rule.name.trim().isEmpty || rule.name.length > 120) {
      throw const FormatException('Nom d’alerte invalide');
    }
    if (rule.deviceId == null && rule.zoneId == null) {
      throw const FormatException('Une cible est obligatoire');
    }
    if (rule.metricKey.trim().isEmpty || rule.metricKey.length > 80) {
      throw const FormatException('Mesure d’alerte invalide');
    }
    if (!const {'gt', 'lt', 'outside', 'stale'}.contains(rule.comparison)) {
      throw const FormatException('Comparaison d’alerte invalide');
    }
    if (rule.comparison == 'gt' && rule.thresholdMax == null ||
        rule.comparison == 'lt' && rule.thresholdMin == null ||
        rule.comparison == 'outside' &&
            (rule.thresholdMin == null || rule.thresholdMax == null)) {
      throw const FormatException('Seuil d’alerte manquant');
    }
    if (rule.thresholdMin != null && !rule.thresholdMin!.isFinite ||
        rule.thresholdMax != null && !rule.thresholdMax!.isFinite ||
        rule.thresholdMin != null &&
            rule.thresholdMax != null &&
            rule.thresholdMin! >= rule.thresholdMax!) {
      throw const FormatException('Seuil d’alerte invalide');
    }
    if (rule.durationSeconds < 0 ||
        rule.cooldownSeconds < 0 ||
        !rule.hysteresis.isFinite ||
        rule.hysteresis < 0) {
      throw const FormatException('Temporisation d’alerte invalide');
    }
  }

  static int _seconds(DateTime value) =>
      value.toUtc().millisecondsSinceEpoch ~/ 1000;
}
