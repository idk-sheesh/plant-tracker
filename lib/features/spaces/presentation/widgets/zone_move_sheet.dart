import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../groups/data/models/plant_group.dart';
import '../../../plants/domain/entities/plant.dart';
import '../../domain/entities/zone_placement.dart';
import '../providers/space_provider.dart';

Future<bool?> showPlantZoneMoveSheet(
  BuildContext context,
  Plant plant,
) {
  return _showMoveSheet(context, plant: plant);
}

Future<bool?> showGroupZoneMoveSheet(
  BuildContext context,
  PlantGroup group,
) {
  return _showMoveSheet(context, group: group);
}

Future<bool?> _showMoveSheet(
  BuildContext context, {
  Plant? plant,
  PlantGroup? group,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _ZoneMoveSheet(plant: plant, group: group),
  );
}

class _ZoneMoveSheet extends StatefulWidget {
  final Plant? plant;
  final PlantGroup? group;

  const _ZoneMoveSheet({this.plant, this.group});

  @override
  State<_ZoneMoveSheet> createState() => _ZoneMoveSheetState();
}

class _ZoneMoveSheetState extends State<_ZoneMoveSheet> {
  final _note = TextEditingController();
  String? _zoneId;
  bool _saving = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final spaces = context.watch<SpaceProvider>();
    final current = widget.plant != null
        ? spaces.placementForPlant(widget.plant!)
        : spaces.placementForGroup(widget.group!.id);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          20,
          20,
          20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Déplacer ${widget.plant?.name ?? widget.group!.name}',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 6),
            Text(
              current == null
                  ? 'Aucun espace actuel'
                  : 'Actuellement : ${spaces.getZone(current.zoneId)?.name ?? 'Zone inconnue'}',
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _zoneId,
              decoration: const InputDecoration(labelText: 'Nouvel espace'),
              items: spaces.zones
                  .map(
                    (zone) => DropdownMenuItem(
                      value: zone.id,
                      child: Text(zone.name),
                    ),
                  )
                  .toList(),
              onChanged: (value) => setState(() => _zoneId = value),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _note,
              decoration: const InputDecoration(labelText: 'Note (facultatif)'),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _saving || _zoneId == null ? null : _move,
                icon: const Icon(Icons.move_down),
                label: const Text('Déplacer vers cette zone'),
              ),
            ),
            if (current != null) ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _saving ? null : () => _close(current),
                  icon: const Icon(Icons.stop_circle_outlined),
                  label: Text(current.groupId != null
                      ? 'Clôturer le placement du groupe'
                      : 'Clôturer ce placement'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _move() async {
    final spaces = context.read<SpaceProvider>();
    final zone = spaces.getZone(_zoneId)!;
    setState(() => _saving = true);
    if (widget.plant != null) {
      await spaces.movePlant(widget.plant!, zone, note: _note.text.trim());
    } else {
      await spaces.moveGroup(widget.group!, zone, note: _note.text.trim());
    }
    if (mounted) Navigator.pop(context, true);
  }

  Future<void> _close(ZonePlacement placement) async {
    final spaces = context.read<SpaceProvider>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Clôturer le placement ?'),
        content: Text(
          placement.groupId != null
              ? 'Les plantes de ce groupe ne seront plus présentes dans la zone. '
                  'L’historique sera conservé.'
              : 'La plante ne sera plus présente dans la zone. '
                  'L’historique sera conservé.',
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
    setState(() => _saving = true);
    try {
      await spaces.closePlacement(placement);
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Impossible de clôturer le placement : $error')),
        );
      }
    }
  }
}
