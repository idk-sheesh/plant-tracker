import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/utils/app_utils.dart';
import '../../../../core/widgets/photo_viewer_screen.dart';
import '../../../../core/widgets/safe_file_image.dart';
import '../../../actions/domain/entities/plant_action.dart';
import '../../../actions/presentation/providers/action_provider.dart';
import '../../../actions/presentation/screens/edit_action_screen.dart';
import '../../../spaces/presentation/providers/space_provider.dart';
import '../../domain/entities/plant.dart';
import '../../presentation/providers/plant_provider.dart';
import '../screens/cutting_protocol_screen.dart';

class ActionTimeline extends StatelessWidget {
  final String plantId;

  const ActionTimeline({super.key, required this.plantId});

  @override
  Widget build(BuildContext context) {
    return Consumer<ActionProvider>(builder: (context, provider, _) {
      final actions = provider.getActionsForPlant(plantId);

      if (provider.isLoading) {
        return const Padding(
          padding: EdgeInsets.all(32),
          child: Center(child: CircularProgressIndicator()),
        );
      }

      if (provider.error != null && actions.isEmpty) {
        return _historyError(context, provider);
      }

      if (actions.isEmpty) {
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFFF5F5F5),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Column(children: [
                Icon(Icons.timeline, size: 40, color: Color(0xFF9E9E9E)),
                SizedBox(height: 12),
                Text(
                  'Aucune action',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                SizedBox(height: 4),
                Text(
                  'Appuyez sur "Ajouter" pour commencer le suivi',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFF757575), fontSize: 13),
                ),
              ]),
            ),
          ),
        );
      }

      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          children: [
            if (provider.error != null) _historyWarning(provider.error!),
            ...List.generate(
              actions.length,
              (i) =>
                  _item(context, actions[i], i == actions.length - 1, provider),
            ),
          ],
        ),
      );
    });
  }

  Widget _historyError(BuildContext context, ActionProvider provider) =>
      Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.error_outline, color: Colors.red, size: 36),
          const SizedBox(height: 8),
          Text(provider.error!, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => provider.loadActionsForPlant(plantId),
            icon: const Icon(Icons.refresh),
            label: const Text('Réessayer'),
          ),
        ]),
      );

  Widget _historyWarning(String message) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF8E1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(children: [
          const Icon(Icons.warning_amber, color: Color(0xFFF57C00), size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text(message, style: const TextStyle(fontSize: 12))),
        ]),
      );

  Widget _item(
    BuildContext context,
    PlantAction action,
    bool isLast,
    ActionProvider provider,
  ) {
    final color = AppUtils.actionColor(action.actionType);
    final isParentCuttingRecord = action.actionType == 'bouturage' &&
        action.parentPlantId == plantId &&
        action.plantId != plantId;

    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: 40,
          child: Column(children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                shape: BoxShape.circle,
                border: Border.all(color: color, width: 2),
              ),
              child: Icon(AppUtils.actionIcon(action.actionType),
                  color: color, size: 18),
            ),
            if (!isLast)
              Expanded(
                child: Container(
                  width: 2,
                  color: const Color(0xFFE0E0E0),
                  margin: const EdgeInsets.symmetric(vertical: 4),
                ),
              ),
          ]),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: GestureDetector(
            onLongPress: isParentCuttingRecord
                ? null
                : () => _options(context, action, provider),
            child: Container(
              margin: EdgeInsets.only(bottom: isLast ? 0 : 12),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: color.withValues(alpha: 0.2)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        AppUtils.actionLabel(action.actionType),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: color,
                        ),
                      ),
                    ),
                    if (action.isWateringCombined) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 3),
                        decoration: BoxDecoration(
                          color:
                              const Color(0xFF29B6F6).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          '+ Arrosage',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF29B6F6),
                          ),
                        ),
                      ),
                    ],
                    if (action.isPlanned) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 3),
                        decoration: BoxDecoration(
                          color:
                              const Color(0xFFFFA000).withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'En attente',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFFFF8F00),
                          ),
                        ),
                      ),
                    ],
                    const Spacer(),
                    Text(
                      AppUtils.timeAgo(action.timestamp),
                      style: const TextStyle(
                          fontSize: 11, color: Color(0xFF9E9E9E)),
                    ),
                    if (!isParentCuttingRecord)
                      IconButton(
                        icon: const Icon(Icons.more_horiz,
                            size: 18, color: Color(0xFF757575)),
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints:
                            const BoxConstraints(minWidth: 32, minHeight: 32),
                        onPressed: () => _options(context, action, provider),
                      ),
                  ]),
                  const SizedBox(height: 10),
                  _details(context, action, color,
                      isParentCuttingRecord: isParentCuttingRecord),
                  if (action.actionType == 'bouturage' &&
                      !action.isPlanned) ...[
                    const SizedBox(height: 10),
                    GardenCuttingProtocolButton(
                      startDate: action.timestamp,
                      cuttingCount: action.quantity?.toInt(),
                    ),
                  ],
                  if (action.isPlanned) ...[
                    const SizedBox(height: 10),
                    Row(children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () =>
                              _postponePlanned(context, action, provider),
                          icon: const Icon(Icons.schedule, size: 16),
                          label: const Text('Reporter 1h'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () =>
                              _completePlanned(context, action, provider),
                          icon: const Icon(Icons.check, size: 16),
                          label: const Text('Valider'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF2E7D32),
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                    ]),
                  ],
                  if (action.notes != null && action.notes!.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFAFAFA),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.notes,
                              size: 14, color: Color(0xFF9E9E9E)),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              action.notes!,
                              style: const TextStyle(
                                  fontSize: 12, color: Color(0xFF616161)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (action.photoPaths.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 70,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: action.photoPaths.length,
                        itemBuilder: (_, i) => GestureDetector(
                          onTap: () =>
                              _fullscreen(context, action.photoPaths, i),
                          child: Container(
                            margin: const EdgeInsets.only(right: 6),
                            width: 70,
                            height: 70,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: SafeFileImage(
                                path: action.photoPaths[i],
                                fit: BoxFit.cover,
                                semanticLabel: 'Photo de l’action',
                                enableFullscreen: false,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 6),
                  Text(
                    AppUtils.formatDateTime(action.timestamp),
                    style:
                        const TextStyle(fontSize: 11, color: Color(0xFFBDBDBD)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _details(BuildContext context, PlantAction action, Color color,
      {bool isParentCuttingRecord = false}) {
    final chips = <Widget>[];

    if (action.quantity != null) {
      chips.add(_chip('${action.quantity}${action.quantityUnit ?? ""}', color));
    }
    if (action.phNA) {
      chips.add(_chip('pH N/A', const Color(0xFF1976D2)));
    } else if (action.ph != null) {
      chips.add(_chip(
          'pH ${action.ph!.toStringAsFixed(1)}', const Color(0xFF1976D2)));
    }
    if (action.tdsNA) {
      chips.add(_chip('TDS N/A', const Color(0xFF7B1FA2)));
    } else if (action.tds != null) {
      chips.add(_chip(
          '${action.tds!.toStringAsFixed(0)} ppm', const Color(0xFF7B1FA2)));
    }
    if (action.productUsed != null) {
      chips.add(_chip(action.productUsed!, color));
    }
    if (action.pruningType != null) {
      chips.add(_chip(action.pruningType!, color));
    }
    if (action.actionType == 'recolte') {
      if (action.harvestWeightFresh != null) {
        chips.add(_chip(
            'Récolté ${action.harvestWeightFresh!.toStringAsFixed(1)} g',
            color));
      }
      if (action.harvestWeightStored != null) {
        chips.add(_chip(
            'Conservé ${action.harvestWeightStored!.toStringAsFixed(1)} g',
            color));
      }
      if (action.harvestWeightWaste != null) {
        chips.add(_chip(
            'Écarté ${action.harvestWeightWaste!.toStringAsFixed(1)} g',
            color));
      }
      if (action.harvestWeightFresh == null &&
          action.harvestWeightStored == null &&
          action.harvestWeightWaste == null) {
        chips.add(_chip('Recolte', color));
      }
    }
    if (action.actionType == 'bouturage') {
      if (action.quantity != null) {
        final count = action.quantity!.toInt();
        chips.add(_chip(
          isParentCuttingRecord
              ? '$count branche(s) coupée(s) pour bouturage'
              : '$count bouture(s)',
          color,
        ));
      }
      if (isParentCuttingRecord) {
        final cutting = context
            .read<PlantProvider>()
            .allPlants
            .where((p) => p.id == action.plantId)
            .firstOrNull;
        if (cutting != null) {
          chips.add(_chip('Bouture : ${cutting.name}', color));
        }
      } else if (action.parentPlantId != null) {
        final parent = context
            .read<PlantProvider>()
            .allPlants
            .where((p) => p.id == action.parentPlantId)
            .firstOrNull;
        if (parent != null) {
          chips.add(_chip('Source: ${parent.name}', color));
        }
      }
      if (action.cuttingNotes != null) {
        chips.add(_chip(action.cuttingNotes!, color));
      }
    }

    if (chips.isEmpty) return const SizedBox.shrink();
    return Wrap(spacing: 6, runSpacing: 6, children: chips);
  }

  Widget _chip(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 12,
            color: color,
            fontWeight: FontWeight.w500,
          ),
        ),
      );

  void _fullscreen(BuildContext context, List<String> photos, int index) {
    PhotoViewerScreen.openGallery(
      context,
      photos,
      initialIndex: index,
      semanticLabel: 'Photo de l’action',
    );
  }

  void _options(
      BuildContext context, PlantAction action, ActionProvider provider) {
    final sourcePlant = context
        .read<PlantProvider>()
        .allPlants
        .where((plant) => plant.id == action.plantId)
        .firstOrNull;
    final canRepeatHere = sourcePlant != null &&
        !sourcePlant.isDead &&
        !sourcePlant.isHarvested &&
        _canRepeatHere(action);
    final sourceCycleActive =
        sourcePlant != null && !sourcePlant.isDead && !sourcePlant.isHarvested;
    final canCopyToPlants = _canCopyToPlants(action);
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 8),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 8),
          if (action.isPlanned && sourceCycleActive)
            ListTile(
              leading: const Icon(Icons.check_circle_outline,
                  color: Color(0xFF2E7D32)),
              title: const Text('Valider maintenant'),
              subtitle: const Text('Passe cette action en historique fait'),
              onTap: () {
                Navigator.pop(context);
                _completePlanned(context, action, provider);
              },
            ),
          if (action.isPlanned && sourceCycleActive)
            ListTile(
              leading:
                  const Icon(Icons.schedule_outlined, color: Color(0xFFF57C00)),
              title: const Text('Reporter 1h'),
              subtitle: const Text('Garde action en attente'),
              onTap: () {
                Navigator.pop(context);
                _postponePlanned(context, action, provider);
              },
            ),
          if (action.isPlanned && !sourceCycleActive)
            const ListTile(
              leading: Icon(Icons.lock_outline, color: Colors.grey),
              title: Text('Cycle terminé'),
              subtitle: Text(
                'Cette action ne peut plus être validée ni reportée.',
              ),
            ),
          if (!action.isPlanned && canRepeatHere)
            ListTile(
              leading: const Icon(Icons.repeat, color: Color(0xFF1976D2)),
              title: const Text('Repeter maintenant'),
              subtitle: Text(_copySubtitle(action)),
              onTap: () {
                Navigator.pop(context);
                _repeatNow(context, action, provider);
              },
            ),
          if (!action.isPlanned && canCopyToPlants)
            ListTile(
              leading:
                  const Icon(Icons.copy_all_outlined, color: Color(0xFF7B1FA2)),
              title: const Text('Copier vers plantes'),
              subtitle: Text(_copySubtitle(action)),
              onTap: () {
                Navigator.pop(context);
                _copyToPlants(context, action, provider);
              },
            ),
          ListTile(
            leading: const Icon(Icons.edit_outlined, color: Color(0xFF2E7D32)),
            title: const Text('Modifier'),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => EditActionScreen(action: action),
                ),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline, color: Colors.red),
            title: const Text('Supprimer', style: TextStyle(color: Colors.red)),
            onTap: () {
              Navigator.pop(context);
              _confirmDelete(context, action, provider);
            },
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  Future<void> _completePlanned(
    BuildContext context,
    PlantAction action,
    ActionProvider provider,
  ) async {
    try {
      await provider.completePlannedAction(action);
      if (context.mounted) {
        await Future.wait([
          context.read<PlantProvider>().loadPlants(),
          context.read<SpaceProvider>().refresh(),
        ]);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('${AppUtils.actionLabel(action.actionType)} validé'),
            backgroundColor: const Color(0xFF2E7D32),
          ));
        }
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Validation impossible: $error'),
          backgroundColor: Colors.red,
        ));
      }
    }
  }

  Future<void> _postponePlanned(
    BuildContext context,
    PlantAction action,
    ActionProvider provider,
  ) async {
    try {
      await provider.postponePlannedAction(action, const Duration(hours: 1));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Action reportée de 1h'),
          backgroundColor: Color(0xFFF57C00),
        ));
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Report impossible: $error'),
          backgroundColor: Colors.red,
        ));
      }
    }
  }

  bool _canRepeatHere(PlantAction action) {
    return action.actionType == 'arrosage' ||
        action.actionType == 'nutriments' ||
        action.actionType == 'traitement' ||
        action.actionType == 'mesure' ||
        action.actionType == 'observation';
  }

  bool _canCopyToPlants(PlantAction action) {
    return action.actionType != 'recolte';
  }

  String _copySubtitle(PlantAction action) {
    switch (action.actionType) {
      case 'arrosage':
        return 'Volume, pH et TDS';
      case 'nutriments':
        return 'Dose, produit, pH et TDS';
      case 'traitement':
        return 'Produit, dose, cible et notes';
      case 'mesure':
        return 'pH, TDS et contexte';
      case 'rempotage':
        return 'Nouveau contenant / pot';
      case 'taille':
        return 'Type de taille et notes';
      case 'floraison':
        return 'Passage en floraison';
      case 'bouturage':
        return 'Nombre, source et notes';
      case 'observation':
        return 'Notes et observation';
      default:
        return 'Memes valeurs';
    }
  }

  Future<void> _repeatNow(
    BuildContext context,
    PlantAction action,
    ActionProvider provider,
  ) async {
    try {
      final copy = await provider.repeatAction(action);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                '${AppUtils.actionLabel(copy.actionType)} repete maintenant'),
            backgroundColor: AppUtils.actionColor(copy.actionType),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur copie action: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _copyToPlants(
    BuildContext context,
    PlantAction action,
    ActionProvider provider,
  ) async {
    final allPlants = context.read<PlantProvider>().allPlants;
    final sourcePlant =
        allPlants.where((p) => p.id == action.plantId).firstOrNull;
    final targets = allPlants
        .where((p) => p.id != action.plantId && !p.isDead && !p.isHarvested)
        .toList()
      ..sort((a, b) {
        if (a.isHarvested != b.isHarvested) return a.isHarvested ? 1 : -1;
        if (a.groupId == sourcePlant?.groupId &&
            b.groupId != sourcePlant?.groupId) {
          return -1;
        }
        if (a.groupId != sourcePlant?.groupId &&
            b.groupId == sourcePlant?.groupId) {
          return 1;
        }
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });

    if (targets.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Aucune autre plante disponible'),
          backgroundColor: Colors.orange,
        ));
      }
      return;
    }

    final selected = <String>{};
    final copiedCount = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => _CopyActionSheet(
        action: action,
        sourcePlant: sourcePlant,
        targets: targets,
        selected: selected,
        provider: provider,
      ),
    );

    if (context.mounted && copiedCount != null && copiedCount > 0) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          '${AppUtils.actionLabel(action.actionType)} copie vers $copiedCount plante${copiedCount > 1 ? "s" : ""}',
        ),
        backgroundColor: AppUtils.actionColor(action.actionType),
      ));
    }
  }

  Future<void> _confirmDelete(
    BuildContext context,
    PlantAction action,
    ActionProvider provider,
  ) async {
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Supprimer ?'),
        content: Text(
          'Supprimer cet enregistrement "${AppUtils.actionLabel(action.actionType)}" ?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              try {
                await provider.deleteAction(action.plantId, action.id);
                if (context.mounted) {
                  await context.read<PlantProvider>().loadPlants();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('Action supprimée'),
                    ));
                  }
                }
              } catch (error) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text('Suppression impossible: $error'),
                    backgroundColor: Colors.red,
                  ));
                }
              }
            },
            child: const Text('Supprimer', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}

