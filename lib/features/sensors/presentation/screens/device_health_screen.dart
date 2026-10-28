import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../domain/entities/device_health_snapshot.dart';
import '../../domain/entities/sensor_device.dart';
import '../providers/sensor_provider.dart';
import 'sensor_calibration_screen.dart';
import 'ota_update_screen.dart';

class DeviceHealthScreen extends StatelessWidget {
  final String? initialDeviceId;

  const DeviceHealthScreen({super.key, this.initialDeviceId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Santé des appareils'),
        actions: [
          Consumer<SensorProvider>(
            builder: (_, sensors, __) => IconButton(
              tooltip: 'Actualiser',
              onPressed: sensors.isSyncingAll ? null : sensors.syncAllDevices,
              icon: const Icon(Icons.refresh),
            ),
          ),
        ],
      ),
      body: Consumer<SensorProvider>(
        builder: (_, sensors, __) {
          final devices = [...sensors.devices]..sort((a, b) {
              if (a.id == initialDeviceId) return -1;
              if (b.id == initialDeviceId) return 1;
              return a.name.compareTo(b.name);
            });
          if (devices.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Aucun appareil enregistré. Scanne un QR appareil pour '
                  'commencer.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: sensors.syncAllDevices,
            child: ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(12),
              itemCount: devices.length,
              itemBuilder: (_, index) {
                final device = devices[index];
                return _HealthCard(
                  device: device,
                  health: sensors.healthForDevice(device.id),
                  availability: sensors.availabilityForDevice(device.id),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _HealthCard extends StatelessWidget {
  final SensorDevice device;
  final DeviceHealthSnapshot? health;
  final Future<double?> availability;

  const _HealthCard({
    required this.device,
    required this.health,
    required this.availability,
  });

  @override
  Widget build(BuildContext context) {
    final online = health?.isOnline ?? device.isOnline;
    final lastContact = health?.observedAt ?? device.lastSeenAt;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor:
                      online ? Colors.green.shade50 : Colors.orange.shade50,
                  child: Icon(
                    device.deviceKind == 'gateway'
                        ? Icons.router
                        : Icons.sensors,
                    color: online ? Colors.green : Colors.orange,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        device.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        '${device.model ?? device.uid} · ${device.transport.toUpperCase()}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                _StatusChip(online: online),
              ],
            ),
            const Divider(height: 24),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _Metric(
                  label: 'Batterie',
                  value: health?.batteryPercent == null
                      ? '—'
                      : '${health!.batteryPercent!.toStringAsFixed(0)} %',
                ),
                _Metric(
                  label: 'RSSI',
                  value: health?.rssi == null ? '—' : '${health!.rssi} dBm',
                ),
                _Metric(
                  label: 'SNR',
                  value: health?.snr == null
                      ? '—'
                      : '${health!.snr!.toStringAsFixed(1)} dB',
                ),
                FutureBuilder<double?>(
                  future: availability,
                  builder: (_, snapshot) => _Metric(
                    label: 'Disponibilité 24 h',
                    value: snapshot.data == null
                        ? '—'
                        : '${snapshot.data!.toStringAsFixed(0)} %',
                  ),
                ),
                _Metric(
                  label: 'Mesures manquantes',
                  value: '${health?.missingReadings ?? 0}',
                ),
                _Metric(
                  label: 'Firmware',
                  value:
                      health?.firmwareVersion ?? device.firmwareVersion ?? '—',
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              lastContact == null
                  ? 'Aucune communication enregistrée'
                  : 'Dernière observation : '
                      '${DateFormat('dd/MM/yyyy HH:mm').format(lastContact)}',
              style: const TextStyle(color: Colors.black54, fontSize: 12),
            ),
            if (health?.lastError case final error?)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Dernière erreur : $error',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Colors.red.shade700, fontSize: 12),
                ),
              ),
            Align(
              alignment: Alignment.centerRight,
              child: Wrap(
                children: [
                  TextButton.icon(
                    icon: const Icon(Icons.system_update_alt),
                    label: const Text('OTA'),
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => OtaUpdateScreen(device: device),
                      ),
                    ),
                  ),
                  TextButton.icon(
                    icon: const Icon(Icons.science_outlined),
                    label: const Text('Calibrer'),
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => SensorCalibrationScreen(device: device),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  final String label;
  final String value;

  const _Metric({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 125, maxWidth: 180),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 11)),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final bool online;

  const _StatusChip({required this.online});

  @override
  Widget build(BuildContext context) {
    return Chip(
      visualDensity: VisualDensity.compact,
      avatar: Icon(
        online ? Icons.check_circle : Icons.cloud_off,
        size: 16,
        color: online ? Colors.green : Colors.orange,
      ),
      label: Text(online ? 'En ligne' : 'Hors ligne'),
    );
  }
}
