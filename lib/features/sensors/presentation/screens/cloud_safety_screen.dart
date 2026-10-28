import 'package:flutter/material.dart';

import '../../../settings/presentation/screens/backup_screen.dart';

class CloudSafetyScreen extends StatelessWidget {
  const CloudSafetyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sécurité des données')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _warningCard(),
          const SizedBox(height: 12),
          _section(
            icon: Icons.phone_android,
            title: 'Avant une mise à jour de l’application',
            children: const [
              'Ouvrir Beta > Sauvegarde.',
              'Créer et partager une sauvegarde vérifiée hors du téléphone.',
              'Ne jamais désinstaller l’ancienne application ni effacer ses données.',
              'Conserver le même package Android et la même signature pour une mise à jour.',
              'Après installation, vérifier plantes, actions, photos et mesures avant toute autre opération.',
            ],
          ),
          const SizedBox(height: 12),
          _section(
            icon: Icons.memory,
            title: 'Avant de reflasher l’ESP32',
            children: const [
              'Le flash doit utiliser la même table de partitions.',
              'Choisir “Erase Flash: None” ou l’équivalent : LittleFS ne doit pas être effacé.',
              'Le nouveau firmware conserve le format de l’historique local et ajoute une file cloud séparée.',
              'Après redémarrage, vérifier /status puis /readings?since= avant d’activer le cloud.',
              'Ne jamais formater LittleFS pour résoudre une erreur sans sauvegarde ou validation préalable.',
            ],
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.storage_outlined),
              title: const Text('Les 5 jours déjà enregistrés'),
              subtitle: const Text(
                'Les mesures déjà dans SQLite restent locales. Le reflash ne doit '
                'pas toucher la base du téléphone ni LittleFS si l’effacement est désactivé.',
              ),
            ),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const BackupScreen()),
            ),
            icon: const Icon(Icons.archive_outlined),
            label: const Text('Ouvrir la sauvegarde locale'),
          ),
          const SizedBox(height: 12),
          const Text(
            'Aucune action de mise à jour, d’installation ou de flash n’est '
            'déclenchée depuis cet écran.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.black54),
          ),
        ],
      ),
    );
  }

  Widget _warningCard() => Card(
        color: const Color(0xFFFFF3E0),
        child: const Padding(
          padding: EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.warning_amber_rounded, color: Color(0xFFE65100)),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Une mise à jour sûre commence par une sauvegarde vérifiée. '
                  'L’interface cloud ne remplace pas cette sauvegarde.',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
      );

  Widget _section({
    required IconData icon,
    required String title,
    required List<String> children,
  }) =>
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, color: const Color(0xFF2E7D32)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ...children.map(
                (item) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('•  '),
                      Expanded(child: Text(item)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
}
