import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../actions/presentation/providers/action_provider.dart';
import '../../../cameras/presentation/widgets/zone_camera_card.dart';
import '../../../plants/domain/entities/plant.dart';
import '../../../plants/presentation/providers/plant_provider.dart';
import '../../../sensors/domain/entities/sensor_reading.dart';
import '../../../sensors/domain/entities/sensor_measurement.dart';
import '../../../sensors/presentation/providers/sensor_provider.dart';
import '../../../sensors/presentation/screens/sensor_history_screen.dart';
import '../../../sensors/presentation/screens/sensor_settings_screen.dart';
import '../../../sensors/presentation/screens/sensor_comparison_screen.dart';
import '../../../sensors/presentation/screens/device_control_screen.dart';
import '../../domain/entities/climate_summary.dart';
import '../../domain/entities/cultivation_zone.dart';
import '../../domain/entities/zone_placement.dart';
import '../providers/space_provider.dart';
import '../widgets/zone_photo_card.dart';
import 'zone_form_screen.dart';

class ZoneDetailScreen extends StatefulWidget {
  final String zoneId;

  const ZoneDetailScreen({super.key, required this.zoneId});

  @override
  State<ZoneDetailScreen> createState() => _ZoneDetailScreenState();
}

class _ZoneDetailScreenState extends State<ZoneDetailScreen> {
  Duration _period = const Duration(hours: 24);
  _FloweringPeriod? _floweringPeriod;

