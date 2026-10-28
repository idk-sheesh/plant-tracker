import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../domain/entities/plant.dart';
import '../../../actions/presentation/providers/action_provider.dart';
import '../../../groups/presentation/providers/group_provider.dart';
import '../../presentation/providers/plant_provider.dart';
import '../screens/plant_detail_screen.dart';
import '../../../../core/utils/numeric_input_parser.dart';
import '../../../../core/utils/app_utils.dart';
import '../../../../core/widgets/safe_file_image.dart';

class PlantCard extends StatelessWidget {
  final Plant plant;
  final int? daysSinceWater;
  final DateTime? floweringStart;

  const PlantCard({
    super.key,
    required this.plant,
    this.daysSinceWater,
    this.floweringStart,
  });

  @override
  Widget build(BuildContext context) {
    final group = context.read<GroupProvider>().getGroupById(plant.groupId);
    final waterColor = _waterColor();

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: plant.isPinned ? 4 : 2,
      color: plant.isPinned ? const Color(0xFFFFFDE7) : null,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => PlantDetailScreen(plantId: plant.id))),
        onLongPress: () => _showCardMenu(context),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            _photo(),
            const SizedBox(width: 14),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Row(children: [
                    if (plant.isPinned) ...[
                      const Icon(Icons.push_pin,
                          size: 13, color: Color(0xFFF57C00)),
                      const SizedBox(width: 4),
                    ],
                    Expanded(
                        child: Text(plant.name,
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w700),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis)),
                    if (plant.isDead)
                      _badge('Morte', const Color(0xFF616161))
                    else if (plant.isHarvested)
                      _badge('Recoltee', const Color(0xFFF57F17))
                    else if (group != null)
                      _badge(group.name, group.color),
                  ]),
                  if (plant.variety != null && plant.variety!.isNotEmpty)
                    Text(plant.variety!,
                        style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF757575),
                            fontStyle: FontStyle.italic)),
                  if (plant.observationCode?.isNotEmpty == true)
                    Text('Repère ${plant.observationCode}',
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  Wrap(spacing: 6, runSpacing: 4, children: [
                    _infoChip(_locationIcon(), plant.locationLabel,
                        const Color(0xFF388E3C)),
                    _infoChip(_containerIcon(), plant.containerLabel,
                        const Color(0xFF795548)),
                    _infoChip(_originIcon(), plant.originLabel,
                        const Color(0xFF7B1FA2)),
                  ]),
                  const SizedBox(height: 4),
                  if (floweringStart != null &&
                      !plant.isDead &&
                      !plant.isHarvested)
                    Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                            'Floraison · ${AppUtils.floweringDuration(floweringStart!).toLowerCase()}',
                            style: const TextStyle(
                                fontSize: 12, color: Color(0xFF7B1FA2)))),
                  Wrap(spacing: 6, runSpacing: 4, children: [
                    _infoChip(Icons.schedule, '${plant.daysSincePotting}j',
                        const Color(0xFF1976D2)),
                    if (plant.isDead)
                      _infoChip(
                          Icons.eco_outlined, 'Morte', const Color(0xFF616161))
                    else if (plant.isHarvested)
                      _infoChip(Icons.agriculture, 'Recoltee',
                          const Color(0xFFF57F17))
                    else if (plant.containerType == 'plein_sol' &&
                        !plant.hasWateringReminder)
                      _infoChip(
                          Icons.grass, 'Plein sol', const Color(0xFF795548))
                    else if (!plant.hasWateringReminder)
                      _infoChip(Icons.water_drop_outlined, 'Rappel désactivé',
                          const Color(0xFF757575))
                    else
                      _infoChip(
                          Icons.water_drop,
                          daysSinceWater == null
                              ? 'Jamais'
                              : daysSinceWater == 0
                                  ? 'Auj.'
                                  : '${daysSinceWater}j',
                          waterColor),
                  ]),
                ])),
            if (!plant.isHarvested &&
                !plant.isDead &&
                (plant.containerType != 'plein_sol' ||
                    plant.hasWateringReminder))
              IconButton(
                  tooltip: 'Arrosage rapide',
                  icon: const Icon(Icons.water_drop,
                      color: Color(0xFF1976D2), size: 22),
                  onPressed: () => _showQuickWaterSheet(context))
            else
              const Icon(Icons.chevron_right, color: Color(0xFFBDBDBD)),
          ]),
        ),
      ),
    );
  }

  Color _waterColor() {
    if (plant.isHarvested || plant.isDead || daysSinceWater == null)
      return const Color(0xFF9E9E9E);
    if (daysSinceWater! > 4) return const Color(0xFFD32F2F);
    if (daysSinceWater! > 2) return const Color(0xFFF57C00);
    return const Color(0xFF1976D2);
  }

  void _showCardMenu(BuildContext context) {
    showModalBottomSheet(
        context: context,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (ctx) => SafeArea(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
              const SizedBox(height: 8),
              Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                      color: const Color(0xFFBDBDBD),
                      borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 12),
              ListTile(
                  leading: Icon(
                      plant.isPinned ? Icons.push_pin_outlined : Icons.push_pin,
                      color: const Color(0xFFF57C00)),
                  title:
                      Text(plant.isPinned ? 'Desepingler' : 'Epingler en haut'),
                  onTap: () {
                    Navigator.pop(ctx);
                    context.read<PlantProvider>().togglePin(plant.id);
                  }),
              const SizedBox(height: 8),
            ])));
  }

  Future<void> _showQuickWaterSheet(BuildContext context) async {
    final result = await showModalBottomSheet<Map<String, String>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _QuickWaterSheet(plantName: plant.name),
    );

    if (!context.mounted || result == null) return;
    await _saveQuickWater(
      context,
      result['volume'] ?? '',
      result['ph'] ?? '',
      result['tds'] ?? '',
    );
  }

  Future<void> _saveQuickWater(
    BuildContext context,
    String vol,
    String ph,
    String tds,
  ) async {
    double? parseOptionalNumber(
      String raw,
      String label, {
      double? min,
      double? max,
    }) {
      return NumericInputParser.optionalBounded(
        raw,
        fieldLabel: label,
        minimum: min,
        maximum: max,
      );
    }

    try {
      final volume = parseOptionalNumber(vol, 'Quantite', min: 0);
      final phValue = parseOptionalNumber(ph, 'pH', min: 3.5, max: 9.0);
      final tdsValue = parseOptionalNumber(tds, 'TDS', min: 0, max: 5000);

      await context.read<ActionProvider>().addAction(
          plantId: plant.id,
          actionType: 'arrosage',
          timestamp: DateTime.now(),
          quantity: volume,
          quantityUnit: 'L',
          ph: phValue,
          phNA: false,
          tds: tdsValue,
          tdsNA: false,
          isWateringCombined: false);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Arrosage enregistre pour ${plant.name}'),
            backgroundColor: const Color(0xFF1976D2),
            duration: const Duration(seconds: 2)));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erreur: $e'), backgroundColor: Colors.red));
      }
    }
  }

  Widget _photo() {
    return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
            width: 72,
            height: 72,
            child: plant.photoPath != null
                ? SafeFileImage(
                    path: plant.photoPath!,
                    fit: BoxFit.cover,
                    semanticLabel: 'Photo de ${plant.name}',
                  )
                : _placeholder()));
  }

  Widget _placeholder() {
    return Container(
      color:
          plant.isHarvested ? const Color(0xFFFFF8E1) : const Color(0xFFE8F5E9),
      child: Center(
        child: Icon(
          plant.isHarvested ? Icons.agriculture : _locationIcon(),
          color: plant.isHarvested
              ? const Color(0xFFF57F17)
              : const Color(0xFF2E7D32),
          size: 34,
        ),
      ),
    );
  }

  IconData _locationIcon() => plant.location == 'outdoor'
      ? Icons.wb_sunny_outlined
      : Icons.home_outlined;

  IconData _containerIcon() {
    switch (plant.containerType) {
      case 'plein_sol':
        return Icons.grass;
      case 'pot_tissu':
        return Icons.shopping_basket_outlined;
      default:
        return Icons.yard_outlined;
    }
  }

  IconData _originIcon() {
    switch (plant.origin) {
      case 'seed':
        return Icons.eco_outlined;
      case 'cutting':
        return Icons.call_split;
      default:
        return Icons.help_outline;
    }
  }

  Widget _badge(String label, Color color) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(8)),
      child: Text(label,
          style: TextStyle(
              color: color, fontSize: 10, fontWeight: FontWeight.w600)));

  Widget _infoChip(IconData icon, String label, Color color) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(6)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 11, color: color),
        const SizedBox(width: 3),
        Text(label,
            style: TextStyle(
                fontSize: 11, color: color, fontWeight: FontWeight.w600),
            maxLines: 1,
            overflow: TextOverflow.ellipsis),
      ]));
}

