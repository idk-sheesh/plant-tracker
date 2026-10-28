import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/utils/app_utils.dart';
import '../../../../core/services/form_draft_store.dart';
import '../../../plants/domain/entities/plant.dart';
import '../../../plants/presentation/providers/plant_provider.dart';
import '../../data/repositories/observation_repository.dart';
import '../../domain/entities/observation_assessment.dart';
import '../providers/observation_provider.dart';
import 'observation_assessment_screen.dart';

class ObservationScreen extends StatelessWidget {
  final String? initialPlantId;
  final ObservationRepository? repository;
  final FormDraftStore? draftStore;
  const ObservationScreen(
      {super.key, this.initialPlantId, this.repository, this.draftStore});

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
        create: (_) => ObservationProvider(repository: repository)..load(),
        child: _ObservationView(
            initialPlantId: initialPlantId, draftStore: draftStore),
      );
}

class _ObservationView extends StatefulWidget {
  final String? initialPlantId;
  final FormDraftStore? draftStore;
  const _ObservationView({this.initialPlantId, this.draftStore});
  @override
  State<_ObservationView> createState() => _ObservationViewState();
}

class _ObservationViewState extends State<_ObservationView> {
  String? _variety;
  String _stage = 'growth';
  final _excluded = <String>{};
  bool _initialized = false;

  String _varietyKey(Plant plant) => (plant.variety ?? '').trim().toLowerCase();