  @override
  Widget build(BuildContext context) {
    final spaces = context.watch<SpaceProvider>();
    final sensors = context.watch<SensorProvider>();
    final plants = context.watch<PlantProvider>();
    final zone = spaces.getZone(widget.zoneId);
    if (zone == null) {
      return const Scaffold(body: Center(child: Text('Espace introuvable')));
    }
    final latest = sensors.latestForZone(zone.id);
    final device = sensors.deviceForZone(zone.id);
    final liveLatest =
        sensors.hasCurrentReadingForZone(zone.id) ? latest : null;
    final plantsInZone = plants.allPlants
        .where((plant) =>
            !plant.isDead &&
            !plant.isHarvested &&
            spaces.placementForPlant(plant)?.zoneId == zone.id)
        .toList(growable: false);
    return Scaffold(
      appBar: AppBar(
        title: Text(zone.name),
        actions: [
          IconButton(
            tooltip: 'Comparer les courbes',
            icon: const Icon(Icons.multiline_chart),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => SensorComparisonScreen(
                  zoneId: zone.id,
                  zoneName: zone.name,
                  sensors: sensors,
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Commandes sûres et programmes',
            icon: const Icon(Icons.tune),
            onPressed: device == null
                ? null
                : () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => DeviceControlScreen(device: device),
                      ),
                    ),
          ),
          IconButton(
            tooltip: 'Modifier l’espace',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => ZoneFormScreen(zone: zone)),
            ),
          ),
          IconButton(
            tooltip: 'Configurer le nœud',
            icon: const Icon(Icons.sensors),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => SensorSettingsScreen(initialZoneId: zone.id),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: () async {
            if (device != null) {
              await sensors.selectDevice(device);
              await sensors.fetchNow();
            }
            if (mounted) setState(() {});
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              _zoneHeader(
                zone,
                liveLatest != null && device?.isOnline != true
                    ? 'mesures reçues via le Pi'
                    : device?.status ?? 'non configuré',
              ),
              const SizedBox(height: 12),
              ZoneCameraCard(zoneId: zone.id, zoneName: zone.name),
              const SizedBox(height: 12),
              ZonePhotoCard(zoneId: zone.id),
              const SizedBox(height: 12),
              _currentMetrics(
                zone,
                liveLatest,
                device == null
                    ? 'Aucun nœud connecté. Les valeurs actuelles sont masquées.'
                    : 'Nœud hors ligne. Les anciennes mesures restent dans l’historique.',
              ),
              const SizedBox(height: 12),
              ..._alerts(zone, liveLatest, sensors, device != null),
              _placements(zone.id, spaces),
              const SizedBox(height: 12),
              const ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.history),
                title: Text('Historique climatique enregistré'),
                subtitle: Text(
                  'Les graphiques ci-dessous sont des relevés passés, pas des valeurs en direct.',
                ),
              ),
              _periodSelector(plantsInZone, spaces),
              FutureBuilder<_PeriodData>(
                future: _loadPeriod(zone, spaces, sensors),
                builder: (_, snapshot) {
                  if (snapshot.hasError) {
                    return const Card(
                      child: Padding(
                        padding: EdgeInsets.all(20),
                        child: Text(
                          'Impossible de calculer les statistiques pour cette période.',
                        ),
                      ),
                    );
                  }
                  if (!snapshot.hasData) {
                    return const Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  final data = snapshot.data!;
                  if (data.readings.isEmpty) {
                    return const Card(
                      child: Padding(
                        padding: EdgeInsets.all(20),
                        child: Text(
                          'Aucun relevé pour cette période. Les dernières '
                          'valeurs connues restent disponibles hors ligne.',
                        ),
                      ),
                    );
                  }
                  return Column(
                    children: [
                      _summary(
                        zone,
                        data.summary,
                        data.periodStart,
                        data.periodEnd,
                      ),
                      const SizedBox(height: 12),
                      _chart('Température', data.readings,
                          (reading) => reading.temperature, Colors.deepOrange),
                      const SizedBox(height: 10),
                      _chart('Humidité', data.readings,
                          (reading) => reading.humidity, Colors.blue),
                      const SizedBox(height: 10),
                      _chart('VPD', data.readings, (reading) => reading.vpd,
                          Colors.green),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.table_chart_outlined),
                        label: const Text('Voir le tableau des mesures'),
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => SensorHistoryScreen(
                              readings: data.readings,
                              measurements: data.measurements,
                              devices: sensors.devices,
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 16),
              _actuators(liveLatest),
            ],
          ),
        ),
      ),
    );
  }

  Future<_PeriodData> _loadPeriod(
    CultivationZone zone,
    SpaceProvider spaces,
    SensorProvider sensors,
  ) async {
    final periodEnd = DateTime.now();
    final requestedStart =
        _floweringPeriod?.analysisStartedAt ?? periodEnd.subtract(_period);
    final periodStart =
        requestedStart.isAfter(periodEnd) ? periodEnd : requestedStart;
    final data = await spaces.climateDataBetween(
      zone,
      periodStart,
      periodEnd,
    );
    final measurements =
        await sensors.measurementsForZoneSince(zone.id, periodStart);
    return _PeriodData(
      readings: data.readings,
      measurements: measurements,
      summary: data.summary,
      periodStart: periodStart,
      periodEnd: periodEnd,
    );
  }

  Widget _zoneHeader(CultivationZone zone, String status) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            CircleAvatar(
              child: Icon(zone.isStorage ? Icons.air : Icons.yard_outlined),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(zone.type.label,
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  Text(zone.dimensionsLabel),
                  Text('Nœud : $status'),
                ],
              ),
            ),
          ]),
        ),
      );

  Widget _currentMetrics(
    CultivationZone zone,
    SensorReading? reading,
    String unavailableMessage,
  ) {
    if (reading == null) {
      return Card(
        color: const Color(0xFFF5F5F5),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.sensors_off, color: Colors.black54),
              const SizedBox(width: 12),
              Expanded(child: Text(unavailableMessage)),
            ],
          ),
        ),
      );
    }
    final values = zone.isStorage
        ? [
            ('Temp.', '${reading.temperature.toStringAsFixed(1)} °C'),
            ('Hum.', '${reading.humidity.toStringAsFixed(1)} %'),
            ('Rosée', '${reading.dewPoint?.toStringAsFixed(1) ?? '—'} °C'),
          ]
        : [
            ('Temp.', '${reading.temperature.toStringAsFixed(1)} °C'),
            ('Hum.', '${reading.humidity.toStringAsFixed(1)} %'),
            ('VPD air', '${reading.vpd.toStringAsFixed(2)} kPa'),
          ];
    final chartBand = VpdChart.classify(
      temperature: reading.temperature,
      humidity: reading.humidity,
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          Row(
            children: values
                .map(
                  (item) => Expanded(
                    child: Column(children: [
                      Text(item.$1,
                          style: const TextStyle(color: Colors.black54)),
                      Text(item.$2,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 16)),
                    ]),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 8),
          Text(
            'Dernière mesure en direct · '
            '${DateFormat('dd/MM HH:mm:ss').format(reading.timestamp)}',
          ),
          const SizedBox(height: 4),
          Text(reading.lightOn == null
              ? 'Lumière indisponible · jour/nuit inconnu'
              : reading.lightOn!
                  ? 'Éclairage détecté · jour'
                  : 'Éclairage éteint détecté · nuit'),
          if (!zone.isStorage) ...[
            const SizedBox(height: 8),
            Text(
              'Grille historique indicative : ${chartBand.shortLabel} · ${chartBand.detail}',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(chartBand.colorValue),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ]),
      ),
    );
  }

  List<Widget> _alerts(
    CultivationZone zone,
    SensorReading? reading,
    SensorProvider sensors,
    bool hasDevice,
  ) {
    final alerts = <String>[];
    if (hasDevice && sensors.isZoneDataStale(zone.id)) {
      alerts.add('Le nœud ne communique plus.');
    }
    if (reading?.waterLow == true) alerts.add('Niveau d’eau bas signalé.');
    if (reading != null &&
        !zone.isStorage &&
        zone.targetProfile.isOutside(
          temperature: reading.temperature,
          humidity: reading.humidity,
        )) {
      alerts.add(
        'Grille historique indicative : couple température / humidité hors plage.',
      );
    }
    return alerts
        .map(
          (alert) => Card(
            color: const Color(0xFFFFEBEE),
            child: ListTile(
              leading: const Icon(Icons.warning_amber, color: Colors.red),
              title: Text(alert),
            ),
          ),
        )
        .toList();
  }

  Widget _periodSelector(
    List<Plant> plantsInZone,
    SpaceProvider spaces,
  ) {
    const presets = [
      (Duration(days: 1), '1 j'),
      (Duration(days: 2), '2 j'),
      (Duration(days: 5), '5 j'),
      (Duration(days: 7), '7 j'),
      (Duration(days: 30), '30 j'),
    ];
    final flowering = _floweringPeriod;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Période d’analyse',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final preset in presets)
                  ChoiceChip(
                    label: Text(preset.$2),
                    selected: flowering == null && _period == preset.$1,
                    onSelected: (_) => setState(() {
                      _period = preset.$1;
                      _floweringPeriod = null;
                    }),
                  ),
                ChoiceChip(
                  avatar: const Icon(Icons.local_florist, size: 18),
                  label: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 190),
                    child: Text(
                      flowering == null
                          ? 'Depuis floraison'
                          : 'Floraison · ${flowering.plantName}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  selected: flowering != null,
                  onSelected: (_) =>
                      _selectFloweringPeriod(plantsInZone, spaces),
                ),
              ],
            ),
            if (flowering != null) ...[
              const SizedBox(height: 10),
              Text(
                flowering.wasLimitedByPlacement
                    ? 'Floraison le ${DateFormat('dd/MM/yyyy').format(flowering.floweringStartedAt)} · '
                        'analyse depuis son entrée dans cette zone le '
                        '${DateFormat('dd/MM/yyyy').format(flowering.analysisStartedAt)}.'
                    : 'Analyse liée à ${flowering.plantName}, en floraison depuis le '
                        '${DateFormat('dd/MM/yyyy').format(flowering.floweringStartedAt)}.',
                style: const TextStyle(fontSize: 12, color: Colors.black54),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _selectFloweringPeriod(
    List<Plant> plantsInZone,
    SpaceProvider spaces,
  ) async {
    if (plantsInZone.isEmpty) {
      _showPeriodMessage('Aucune plante n’est actuellement dans cette zone.');
      return;
    }

    Map<String, DateTime> starts;
    try {
      starts = await context
          .read<ActionProvider>()
          .latestFloweringStartsForPlants(
              plantsInZone.map((plant) => plant.id));
    } catch (_) {
      if (mounted) {
        _showPeriodMessage('Impossible de lire les débuts de floraison.');
      }
      return;
    }
    if (!mounted) return;

    final now = DateTime.now();
    final choices = <_FloweringPeriod>[];
    for (final plant in plantsInZone) {
      final floweringStartedAt = starts[plant.id];
      final placement = spaces.placementForPlant(plant);
      if (floweringStartedAt == null ||
          floweringStartedAt.isAfter(now) ||
          placement == null ||
          placement.zoneId != widget.zoneId) {
        continue;
      }
      final analysisStartedAt = placement.enteredAt.isAfter(floweringStartedAt)
          ? placement.enteredAt
          : floweringStartedAt;
      choices.add(
        _FloweringPeriod(
          plantName: plant.name,
          floweringStartedAt: floweringStartedAt,
          analysisStartedAt: analysisStartedAt,
        ),
      );
    }
    choices.sort((a, b) => a.plantName.compareTo(b.plantName));
    if (choices.isEmpty) {
      _showPeriodMessage(
        'Aucun début de floraison enregistré pour les plantes présentes.',
      );
      return;
    }

    final selected = choices.length == 1
        ? choices.single
        : await showModalBottomSheet<_FloweringPeriod>(
            context: context,
            showDragHandle: true,
            builder: (sheetContext) => SafeArea(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.7,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
                      child: Text(
                        'Choisir une plante',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Flexible(
                      child: ListView(
                        shrinkWrap: true,
                        children: choices
                            .map(
                              (choice) => ListTile(
                                leading: const Icon(Icons.local_florist),
                                title: Text(choice.plantName),
                                subtitle: Text(
                                  'Floraison depuis le '
                                  '${DateFormat('dd/MM/yyyy').format(choice.floweringStartedAt)}',
                                ),
                                onTap: () =>
                                    Navigator.pop(sheetContext, choice),
                              ),
                            )
                            .toList(growable: false),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
    if (!mounted || selected == null) return;
    setState(() => _floweringPeriod = selected);
  }

  void _showPeriodMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Widget _summary(
    CultivationZone zone,
    ClimateSummary summary,
    DateTime periodStart,
    DateTime periodEnd,
  ) =>
      SizedBox(
        width: double.infinity,
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Résumé climatique',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(
                  'Période : ${DateFormat('dd/MM/yyyy HH:mm').format(periodStart)} '
                  '→ ${DateFormat('dd/MM/yyyy HH:mm').format(periodEnd)}',
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),
                const SizedBox(height: 12),
                _statisticsTable(zone, summary),
                const SizedBox(height: 12),
                Text(
                  '${summary.sampleCount} relevé${summary.sampleCount > 1 ? 's' : ''} · '
                  'Disponibilité : ${summary.availabilityPercent.toStringAsFixed(0)} %',
                ),
                Text(
                    'Zone de danger : ${_duration(summary.outOfRangeDuration)}'),
                Text(
                    'Plus longue excursion : ${_duration(summary.longestExcursion)}'),
                if (zone.isStorage)
                  Text(
                    'Stabilité : ±${summary.temperatureStdDev.toStringAsFixed(1)} °C, '
                    '±${summary.humidityStdDev.toStringAsFixed(1)} % HR',
                  ),
              ],
            ),
          ),
        ),
      );

  Widget _statisticsTable(
    CultivationZone zone,
    ClimateSummary summary,
  ) {
    final rows = <(String, MetricSummary, int)>[
      ('Temp. °C', summary.temperature, 1),
      ('Hum. %', summary.humidity, 1),
      if (!zone.isStorage) ('VPD kPa', summary.vpd, 2),
    ];
    return Table(
      columnWidths: const {
        0: FlexColumnWidth(1.4),
        1: FlexColumnWidth(),
        2: FlexColumnWidth(),
        3: FlexColumnWidth(),
        4: FlexColumnWidth(),
      },
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: [
        TableRow(
          children: [
            const SizedBox.shrink(),
            _statCell('Min', isHeader: true),
            _statCell('Moy.', isHeader: true),
            _statCell('Méd.', isHeader: true),
            _statCell('Max', isHeader: true),
          ],
        ),
        for (final row in rows)
          TableRow(
            children: [
              _statCell(row.$1, isLabel: true),
              _statCell(row.$2.minimum.toStringAsFixed(row.$3)),
              _statCell(row.$2.average.toStringAsFixed(row.$3)),
              _statCell(row.$2.median.toStringAsFixed(row.$3)),
              _statCell(row.$2.maximum.toStringAsFixed(row.$3)),
            ],
          ),
      ],
    );
  }

  Widget _statCell(
    String value, {
    bool isHeader = false,
    bool isLabel = false,
  }) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
        child: Text(
          value,
          textAlign: isLabel ? TextAlign.left : TextAlign.center,
          style: TextStyle(
            fontSize: 12,
            color: isHeader ? Colors.black54 : null,
            fontWeight:
                isHeader || isLabel ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      );

  String _duration(Duration value) {
    final hours = value.inHours;
    final minutes = value.inMinutes.remainder(60);
    return '${hours}h ${minutes.toString().padLeft(2, '0')}min';
  }

  Widget _chart(
    String title,
    List<SensorReading> readings,
    double Function(SensorReading) select,
    Color color,
  ) {
    final step = readings.length > 600 ? (readings.length / 600).ceil() : 1;
    final sampled = <SensorReading>[
      for (var i = 0; i < readings.length; i += step) readings[i],
    ];
    if (sampled.last.timestamp != readings.last.timestamp) {
      sampled.add(readings.last);
    }
    final spots = sampled
        .asMap()
        .entries
        .map((entry) => FlSpot(entry.key.toDouble(), select(entry.value)))
        .toList();
    final values = sampled.map(select).toList();
    final lowest = values.reduce((a, b) => a < b ? a : b);
    final highest = values.reduce((a, b) => a > b ? a : b);
    final range = highest - lowest;
    final padding = range == 0
        ? (highest.abs() < 1 ? 1.0 : highest.abs() * 0.1)
        : range * 0.12;
    final labelIndexes = _dateLabelIndexes(sampled.length);
    final dateFormat = DateFormat('dd/MM');
    final decimals = title == 'VPD' ? 2 : 0;

    return SizedBox(
      width: double.infinity,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              SizedBox(
                height: 160,
                child: LineChart(
                  LineChartData(
                    minX: -0.25,
                    maxX: spots.last.x + 0.25,
                    minY: lowest - padding,
                    maxY: highest + padding,
                    gridData: const FlGridData(show: true),
                    titlesData: FlTitlesData(
                      topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 38,
                          getTitlesWidget: (value, _) => Text(
                            value.toStringAsFixed(decimals),
                            style: const TextStyle(
                              fontSize: 9,
                              color: Color(0xFF757575),
                            ),
                          ),
                        ),
                      ),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 26,
                          interval: 1,
                          getTitlesWidget: (value, meta) {
                            if (value != value.roundToDouble()) {
                              return const SizedBox.shrink();
                            }
                            final index = value.round();
                            if (index < 0 ||
                                index >= sampled.length ||
                                !labelIndexes.contains(index)) {
                              return const SizedBox.shrink();
                            }
                            return SideTitleWidget(
                              meta: meta,
                              space: 4,
                              fitInside: SideTitleFitInsideData.fromTitleMeta(
                                meta,
                              ),
                              child: Text(
                                dateFormat.format(sampled[index].timestamp),
                                style: const TextStyle(
                                  fontSize: 9,
                                  color: Color(0xFF757575),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    borderData: FlBorderData(show: false),
                    lineBarsData: [
                      LineChartBarData(
                        spots: spots,
                        isCurved: true,
                        color: color,
                        barWidth: 2,
                        dotData: const FlDotData(show: false),
                        belowBarData: BarAreaData(
                          show: true,
                          color: color.withValues(alpha: 0.08),
                        ),
                      ),
                    ],
                    lineTouchData: LineTouchData(
                      touchTooltipData: LineTouchTooltipData(
                        getTooltipColor: (_) => Colors.white,
                        fitInsideHorizontally: true,
                        fitInsideVertically: true,
                        getTooltipItems: (touchedSpots) =>
                            touchedSpots.map((spot) {
                          final index = spot.x.round();
                          final reading = index >= 0 && index < sampled.length
                              ? sampled[index]
                              : null;
                          final date = reading == null
                              ? ''
                              : DateFormat('dd/MM/yyyy HH:mm')
                                  .format(reading.timestamp);
                          return LineTooltipItem(
                            '${spot.y.toStringAsFixed(decimals)}\n$date',
                            TextStyle(
                              color: color,
                              fontWeight: FontWeight.w700,
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Set<int> _dateLabelIndexes(int length) {
    if (length <= 3) return {for (var i = 0; i < length; i++) i};
    return {0, length ~/ 2, length - 1};
  }

  Widget _actuators(SensorReading? reading) {
    if (reading == null || reading.fanPercent == null) {
      return const SizedBox.shrink();
    }
    return Card(
      child: ListTile(
        leading: const Icon(Icons.tune),
        title: const Text('Sorties du nœud'),
        subtitle: Text(
          'Ventilation : ${reading.fanPercent!.toStringAsFixed(0)} %',
        ),
      ),
    );
  }

  Widget _placements(String zoneId, SpaceProvider spaces) => FutureBuilder(
        future: spaces.historyForZone(zoneId),
        builder: (_, AsyncSnapshot<List<ZonePlacement>> snapshot) {
          final placements = snapshot.data ?? [];
          return Card(
            child: ExpansionTile(
              title: const Text('Présences dans la zone'),
              children: placements.isEmpty
                  ? const [ListTile(title: Text('Aucun placement enregistré'))]
                  : placements
                      .map(
                        (placement) => ListTile(
                          leading: Icon(
                            placement.isPlant ? Icons.eco : Icons.folder,
                          ),
                          title: Text(placement.entityName),
                          subtitle: Text(
                            '${DateFormat('dd/MM/yyyy HH:mm').format(placement.enteredAt)} '
                            '→ ${placement.exitedAt == null ? 'maintenant' : DateFormat('dd/MM/yyyy HH:mm').format(placement.exitedAt!)}',
                          ),
                          trailing: placement.isActive
                              ? IconButton(
                                  tooltip: 'Clôturer le placement',
                                  icon: const Icon(Icons.stop_circle_outlined),
                                  onPressed: () =>
                                      _confirmClosePlacement(spaces, placement),
                                )
                              : null,
                        ),
                      )
                      .toList(),
            ),
          );
        },
      );

  Future<void> _confirmClosePlacement(
    SpaceProvider spaces,
    ZonePlacement placement,
  ) async {
    final zoneName = spaces.getZone(placement.zoneId)?.name ?? 'cette zone';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Clôturer le placement ?'),
        content: Text(
          placement.isPlant
              ? '${placement.entityName} ne sera plus considérée comme présente dans $zoneName. '
                  'Son historique et les relevés restent conservés.'
              : 'Le placement du groupe ${placement.entityName} sera clôturé dans $zoneName. '
                  'Les plantes qui en héritent ne seront plus présentes dans cette zone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Clôturer'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await spaces.closePlacement(placement);
      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Placement de ${placement.entityName} clôturé')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Impossible de clôturer le placement : $error')),
        );
      }
    }
  }
}

class _PeriodData {
  final List<SensorReading> readings;
  final List<SensorMeasurement> measurements;
  final ClimateSummary summary;
  final DateTime periodStart;
  final DateTime periodEnd;

  const _PeriodData({
    required this.readings,
    required this.measurements,
    required this.summary,
    required this.periodStart,
    required this.periodEnd,
  });
}

class _FloweringPeriod {
  final String plantName;
  final DateTime floweringStartedAt;
  final DateTime analysisStartedAt;

  const _FloweringPeriod({
    required this.plantName,
    required this.floweringStartedAt,
    required this.analysisStartedAt,
  });

  bool get wasLimitedByPlacement =>
      analysisStartedAt.isAfter(floweringStartedAt);
}
