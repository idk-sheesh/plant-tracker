import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../../domain/entities/plant.dart';
import '../providers/plant_provider.dart';
import '../../../actions/domain/entities/plant_action.dart';
import '../../../actions/presentation/providers/action_provider.dart';
import '../../../groups/presentation/providers/group_provider.dart';
import '../../../plants/presentation/screens/add_action_screen.dart';
import '../widgets/action_timeline.dart';
import '../widgets/qr_code_dialog.dart';
import '../../../../core/utils/app_utils.dart';
import '../../../../core/widgets/photo_viewer_screen.dart';
import '../../../../core/widgets/safe_file_image.dart';
import 'edit_plant_screen.dart';
import '../../../../core/services/shareable_export_service.dart';
import '../../../spaces/presentation/providers/space_provider.dart';
import '../../../spaces/presentation/widgets/zone_move_sheet.dart';
import '../../../spaces/domain/entities/zone_placement.dart';
import '../../../sensors/domain/entities/sensor_reading.dart';
import 'cycle_export_screen.dart';
import '../../../observations/presentation/screens/observation_screen.dart';

class PlantDetailScreen extends StatefulWidget {
  final String plantId;
  final bool showQr;
  const PlantDetailScreen(
      {super.key, required this.plantId, this.showQr = false});
  @override
  State<PlantDetailScreen> createState() => _PlantDetailScreenState();
}

