import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../../core/utils/app_utils.dart';
import '../../../../core/services/form_draft_store.dart';
import '../../../plants/domain/entities/plant.dart';
import '../../../plants/presentation/providers/plant_provider.dart';
import '../../../plants/presentation/screens/plant_detail_screen.dart';
import '../../../plants/presentation/screens/add_action_screen.dart';
import '../../../spaces/presentation/providers/space_provider.dart';
import '../../domain/entities/plant_action.dart';
import '../../domain/entities/action_suggestion.dart';
import '../providers/action_provider.dart';

class PlannedActionsScreen extends StatefulWidget {
  final FormDraftStore? draftStore;
  const PlannedActionsScreen({super.key, this.draftStore});

  @override
  State<PlannedActionsScreen> createState() => _PlannedActionsScreenState();
}

class _PlannedActionsScreenState extends State<PlannedActionsScreen>
    with WidgetsBindingObserver {
  final _busy = <String>{};
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final provider = context.read<ActionProvider>();
      provider.loadPlannedActions();
      if (!provider.isHomeSummaryLoading) provider.loadHomeSummaries();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final actions = context.read<ActionProvider>();
    await Future.wait([
      actions.loadHomeSummaries(),
      actions.loadPlannedActions(),
      context.read<PlantProvider>().loadPlants()
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
        length: 2,
        child: Scaffold(
          backgroundColor: const Color(0xFFF5F5F5),
          appBar: AppBar(
              title: const Text('À faire'),
              bottom: const TabBar(
                  labelColor: Colors.white,
                  unselectedLabelColor: Colors.white70,
                  indicatorColor: Colors.white,
                  tabs: [
                    Tab(text: 'Proposées'),
                    Tab(text: 'Planifiées'),
                  ])),
          body: Consumer2<ActionProvider, PlantProvider>(
            builder: (_, actions, plants, __) {
              return TabBarView(children: [
                _proposed(actions, plants),
                _scheduled(actions, plants),
              ]);
            },
          ),
        ));
  }

  Widget _scheduled(ActionProvider actions, PlantProvider plants) {
    if (actions.isPlannedLoading && actions.plannedActions.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (actions.plannedError != null && actions.plannedActions.isEmpty) {
      return _error(actions);
    }
    if (actions.plannedActions.isEmpty) return _empty(actions);
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
        itemCount: actions.plannedActions.length,
        itemBuilder: (_, index) {
          final action = actions.plannedActions[index];
          final plant = _plantFor(plants, action.plantId);
          return _PlannedActionCard(
            action: action,
            plant: plant,
            onComplete:
                plant == null || _cycleEnded(plant) || _busy.contains(action.id)
                    ? null
                    : () => _complete(actions, action),
            onPostpone:
                plant == null || _cycleEnded(plant) || _busy.contains(action.id)
                    ? null
                    : (duration) => _postpone(actions, action, duration),
            onDelete: () => _delete(actions, action),
            onOpen: plant == null
                ? null
                : () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => PlantDetailScreen(plantId: plant.id),
                      ),
                    ),
          );
        },
      ),
    );
  }

  Widget _proposed(ActionProvider actions, PlantProvider plants) {
    if (!actions.homeSummariesLoaded ||
        actions.isPlannedLoading ||
        plants.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    final error =
        actions.homeSummariesError ?? actions.plannedError ?? plants.error;
    if (error != null) {
      return Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(error),
        FilledButton(onPressed: _refresh, child: const Text('Réessayer')),
      ]));
    }
    final suggestions = ActionSuggestion.forPlants(
        plants: plants.allPlants,
        summaries: actions.homeSummaries,
        planned: actions.plannedActions);
    return RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
          children: [
            const Padding(
                padding: EdgeInsets.all(8),
                child: Text(
                    'Des idées basées sur ton journal. Ouvre une proposition pour la compléter '
                    'et l’enregistrer, ou choisis une date pour la planifier.')),
            if (suggestions.isEmpty)
              const Padding(
                  padding: EdgeInsets.all(32),
                  child: Text(
                      'Rien à proposer pour le moment. Tes actions planifiées restent dans l’autre onglet.',
                      textAlign: TextAlign.center)),
            for (final suggestion in suggestions)
              Card(
                  child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(suggestion.plant.observationLabel,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold)),
                            const SizedBox(height: 6),
                            Text(suggestion.title,
                                style: const TextStyle(fontSize: 16)),
                            const SizedBox(height: 6),
                            Text(suggestion.reason),
                            const SizedBox(height: 12),
                            Wrap(spacing: 8, runSpacing: 4, children: [
                              FilledButton.icon(
                                  onPressed: () => _openSuggestion(suggestion),
                                  icon: const Icon(Icons.edit_outlined),
                                  label: const Text('Réaliser')),
                              OutlinedButton.icon(
                                  onPressed: () =>
                                      _openSuggestion(suggestion, plan: true),
                                  icon: const Icon(Icons.event_outlined),
                                  label: const Text('Planifier')),
                            ]),
                          ]))),
          ],
        ));
  }

  Future<void> _openSuggestion(ActionSuggestion suggestion,
      {bool plan = false}) async {
    final now = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day + 1, 9);
    await Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => AddActionScreen(
                plant: suggestion.plant,
                initialActionType: suggestion.actionType,
                draftStore: widget.draftStore,
                initialDate: plan ? tomorrow : null)));
    if (mounted) setState(() {});
  }

  Plant? _plantFor(PlantProvider provider, String id) {
    for (final plant in provider.allPlants) {
      if (plant.id == id) return plant;
    }
    return null;
  }

  bool _cycleEnded(Plant plant) => plant.isDead || plant.isHarvested;

  Widget _error(ActionProvider provider) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(provider.plannedError!, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: provider.loadPlannedActions,
              icon: const Icon(Icons.refresh),
              label: const Text('Réessayer'),
            ),
          ]),
        ),
      );

  Widget _empty(ActionProvider provider) => RefreshIndicator(
        onRefresh: provider.loadPlannedActions,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(height: 140),
            Icon(Icons.event_available_outlined, size: 58, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              'Aucune action planifiée',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 8),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                'Choisis une date future quand tu ajoutes une action sur une plante.',
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      );

  Future<void> _complete(
    ActionProvider provider,
    PlantAction action,
  ) async {
    if (_busy.contains(action.id)) return;
    setState(() => _busy.add(action.id));
    try {
      await provider.completePlannedAction(action);
      if (!mounted) return;
      await Future.wait([
        context.read<PlantProvider>().loadPlants(),
        context.read<SpaceProvider>().refresh(),
      ]);
      if (mounted)
        _message('${AppUtils.actionLabel(action.actionType)} validé');
    } catch (error) {
      if (mounted) _message('Validation impossible : $error', error: true);
    } finally {
      if (mounted) setState(() => _busy.remove(action.id));
    }
  }

  Future<void> _postpone(
    ActionProvider provider,
    PlantAction action,
    Duration duration,
  ) async {
    try {
      await provider.postponePlannedAction(action, duration);
      if (mounted) _message('Action reportée');
    } catch (error) {
      if (mounted) _message('Report impossible : $error', error: true);
    }
  }

  Future<void> _delete(ActionProvider provider, PlantAction action) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Supprimer cette action planifiée ?'),
        content: const Text('Cette suppression est définitive.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await provider.deleteAction(action.plantId, action.id);
      if (mounted) _message('Action planifiée supprimée');
    } catch (error) {
      if (mounted) _message('Suppression impossible : $error', error: true);
    }
  }

  void _message(String value, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(value),
      backgroundColor: error ? Colors.red : const Color(0xFF2E7D32),
    ));
  }
}

