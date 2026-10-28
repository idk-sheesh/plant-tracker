import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../domain/entities/sensor_measurement.dart';
import '../../domain/entities/sensor_reading.dart';
import '../providers/sensor_provider.dart';

class SensorComparisonScreen extends StatefulWidget {
  final String zoneId;
  final String zoneName;
  final SensorProvider sensors;

  const SensorComparisonScreen({
    super.key,
    required this.zoneId,
    required this.zoneName,
    required this.sensors,
  });

  @override
  State<SensorComparisonScreen> createState() => _SensorComparisonScreenState();
}

class _SensorComparisonScreenState extends State<SensorComparisonScreen> {
  Duration _period = const Duration(hours: 24);
  late Future<List<_MetricSeries>> _series;
  final Set<String> _selected = {
    'temperature_c',
    'humidity_percent',
    'vpd_kpa',
  };

  @override
  void initState() {
    super.initState();
    _series = _load();
  }

  @override
  void didUpdateWidget(covariant SensorComparisonScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.zoneId != widget.zoneId ||
        oldWidget.sensors != widget.sensors) {
      _series = _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Comparer · ${widget.zoneName}')),
      body: FutureBuilder<List<_MetricSeries>>(
        future: _series,
        builder: (_, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('Impossible de charger les mesures.'),
              TextButton(
                  onPressed: () => setState(() => _series = _load()),
                  child: const Text('Réessayer')),
            ]));
          }
          final all = snapshot.data ?? const [];
          final selected =
              all.where((item) => _selected.contains(item.key)).toList();
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Wrap(
                spacing: 8,
                children: {
                  const Duration(hours: 24): '24 h',
                  const Duration(days: 3): '3 j',
                  const Duration(days: 7): '7 j',
                  const Duration(days: 30): '30 j',
                }
                    .entries
                    .map((entry) => ChoiceChip(
                          label: Text(entry.value),
                          selected: _period == entry.key,
                          onSelected: (_) => setState(() {
                            _period = entry.key;
                            _series = _load();
                          }),
                        ))
                    .toList(),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: all
                    .map((series) => FilterChip(
                          selected: _selected.contains(series.key),
                          label: Text('${series.label} (${series.unit})'),
                          onSelected: (value) => setState(() {
                            value
                                ? _selected.add(series.key)
                                : _selected.remove(series.key);
                          }),
                        ))
                    .toList(),
              ),
              const SizedBox(height: 12),
              if (selected.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: Text('Sélectionne au moins une courbe.'),
                  ),
                )
              else if (selected.every((item) => item.points.isEmpty))
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: Text('Aucune mesure sur cette période.'),
                  ),
                )
              else ...[
                const Padding(
                  padding: EdgeInsets.fromLTRB(8, 4, 8, 8),
                  child: Text(
                    'Chaque graphique garde son unité et les mêmes dates. '
                    'Touche une courbe pour lire la mesure exacte. '
                    'La lumière ADC est un signal brut, pas une mesure en lux.',
                  ),
                ),
                ...selected.map((series) => series.points.isEmpty
                    ? ListTile(
                        title: Text(series.label),
                        subtitle:
                            const Text('Aucune mesure sur cette période.'))
                    : _chart(series, selected)),
              ],
            ],
          );
        },
      ),
    );
  }

  Future<List<_MetricSeries>> _load() async {
    final values = await Future.wait([
      widget.sensors.historyForZone(widget.zoneId, _period),
      widget.sensors.measurementsForZone(widget.zoneId, _period),
    ]);
    final readings = values[0] as List<SensorReading>;
    final measurements = values[1] as List<SensorMeasurement>;
    final series = <_MetricSeries>[
      _MetricSeries.fromReadings(
        key: 'temperature_c',
        label: 'Température',
        unit: '°C',
        color: Colors.deepOrange,
        readings: readings,
        select: (item) => item.temperature,
      ),
      _MetricSeries.fromReadings(
        key: 'humidity_percent',
        label: 'Humidité',
        unit: '%',
        color: Colors.blue,
        readings: readings,
        select: (item) => item.humidity,
      ),
      _MetricSeries.fromReadings(
        key: 'vpd_kpa',
        label: 'VPD',
        unit: 'kPa',
        color: Colors.green,
        readings: readings,
        select: (item) => item.vpd,
      ),
    ];
    final byKey = <String, List<SensorMeasurement>>{};
    for (final measurement in measurements) {
      if (measurement.numericValue != null) {
        byKey.putIfAbsent(measurement.capabilityKey, () => []).add(measurement);
      }
    }
    const colors = [
      Colors.purple,
      Colors.teal,
      Colors.amber,
      Colors.indigo,
      Colors.brown
    ];
    var colorIndex = 0;
    for (final entry in byKey.entries) {
      if (series.any((item) => item.key == entry.key)) continue;
      series.add(_MetricSeries.fromMeasurements(
        key: entry.key,
        label: entry.key == 'light_adc_raw' ? 'Lumière brute' : entry.key,
        unit: entry.value.first.unit ?? '—',
        color: colors[colorIndex++ % colors.length],
        measurements: entry.value,
      ));
    }
    return series;
  }

  String _format(double value, String unit) => value
      .toStringAsFixed(unit == 'ADC'
          ? 0
          : unit == 'kPa'
              ? 2
              : 1)
      .replaceAll('.', ',');

  Widget _chart(_MetricSeries series, List<_MetricSeries> selection) {
    final plotted = [series];
    final allDates = selection
        .expand((item) => item.points.map((point) => point.at))
        .toList();
    final origin = allDates.reduce((a, b) => a.isBefore(b) ? a : b);
    final end = allDates.reduce((a, b) => a.isAfter(b) ? a : b);
    final spanMinutes = end.difference(origin).inMilliseconds / 60000;
    final labelInterval = spanMinutes > 0 ? spanMinutes / 2 : 1.0;
    final padding = (series.maximum - series.minimum).abs() * 0.1;
    final yPadding = padding > 0
        ? padding
        : series.unit == 'kPa'
            ? 0.1
            : 1.0;
    final sampledByBar = <List<_MetricPoint>>[];
    final bars = plotted.map((item) {
      final step =
          item.points.length > 600 ? (item.points.length / 600).ceil() : 1;
      final spots = <FlSpot>[];
      final sampled = <_MetricPoint>[];
      for (var index = 0; index < item.points.length; index += step) {
        final point = item.points[index];
        sampled.add(point);
        spots.add(FlSpot(
            point.at.difference(origin).inMilliseconds / 60000, point.value));
      }
      if (sampled.last != item.points.last) {
        final point = item.points.last;
        sampled.add(point);
        spots.add(FlSpot(
            point.at.difference(origin).inMilliseconds / 60000, point.value));
      }
      sampledByBar.add(sampled);
      return LineChartBarData(
        spots: spots,
        isCurved: false,
        color: item.color,
        barWidth: 2,
        dotData: FlDotData(show: spots.length == 1),
      );
    }).toList();
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 16, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${series.label} (${series.unit})',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: series.color)),
            const SizedBox(height: 8),
            Text(
                'Dernier : ${_format(series.points.last.value, series.unit)} ${series.unit}'
                ' · ${DateFormat('dd/MM HH:mm').format(series.points.last.at)}'),
            Text('Min. ${_format(series.minimum, series.unit)} · '
                'Moy. ${_format(series.average, series.unit)} · '
                'Max. ${_format(series.maximum, series.unit)} ${series.unit}'),
            Text('${series.points.length} relevés'),
            const SizedBox(height: 8),
            Text(
              '${DateFormat('dd/MM HH:mm').format(origin)} au '
              '${DateFormat('dd/MM HH:mm').format(end)}',
            ),
            Text('Axe vertical : ${series.unit}'),
            const SizedBox(height: 8),
            SizedBox(
              height: 230,
              child: LineChart(LineChartData(
                minX: 0,
                maxX: spanMinutes == 0 ? 1 : spanMinutes,
                minY: series.minimum - yPadding,
                maxY: series.maximum + yPadding,
                lineBarsData: bars,
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 58,
                    interval:
                        (series.maximum - series.minimum + 2 * yPadding) / 3,
                    getTitlesWidget: (value, meta) => SideTitleWidget(
                      meta: meta,
                      child: Text(_format(value, series.unit),
                          style: const TextStyle(fontSize: 12)),
                    ),
                  )),
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 52,
                      interval: labelInterval,
                      getTitlesWidget: (value, meta) => SideTitleWidget(
                        meta: meta,
                        fitInside: SideTitleFitInsideData.fromTitleMeta(meta),
                        child: Text(
                          DateFormat('dd/MM\nHH:mm').format(
                            origin.add(Duration(
                                milliseconds: (value * 60000).round())),
                          ),
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ),
                  ),
                ),
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipColor: (_) => Colors.white,
                    fitInsideHorizontally: true,
                    fitInsideVertically: true,
                    getTooltipItems: (spots) => spots.map((spot) {
                      final item = plotted[spot.barIndex];
                      final point = sampledByBar[spot.barIndex][spot.spotIndex];
                      return LineTooltipItem(
                        '${item.label} : ${_format(point.value, item.unit)} '
                        '${item.unit}\n${DateFormat('dd/MM HH:mm').format(point.at)}',
                        TextStyle(
                          color: item.color,
                          fontWeight: FontWeight.w600,
                        ),
                      );
                    }).toList(),
                  ),
                ),
              )),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricPoint {
  final DateTime at;
  final double value;

  const _MetricPoint(this.at, this.value);
}

