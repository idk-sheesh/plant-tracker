import 'dart:math' as math;

import '../../../sensors/domain/entities/sensor_reading.dart';
import 'cultivation_zone.dart';

class MetricSummary {
  final double average;
  final double median;
  final double minimum;
  final double maximum;

  const MetricSummary({
    required this.average,
    required this.median,
    required this.minimum,
    required this.maximum,
  });
}

class ClimateSummary {
  final MetricSummary temperature;
  final MetricSummary humidity;
  final MetricSummary vpd;
  final Duration outOfRangeDuration;
  final Duration longestExcursion;
  final Duration mistDuration;
  final double availabilityPercent;
  final double temperatureStdDev;
  final double humidityStdDev;
  final int sampleCount;

  const ClimateSummary({
    required this.temperature,
    required this.humidity,
    required this.vpd,
    required this.outOfRangeDuration,
    required this.longestExcursion,
    required this.mistDuration,
    required this.availabilityPercent,
    required this.temperatureStdDev,
    required this.humidityStdDev,
    required this.sampleCount,
  });

  factory ClimateSummary.empty() => const ClimateSummary(
        temperature:
            MetricSummary(average: 0, median: 0, minimum: 0, maximum: 0),
        humidity: MetricSummary(average: 0, median: 0, minimum: 0, maximum: 0),
        vpd: MetricSummary(average: 0, median: 0, minimum: 0, maximum: 0),
        outOfRangeDuration: Duration.zero,
        longestExcursion: Duration.zero,
        mistDuration: Duration.zero,
        availabilityPercent: 0,
        temperatureStdDev: 0,
        humidityStdDev: 0,
        sampleCount: 0,
      );

  factory ClimateSummary.calculate({
    required List<SensorReading> readings,
    required ClimateTargetProfile profile,
    required DateTime periodStart,
    DateTime? periodEnd,
    Duration expectedInterval = const Duration(minutes: 1),
  }) {
    final end = periodEnd ?? DateTime.now();
    final values = readings
        .where((reading) =>
            !reading.timestamp.isBefore(periodStart) &&
            !reading.timestamp.isAfter(end))
        .toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    if (values.isEmpty) return ClimateSummary.empty();

    MetricSummary metric(double Function(SensorReading) select) {
      final data = values.map(select).toList()..sort();
      final middle = data.length ~/ 2;
      final median = data.length.isOdd
          ? data[middle]
          : (data[middle - 1] + data[middle]) / 2;
      return MetricSummary(
        average: data.reduce((a, b) => a + b) / data.length,
        median: median,
        minimum: data.reduce(math.min),
        maximum: data.reduce(math.max),
      );
    }

    double stdDev(double Function(SensorReading) select) {
      final data = values.map(select).toList();
      final average = data.reduce((a, b) => a + b) / data.length;
      final variance = data
              .map((value) => math.pow(value - average, 2).toDouble())
              .reduce((a, b) => a + b) /
          data.length;
      return math.sqrt(variance);
    }

    var outOfRange = Duration.zero;
    var longest = Duration.zero;
    var currentExcursion = Duration.zero;
    var mist = Duration.zero;
    final maxCreditedGap = expectedInterval * 5;
    for (var index = 0; index < values.length; index++) {
      final current = values[index];
      var interval = expectedInterval;
      if (index + 1 < values.length) {
        final gap = values[index + 1].timestamp.difference(current.timestamp);
        if (!gap.isNegative)
          interval = gap > maxCreditedGap ? maxCreditedGap : gap;
      }
      final outside = profile.isOutside(
        temperature: current.temperature,
        humidity: current.humidity,
      );
      if (outside) {
        outOfRange += interval;
        currentExcursion += interval;
        if (currentExcursion > longest) longest = currentExcursion;
      } else {
        currentExcursion = Duration.zero;
      }
      if (current.mistOn) mist += interval;
    }

    final expectedSamples = math.max(
      1,
      end.difference(periodStart).inSeconds /
          math.max(1, expectedInterval.inSeconds),
    );
    final availability = math.min(100.0, values.length / expectedSamples * 100);

    return ClimateSummary(
      temperature: metric((reading) => reading.temperature),
      humidity: metric((reading) => reading.humidity),
      vpd: metric((reading) => reading.vpd),
      outOfRangeDuration: outOfRange,
      longestExcursion: longest,
      mistDuration: mist,
      availabilityPercent: availability,
      temperatureStdDev: stdDev((reading) => reading.temperature),
      humidityStdDev: stdDev((reading) => reading.humidity),
      sampleCount: values.length,
    );
  }
}
