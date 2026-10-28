import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../sensors/domain/entities/sensor_device.dart';
import '../../../sensors/presentation/providers/sensor_provider.dart';
import '../../../sensors/presentation/screens/cloud_screen.dart';
import '../../../sensors/presentation/screens/device_control_screen.dart';
import '../../../sensors/presentation/screens/device_health_screen.dart';
import '../../../sensors/presentation/screens/gateway_screen.dart';
import '../../../sensors/presentation/screens/ota_update_screen.dart';
import '../../../sensors/presentation/screens/sensor_alerts_screen.dart';
import '../../../sensors/presentation/screens/sensor_settings_screen.dart';

class AdvancedHardwareScreen extends StatefulWidget {
  const AdvancedHardwareScreen({super.key});

  @override
  State<AdvancedHardwareScreen> createState() => _AdvancedHardwareScreenState();
}

class _AdvancedHardwareScreenState extends State<AdvancedHardwareScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<SensorProvider>().initialize();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Matériel avancé / Lab')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          const Card(
            color: Color(0xFFFFF8E1),
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Fonctions expérimentales pour les nœuds ESP32, passerelles '
                'et services distants. Le carnet de culture reste utilisable '
                'sans aucun appareil.',
              ),
            ),
          ),
          _entry(
            Icons.sensors,
            'Nœuds et association',
            'Configurer ou rattacher un appareil à un espace',
            () => _open(const SensorSettingsScreen()),
          ),
          _entry(
            Icons.router_outlined,
            'Passerelle',
            'HTTP, MQTT et nœuds LoRa autorisés',
            () => _open(const GatewayScreen()),
          ),
          _entry(
            Icons.cloud_outlined,
            'Cloud opt-in',
            'Connexion et synchronisation distante',
            () => _open(const CloudScreen()),
          ),
          _entry(
            Icons.notifications_active_outlined,
            'Alertes',
            'Règles et événements persistants',
            () => _open(const SensorAlertsScreen()),
          ),
          _entry(
            Icons.health_and_safety_outlined,
            'Santé des appareils',
            'Disponibilité, batterie et diagnostic',
            () => _open(const DeviceHealthScreen()),
          ),
          _entry(
            Icons.tune,
            'Commandes et automatisations',
            'Commandes sûres et programmes horaires',
            () => _openForDevice(
              (device) => DeviceControlScreen(device: device),
            ),
          ),
          _entry(
            Icons.system_update_alt,
            'Mises à jour OTA',
            'Firmware signé et suivi anti-rollback',
            () => _openForDevice(
              (device) => OtaUpdateScreen(device: device),
            ),
          ),
        ],
      ),
    );
  }

  Widget _entry(
    IconData icon,
    String title,
    String subtitle,
    VoidCallback onTap,
  ) =>
      Card(
        child: ListTile(
          leading: Icon(icon, color: const Color(0xFF2E7D32)),
          title: Text(title),
          subtitle: Text(subtitle),
          trailing: const Icon(Icons.chevron_right),
          onTap: onTap,
        ),
      );

  Future<void> _open(Widget screen) => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => screen),
      );

  Future<void> _openForDevice(
    Widget Function(SensorDevice device) builder,
  ) async {
    final devices = context.read<SensorProvider>().devices;
    if (devices.isEmpty) {
      final configure = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Aucun appareil configuré'),
          content: const Text(
            'Ajoute d’abord un nœud pour accéder à cette fonction.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Plus tard'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Configurer'),
            ),
          ],
        ),
      );
      if (configure == true && mounted) {
        await _open(const SensorSettingsScreen());
      }
      return;
    }
    SensorDevice? selected;
    if (devices.length == 1) {
      selected = devices.first;
    } else {
      selected = await showDialog<SensorDevice>(
        context: context,
        builder: (_) => SimpleDialog(
          title: const Text('Choisir un appareil'),
          children: [
            for (final device in devices)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(context, device),
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.sensors),
                  title: Text(device.name),
                  subtitle: Text(device.status),
                ),
              ),
          ],
        ),
      );
    }
    if (selected != null && mounted) await _open(builder(selected));
  }
}