class _QuickWaterSheet extends StatefulWidget {
  final String plantName;

  const _QuickWaterSheet({required this.plantName});

  @override
  State<_QuickWaterSheet> createState() => _QuickWaterSheetState();
}

class _QuickWaterSheetState extends State<_QuickWaterSheet> {
  final _volumeCtrl = TextEditingController();
  final _phCtrl = TextEditingController();
  final _tdsCtrl = TextEditingController();

  @override
  void dispose() {
    _volumeCtrl.dispose();
    _phCtrl.dispose();
    _tdsCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final bottomPadding = media.viewInsets.bottom + media.padding.bottom + 40;

    return SingleChildScrollView(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, bottomPadding),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            const Icon(Icons.water_drop, color: Color(0xFF1976D2), size: 22),
            const SizedBox(width: 10),
            Expanded(
                child: Text('Arrosage rapide - ${widget.plantName}',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis)),
          ]),
          const SizedBox(height: 4),
          const Text('Volume, pH et TDS facultatifs',
              style: TextStyle(fontSize: 12, color: Color(0xFF9E9E9E))),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
                child: TextField(
                    controller: _volumeCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                        labelText: 'Volume (L)',
                        prefixIcon: Icon(Icons.straighten, size: 18),
                        border: OutlineInputBorder()))),
            const SizedBox(width: 12),
            Expanded(
                child: TextField(
                    controller: _phCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                        labelText: 'pH',
                        prefixIcon: Icon(Icons.science, size: 18),
                        border: OutlineInputBorder()))),
          ]),
          const SizedBox(height: 12),
          TextField(
              controller: _tdsCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                  labelText: 'TDS (ppm)',
                  prefixIcon: Icon(Icons.water_drop_outlined, size: 18),
                  border: OutlineInputBorder())),
          const SizedBox(height: 18),
          SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                  icon: const Icon(Icons.water_drop),
                  label: const Text('Enregistrer'),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1976D2),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16)),
                  onPressed: () {
                    FocusScope.of(context).unfocus();
                    Navigator.pop(context, {
                      'volume': _volumeCtrl.text,
                      'ph': _phCtrl.text,
                      'tds': _tdsCtrl.text,
                    });
                  })),
        ]),
      ),
    );
  }
}