class _CopyActionSheet extends StatefulWidget {
  final PlantAction action;
  final Plant? sourcePlant;
  final List<Plant> targets;
  final Set<String> selected;
  final ActionProvider provider;

  const _CopyActionSheet({
    required this.action,
    required this.sourcePlant,
    required this.targets,
    required this.selected,
    required this.provider,
  });

  @override
  State<_CopyActionSheet> createState() => _CopyActionSheetState();
}

class _CopyActionSheetState extends State<_CopyActionSheet> {
  bool _isSaving = false;

  @override
  Widget build(BuildContext context) {
    final color = AppUtils.actionColor(widget.action.actionType);
    final sameGroup = widget.sourcePlant?.groupId;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 10,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 14),
          Row(children: [
            Icon(Icons.copy_all_outlined, color: color),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Copier ${AppUtils.actionLabel(widget.action.actionType)}',
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'Nouvelle action avec les memes valeurs',
                    style: TextStyle(fontSize: 12, color: Color(0xFF757575)),
                  ),
                ],
              ),
            ),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            _quickButton(
              label: 'Meme groupe',
              onTap: sameGroup == null
                  ? null
                  : () => _selectWhere((p) =>
                      p.groupId == sameGroup && !p.isHarvested && !p.isDead),
            ),
            const SizedBox(width: 8),
            _quickButton(
              label: 'Actives',
              onTap: () => _selectWhere((p) => !p.isHarvested && !p.isDead),
            ),
            const SizedBox(width: 8),
            _quickButton(
              label: 'Vider',
              onTap: widget.selected.isEmpty
                  ? null
                  : () => setState(() => widget.selected.clear()),
            ),
          ]),
          const SizedBox(height: 12),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 360),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: widget.targets.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, index) {
                final plant = widget.targets[index];
                final isSelected = widget.selected.contains(plant.id);
                return CheckboxListTile(
                  value: isSelected,
                  enabled: !_isSaving,
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text(
                    plant.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: plant.isHarvested
                          ? const Color(0xFF9E9E9E)
                          : const Color(0xFF212121),
                    ),
                  ),
                  subtitle: Text(
                    [
                      if (plant.variety != null && plant.variety!.isNotEmpty)
                        plant.variety!,
                      plant.isHarvested ? 'Recoltee' : 'Active',
                      if (plant.groupId == widget.sourcePlant?.groupId)
                        'meme groupe',
                    ].join(' - '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onChanged: (value) {
                    setState(() {
                      if (value == true) {
                        widget.selected.add(plant.id);
                      } else {
                        widget.selected.remove(plant.id);
                      }
                    });
                  },
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: widget.selected.isEmpty || _isSaving ? null : _save,
              icon: _isSaving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.copy_all_outlined),
              label: Text(
                widget.selected.isEmpty
                    ? 'Selectionner au moins une plante'
                    : 'Copier vers ${widget.selected.length} plante${widget.selected.length > 1 ? "s" : ""}',
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: color,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _quickButton({required String label, required VoidCallback? onTap}) {
    return Expanded(
      child: OutlinedButton(
        onPressed: _isSaving ? null : onTap,
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        ),
        child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
    );
  }

  void _selectWhere(bool Function(Plant plant) test) {
    setState(() {
      widget.selected
        ..clear()
        ..addAll(widget.targets.where(test).map((p) => p.id));
    });
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    try {
      final copied = await widget.provider.copyActionToPlants(
        widget.action,
        widget.selected.toList(),
      );
      if (mounted) Navigator.pop(context, copied.length);
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Erreur copie: $e'),
          backgroundColor: Colors.red,
        ));
      }
    }
  }
}
