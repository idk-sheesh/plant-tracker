import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../spaces/domain/entities/climate_summary.dart';
import '../../../spaces/domain/entities/cultivation_zone.dart';
import '../../../spaces/presentation/providers/space_provider.dart';
import '../../../spaces/presentation/screens/zone_detail_screen.dart';
import '../../../spaces/presentation/screens/zone_form_screen.dart';
import '../providers/cloud_provider.dart';
import '../providers/sensor_provider.dart';
import 'cloud_screen.dart';
import 'sensor_settings_screen.dart';

class SensorScreen extends StatefulWidget {
  const SensorScreen({super.key});

  @override
  State<SensorScreen> createState() => _SensorScreenState();
}

class _SensorScreenState extends State<SensorScreen>
    with WidgetsBindingObserver {
  Timer? _refreshTimer;
  bool _isRefreshing = false;
  bool _isForeground = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await context.read<SpaceProvider>().initialize();
      await _syncSources();
      if (mounted && _isForeground) {
        _refreshTimer?.cancel();
        _refreshTimer = Timer.periodic(
          const Duration(minutes: 1),
          (_) => unawaited(_syncSources()),
        );
      }
    });
  }

  Future<void> _syncSources() async {
    if (!mounted || !_isForeground || _isRefreshing) return;
    _isRefreshing = true;
    try {
      final sensors = context.read<SensorProvider>();
      final cloud = context.read<CloudProvider>();
      await sensors.initialize();
      final cloudSynced =
          cloud.isConfigured ? await cloud.synchronizeMyData() : <String>{};
      if (!mounted) return;
      if (cloudSynced.isNotEmpty) await sensors.refreshFromLocalCache();
      await sensors.syncAllDevices(skipDeviceIds: cloudSynced);
    } finally {
      _isRefreshing = false;
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _isForeground = state == AppLifecycleState.resumed;
    if (state == AppLifecycleState.resumed && mounted) {
      // Le téléphone peut avoir retrouvé le Wi-Fi de la maison pendant que
      // l'application était en arrière-plan. La synchronisation reprend alors
      // immédiatement, sans attendre le prochain cycle de la minuterie.
      unawaited(_syncSources());
    } else {
      _refreshTimer?.cancel();
      _refreshTimer = null;
    }
    if (state == AppLifecycleState.resumed && _refreshTimer == null) {
      _refreshTimer = Timer.periodic(
          const Duration(minutes: 1), (_) => unawaited(_syncSources()));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Text('Espaces'),
        actions: [
          TextButton.icon(
            style: TextButton.styleFrom(
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
            icon: const Icon(Icons.cloud_sync_outlined, size: 20),
            label: const Text('Synchro'),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const CloudScreen()),
            ),
          ),
          IconButton(
            tooltip: 'Ajouter un espace',
            icon: const Icon(Icons.add),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ZoneFormScreen()),
            ),
          ),
        ],
      ),
      body: Consumer2<SpaceProvider, SensorProvider>(
        builder: (_, spaces, sensors, __) {
          if (spaces.isLoading && spaces.zones.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }
          if (spaces.error != null && spaces.zones.isEmpty) {
            return _error(spaces.error!, spaces.refresh);
          }
          return RefreshIndicator(
            onRefresh: () async {
              await _syncSources();
              await spaces.refresh();
            },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(12),
              children: [
                if (sensors.devices.isEmpty) _noDevice(context),
                ...spaces.zones.map(
                  (zone) => _ZoneCard(
                    zone: zone,
                    spaces: spaces,
                    sensors: sensors,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ZoneDetailScreen(zoneId: zone.id),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 80),
              ],
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const SensorSettingsScreen()),
        ),
        icon: const Icon(Icons.sensors),
        label: const Text('Nœud'),
      ),
    );
  }

  Widget _noDevice(BuildContext context) => Card(
        color: const Color(0xFFE3F2FD),
        child: ListTile(
          leading: const Icon(Icons.sensors_off),
          title: const Text('Aucun nœud configuré'),
          subtitle: const Text(
            'Les cinq espaces fonctionnent déjà hors ligne. Ajoute un ESP '
            'quand le firmware sera prêt.',
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const SensorSettingsScreen()),
          ),
        ),
      );

  Widget _error(String message, Future<void> Function() retry) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(onPressed: retry, child: const Text('Réessayer')),
          ],
        ),
      );
}