class _PlannedActionCard extends StatelessWidget {
  final PlantAction action;
  final Plant? plant;
  final VoidCallback? onComplete;
  final ValueChanged<Duration>? onPostpone;
  final VoidCallback onDelete;
  final VoidCallback? onOpen;

  const _PlannedActionCard({
    required this.action,
    required this.plant,
    required this.onComplete,
    required this.onPostpone,
    required this.onDelete,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final ended = plant?.isDead == true || plant?.isHarvested == true;
    final overdue = action.timestamp.isBefore(DateTime.now());
    final color = AppUtils.actionColor(action.actionType);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                CircleAvatar(
                  backgroundColor: color.withValues(alpha: 0.12),
                  child: Icon(AppUtils.actionIcon(action.actionType),
                      color: color),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        AppUtils.actionLabel(action.actionType),
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      Text(plant?.name ?? 'Plante introuvable'),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Options',
                  onSelected: (value) {
                    if (value == 'day') {
                      onPostpone?.call(const Duration(days: 1));
                    } else if (value == 'week') {
                      onPostpone?.call(const Duration(days: 7));
                    } else if (value == 'delete') {
                      onDelete();
                    }
                  },
                  itemBuilder: (_) => [
                    if (onPostpone != null) ...const [
                      PopupMenuItem(
                          value: 'day', child: Text('Reporter 1 jour')),
                      PopupMenuItem(
                          value: 'week', child: Text('Reporter 1 semaine')),
                    ],
                    const PopupMenuItem(
                      value: 'delete',
                      child: Text('Supprimer'),
                    ),
                  ],
                ),
              ]),
              const SizedBox(height: 12),
              Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 6,
                  children: [
                    Icon(Icons.schedule,
                        size: 18,
                        color: overdue ? Colors.red.shade700 : Colors.black54),
                    const SizedBox(width: 6),
                    Text(
                      DateFormat('dd/MM/yyyy à HH:mm').format(action.timestamp),
                      style: TextStyle(
                        color: overdue ? Colors.red.shade700 : Colors.black87,
                        fontWeight: overdue ? FontWeight.w700 : FontWeight.w400,
                      ),
                    ),
                    if (overdue) const Text(' · en retard'),
                  ]),
              if (ended) ...[
                const SizedBox(height: 10),
                const Text(
                  'Cycle terminé : cette action ne peut plus être validée.',
                  style: TextStyle(color: Color(0xFFB71C1C)),
                ),
              ],
              if (onComplete != null) ...[
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    onPressed: onComplete,
                    icon: const Icon(Icons.check, size: 18),
                    label: const Text('Valider maintenant'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
