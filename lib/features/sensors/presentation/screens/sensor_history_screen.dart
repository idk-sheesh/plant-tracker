import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../domain/entities/sensor_device.dart';
import '../../domain/entities/sensor_measurement.dart';
import '../../domain/entities/sensor_reading.dart';

/// Shows the exact readings used by the climate charts for the selected period.
class SensorHistoryScreen extends StatefulWidget {
  final List<SensorReading> readings;
  final List<SensorMeasurement> measurements;
  final List<SensorDevice> devices;

  const SensorHistoryScreen({
    super.key,
    required this.readings,
    required this.measurements,
    required this.devices,
  });

  @override
  State<SensorHistoryScreen> createState() => _SensorHistoryScreenState();
}

class _SensorHistoryScreenState extends State<SensorHistoryScreen> {
  static const _mobilePageSize = 20;
  late final _SensorHistorySource _source;
  final ScrollController _scrollController = ScrollController();
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _source = _SensorHistorySource(
        widget.readings, widget.measurements, widget.devices, DateTime.now());
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _source.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Tableau des mesures')),
        body: widget.readings.isEmpty
            ? const Center(child: Text('Aucune mesure pour cette période.'))
            : LayoutBuilder(
                builder: (context, constraints) => constraints.maxWidth < 1000
                    ? _mobileHistory()
                    : _wideHistory(),
              ),
      );

  Widget _mobileHistory() {
    final pageCount = (widget.readings.length / _mobilePageSize).ceil();
    final start = _page * _mobilePageSize;
    final end = (start + _mobilePageSize).clamp(0, widget.readings.length);
    return ListView(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      children: [
        Text(
            '${widget.readings.length} relevés · du plus récent au plus ancien',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 6),
        const Text('État = état actuel du nœud. ADC = lumière brute non '
            'étalonnée. — = donnée absente.'),
        _mobileNavigation(pageCount),
        for (var index = start; index < end; index++)
          _mobileReading(_source.rowValues(index)),
        _mobileNavigation(pageCount),
      ],
    );
  }

  Widget _mobileNavigation(int pageCount) => Row(
        children: [
          IconButton(
            tooltip: 'Première page',
            onPressed: _page == 0 ? null : () => _goToPage(0),
            icon: const Icon(Icons.first_page),
          ),
          IconButton(
            tooltip: 'Page précédente',
            onPressed: _page == 0 ? null : () => _goToPage(_page - 1),
            icon: const Icon(Icons.chevron_left),
          ),
          Expanded(
            child: Text('Page ${_page + 1} / $pageCount',
                textAlign: TextAlign.center),
          ),
          IconButton(
            tooltip: 'Page suivante',
            onPressed:
                _page + 1 >= pageCount ? null : () => _goToPage(_page + 1),
            icon: const Icon(Icons.chevron_right),
          ),
          IconButton(
            tooltip: 'Dernière page',
            onPressed:
                _page + 1 >= pageCount ? null : () => _goToPage(pageCount - 1),
            icon: const Icon(Icons.last_page),
          ),
        ],
      );

  void _goToPage(int page) {
    setState(() => _page = page);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scrollController.hasClients) {
        _scrollController.jumpTo(0);
      }
    });
  }

  Widget _mobileReading(List<String> values) => Card(
        margin: const EdgeInsets.only(bottom: 10),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${values[0]} · ${values[1]}',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(values[2]),
              Text('État actuel : ${values[3]} · ${values[11]}'),
              const Divider(height: 18),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  _mobileMetric('Température', values[4]),
                  _mobileMetric('Humidité', values[5]),
                  _mobileMetric('VPD air', values[6]),
                ],
              ),
              const SizedBox(height: 10),
              Text('Lumière : ${values[7]}'),
              Text('Jour / nuit : ${values[8]}'),
              if (values[9] != '—' || values[10] != '—') ...[
                const SizedBox(height: 4),
                if (values[9] != '—') Text('Brumisation : ${values[9]}'),
                if (values[10] != '—') Text('Ventilation : ${values[10]}'),
              ],
            ],
          ),
        ),
      );

  Widget _mobileMetric(String label, String value) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Colors.black54)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      );

  Widget _wideHistory() => ListView(
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'État = état actuel du nœud. Jour/nuit = éclairage détecté '
              'par la lumière au moment du relevé. ADC = valeur brute '
              'non étalonnée. — = donnée absente.',
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: 2000,
              child: PaginatedDataTable(
                header: Text('${widget.readings.length} relevés'),
                rowsPerPage: 10,
                showFirstLastButtons: true,
                columns: const [
                  DataColumn(label: Text('Date')),
                  DataColumn(label: Text('Heure')),
                  DataColumn(label: Text('Capteur / ID')),
                  DataColumn(label: Text('État actuel')),
                  DataColumn(label: Text('Température')),
                  DataColumn(label: Text('Humidité')),
                  DataColumn(label: Text('VPD air')),
                  DataColumn(label: Text('Lumière')),
                  DataColumn(label: Text('Jour / Nuit')),
                  DataColumn(label: Text('Brumisation')),
                  DataColumn(label: Text('Ventilation (%)')),
                  DataColumn(label: Text('Fraîcheur')),
                ],
                source: _source,
              ),
            ),
          ),
        ],
      );
}

