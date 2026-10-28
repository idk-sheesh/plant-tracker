import 'dart:developer' as developer;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../domain/entities/sensor_alert.dart';
import '../../domain/entities/sensor_device.dart';
import '../../domain/entities/sensor_reading.dart';
import '../repositories/sensor_alert_repository.dart';

abstract interface class SensorAlertNotifier {
  Future<void> show(SensorAlertEvent event);
}

class LocalSensorAlertNotifier implements SensorAlertNotifier {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _ready = false;

  static Future<void> init() async {
    if (_ready) return;
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );
    await _plugin.initialize(settings: settings);
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android?.requestNotificationsPermission();
    _ready = true;
  }

  @override
  Future<void> show(SensorAlertEvent event) async {
    await init();
    await _plugin.show(
      id: _notificationId(event.id),
      title: event.severity == 'critical'
          ? 'Alerte critique GardenJournal'
          : 'Alerte capteur GardenJournal',
      body: event.message,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          'sensor_alerts',
          'Alertes capteurs',
          channelDescription: 'Alertes persistantes des nœuds GardenJournal',
          importance:
              event.severity == 'critical' ? Importance.max : Importance.high,
          priority: event.severity == 'critical' ? Priority.max : Priority.high,
        ),
      ),
      payload: event.id,
    );
  }

  static int _notificationId(String value) {
    var hash = 0;
    for (final code in value.codeUnits) {
      hash = (hash * 31 + code) & 0x7fffffff;
    }
    return hash == 0 ? 1 : hash;
  }
}

class SensorAlertService {
  final SensorAlertRepository repository;
  final SensorAlertNotifier notifier;
  final DateTime Function() _clock;

  SensorAlertService({
    SensorAlertRepository? repository,
    SensorAlertNotifier? notifier,
    DateTime Function()? clock,
  })  : repository = repository ?? SensorAlertRepository(),
        notifier = notifier ?? LocalSensorAlertNotifier(),
        _clock = clock ?? DateTime.now;

  Future<void> evaluateReading(
    SensorDevice device,
    SensorReading reading,
  ) async {
    final rules = await repository.getRulesForTarget(
      deviceId: device.id,
      zoneId: device.zoneId,
    );
    for (final rule in rules) {
      if (rule.comparison == 'stale') {
        await _evaluate(rule, conditionOverride: false, at: reading.timestamp);
        continue;
      }
      final value = _valueFor(rule.metricKey, reading);
      if (value == null || !value.isFinite) continue;
      await _evaluate(rule, value: value, at: reading.timestamp);
    }
  }

  Future<void> evaluateOffline(SensorDevice device) async {
    final rules = await repository.getRulesForTarget(
      deviceId: device.id,
      zoneId: device.zoneId,
    );
    final now = _clock();
    for (final rule in rules.where((item) => item.comparison == 'stale')) {
      await _evaluate(rule, conditionOverride: true, at: now);
    }
  }

  Future<void> _evaluate(
    SensorAlertRule rule, {
    double? value,
    bool? conditionOverride,
    required DateTime at,
  }) async {
    final result = await repository.evaluate(
      rule,
      value: value,
      conditionOverride: conditionOverride,
      observedAt: at,
    );
    final event = result.openedEvent;
    if (event == null || !result.shouldNotify) return;
    try {
      await notifier.show(event);
      await repository.markNotificationSent(event.id, _clock());
    } catch (error, stackTrace) {
      developer.log(
        'Notification d’alerte non envoyée; l’événement reste persistant',
        name: 'gardenjournal.sensor_alerts',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  static double? _valueFor(String key, SensorReading reading) {
    switch (key) {
      case 'temperature':
      case 'temperature_c':
        return reading.temperature;
      case 'humidity':
      case 'humidity_percent':
        return reading.humidity;
      case 'vpd':
      case 'vpd_kpa':
        return reading.vpd;
      case 'dew_point_c':
        return reading.dewPoint;
      case 'fan_percent':
        return reading.fanPercent;
      case 'rssi':
        return reading.rssi?.toDouble();
    }
    for (final measurement in reading.measurements) {
      if (measurement.capabilityKey == key) return measurement.numericValue;
    }
    return null;
  }
}
