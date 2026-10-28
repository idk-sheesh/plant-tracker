import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/plant_provider.dart';
import '../../domain/entities/plant.dart';
import '../../../actions/presentation/providers/action_provider.dart';
import '../../../groups/data/models/plant_group.dart';
import '../../../groups/presentation/providers/group_provider.dart';
import '../widgets/plant_card.dart';
import '../../../groups/presentation/screens/groups_screen.dart';
import 'create_plant_screen.dart';
import '../../../observations/presentation/screens/observation_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _search = '';
  bool _showSearch = false;
  bool _showFollowUp = true;
  bool _showActive = true;
  bool _showHarvested = false;
  bool _showDead = false;
  String? _groupBrowseId;
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<ActionProvider>().loadHomeSummaries();
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: _showSearch
            ? TextField(
                controller: _searchCtrl,
                autofocus: true,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                    hintText: 'Rechercher...',
                    hintStyle: TextStyle(color: Colors.white70),
                    border: InputBorder.none,
                    filled: false,
                    contentPadding: EdgeInsets.zero),
                onChanged: (v) => setState(() => _search = v))
            : const Text('GardenJournal'),
        actions: [
          IconButton(
              tooltip: 'Observations du jardin',
              icon: const Icon(Icons.science_outlined),
              onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const ObservationScreen()))),
          IconButton(
              icon: Icon(_showSearch ? Icons.close : Icons.search),
              onPressed: () => setState(() {
                    _showSearch = !_showSearch;
                    if (!_showSearch) {
                      _search = '';
                      _searchCtrl.clear();
                    }
                  })),
          IconButton(
              icon: const Icon(Icons.folder_outlined),
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const GroupsScreen()),
                );
                if (!context.mounted) return;
                final plants = context.read<PlantProvider>();
                final groups = context.read<GroupProvider>();
                await plants.loadPlants();
                final selectedGroupId = plants.filterGroupId;
                if (selectedGroupId != null &&
                    groups.getGroupById(selectedGroupId) == null) {
                  plants.setGroupFilter(null);
                }
                if (_groupBrowseId != null &&
                    groups.getGroupById(_groupBrowseId) == null) {
                  setState(() => _groupBrowseId = null);
                }
              }),
        ],
      ),
      body: Column(children: [
        _groupFilter(),
        Expanded(child: _plantList()),
      ]),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const CreatePlantScreen())),
        icon: const Icon(Icons.add),
        label: const Text('Nouvelle plante'),
      ),
    );
  }

  Widget _groupFilter() {
    return Consumer<GroupProvider>(builder: (_, gp, __) {
      if (gp.groups.isEmpty) return const SizedBox.shrink();
      return Consumer<PlantProvider>(builder: (_, pp, __) {
        final current = gp.getGroupById(_groupBrowseId);
        final folders = gp.groups
            .where((group) => group.parentGroupId == _groupBrowseId)
            .toList();
        final breadcrumbs = _groupBreadcrumbs(gp, current);

        return Container(
          color: Colors.white,
          padding: const EdgeInsets.only(top: 4, bottom: 6),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (current != null)
              SizedBox(
                height: 30,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  children: [
                    _breadcrumbButton(
                      label: 'Toutes',
                      onTap: () => _openGroupLevel(null, pp, null),
                      isCurrent: false,
                    ),
                    for (final group in breadcrumbs) ...[
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 2),
                        child: Icon(Icons.chevron_right,
                            size: 18, color: Color(0xFF9E9E9E)),
                      ),
                      _breadcrumbButton(
                        label: group.name,
                        onTap: () => _openGroupLevel(group.id, pp, group.id),
                        isCurrent: group.id == current.id,
                      ),
                    ],
                  ],
                ),
              ),
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                children: [
                  if (current == null)
                    _folderChip(
                      label: 'Toutes',
                      color: const Color(0xFF2E7D32),
                      selected: pp.filterGroupId == null,
                      onTap: () => _openGroupLevel(null, pp, null),
                    ),
                  ...folders.map((group) => _folderChip(
                        label: group.name,
                        color: group.color,
                        selected: pp.filterGroupId == group.id,
                        onTap: () => _openGroupLevel(group.id, pp, group.id),
                      )),
                  if (current != null && folders.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(left: 4, top: 2),
                      child: Text('Aucun sous-dossier',
                          style: TextStyle(
                              color: Color(0xFF757575), fontSize: 12)),
                    ),
                ],
              ),
            ),
          ]),
        );
      });
    });
  }

  List<PlantGroup> _groupBreadcrumbs(
      GroupProvider provider, PlantGroup? current) {
    final result = <PlantGroup>[];
    final visited = <String>{};
    var group = current;
    while (group != null && visited.add(group.id)) {
      result.insert(0, group);
      group = provider.getGroupById(group.parentGroupId);
    }
    return result;
  }

  void _openGroupLevel(
      String? groupId, PlantProvider plants, String? filterGroupId) {
    setState(() => _groupBrowseId = groupId);
    plants.setGroupFilter(filterGroupId);
  }

  Widget _breadcrumbButton({
    required String label,
    required VoidCallback onTap,
    required bool isCurrent,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Text(label,
            style: TextStyle(
                color: isCurrent
                    ? const Color(0xFF2E7D32)
                    : const Color(0xFF616161),
                fontSize: 12,
                fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500)),
      ),
    );
  }

  Widget _folderChip({
    required String label,
    required Color color,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
        selectedColor: color,
        labelStyle: TextStyle(
            color: selected ? Colors.white : const Color(0xFF212121),
            fontWeight: FontWeight.w500),
        showCheckmark: false,
      ),
    );
  }

  Widget _plantList() {
    return Consumer2<PlantProvider, ActionProvider>(builder: (_, pp, ap, __) {
      if (pp.isLoading) return const Center(child: CircularProgressIndicator());
      if (pp.error != null && pp.plants.isEmpty) {
        return _loadError(pp.error!, pp.loadPlants);
      }
      if (!ap.homeSummariesLoaded) {
        return const Center(child: CircularProgressIndicator());
      }

      var plants = pp.plants;
      if (_search.isNotEmpty) {
        final q = _search.toLowerCase();
        plants = plants
            .where((p) =>
                p.name.toLowerCase().contains(q) ||
                (p.variety?.toLowerCase().contains(q) ?? false) ||
                (p.observationCode?.toLowerCase().contains(q) ?? false) ||
                p.cultureType.toLowerCase().contains(q))
            .toList();
      }

      if (plants.isEmpty) return _emptyState();

      final items = plants
          .map((p) => _PlantHomeItem(
                p,
                ap.daysSinceWaterForPlant(p),
                ap.lastActivityForPlant(p),
              ))
          .toList();

      final pinned = items
          .where((i) =>
              i.plant.isPinned && !i.plant.isHarvested && !i.plant.isDead)
          .toList()
        ..sort(_compareActivity);
      final pinnedIds = pinned.map((i) => i.plant.id).toSet();

      final followUp = items
          .where((i) => _needsAttention(i) && !pinnedIds.contains(i.plant.id))
          .toList()
        ..sort(_compareActivity);
      final followIds = followUp.map((i) => i.plant.id).toSet();

      final active = items
          .where((i) =>
              !i.plant.isHarvested &&
              !i.plant.isDead &&
              !pinnedIds.contains(i.plant.id) &&
              !followIds.contains(i.plant.id))
          .toList()
        ..sort(_compareActivity);

      final harvested = items
          .where((i) => i.plant.isHarvested && !i.plant.isDead)
          .toList()
        ..sort(_compareActivity);
      final dead = items.where((i) => i.plant.isDead).toList()
        ..sort(_compareActivity);

      final children = <Widget>[
        if (pp.error != null) _providerWarning(pp.error!),
        if (ap.homeSummariesError != null)
          _homeSummaryWarning(ap.homeSummariesError!),
        if (pinned.isNotEmpty)
          _section('Epinglees', '${pinned.length}', Icons.push_pin,
              const Color(0xFFF57C00)),
        ...pinned.map(_card),
        if (followUp.isNotEmpty) _followUpToggle(followUp.length),
        if (_showFollowUp) ...followUp.map(_card),
        if (active.isNotEmpty) _activeToggle(active.length),
        if (_showActive) ...active.map(_card),
        if (harvested.isNotEmpty) _harvestedToggle(harvested.length),
        if (_showHarvested) ...harvested.map(_card),
        if (dead.isNotEmpty) _deadToggle(dead.length),
        if (_showDead) ...dead.map(_card),
        const SizedBox(height: 88),
      ];

      return RefreshIndicator(
          onRefresh: () async {
            await Future.wait([
              pp.loadPlants(),
              ap.loadHomeSummaries(),
            ]);
          },
          child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: children));
    });
  }

  Widget _loadError(String message, Future<void> Function() retry) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 40),
            const SizedBox(height: 10),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: retry,
              icon: const Icon(Icons.refresh),
              label: const Text('Réessayer'),
            ),
          ]),
        ),
      );

  Widget _providerWarning(String message) => Container(
        margin: const EdgeInsets.fromLTRB(16, 6, 16, 4),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: const Color(0xFFFFEBEE),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(children: [
          const Icon(Icons.error_outline, color: Colors.red, size: 19),
          const SizedBox(width: 8),
          Expanded(child: Text(message, style: const TextStyle(fontSize: 12))),
        ]),
      );

  Widget _emptyState() {
    return Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      const Text('Aucune plante',
          style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: Color(0xFF424242))),
      const SizedBox(height: 8),
      Text(
          _search.isNotEmpty
              ? 'Essayez une autre recherche'
              : 'Appuyez sur + pour ajouter votre premiere plante',
          style: const TextStyle(color: Color(0xFF757575))),
    ]));
  }

  int _compareActivity(_PlantHomeItem a, _PlantHomeItem b) =>
      b.lastActivity.compareTo(a.lastActivity);

  bool _needsAttention(_PlantHomeItem item) {
    final plant = item.plant;
    if (!plant.hasWateringReminder) {
      return false;
    }
    return item.daysSinceWater == null || item.daysSinceWater! >= 3;
  }

  Widget _card(_PlantHomeItem item) => PlantCard(
      plant: item.plant,
      daysSinceWater: item.daysSinceWater,
      floweringStart: context
          .read<ActionProvider>()
          .homeSummaries[item.plant.id]
          ?.lastFloweringAt);

  Widget _homeSummaryWarning(String message) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFFFE082)),
      ),
      child: Row(children: [
        const Icon(Icons.warning_amber, color: Color(0xFFF57C00), size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            '$message: certains compteurs peuvent etre incomplets.',
            style: const TextStyle(fontSize: 12, color: Color(0xFF795548)),
          ),
        ),
      ]),
    );
  }

  Widget _section(String title, String count, IconData icon, Color color) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      child: Row(children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Text(title,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8)),
          child: Text(count,
              style: TextStyle(
                  color: color, fontSize: 11, fontWeight: FontWeight.w700)),
        ),
      ]),
    );
  }

  Widget _harvestedToggle(int count) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
      child: OutlinedButton.icon(
        onPressed: () => setState(() => _showHarvested = !_showHarvested),
        icon: Icon(_showHarvested ? Icons.expand_less : Icons.expand_more),
        label: Text(_showHarvested
            ? 'Masquer les recoltees ($count)'
            : 'Voir les recoltees ($count)'),
        style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFFF57F17),
            side: const BorderSide(color: Color(0xFFFFE082)),
            backgroundColor: const Color(0xFFFFF8E1),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10))),
      ),
    );
  }

  Widget _followUpToggle(int count) {
    return _plantListToggle(
      count: count,
      isExpanded: _showFollowUp,
      expandedLabel: 'Masquer les plantes a suivre',
      collapsedLabel: 'Voir les plantes a suivre',
      icon: Icons.priority_high,
      color: const Color(0xFFD32F2F),
      borderColor: const Color(0xFFEF9A9A),
      backgroundColor: const Color(0xFFFFEBEE),
      onPressed: () => setState(() => _showFollowUp = !_showFollowUp),
    );
  }

  Widget _activeToggle(int count) {
    return _plantListToggle(
      count: count,
      isExpanded: _showActive,
      expandedLabel: 'Masquer les plantes actives',
      collapsedLabel: 'Voir les plantes actives',
      icon: Icons.local_florist,
      color: const Color(0xFF2E7D32),
      borderColor: const Color(0xFFA5D6A7),
      backgroundColor: const Color(0xFFE8F5E9),
      onPressed: () => setState(() => _showActive = !_showActive),
    );
  }

  Widget _plantListToggle({
    required int count,
    required bool isExpanded,
    required String expandedLabel,
    required String collapsedLabel,
    required IconData icon,
    required Color color,
    required Color borderColor,
    required Color backgroundColor,
    required VoidCallback onPressed,
  }) {
    final label = isExpanded ? expandedLabel : collapsedLabel;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon),
        label: Row(
          children: [
            Expanded(child: Text('$label ($count)')),
            Icon(isExpanded ? Icons.expand_less : Icons.expand_more),
          ],
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: color,
          side: BorderSide(color: borderColor),
          backgroundColor: backgroundColor,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
    );
  }

  Widget _deadToggle(int count) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: OutlinedButton.icon(
        onPressed: () => setState(() => _showDead = !_showDead),
        icon: Icon(_showDead ? Icons.expand_less : Icons.expand_more),
        label: Text(_showDead
            ? 'Masquer les plantes mortes ($count)'
            : 'Voir les plantes mortes ($count)'),
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFF616161),
          side: const BorderSide(color: Color(0xFFBDBDBD)),
          backgroundColor: const Color(0xFFF5F5F5),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
    );
  }
}

class _PlantHomeItem {
  final Plant plant;
  final int? daysSinceWater;
  final DateTime lastActivity;
  const _PlantHomeItem(this.plant, this.daysSinceWater, this.lastActivity);
}