class _PlantDetailScreenState extends State<PlantDetailScreen> {
  Plant? _plant;
  bool _isLoading = true;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _loadError = null;
      });
    }
    try {
      final plant =
          await context.read<PlantProvider>().getPlantById(widget.plantId);
      await context.read<ActionProvider>().loadActionsForPlant(widget.plantId);
      if (mounted) {
        setState(() => _plant = plant);
        if (plant != null && widget.showQr) {
          WidgetsBinding.instance.addPostFrameCallback((_) => _showQr(plant));
        }
      }
    } catch (error, stackTrace) {
      FlutterError.reportError(FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'gardenjournal plant detail',
        context: ErrorDescription('chargement de la fiche plante'),
      ));
      if (mounted) _loadError = 'Impossible de charger cette plante';
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
              ? _loadErrorView()
              : _plant == null
                  ? const Center(child: Text('Plante introuvable'))
                  : Consumer2<PlantProvider, ActionProvider>(
                      builder: (_, pp, ap, __) {
                      final plant = pp.allPlants.firstWhere(
                          (p) => p.id == widget.plantId,
                          orElse: () => _plant!);
                      return _content(plant, ap);
                    }),
    );
  }

  Widget _loadErrorView() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 42),
            const SizedBox(height: 12),
            Text(_loadError!, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh),
              label: const Text('Réessayer'),
            ),
          ]),
        ),
      );

  Widget _content(Plant plant, ActionProvider ap) {
    final doneActions =
        ap.getActionsForPlant(plant.id).where((a) => a.isDone).toList();

    final lastWater = doneActions
        .where((a) =>
            a.actionType == 'arrosage' ||
            (a.actionType == 'nutriments' && a.isWateringCombined))
        .toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    final daysSinceWater = (!plant.isHarvested &&
            !plant.isDead &&
            plant.hasWateringReminder &&
            lastWater.isNotEmpty)
        ? DateTime.now().difference(lastWater.first.timestamp).inDays
        : null;

    final lastRepot = doneActions
        .where((a) => a.actionType == 'rempotage')
        .toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    final currentPot =
        lastRepot.isNotEmpty && lastRepot.first.productUsed != null
            ? lastRepot.first.productUsed
            : plant.potSize;

    return CustomScrollView(slivers: [
      _appBar(plant),
      SliverToBoxAdapter(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _infoCards(plant, ap, daysSinceWater, currentPot),
        Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: OutlinedButton.icon(
                icon: const Icon(Icons.science_outlined),
                label: const Text('Noter / comparer les plantes'),
                onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) =>
                            ObservationScreen(initialPlantId: plant.id))))),
        _zoneHistory(plant),
        _chartSection(doneActions),
        _actionsHeader(plant),
        ActionTimeline(plantId: plant.id),
        const SizedBox(height: 100),
      ])),
    ]);
  }

  // AppBar
  Widget _appBar(Plant plant) => SliverAppBar(
        expandedHeight: plant.photoPath != null ? 260 : 160,
        pinned: true,
        backgroundColor: const Color(0xFF2E7D32),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
              icon: const Icon(Icons.qr_code), onPressed: () => _showQr(plant)),
          PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              onSelected: (v) => _menu(v, plant),
              itemBuilder: (_) => [
                    const PopupMenuItem(
                        value: 'edit',
                        child: Row(children: [
                          Icon(Icons.edit_outlined, size: 20),
                          SizedBox(width: 10),
                          Text('Modifier')
                        ])),
                    if (!plant.isDead && !plant.isHarvested)
                      const PopupMenuItem(
                          value: 'move_zone',
                          child: Row(children: [
                            Icon(Icons.move_down, size: 20),
                            SizedBox(width: 10),
                            Text('Déplacer vers une zone')
                          ])),
                    const PopupMenuItem(
                        value: 'duplicate',
                        child: Row(children: [
                          Icon(Icons.copy_outlined, size: 20),
                          SizedBox(width: 10),
                          Text('Dupliquer')
                        ])),
                    const PopupMenuItem(
                        value: 'export',
                        child: Row(children: [
                          Icon(Icons.picture_as_pdf_outlined,
                              size: 20, color: Color(0xFF1976D2)),
                          SizedBox(width: 10),
                          Text('Exporter historique PDF',
                              style: TextStyle(color: Color(0xFF1976D2)))
                        ])),
                    const PopupMenuItem(
                        value: 'cycle_export',
                        child: Row(children: [
                          Icon(Icons.verified_outlined,
                              size: 20, color: Color(0xFF2E7D32)),
                          SizedBox(width: 10),
                          Text('Exporter cycle vérifiable',
                              style: TextStyle(color: Color(0xFF2E7D32)))
                        ])),
                    const PopupMenuItem(
                        value: 'delete',
                        child: Row(children: [
                          Icon(Icons.delete_outline,
                              size: 20, color: Colors.red),
                          SizedBox(width: 10),
                          Text('Supprimer', style: TextStyle(color: Colors.red))
                        ])),
                  ]),
        ],
        flexibleSpace: FlexibleSpaceBar(
          titlePadding:
              const EdgeInsetsDirectional.only(start: 56, end: 72, bottom: 14),
          title: Text(plant.name,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
          background: plant.photoPath != null
              ? GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => PhotoViewerScreen.open(
                    context,
                    plant.photoPath!,
                    semanticLabel: 'Photo de ${plant.name}',
                  ),
                  child: Stack(fit: StackFit.expand, children: [
                    SafeFileImage(
                      path: plant.photoPath!,
                      fit: BoxFit.cover,
                      semanticLabel: 'Photo de ${plant.name}',
                      enableFullscreen: false,
                    ),
                    IgnorePointer(
                      child: Container(
                          decoration: BoxDecoration(
                              gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.7)
                          ]))),
                    ),
                  ]),
                )
              : Container(
                  decoration: const BoxDecoration(
                      gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFF2E7D32), Color(0xFF4CAF50)])),
                  child: Center(
                      child: Icon(
                          plant.isDead
                              ? Icons.eco_outlined
                              : plant.isHarvested
                                  ? Icons.agriculture
                                  : Icons.local_florist,
                          size: 80,
                          color: Colors.white70))),
        ),
      );

  // Info cards
  Widget _infoCards(
      Plant plant, ActionProvider ap, int? daysSinceWater, String? currentPot) {
    final group = context.read<GroupProvider>().getGroupById(plant.groupId);
    final waterColor = daysSinceWater == null
        ? const Color(0xFF9E9E9E)
        : daysSinceWater > 4
            ? const Color(0xFFD32F2F)
            : daysSinceWater > 2
                ? const Color(0xFFF57C00)
                : const Color(0xFF1976D2);
    final actions =
        ap.getActionsForPlant(plant.id).where((a) => a.isDone).toList();
    final recoltes = actions.where((a) => a.actionType == 'recolte').toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    final floraisons = actions
        .where((a) => a.actionType == 'floraison')
        .toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

    // Poids recolte depuis la derniere action recolte
    final harvestAction = recoltes.isNotEmpty ? recoltes.first : null;
    final hasWet = harvestAction?.harvestWeightFresh != null;
    final hasDry = harvestAction?.harvestWeightStored != null;
    final hasWaste = harvestAction?.harvestWeightWaste != null;

    return Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Consumer<SpaceProvider>(builder: (_, spaces, __) {
            final cycleEnded = plant.isDead || plant.isHarvested;
            final placement = spaces.placementForPlant(plant);
            final zone = spaces.getZone(placement?.zoneId);
            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: ListTile(
                leading: const Icon(Icons.location_on_outlined),
                title: Text(cycleEnded
                    ? 'Hors des espaces actifs'
                    : zone?.name ?? 'Aucune zone'),
                subtitle: Text(cycleEnded
                    ? 'Le cycle est terminé; l’historique de placement reste conservé.'
                    : placement == null
                        ? 'Place cette plante dans un espace de culture'
                        : 'Depuis le ${DateFormat('dd/MM/yyyy').format(placement.enteredAt)}'),
                trailing: cycleEnded ? null : const Icon(Icons.chevron_right),
                onTap: cycleEnded
                    ? null
                    : () => showPlantZoneMoveSheet(context, plant),
              ),
            );
          }),
          // Stat cards top
          Row(children: [
            _statCard('Age', '${plant.daysSincePotting}j', Icons.schedule,
                const Color(0xFF1976D2)),
            const SizedBox(width: 8),
            if (plant.isDead)
              _statCard(
                  'Cycle', 'Morte', Icons.eco_outlined, const Color(0xFF616161))
            else if (plant.isHarvested)
              _statCard(
                'Recolte',
                harvestAction == null
                    ? 'Recoltee'
                    : AppUtils.formatDate(harvestAction.timestamp),
                Icons.agriculture,
                const Color(0xFFF57F17),
              )
            else if (plant.containerType == 'plein_sol' &&
                !plant.hasWateringReminder)
              _statCard('Contenant', 'Plein sol', Icons.grass,
                  const Color(0xFF795548))
            else if (!plant.hasWateringReminder)
              _statCard('Arrosage', 'Sans rappel', Icons.water_drop_outlined,
                  const Color(0xFF757575))
            else
              _statCard(
                  'Arrosage',
                  daysSinceWater == null
                      ? 'Jamais'
                      : daysSinceWater == 0
                          ? "Auj."
                          : '${daysSinceWater}j',
                  Icons.water_drop,
                  waterColor),
            const SizedBox(width: 8),
            if (currentPot != null && plant.containerType != 'plein_sol')
              _statCard('Pot', currentPot, Icons.yard_outlined,
                  const Color(0xFF795548))
            else
              _statCard('Culture', _short(plant.cultureType, 8), Icons.eco,
                  const Color(0xFF7B1FA2)),
          ]),

          // Poids recolte si disponibles
          if (hasWet || hasDry || hasWaste) ...[
            const SizedBox(height: 12),
            _harvestWeightCard(harvestAction!),
          ],

          const SizedBox(height: 16),
          // Detail card
          _detailCard(
              plant, group, currentPot, daysSinceWater, floraisons, recoltes),
          if (plant.notes != null && plant.notes!.isNotEmpty) ...[
            const SizedBox(height: 12),
            _notesCard(plant.notes!),
          ],
        ]));
  }

  Widget _harvestWeightCard(PlantAction action) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
          color: const Color(0xFFFFF8E1),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFFFE082))),
      child: Wrap(
          alignment: WrapAlignment.spaceAround,
          spacing: 20,
          runSpacing: 10,
          children: [
            if (action.harvestWeightFresh != null)
              _weightStat('Récolté',
                  '${action.harvestWeightFresh!.toStringAsFixed(1)} g'),
            if (action.harvestWeightStored != null)
              _weightStat('Secs',
                  '${action.harvestWeightStored!.toStringAsFixed(1)} g'),
            if (action.harvestWeightWaste != null)
              _weightStat(
                  'Trim', '${action.harvestWeightWaste!.toStringAsFixed(1)} g'),
            if (action.harvestWeightStored != null &&
                action.harvestWeightWaste != null)
              _weightStat('Total',
                  '${(action.harvestWeightStored! + action.harvestWeightWaste!).toStringAsFixed(1)} g'),
          ]),
    );
  }

  Widget _weightStat(String label, String value) => Column(children: [
        Text(value,
            style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFFF57F17))),
        Text(label,
            style: const TextStyle(fontSize: 11, color: Color(0xFF795548))),
      ]);

  Widget _statCard(String label, String value, IconData icon, Color color) =>
      Expanded(
          child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
              decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: color.withValues(alpha: 0.2))),
              child: Column(children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(height: 4),
                Text(value,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: color)),
                Text(label,
                    style: const TextStyle(
                        fontSize: 10, color: Color(0xFF757575))),
              ])));

  Widget _detailCard(
      Plant plant,
      dynamic group,
      String? currentPot,
      int? daysSinceWater,
      List<PlantAction> floraisons,
      List<PlantAction> recoltes) {
    final ended = plant.isHarvested || plant.isDead;
    final terminalActions = context
        .read<ActionProvider>()
        .getActionsForPlant(plant.id)
        .where((a) =>
            a.isDone && (a.actionType == 'mort' || a.actionType == 'recolte'))
        .toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    // A finished cycle must not keep accumulating flowering days.
    final floweringEnd = ended ? terminalActions.firstOrNull?.timestamp : null;
    return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE0E0E0))),
        child: Column(children: [
          _row('Mise en pot', AppUtils.formatDate(plant.pottingDate),
              Icons.calendar_today_outlined),
          _div(),
          _row('Origine', plant.originLabel, Icons.history_edu_outlined),
          _div(),
          _row('Emplacement', plant.locationLabel, Icons.place_outlined),
          _div(),
          _row('Contenant', plant.containerLabel, Icons.inbox_outlined),
          _div(),
          _row('Culture', plant.cultureType, Icons.science_outlined),
          if (currentPot != null && plant.containerType != 'plein_sol') ...[
            _div(),
            _row('Pot actuel', currentPot, Icons.yard_outlined)
          ],
          if (daysSinceWater != null) ...[
            _div(),
            _row(
                'Dernier arrosage',
                daysSinceWater == 0
                    ? "Aujourd'hui"
                    : 'Il y a ${daysSinceWater}j',
                Icons.water_drop_outlined)
          ],
          if (floraisons.isNotEmpty) ...[
            _div(),
            _row(
                ended ? 'Durée floraison' : 'Floraison',
                ended
                    ? floweringEnd == null
                        ? 'Fin non datée'
                        : '${AppUtils.elapsedDays(floraisons.first.timestamp, end: floweringEnd)} jours'
                    : AppUtils.floweringDuration(floraisons.first.timestamp),
                Icons.local_florist)
          ],
          if (recoltes.isNotEmpty) ...[
            _div(),
            _row('Recolte', AppUtils.formatDate(recoltes.first.timestamp),
                Icons.agriculture)
          ],
          if (plant.variety != null && plant.variety!.isNotEmpty) ...[
            _div(),
            _row('Variete', plant.variety!, Icons.grass)
          ],
          if (plant.observationCode?.isNotEmpty == true) ...[
            _div(),
            _row('Repère de plante', plant.observationCode!,
                Icons.science_outlined),
          ],
          if (group != null) ...[
            _div(),
            _row('Groupe', group.name, Icons.folder_outlined)
          ],
          _div(),
          _row('Cree le', AppUtils.formatDate(plant.createdAt),
              Icons.add_circle_outline),
        ]));
  }

  Widget _row(String label, String value, IconData icon) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(children: [
        Icon(icon, size: 18, color: const Color(0xFF2E7D32)),
        const SizedBox(width: 10),
        SizedBox(
          width: 120,
          child: Text(label,
              style: const TextStyle(fontSize: 13, color: Color(0xFF757575))),
        ),
        Expanded(
            child: Text(value,
                style:
                    const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                textAlign: TextAlign.right)),
      ]));

  Widget _div() => const Divider(height: 1, color: Color(0xFFF0F0F0));

  Widget _notesCard(String notes) => Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: const Color(0xFFFFFDE7),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFFFF176))),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.sticky_note_2_outlined,
            color: Color(0xFFF57F17), size: 20),
        const SizedBox(width: 10),
        Expanded(
            child:
                Text(notes, style: const TextStyle(fontSize: 14, height: 1.5))),
      ]));

  // Graphe pH / TDS
  Widget _chartSection(List<PlantAction> actions) {
    final phActions = actions.where((a) => _isValidPh(a.ph) && !a.phNA).toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    final tdsActions = actions.where((a) => a.tds != null && !a.tdsNA).toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

    if (phActions.isEmpty && tdsActions.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: _PhTdsChart(phActions: phActions, tdsActions: tdsActions),
    );
  }

  bool _isValidPh(double? value) {
    if (value == null) return false;
    return value >= 3.5 && value <= 9.0;
  }

  // Actions header
  Widget _actionsHeader(Plant plant) {
    final cycleEnded = plant.isDead || plant.isHarvested;
    return Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        child: Row(children: [
          const Text('Historique',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const Spacer(),
          ElevatedButton.icon(
              onPressed: cycleEnded ? null : () => _addAction(plant),
              icon: Icon(cycleEnded ? Icons.lock_outline : Icons.add, size: 18),
              label: Text(cycleEnded ? 'Cycle terminé' : 'Ajouter'),
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2E7D32),
                  disabledBackgroundColor: const Color(0xFFE0E0E0),
                  disabledForegroundColor: const Color(0xFF616161),
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  textStyle: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)))),
        ]));
  }

  Future<void> _addAction(Plant plant) async {
    if (plant.isDead || plant.isHarvested) return;
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => AddActionScreen(plant: plant)),
    );
    if (saved != true || !mounted) return;
    await context.read<ActionProvider>().loadActionsForPlant(plant.id);
  }

  // Menu
  Widget _zoneHistory(Plant plant) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: FutureBuilder<List<ZonePlacement>>(
          future: context.read<SpaceProvider>().historyForPlant(
                plant.id,
                groupId: plant.groupId,
              ),
          builder: (_, snapshot) {
            final placements = snapshot.data ?? const <ZonePlacement>[];
            if (placements.isEmpty) return const SizedBox.shrink();
            final spaces = context.read<SpaceProvider>();
            return Card(
              child: ExpansionTile(
                initiallyExpanded: true,
                title: const Text('Parcours climatique'),
                subtitle: Text('${placements.length} période(s) en zone'),
                children: placements.map((placement) {
                  final zone = spaces.getZone(placement.zoneId);
                  if (zone == null) {
                    return const ListTile(
                      leading: Icon(Icons.warning_amber_outlined),
                      title: Text('Zone inconnue'),
                    );
                  }
                  final end = placement.exitedAt ?? DateTime.now();
                  return FutureBuilder<List<SensorReading>>(
                    future: spaces.climateReadingsBetween(
                      zone.id,
                      placement.enteredAt,
                      end: placement.exitedAt,
                    ),
                    builder: (_, climateSnapshot) {
                      final readings = (climateSnapshot.data ??
                              const <SensorReading>[])
                          .where((reading) => !reading.timestamp.isAfter(end))
                          .toList();
                      final dateRange =
                          '${DateFormat('dd/MM/yyyy').format(placement.enteredAt)} '
                          '→ ${placement.exitedAt == null ? 'maintenant' : DateFormat('dd/MM/yyyy').format(placement.exitedAt!)}';
                      final average = readings.isEmpty
                          ? null
                          : 'Moy. ${_average(readings.map((r) => r.temperature)).toStringAsFixed(1)} °C / '
                              '${_average(readings.map((r) => r.humidity)).toStringAsFixed(0)} % / '
                              '${_average(readings.map((r) => r.vpd)).toStringAsFixed(2)} kPa';
                      return Column(
                        children: [
                          ListTile(
                            leading: const Icon(Icons.thermostat),
                            title: Text(zone.name),
                            subtitle: Text(
                              '$dateRange\n${average ?? 'Aucune mesure synchronisée'}',
                            ),
                          ),
                          if (climateSnapshot.connectionState ==
                              ConnectionState.waiting)
                            const LinearProgressIndicator(minHeight: 2),
                          if (readings.length >= 2)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
                              child: _ClimatePlacementChart(readings: readings),
                            ),
                        ],
                      );
                    },
                  );
                }).toList(),
              ),
            );
          },
        ),
      );

  double _average(Iterable<double> values) {
    final list = values.toList();
    return list.reduce((total, value) => total + value) / list.length;
  }

  void _showQr(Plant plant) =>
      showDialog(context: context, builder: (_) => QrCodeDialog(plant: plant));

  Future<void> _menu(String value, Plant plant) async {
    if (value == 'edit') {
      await Navigator.push(context,
          MaterialPageRoute(builder: (_) => EditPlantScreen(plant: plant)));
      if (mounted) setState(() {});
    } else if (value == 'move_zone') {
      await showPlantZoneMoveSheet(context, plant);
      if (mounted) setState(() {});
    } else if (value == 'duplicate') {
      final cutting = await context.read<PlantProvider>().duplicatePlant(plant);
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('"${cutting.name}" cree !'),
            backgroundColor: const Color(0xFF2E7D32)));
    } else if (value == 'export') {
      final actions = context
          .read<ActionProvider>()
          .getActionsForPlant(plant.id)
          .where((a) => a.isDone)
          .toList();
      if (mounted)
        await ShareableExportService.exportPlantHistory(
            context, plant, actions);
    } else if (value == 'cycle_export') {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => CycleExportScreen(plant: plant)),
      );
    } else if (value == 'delete') {
      showDialog(
          context: context,
          builder: (_) => AlertDialog(
                  title: const Text('Supprimer ?'),
                  content: Text(
                      'Supprime "${plant.name}" et tout son historique definitivement.'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Annuler')),
                    TextButton(
                        onPressed: () async {
                          Navigator.pop(context);
                          await context
                              .read<PlantProvider>()
                              .deletePlant(plant.id);
                          if (mounted) Navigator.pop(context);
                        },
                        child: const Text('Supprimer',
                            style: TextStyle(color: Colors.red))),
                  ]));
    }
  }

  String _short(String t, int n) =>
      t.length <= n ? t : '${t.substring(0, n)}...';
}

