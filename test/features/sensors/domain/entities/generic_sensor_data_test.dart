import 'package:flutter_test/flutter_test.dart';
import 'package:garden_journal/features/sensors/domain/entities/device_capability.dart';
import 'package:garden_journal/features/sensors/domain/entities/sensor_reading.dart';

void main() {
  test('parse capacités et mesures génériques sans modifier le relevé fixe',
      () {
    final reading = SensorReading.fromJson({
      'deviceId': 'greenhouse-01',
      'timestamp': 1783947600,
      'temperature': 24.6,
      'humidity': 57.2,
      'vpd': 1.28,
      'mistOn': true,
      'capabilities': {
        'water_ph': {
          'type': 'number',
          'label': 'pH eau',
          'unit': 'pH',
          'min': 0,
          'max': 14,
        },
        'pump_enabled': {
          'type': 'boolean',
          'label': 'Pompe',
          'writable': true,
        },
      },
      'measurements': {
        'water_ph': {'value': 6.2, 'unit': 'pH', 'quality': 'good'},
        'pump_enabled': true,
      },
    }, now: DateTime.utc(2026, 7, 19));

    expect(reading.temperature, 24.6);
    expect(reading.capabilities, hasLength(2));
    expect(reading.measurements, hasLength(3));
    expect(
      reading.measurements
          .singleWhere((item) => item.capabilityKey == 'mist_state')
          .booleanValue,
      isTrue,
    );
    expect(
      reading.capabilities.singleWhere((item) => item.key == 'pump_enabled'),
      isA<DeviceCapability>().having(
        (item) => item.isWritable,
        'écriture',
        isTrue,
      ),
    );
    expect(
      reading.measurements
          .singleWhere((item) => item.capabilityKey == 'water_ph')
          .displayValue,
      '6.2 pH',
    );
  });

  test('refuse un type déclaré incohérent avec la mesure', () {
    expect(
      () => SensorReading.fromJson({
        'deviceId': 'greenhouse-01',
        'timestamp': 1783947600,
        'temperature': 24.6,
        'humidity': 57.2,
        'capabilities': {
          'water_ph': {'type': 'boolean'},
        },
        'measurements': {'water_ph': 6.2},
      }, now: DateTime.utc(2026, 7, 19)),
      throwsFormatException,
    );
  });

  test('refuse clés, bornes et volumes non sûrs', () {
    expect(
      () => DeviceCapability.parseCollection({
        'water ph': {'type': 'number'},
      }, deviceId: 'greenhouse-01'),
      throwsFormatException,
    );
    expect(
      () => DeviceCapability.parseCollection({
        'water_ph': {'type': 'number', 'min': 14, 'max': 0},
      }, deviceId: 'greenhouse-01'),
      throwsFormatException,
    );
    expect(
      () => SensorReading.fromJson({
        'deviceId': 'greenhouse-01',
        'timestamp': 1783947600,
        'temperature': 24.6,
        'humidity': 57.2,
        'measurements': {
          for (var index = 0; index < 201; index++) 'metric_$index': index,
        },
      }, now: DateTime.utc(2026, 7, 19)),
      throwsFormatException,
    );
  });
}
