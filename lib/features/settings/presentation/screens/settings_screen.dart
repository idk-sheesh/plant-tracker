import 'package:flutter/material.dart';

import '../../../../core/config/app_config.dart';
import 'advanced_hardware_screen.dart';
import 'backup_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(title: const Text('Réglages')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _entry(
            context,
            Icons.archive_outlined,
            'Sauvegarde locale',
            'Exporter ou restaurer la base et les photos',
            const BackupScreen(),
          ),
          _entry(
            context,
            Icons.science_outlined,
            'Matériel avancé / Lab',
            'Cloud, passerelle, alertes, santé, OTA et automatisations',
            const AdvancedHardwareScreen(),
          ),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    const Icon(Icons.science, color: Color(0xFF2E7D32)),
                    const SizedBox(width: 10),
                    Text(
                      AppConfig.editionLabel,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ]),
                  const SizedBox(height: 12),
                  const Text(
                    'Carnet de jardinage pour tomates et orchidées. Les '
                    'données sont conservées localement sur votre appareil.',
                  ),
                  const Divider(height: 28),
                  _line('Application', AppConfig.appName),
                  _line('Projet', AppConfig.projectLabel),
                  _line('Version publique', AppConfig.editionLabel),
                  _line('Version technique', AppConfig.appVersion),
                  _line('Build', AppConfig.buildId),
                  _line('Testeur', AppConfig.testerId),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _entry(
    BuildContext context,
    IconData icon,
    String title,
    String subtitle,
    Widget screen,
  ) =>
      Card(
        child: ListTile(
          leading: Icon(icon, color: const Color(0xFF2E7D32)),
          title: Text(title),
          subtitle: Text(subtitle),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => screen),
          ),
        ),
      );

  Widget _line(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 124,
              child: Text(label, style: const TextStyle(color: Colors.black54)),
            ),
            Expanded(
              child: Text(value,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      );
}