// Section
// Graphe pH / TDS
// Section
enum _ClimateMetric { temperature, humidity, vpd }

class _ClimatePlacementChart extends StatefulWidget {
  final List<SensorReading> readings;

  const _ClimatePlacementChart({required this.readings});

  @override
  State<_ClimatePlacementChart> createState() => _ClimatePlacementChartState();
}

class _ClimatePlacementChartState extends State<_ClimatePlacementChart> {
  _ClimateMetric _metric = _ClimateMetric.temperature;

  String get _title => switch (_metric) {
        _ClimateMetric.temperature => 'Température',
        _ClimateMetric.humidity => 'Humidité',
        _ClimateMetric.vpd => 'VPD',
      };

  String get _unit => switch (_metric) {
        _ClimateMetric.temperature => ' °C',
        _ClimateMetric.humidity => ' %',
        _ClimateMetric.vpd => ' kPa',
      };

  Color get _color => switch (_metric) {
        _ClimateMetric.temperature => Colors.deepOrange,
        _ClimateMetric.humidity => Colors.blue,
        _ClimateMetric.vpd => Colors.green,
      };

  double _value(SensorReading reading) => switch (_metric) {
        _ClimateMetric.temperature => reading.temperature,
        _ClimateMetric.humidity => reading.humidity,
        _ClimateMetric.vpd => reading.vpd,
      };