class _ZoneCard extends StatelessWidget {
  final CultivationZone zone;
  final SpaceProvider spaces;
  final SensorProvider sensors;
  final VoidCallback onTap;

  const _ZoneCard({
    required this.zone,
    required this.spaces,
    required this.sensors,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final reading = sensors.latestForZone(zone.id);
    final device = sensors.deviceForZone(zone.id);
    final stale = sensors.isZoneDataStale(zone.id);
    final hasLiveData =
        sensors.hasCurrentReadingForZone(zone.id) && reading != null;
    final liveReading = hasLiveData ? reading : null;
    final occupants = spaces.occupants(zone.id);
    return Card(
      margin: const EdgeInsets.only(top: 10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                CircleAvatar(
                  backgroundColor: zone.isStorage
                      ? const Color(0xFFE3F2FD)
                      : const Color(0xFFE8F5E9),
                  child: Icon(zone.isStorage ? Icons.air : Icons.yard),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(zone.name,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 16)),
                      Text('${zone.type.label} · ${zone.dimensionsLabel}'),
                      if (device != null)
                        Text('${device.name} · ${device.uid}',
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
                Icon(
                  device == null
                      ? Icons.sensors_off
                      : hasLiveData
                          ? Icons.sensors
                          : Icons.cloud_off,
                  color: device == null
                      ? Colors.grey
                      : hasLiveData
                          ? Colors.green
                          : Colors.orange,
                ),
              ]),
              const SizedBox(height: 12),
              Text(
                occupants.isEmpty
                    ? 'Aucune plante ou groupe présent'
                    : occupants.map((item) => item.entityName).join(', '),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const Divider(height: 24),
              if (liveReading == null) ...[
                Text(
                  device == null
                      ? 'Aucun nœud connecté'
                      : device.status == 'offline'
                          ? 'Nœud hors ligne · mesures actuelles indisponibles'
                          : 'Mesure périmée · valeurs actuelles indisponibles',
                  style: const TextStyle(color: Colors.black54),
                ),
                if (reading != null)
                  Text('Dernier relevé conservé : '
                      '${DateFormat('dd/MM HH:mm:ss').format(reading.timestamp)}'),
              ] else ...[
                Row(children: [
                  _metric('Temp.',
                      '${liveReading.temperature.toStringAsFixed(1)} °C'),
                  _metric(
                      'Hum.', '${liveReading.humidity.toStringAsFixed(0)} %'),
                  _metric(
                    zone.isStorage ? 'Rosée' : 'VPD air',
                    zone.isStorage
                        ? '${liveReading.dewPoint?.toStringAsFixed(1) ?? '—'} °C'
                        : '${liveReading.vpd.toStringAsFixed(2)} kPa',
                  ),
                ]),
                const SizedBox(height: 8),
                Text(
                  '${stale ? 'Périmé' : 'Récent'} · Mesuré le '
                  '${DateFormat('dd/MM HH:mm:ss').format(liveReading.timestamp)}',
                  style: TextStyle(
                    color: stale ? Colors.orange.shade800 : Colors.black54,
                    fontSize: 12,
                  ),
                ),
                Text(liveReading.lightOn == null
                    ? 'Lumière indisponible · jour/nuit inconnu'
                    : liveReading.lightOn!
                        ? 'Lumière détectée · jour'
                        : 'Lumière éteinte détectée · nuit'),
              ],
              if (hasLiveData)
                FutureBuilder<ClimateSummary>(
                  future:
                      spaces.climateSummary(zone, const Duration(hours: 24)),
                  builder: (_, snapshot) {
                    final summary = snapshot.data;
                    if (summary == null || summary.sampleCount == 0) {
                      return const SizedBox.shrink();
                    }
                    return Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(
                        '24 h · moy. ${summary.temperature.average.toStringAsFixed(1)} °C / '
                        '${summary.humidity.average.toStringAsFixed(0)} % · '
                        'hors grille indicative ${summary.outOfRangeDuration.inMinutes} min · '
                        'dispo ${summary.availabilityPercent.toStringAsFixed(0)} %',
                        style: const TextStyle(fontSize: 12),
                      ),
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _metric(String label, String value) => Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(fontSize: 11, color: Colors.black54)),
            Text(value,
                style:
                    const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          ],
        ),
      );
}