class _MetricSeries {
  final String key;
  final String label;
  final String unit;
  final Color color;
  final List<_MetricPoint> points;

  const _MetricSeries({
    required this.key,
    required this.label,
    required this.unit,
    required this.color,
    required this.points,
  });

  factory _MetricSeries.fromReadings({
    required String key,
    required String label,
    required String unit,
    required Color color,
    required List<SensorReading> readings,
    required double Function(SensorReading) select,
  }) =>
      _MetricSeries(
        key: key,
        label: label,
        unit: unit,
        color: color,
        points: readings
            .where((item) => select(item).isFinite)
            .map((item) => _MetricPoint(item.timestamp, select(item)))
            .toList()
          ..sort((a, b) => a.at.compareTo(b.at)),
      );

  factory _MetricSeries.fromMeasurements({
    required String key,
    required String label,
    required String unit,
    required Color color,
    required List<SensorMeasurement> measurements,
  }) =>
      _MetricSeries(
        key: key,
        label: label,
        unit: unit,
        color: color,
        points: measurements
            .where((item) => item.numericValue?.isFinite == true)
            .map((item) => _MetricPoint(item.timestamp, item.numericValue!))
            .toList()
          ..sort((a, b) => a.at.compareTo(b.at)),
      );

  double get minimum =>
      points.map((item) => item.value).reduce((a, b) => a < b ? a : b);
  double get maximum =>
      points.map((item) => item.value).reduce((a, b) => a > b ? a : b);
  double get average =>
      points.fold<double>(0, (sum, item) => sum + item.value) / points.length;
}