  List<SensorReading> get _chartReadings {
    if (widget.readings.length <= 300) return widget.readings;
    final lastIndex = widget.readings.length - 1;
    return List.generate(
      300,
      (index) => widget.readings[(index * lastIndex / 299).round()],
    );
  }

  @override
  Widget build(BuildContext context) {
    final data = _chartReadings;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAF8),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE0E0E0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.show_chart, size: 18, color: Color(0xFF2E7D32)),
              const SizedBox(width: 6),
              Text(
                'Mesures climatiques',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SegmentedButton<_ClimateMetric>(
            segments: const [
              ButtonSegment(
                value: _ClimateMetric.temperature,
                label: Text('Temp.'),
              ),
              ButtonSegment(
                value: _ClimateMetric.humidity,
                label: Text('Hum.'),
              ),
              ButtonSegment(
                value: _ClimateMetric.vpd,
                label: Text('VPD'),
              ),
            ],
            selected: {_metric},
            onSelectionChanged: (values) =>
                setState(() => _metric = values.first),
          ),
          const SizedBox(height: 10),
          Text(
            '${_title} · ${_value(widget.readings.last).toStringAsFixed(_metric == _ClimateMetric.vpd ? 2 : 1)}$_unit',
            style: TextStyle(
              color: _color,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          SizedBox(height: 170, child: LineChart(_chartData(data))),
          if (widget.readings.length > data.length)
            Text(
              '${widget.readings.length} mesures · affichage échantillonné',
              style: const TextStyle(fontSize: 11, color: Color(0xFF757575)),
            )
          else
            Text(
              '${widget.readings.length} mesure${widget.readings.length > 1 ? 's' : ''}',
              style: const TextStyle(fontSize: 11, color: Color(0xFF757575)),
            ),
        ],
      ),
    );
  }

  LineChartData _chartData(List<SensorReading> data) {
    final values = data.map(_value).toList();
    final spots = values
        .asMap()
        .entries
        .map((entry) => FlSpot(entry.key.toDouble(), entry.value))
        .toList();
    final lowest = values.reduce((a, b) => a < b ? a : b);
    final highest = values.reduce((a, b) => a > b ? a : b);
    final range = highest - lowest;
    final padding = range == 0
        ? (highest.abs() < 1 ? 1.0 : highest.abs() * 0.1)
        : range * 0.12;
    final labels = _dateLabelIndexes(data.length);
    final dateFormat = DateFormat('dd/MM');
    final decimals = _metric == _ClimateMetric.vpd ? 2 : 1;

    return LineChartData(
      minX: -0.25,
      maxX: spots.last.x + 0.25,
      minY: lowest - padding,
      maxY: highest + padding,
      gridData: FlGridData(
        show: true,
        getDrawingHorizontalLine: (_) =>
            const FlLine(color: Color(0xFFE8EDE8), strokeWidth: 1),
        getDrawingVerticalLine: (_) =>
            const FlLine(color: Color(0xFFE8EDE8), strokeWidth: 1),
      ),
      borderData: FlBorderData(show: false),
      titlesData: FlTitlesData(
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles:
            const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 42,
            getTitlesWidget: (value, _) => Text(
              value.toStringAsFixed(decimals),
              style: const TextStyle(fontSize: 9, color: Color(0xFF757575)),
            ),
          ),
        ),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 26,
            interval: 1,
            getTitlesWidget: (value, meta) {
              if (value != value.roundToDouble())
                return const SizedBox.shrink();
              final index = value.round();
              if (index < 0 ||
                  index >= data.length ||
                  !labels.contains(index)) {
                return const SizedBox.shrink();
              }
              return SideTitleWidget(
                meta: meta,
                space: 4,
                fitInside: SideTitleFitInsideData.fromTitleMeta(meta),
                child: Text(
                  dateFormat.format(data[index].timestamp),
                  style: const TextStyle(fontSize: 9, color: Color(0xFF757575)),
                ),
              );
            },
          ),
        ),
      ),
      lineBarsData: [
        LineChartBarData(
          spots: spots,
          isCurved: true,
          color: _color,
          barWidth: 2,
          dotData: const FlDotData(show: false),
          belowBarData: BarAreaData(
            show: true,
            color: _color.withValues(alpha: 0.08),
          ),
        ),
      ],
      lineTouchData: LineTouchData(
        touchTooltipData: LineTouchTooltipData(
          getTooltipColor: (_) => Colors.white,
          fitInsideHorizontally: true,
          fitInsideVertically: true,
          getTooltipItems: (spots) => spots.map((spot) {
            final index = spot.x.round();
            final timestamp = index >= 0 && index < data.length
                ? dateFormat.format(data[index].timestamp)
                : '';
            return LineTooltipItem(
              '${spot.y.toStringAsFixed(decimals)}$_unit\n$timestamp',
              TextStyle(color: _color, fontWeight: FontWeight.w700),
            );
          }).toList(),
        ),
      ),
    );
  }

  Set<int> _dateLabelIndexes(int length) {
    if (length <= 3) return {for (var i = 0; i < length; i++) i};
    return {0, length ~/ 2, length - 1};
  }
}

