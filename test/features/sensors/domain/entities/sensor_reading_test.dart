import 'package:flutter_test/flutter_test.dart';
import 'package:garden_journal/features/sensors/domain/entities/sensor_reading.dart';

void main() {
  test('convertit une mesure HTTP vers le schéma SQLite', () {
    final reading = SensorReading.fromJson({
      'deviceId': 'greenhouse-01',
      'timestamp': 1783947600,
      'temperature': 24.6,
      'humidity': 57.2,
      'vpd': 1.28,
      'mistOn': true,
      'fanPercent': 35,
    });

    final map = reading.toMap();

    expect(map['id'], 'greenhouse-01-1783947600');
    expect(map['device_id'], 'greenhouse-01');
    expect(map['measured_at'], 1783947600);
    expect(map['mist_on'], 1);
    expect(map['fan_percent'], 35);
  });

  test('calcule le VPD quand le champ est absent', () {
    final reading = SensorReading.fromJson({
      'deviceId': 'greenhouse-01',
      'timestamp': 1783947600,
      'temperature': 24.6,
      'humidity': 57.2,
      'mistOn': false,
    });

    expect(reading.vpd, closeTo(1.31, 0.02));
  });

  test('refuse timestamp invalide au lieu de le remplacer par maintenant', () {
    for (final timestamp in [null, 'invalide', 0, double.nan]) {
      expect(
        () => SensorReading.fromJson({
          'deviceId': 'greenhouse-01',
          'timestamp': timestamp,
          'temperature': 24.6,
          'humidity': 57.2,
        }),
        throwsFormatException,
      );
    }
  });

  test('refuse mesures non finies ou hors bornes', () {
    for (final values in [
      {'temperature': 100, 'humidity': 50, 'vpd': 1},
      {'temperature': 20, 'humidity': 101, 'vpd': 1},
      {'temperature': 20, 'humidity': 50, 'vpd': 11},
      {'temperature': double.infinity, 'humidity': 50, 'vpd': 1},
    ]) {
      expect(
        () => SensorReading.fromJson({
          'deviceId': 'greenhouse-01',
          'timestamp': 1783947600,
          ...values,
        }),
        throwsFormatException,
      );
    }
  });

  test('refuse identifiant vide, RSSI et ventilateur hors bornes', () {
    for (final extra in [
      {'deviceId': ''},
      {'deviceId': 'greenhouse-01', 'rssi': -200},
      {'deviceId': 'greenhouse-01', 'fanPercent': 101},
    ]) {
      expect(
        () => SensorReading.fromJson({
          'timestamp': 1783947600,
          'temperature': 24.6,
          'humidity': 57.2,
          ...extra,
        }),
        throwsFormatException,
      );
    }
  });
}