class _SensorHistorySource extends DataTableSource {
  final List<SensorReading> readings;
  final Map<String, SensorDevice> devices;
  final Map<String, Map<String, SensorMeasurement>> measurements;
  final DateTime now;

  _SensorHistorySource(this.readings, List<SensorMeasurement> values,
      List<SensorDevice> devices, this.now)
      : devices = {for (final device in devices) device.id: device},
        measurements = {} {
    for (final value in values) {
      measurements.putIfAbsent('${value.deviceId}:${value.timestampSeconds}',
          () => {})[value.capabilityKey] = value;
    }
  }

  @override
  int get rowCount => readings.length;

  @override
  bool get isRowCountApproximate => false;

  @override
  int get selectedRowCount => 0;

  @override
  DataRow? getRow(int index) {
    if (index >= readings.length) return null;
    final values = rowValues(index);
    return DataRow.byIndex(
      index: index,
      cells: values.map((value) => DataCell(Text(value))).toList(),
    );
  }

  List<String> rowValues(int index) {
    final reading = readings[readings.length - 1 - index];
    final device = devices[reading.deviceId];
    final values =
        measurements['${reading.deviceId}:${reading.timestampSeconds}'];
    final rawLight = values?['light_adc_raw']?.numericValue;
    final lightDetected =
        reading.lightOn ?? values?['light_detected']?.booleanValue;
    final mist = values?['mist_state']?.booleanValue;
    final age = now.difference(reading.timestamp);
    final freshness = device?.status == 'offline'
        ? 'Hors ligne'
        : age >= Duration.zero && age <= const Duration(minutes: 5)
            ? 'Récent'
            : 'Périmé';
    return [
      DateFormat('dd/MM/yyyy').format(reading.timestamp),
      DateFormat('HH:mm:ss').format(reading.timestamp),
      '${device?.name ?? 'Capteur inconnu'} · ${reading.deviceId}',
      device?.status ?? 'Inconnu',
      '${reading.temperature.toStringAsFixed(1)} °C',
      '${reading.humidity.toStringAsFixed(1)} %',
      '${reading.vpd.toStringAsFixed(2)} kPa',
      rawLight == null ? '—' : '${rawLight.toStringAsFixed(0)} ADC',
      lightDetected == null
          ? 'Lumière indisponible'
          : lightDetected
              ? 'Jour détecté'
              : 'Nuit détectée',
      mist == null
          ? '—'
          : mist
              ? 'ON'
              : 'OFF',
      reading.fanPercent == null
          ? '—'
          : '${reading.fanPercent!.toStringAsFixed(0)} %',
      freshness,
    ];
  }
}