  @override
  Widget build(BuildContext context) {
    final plants = context.watch<PlantProvider>();
    final observations = context.watch<ObservationProvider>();
    if (!_initialized && plants.allPlants.isNotEmpty) {
      final initial = plants.allPlants
          .where((p) => p.id == widget.initialPlantId)
          .firstOrNull;
      _variety = _varietyKey(initial ?? plants.allPlants.first);
      _initialized = true;
    }
    final varieties = <String, String>{};
    for (final plant in plants.allPlants) {
      varieties.putIfAbsent(
          _varietyKey(plant),
          () => plant.variety?.trim().isNotEmpty == true
              ? plant.variety!.trim()
              : 'Sans variété renseignée');
    }
    final variety =
        varieties.containsKey(_variety) ? _variety : varieties.keys.firstOrNull;
    final candidates = plants.allPlants
        .where((p) => _varietyKey(p) == variety)
        .toList()
      ..sort((a, b) => a.observationLabel.compareTo(b.observationLabel));
    final selected =
        candidates.where((p) => !_excluded.contains(p.id)).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Observations du jardin')),
      body: observations.isLoading || plants.isLoading
          ? const Center(child: CircularProgressIndicator())
          : observations.error != null || plants.error != null
              ? Center(
                  child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Text(observations.error ?? plants.error!),
                        FilledButton(
                            onPressed: () async {
                              await Future.wait(
                                  [observations.load(), plants.loadPlants()]);
                            },
                            child: const Text('Réessayer')),
                      ])))
              : candidates.isEmpty
                  ? const Center(
                      child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Text(
                              'Ajoute tes plantes avec une même variété et un code repère différent (P01, P02…).')))
                  : RefreshIndicator(
                      onRefresh: observations.load,
                      child: ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          const Text(
                              'Compare les plantes d’une même variété au même stade. '
                              'Sélectionne les plantes de ton jardin ; les cases vides restent non notées.'),
                          const SizedBox(height: 16),
                          DropdownButtonFormField<String>(
                              key: ValueKey('variety-$variety'),
                              initialValue: variety,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                  labelText: 'Espèce / variété'),
                              items: varieties.entries
                                  .map((e) => DropdownMenuItem(
                                      value: e.key,
                                      child: Text(e.value,
                                          overflow: TextOverflow.ellipsis)))
                                  .toList(),
                              onChanged: (v) => setState(() {
                                    _variety = v;
                                    _excluded.clear();
                                  })),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<String>(
                              initialValue: _stage,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                  labelText: 'Stade comparé'),
                              items: observationStages.entries
                                  .map((e) => DropdownMenuItem(
                                      value: e.key,
                                      child: Text(e.value,
                                          overflow: TextOverflow.ellipsis)))
                                  .toList(),
                              onChanged: (v) => setState(() => _stage = v!)),
                          const SizedBox(height: 12),
                          Wrap(spacing: 8, runSpacing: 4, children: [
                            for (final plant in candidates)
                              FilterChip(
                                  label: Text(plant.observationLabel),
                                  selected: !_excluded.contains(plant.id),
                                  onSelected: (v) => setState(() {
                                        v
                                            ? _excluded.remove(plant.id)
                                            : _excluded.add(plant.id);
                                      })),
                          ]),
                          const SizedBox(height: 12),
                          FilledButton.icon(
                              onPressed: selected.isEmpty
                                  ? null
                                  : () => _noteAll(selected),
                              icon: const Icon(Icons.playlist_add_check),
                              label: Text(
                                  'Noter les ${selected.length} plantes à la suite')),
                          if (selected.isNotEmpty) ...[
                            const SizedBox(height: 16),
                            const Text(
                                'Dernière observation de chaque plante pour ce stade. '
                                'Fais défiler le tableau horizontalement pour comparer.'),
                            const SizedBox(height: 8),
                            _comparison(selected, observations),
                            const SizedBox(height: 20),
                            const Text('Historique des observations',
                                style: TextStyle(fontWeight: FontWeight.bold)),
                            for (final plant in selected) ...[
                              ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: Text(plant.observationLabel),
                                  subtitle: Text(plant.isDead
                                      ? 'Plante morte · historique conservé'
                                      : plant.isHarvested
                                          ? 'Récoltée'
                                          : plant.variety ?? ''),
                                  trailing: TextButton(
                                      onPressed: () => _edit(plant),
                                      child: const Text('Noter'))),
                              for (final assessment in observations.assessments
                                  .where((a) =>
                                      a.plantId == plant.id &&
                                      a.stage == _stage))
                                ListTile(
                                    title: Text(AppUtils.formatDate(
                                        assessment.observedAt)),
                                    subtitle: Text(
                                        '${assessment.scores.length} critères · ${observationDecisions[assessment.decision]}'
                                        '${assessment.notes?.isNotEmpty == true ? '\n${assessment.notes}' : ''}'),
                                    trailing: const Icon(Icons.edit_outlined),
                                    onTap: () =>
                                        _edit(plant, existing: assessment)),
                            ],
                          ],
                          const SizedBox(height: 32),
                        ],
                      )),
    );
  }

  Widget _comparison(List<Plant> plants, ObservationProvider provider) {
    final latest = {
      for (final p in plants) p.id: provider.latest(p.id, _stage)
    };
    DataRow row(String label, String Function(ObservationAssessment?) value) =>
        DataRow(cells: [
          DataCell(SizedBox(width: 170, child: Text(label))),
          for (final p in plants)
            DataCell(SizedBox(
                width: 140,
                child: Text(value(latest[p.id]),
                    maxLines: 4, overflow: TextOverflow.ellipsis))),
        ]);
    return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columnSpacing: 16,
          dataRowMinHeight: 48,
          dataRowMaxHeight: 110,
          columns: [
            const DataColumn(label: Text('Critère')),
            for (final plant in plants)
              DataColumn(
                  label: SizedBox(
                      width: 140,
                      child: Text(plant.observationLabel,
                          maxLines: 3, overflow: TextOverflow.ellipsis)))
          ],
          rows: [
            row(
                'Date d’observation',
                (a) =>
                    a == null ? 'Non noté' : AppUtils.formatDate(a.observedAt)),
            for (final c in observationScores)
              row(
                  c.label,
                  (a) => a?.scores[c.key] == null
                      ? '—'
                      : '${a!.scores[c.key]} / 5'),
            for (final c in observationMeasurements)
              row(
                  '${c.label} (${c.unit})',
                  (a) =>
                      a?.measurements[c.key]?.toString().replaceAll('.', ',') ??
                      '—'),
            row('Profil aromatique',
                (a) => a?.aromas?.isNotEmpty == true ? a!.aromas! : '—'),
            row('Notes', (a) => a?.notes?.isNotEmpty == true ? a!.notes! : '—'),
            row(
                'Sélection',
                (a) =>
                    a == null ? '—' : observationDecisions[a.decision] ?? '—'),
          ],
        ));
  }

  Future<bool?> _edit(Plant plant, {ObservationAssessment? existing}) {
    final provider = context.read<ObservationProvider>();
    return Navigator.push<bool>(
        context,
        MaterialPageRoute(
            builder: (_) => ChangeNotifierProvider.value(
                value: provider,
                child: ObservationAssessmentScreen(
                  plant: plant,
                  existing: existing,
                  initialStage: _stage,
                  draftStore: widget.draftStore,
                ))));
  }

  Future<void> _noteAll(List<Plant> plants) async {
    for (final plant in plants) {
      final saved = await _edit(plant);
      if (!mounted || saved != true) return;
    }
  }
}