class _PhTdsChart extends StatefulWidget {
  final List<PlantAction> phActions;
  final List<PlantAction> tdsActions;
  const _PhTdsChart({required this.phActions, required this.tdsActions});

  @override
  State<_PhTdsChart> createState() => _PhTdsChartState();
}

class _PhTdsChartState extends State<_PhTdsChart> {
  bool _showPh = true;

  List<PlantAction> get _data => _showPh ? widget.phActions : widget.tdsActions;

  static const _phColor = Color(0xFF1976D2);
  static const _tdsColor = Color(0xFFF57C00);

  @override
  void initState() {
    super.initState();
    // Si pas de donnees pH, demarrer sur TDS
    if (widget.phActions.isEmpty && widget.tdsActions.isNotEmpty) {
      _showPh = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    final color = _showPh ? _phColor : _tdsColor;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE0E0E0))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // En-tete + toggles
        Row(children: [
          const Icon(Icons.show_chart, color: Color(0xFF2E7D32), size: 20),
          const SizedBox(width: 8),
          const Text('Evolution',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          const Spacer(),
          _toggle('pH', true, widget.phActions.isNotEmpty),
          const SizedBox(width: 8),
          _toggle('TDS', false, widget.tdsActions.isNotEmpty),
        ]),
        const SizedBox(height: 16),
        if (data.isNotEmpty) _latestValue(data.last, color),
        if (data.isNotEmpty) const SizedBox(height: 12),

        if (data.isEmpty)
          Container(
            height: 80,
            alignment: Alignment.center,
            child: Text('Aucune donnee ${_showPh ? "pH" : "TDS"} enregistree',
                style: const TextStyle(color: Color(0xFF9E9E9E), fontSize: 13)),
          )
        else if (data.length < 2)
          Container(
            height: 80,
            alignment: Alignment.center,
            child: const Text('Ajoutez une 2e mesure pour tracer la tendance',
                style: TextStyle(color: Color(0xFF9E9E9E), fontSize: 13)),
          )
        else
          SizedBox(
            height: 180,
            child: LineChart(_buildChartData(data, color)),
          ),

        // Nb de mesures
        if (data.isNotEmpty)
          Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('${data.length} mesure${data.length > 1 ? "s" : ""}',
                  style:
                      const TextStyle(fontSize: 11, color: Color(0xFF9E9E9E)))),
      ]),
    );
  }

  Widget _toggle(String label, bool isPh, bool hasData) {
    final selected = _showPh == isPh;
    final color = isPh ? _phColor : _tdsColor;
    return GestureDetector(
      onTap: hasData ? () => setState(() => _showPh = isPh) : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
            color: selected
                ? color
                : (hasData
                    ? color.withValues(alpha: 0.08)
                    : const Color(0xFFF5F5F5)),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
                color: selected ? color : color.withValues(alpha: 0.3))),
        child: Text(label,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: selected
                    ? Colors.white
                    : (hasData ? color : const Color(0xFFBDBDBD)))),
      ),
    );
  }

  Widget _latestValue(PlantAction action, Color color) {
    final value = _showPh ? action.ph! : action.tds!;
    final unit = _showPh ? '' : ' ppm';
    final fmt = DateFormat('dd/MM');
    final isOk = !_showPh || (value >= 5.8 && value <= 6.5);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10)),
      child: Row(children: [
        Text(_showPh ? 'Dernier pH' : 'Dernier TDS',
            style: const TextStyle(fontSize: 12, color: Color(0xFF757575))),
        const Spacer(),
        Text('${value.toStringAsFixed(_showPh ? 2 : 0)}$unit',
            style: TextStyle(
                fontSize: 17, fontWeight: FontWeight.w800, color: color)),
        const SizedBox(width: 8),
        if (_showPh)
          Icon(isOk ? Icons.check_circle : Icons.warning_amber_rounded,
              size: 17,
              color: isOk ? const Color(0xFF2E7D32) : const Color(0xFFF57C00)),
        const SizedBox(width: 8),
        Text(fmt.format(action.timestamp),
            style: const TextStyle(fontSize: 11, color: Color(0xFF9E9E9E))),
      ]),
    );
  }

  LineChartData _buildChartData(List<PlantAction> data, Color color) {
    final spots = data
        .asMap()
        .entries
        .map((e) =>
            FlSpot(e.key.toDouble(), _showPh ? e.value.ph! : e.value.tds!))
        .toList();
    final lastX = (spots.length - 1).toDouble();

    // Bornes Y
    final values = spots.map((s) => s.y).toList();
    final lowest = values.reduce((a, b) => a < b ? a : b);
    final highest = values.reduce((a, b) => a > b ? a : b);
    final minY = _showPh
        ? (lowest < 5.0 ? lowest - 0.2 : 5.0).clamp(0.0, 14.0)
        : (lowest * 0.85).clamp(0.0, double.infinity);
    final maxY = _showPh
        ? (highest > 7.5 ? highest + 0.2 : 7.5).clamp(0.0, 14.0)
        : highest * 1.15;

    // Quatre libellés au maximum : sur mobile, plus de dates se chevauchent.
    // Les points restent répartis uniformément pour que plusieurs mesures le
    // même jour restent lisibles.
    final labelIndexes = _dateLabelIndexes(data.length);
    final fmt = DateFormat('dd/MM');

    return LineChartData(
      minX: -0.35,
      maxX: lastX + 0.35,
      minY: minY,
      maxY: maxY,
      gridData: FlGridData(
          show: true,
          horizontalInterval: _showPh ? 0.5 : null,
          getDrawingHorizontalLine: (v) =>
              FlLine(color: const Color(0xFFF0F0F0), strokeWidth: 1),
          getDrawingVerticalLine: (v) =>
              FlLine(color: const Color(0xFFF0F0F0), strokeWidth: 1)),
      borderData: FlBorderData(show: false),
      rangeAnnotations: _showPh
          ? RangeAnnotations(horizontalRangeAnnotations: [
              HorizontalRangeAnnotation(
                  y1: 5.8,
                  y2: 6.5,
                  color: const Color(0xFF2E7D32).withValues(alpha: 0.08)),
            ])
          : const RangeAnnotations(),
      titlesData: FlTitlesData(
        topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        leftTitles: AxisTitles(
            sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 40,
                getTitlesWidget: (v, _) => Text(
                    _showPh ? v.toStringAsFixed(1) : v.toInt().toString(),
                    style: const TextStyle(
                        fontSize: 10, color: Color(0xFF9E9E9E))))),
        bottomTitles: AxisTitles(
            sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 30,
                interval: 1,
                getTitlesWidget: (v, meta) {
                  if (v != v.roundToDouble()) return const SizedBox.shrink();
                  final idx = v.round();
                  if (idx < 0 ||
                      idx >= data.length ||
                      !labelIndexes.contains(idx)) {
                    return const SizedBox.shrink();
                  }
                  return SideTitleWidget(
                    meta: meta,
                    space: 6,
                    fitInside: SideTitleFitInsideData.fromTitleMeta(meta),
                    child: SizedBox(
                      width: 38,
                      child: Text(
                        fmt.format(data[idx].timestamp),
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.clip,
                        style: const TextStyle(
                            fontSize: 9, color: Color(0xFF9E9E9E)),
                      ),
                    ),
                  );
                })),
      ),
      lineBarsData: [
        LineChartBarData(
            spots: spots,
            isCurved: false,
            color: color,
            barWidth: 2,
            dotData: FlDotData(
                show: true,
                getDotPainter: (spot, _, __, ___) => FlDotCirclePainter(
                    radius: 3,
                    color: color,
                    strokeWidth: 2,
                    strokeColor: Colors.white)),
            belowBarData:
                BarAreaData(show: true, color: color.withValues(alpha: 0.08))),
      ],
      lineTouchData: LineTouchData(
        touchSpotThreshold: 24,
        touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => Colors.white,
            tooltipBorderRadius: BorderRadius.circular(8),
            tooltipPadding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            tooltipMargin: 8,
            maxContentWidth: 130,
            fitInsideHorizontally: true,
            fitInsideVertically: true,
            tooltipBorder: BorderSide(color: color.withValues(alpha: 0.28)),
            getTooltipItems: (spots) => spots.map((s) {
                  final idx = s.x.toInt();
                  final label = idx >= 0 && idx < data.length
                      ? fmt.format(data[idx].timestamp)
                      : '';
                  return LineTooltipItem(
                      '${_showPh ? "pH" : "TDS"}: ${s.y.toStringAsFixed(_showPh ? 2 : 0)}\n$label',
                      TextStyle(
                          color: color,
                          fontSize: 12,
                          fontWeight: FontWeight.w700));
                }).toList()),
      ),
    );
  }

  Set<int> _dateLabelIndexes(int length) {
    if (length <= 4) return {for (var i = 0; i < length; i++) i};
    return {
      for (var i = 0; i < 4; i++) ((length - 1) * i / 3).round(),
    };
  }
}
