import 'package:flutter_test/flutter_test.dart';
import 'package:garden_journal/features/sensors/domain/entities/sensor_reading.dart';
import 'package:garden_journal/features/spaces/domain/entities/climate_summary.dart';
import 'package:garden_journal/features/spaces/domain/entities/cultivation_zone.dart';

void main() {
  test('calcule moyenne, disponibilité et durée hors plage', () {
    final start = DateTime.utc(2026, 7, 14, 10);
    final readings = [
      _reading(start, 24, 60, 1.0, false),
      _reading(start.add(const Duration(minutes: 1)), 30, 60, 1.0, true),
      _reading(start.add(const Duration(minutes: 2)), 31, 80, 1.8, true),
      _reading(start.add(const Duration(minutes: 3)), 24, 60, 1.0, false),
    ];

    final summary = ClimateSummary.calculate(
      readings: readings,
      profile: const ClimateTargetProfile(
        temperatureMin: 20,
        temperatureMax: 28,
        humidityMin: 50,
        humidityMax: 70,
        vpdMin: 0.8,
        vpdMax: 1.4,
      ),
      periodStart: start,
      periodEnd: start.add(const Duration(minutes: 4)),
    );

    expect(summary.temperature.average, 27.25);
    expect(summary.temperature.median, 27);
    expect(summary.temperature.minimum, 24);
    expect(summary.temperature.maximum, 31);
    expect(summary.outOfRangeDuration, const Duration(minutes: 1));
    expect(summary.longestExcursion, const Duration(minutes: 1));
    expect(summary.mistDuration, const Duration(minutes: 2));
    expect(summary.availabilityPercent, 100);
  });

  test('calcule la médiane paire et impaire de chaque mesure', () {
    final start = DateTime.utc(2026, 7, 14, 10);
    final even = ClimateSummary.calculate(
      readings: [
        _reading(start, 18, 40, 0.8, false),
        _reading(start.add(const Duration(minutes: 1)), 30, 80, 1.6, false),
      ],
      profile: const ClimateTargetProfile(),
      periodStart: start,
      periodEnd: start.add(const Duration(minutes: 2)),
    );
    final odd = ClimateSummary.calculate(
      readings: [
        _reading(start, 30, 80, 1.6, false),
        _reading(start.add(const Duration(minutes: 1)), 18, 40, 0.8, false),
        _reading(start.add(const Duration(minutes: 2)), 24, 60, 1.2, false),
      ],
      profile: const ClimateTargetProfile(),
      periodStart: start,
      periodEnd: start.add(const Duration(minutes: 3)),
    );

    expect(even.temperature.median, 24);
    expect(even.humidity.median, 60);
    expect(even.vpd.median, closeTo(1.2, 0.000001));
    expect(odd.temperature.median, 24);
    expect(odd.humidity.median, 60);
    expect(odd.vpd.median, closeTo(1.2, 0.000001));
  });

  test('classe le couple température humidité selon le tableau VPD', () {
    expect(
      VpdChart.classify(temperature: 24, humidity: 60),
      VpdChartBand.lowTranspiration,
    );
    expect(
      VpdChart.classify(temperature: 24, humidity: 50),
      VpdChartBand.healthyTranspiration,
    );
    expect(
      VpdChart.classify(temperature: 24, humidity: 40),
      VpdChartBand.highTranspiration,
    );
    expect(
      VpdChart.classify(temperature: 24, humidity: 24),
      VpdChartBand.danger,
    );
    expect(
      VpdChart.classify(temperature: 24, humidity: 90),
      VpdChartBand.danger,
    );
    expect(
      VpdChart.classify(temperature: 35, humidity: 54),
      VpdChartBand.danger,
    );
  });

  test('ignore les anciennes limites indépendantes du profil', () {
    const profile = ClimateTargetProfile(
      temperatureMin: 30,
      temperatureMax: 31,
      humidityMin: 10,
      humidityMax: 20,
      vpdMin: 2,
      vpdMax: 3,
    );

    expect(
      profile.isOutside(temperature: 24, humidity: 50),
      isFalse,
    );
  });
}

SensorReading _reading(
  DateTime timestamp,
  double temperature,
  double humidity,
  double vpd,
  bool mistOn,
) {
  return SensorReading(
    deviceId: 'greenhouse-01',
    zoneId: 'zone-main',
    temperature: temperature,
    humidity: humidity,
    vpd: vpd,
    timestamp: timestamp,
    mistOn: mistOn,
  );
}
