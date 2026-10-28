import 'package:flutter_test/flutter_test.dart';
import 'package:garden_journal/features/sensors/domain/entities/sensor_reading.dart';

void main() {
  // FAO-56 e°(T) in kPa. Reference calculations retain full precision.
  const cases = <(double, double, double, double)>[
    (-10, 95, 0.285710982, 0.014285549),
    (15, 80, 1.705346232, 0.341069246),
    (25, 50, 3.167777718, 1.583888859),
    (35, 25, 5.622681238, 4.217010929),
    (20, 99.5, 2.338281271, 0.011691406),
    (20, 0, 2.338281271, 2.338281271),
    (20, 100, 2.338281271, 0),
    (40, 5, 7.375613593, 7.006832913),
  ];

  test('VPD air : vecteurs numériques FAO-56', () {
    for (final (temperature, humidity, saturation, expected) in cases) {
      final actual = SensorReading.calculateVpd(temperature, humidity);
      expect(actual, closeTo(expected, 1e-8));
      expect(actual, closeTo(saturation * (1 - humidity / 100), 1e-8));
    }
  });

  test('ingestion recalcule le VPD reçu et conserve la lumière historique', () {
    final reading = SensorReading.fromJson({
      'deviceId': 'culture-ldr-01',
      'timestamp': 1783947600,
      'temperature': 25,
      'humidity': 50,
      'vpd': 1.584,
      'lightRaw': 3498,
      'lightOn': true,
      'mistOn': false,
    });
    expect(reading.vpd, closeTo(1.583888859, 1e-8));
    expect(reading.lightOn, isTrue);
    expect(
        reading.measurements
            .singleWhere((item) => item.capabilityKey == 'light_adc_raw')
            .numericValue,
        3498);
    expect(
        reading.measurements
            .singleWhere((item) => item.capabilityKey == 'mist_state')
            .booleanValue,
        isFalse);
    expect(
      () => SensorReading.fromJson({
        'deviceId': 'culture-ldr-01',
        'timestamp': 1783947600,
        'temperature': 25,
        'humidity': 50,
        'vpd': 2.0,
      }),
      throwsFormatException,
    );
  });

  test('ancien firmware sans actionneur ne crée pas de sortie brumisation', () {
    final reading = SensorReading.fromJson({
      'deviceId': 'culture-ldr-01',
      'timestamp': 1783947600,
      'temperature': 25,
      'humidity': 50,
      'mistOn': false,
      'firmwareVersion': '0.3.3-sht40-light-wifi-diagnostics',
    });
    expect(reading.measurements.where((m) => m.capabilityKey == 'mist_state'),
        isEmpty);
  });
}
