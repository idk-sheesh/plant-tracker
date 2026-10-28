import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/services/gardenjournal_backup_service.dart';
import '../../../../core/utils/app_utils.dart';
import '../../../actions/presentation/providers/action_provider.dart';
import '../../../cameras/presentation/providers/camera_provider.dart';
import '../../../groups/presentation/providers/group_provider.dart';
import '../../../plants/presentation/providers/plant_provider.dart';
import '../../../sensors/presentation/providers/sensor_provider.dart';
import '../../../spaces/presentation/providers/space_provider.dart';

class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key});

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  static const _channel = MethodChannel('gardenjournal/platform');
  final _service = GardenJournalBackupService();
  bool _busy = false;
  String? _status;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sauvegarde locale')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'La sauvegarde contient la base locale et les photos du téléphone. '
                'Les JPEG conservés sur le Raspberry Pi restent séparés. '
                'Elle ne contient aucun mot de passe, mais peut contenir '
                'des informations privées : conservez-la dans un emplacement sûr.',
              ),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _busy ? null : _export,
            icon: const Icon(Icons.archive_outlined),
            label: const Text('Créer et partager une sauvegarde'),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _busy ? null : _selectAndRestore,
            icon: const Icon(Icons.restore),
            label: const Text('Restaurer une sauvegarde'),
          ),
          if (_busy) ...[
            const SizedBox(height: 24),
            const Center(child: CircularProgressIndicator()),
          ],
          if (_status != null) ...[
            const SizedBox(height: 24),
            Semantics(
              liveRegion: true,
              child: Text(_status!, textAlign: TextAlign.center),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _export() async {
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      final result = await _service.exportBackup();
      if (!mounted) return;
      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile(
              result.file.path,
              mimeType: 'application/json',
            ),
          ],
          subject: 'Sauvegarde GardenJournal',
          text: result.warnings.isEmpty
              ? 'Sauvegarde GardenJournal vérifiée.'
              : 'Sauvegarde créée avec ${result.warnings.length} avertissement(s).',
        ),
      );
      if (mounted) setState(() => _status = 'Sauvegarde créée et vérifiée.');
    } catch (error) {
      if (mounted) setState(() => _status = 'Échec de la sauvegarde : $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _selectAndRestore() async {
    setState(() {
      _busy = true;
      _status = null;
    });
    File? temporary;
    SensorProvider? sensorProvider;
    var sensorPaused = false;
    var restored = false;
    try {
      final selectedPath =
          await _channel.invokeMethod<String>('pickBackupFile');
      if (selectedPath == null) {
        if (mounted) setState(() => _status = 'Restauration annulée.');
        return;
      }
      temporary = File(selectedPath);
      final inspection = await _service.inspectBackup(temporary);
      if (!mounted) return;
      final confirmed = await _confirmInspectedBackup(inspection);
      if (confirmed != true) {
        if (mounted) setState(() => _status = 'Restauration annulée.');
        return;
      }

      final groupProvider = context.read<GroupProvider>();
      final plantProvider = context.read<PlantProvider>();
      final actionProvider = context.read<ActionProvider>();
      final spaceProvider = context.read<SpaceProvider>();
      final cameraProvider = context.read<CameraProvider>();
      sensorProvider = context.read<SensorProvider>();
      if (sensorProvider.hasActiveOperation) {
        setState(() {
          _status = 'Restauration reportée : attendez la fin de la '
              'synchronisation capteur.';
        });
        return;
      }
      sensorProvider.stopAutoRefresh();
      sensorPaused = true;

      final result = await _service.importBackup(temporary);
      restored = true;
      await Future.wait([
        groupProvider.loadGroups(),
        plantProvider.loadPlants(),
        spaceProvider.refresh(),
      ]);
      final actionsReady = await actionProvider.reloadAfterRestore();
      final sensorsReady = await sensorProvider.reloadAfterRestore();
      final camerasReady = await cameraProvider.reloadAfterRestore();
      sensorPaused = false;

      if (mounted) {
        final warnings = <String>[
          ...inspection.warnings,
          ...result.warnings,
          if (groupProvider.error != null ||
              plantProvider.error != null ||
              spaceProvider.error != null ||
              !actionsReady ||
              !sensorsReady ||
              !camerasReady)
            'Certaines vues ou certains rappels doivent être vérifiés.',
        ];
        setState(() {
          _status = 'Restauration terminée. Sauvegarde de secours : '
              '${path.basename(result.safetyBackup.path)}'
              '${warnings.isEmpty ? '' : ' — ${warnings.length} avertissement(s).'}';
        });
      }
    } on PlatformException catch (error) {
      if (mounted) {
        setState(() => _status =
            'Lecture du fichier impossible : ${error.message ?? error.code}');
      }
    } catch (error) {
      if (mounted) {
        setState(() => _status = restored
            ? 'Données restaurées, mais actualisation incomplète : $error'
            : 'Restauration refusée : $error');
      }
    } finally {
      try {
        if (temporary != null && await temporary.exists()) {
          await temporary.delete();
        }
      } catch (error, stackTrace) {
        FlutterError.reportError(FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'gardenjournal backup',
          context: ErrorDescription('nettoyage du fichier d’import'),
        ));
      }
      if (sensorPaused) sensorProvider?.startAutoRefresh();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool?> _confirmInspectedBackup(BackupInspection inspection) {
    final counts = inspection.tableCounts;
    final sizeMb = inspection.sourceBytes / (1024 * 1024);
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        scrollable: true,
        title: const Text('Confirmer la restauration'),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Sauvegarde vérifiée. Vérifiez son contenu avant de remplacer '
              'les données actuelles.',
            ),
            const SizedBox(height: 12),
            Text('Créée le : '
                '${AppUtils.formatDateTime(inspection.createdAt.toLocal())}'),
            Text('Version app : ${inspection.appVersion}'),
            Text('Version base : ${inspection.databaseVersion}'),
            Text('Plantes : ${counts['plants'] ?? 0}'),
            Text('Actions : ${counts['actions'] ?? 0}'),
            Text('Groupes : ${counts['groups'] ?? 0}'),
            Text('Photos : ${inspection.photoCount}'),
            Text('Taille : ${sizeMb.toStringAsFixed(1)} Mio'),
            if (inspection.warnings.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                '${inspection.warnings.length} avertissement(s) dans '
                'la sauvegarde.',
                style: const TextStyle(color: Color(0xFFF57C00)),
              ),
            ],
            const SizedBox(height: 12),
            const Text(
              'Les données actuelles seront d’abord exportées dans une '
              'sauvegarde de secours, puis remplacées.',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Restaurer'),
          ),
        ],
      ),
    );
  }
}
