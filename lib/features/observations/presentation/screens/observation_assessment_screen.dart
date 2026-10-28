import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../../../../core/services/form_draft_store.dart';
import '../../../../core/utils/app_utils.dart';
import '../../../../core/utils/numeric_input_parser.dart';
import '../../../../core/widgets/form_draft_banner.dart';
import '../../../plants/domain/entities/plant.dart';
import '../../domain/entities/observation_assessment.dart';
import '../providers/observation_provider.dart';

class ObservationAssessmentScreen extends StatefulWidget {
  final Plant plant;
  final String initialStage;
  final ObservationAssessment? existing;
  final FormDraftStore? draftStore;
  const ObservationAssessmentScreen(
      {super.key,
      required this.plant,
      this.initialStage = 'growth',
      this.existing,
      this.draftStore});

  @override
  State<ObservationAssessmentScreen> createState() =>
      _ObservationAssessmentScreenState();
}

class _ObservationAssessmentScreenState
    extends State<ObservationAssessmentScreen> {
  final _scores = <String, int>{};
  final _measurements = <String, TextEditingController>{};
  final _aromas = TextEditingController();
  final _notes = TextEditingController();
  late String _stage;
  String _decision = 'undecided';
  late DateTime _date;
  late final FormDraftSession _draft;
  bool _restored = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _stage = existing?.stage ?? widget.initialStage;
    _date = existing?.observedAt ?? DateTime.now();
    _scores.addAll(existing?.scores ?? {});
    _aromas.text = existing?.aromas ?? '';
    _notes.text = existing?.notes ?? '';
    _decision = existing?.decision ?? 'undecided';
    for (final c in observationMeasurements) {
      _measurements[c.key] = TextEditingController(
          text:
              existing?.measurements[c.key]?.toString().replaceAll('.', ',') ??
                  '');
    }
    _draft = FormDraftSession(
        store: widget.draftStore,
        key: 'observation-${widget.plant.id}-${existing?.id ?? 'new'}',
        snapshot: _snapshot);
    WidgetsBinding.instance.addPostFrameCallback((_) => _restore());
  }

  Map<String, dynamic> _snapshot() => {
        'version': 1,
        'stage': _stage,
        'date': _date.toIso8601String(),
        'scores': Map<String, int>.from(_scores),
        'measurements': {
          for (final e in _measurements.entries) e.key: e.value.text
        },
        'aromas': _aromas.text,
        'notes': _notes.text,
        'decision': _decision,
      };

  Future<void> _restore() async {
    final draft = await _draft.restore();
    if (!mounted) return;
    if (draft != null && draft['version'] == 1) {
      setState(() {
        if (observationStages.containsKey(draft['stage']))
          _stage = draft['stage'] as String;
        if (observationDecisions.containsKey(draft['decision']))
          _decision = draft['decision'] as String;
        _date = DateTime.tryParse('${draft['date']}') ?? _date;
        final scores = draft['scores'];
        if (scores is Map) {
          _scores.clear();
          for (final c in observationScores) {
            final value = scores[c.key];
            if (value is int && value >= 1 && value <= 5)
              _scores[c.key] = value;
          }
        }
        final measures = draft['measurements'];
        if (measures is Map) {
          for (final e in _measurements.entries) {
            if (measures[e.key] is String)
              e.value.text = measures[e.key] as String;
          }
        }
        _aromas.text = draft['aromas'] as String? ?? _aromas.text;
        _notes.text = draft['notes'] as String? ?? _notes.text;
        _restored = true;
      });
    }
    _draft.start();
  }

  @override
  void dispose() {
    _draft.dispose();
    _aromas.dispose();
    _notes.dispose();
    for (final c in _measurements.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(widget.plant.observationLabel), actions: [
          IconButton(
              tooltip: 'Abandonner le brouillon',
              icon: const Icon(Icons.delete_outline),
              onPressed: _saving
                  ? null
                  : () async {
                      await _draft.clear();
                      if (context.mounted) Navigator.pop(context);
                    }),
        ]),
        body: AbsorbPointer(
            absorbing: _saving,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                FormDraftBanner(restored: _restored),
                const Text(
                    'Note de 1 à 5 : 5 correspond le mieux à ce que tu recherches. '
                    'Laisse les critères non observés vides. Chaque observation garde sa date.'),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                    key: ValueKey('stage-$_stage'),
                    initialValue: _stage,
                    decoration:
                        const InputDecoration(labelText: 'Stade comparé'),
                    items: observationStages.entries
                        .map((e) => DropdownMenuItem(
                            value: e.key, child: Text(e.value)))
                        .toList(),
                    onChanged: (v) => setState(() => _stage = v!)),
                ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.calendar_today),
                    title: Text(AppUtils.formatDate(_date)),
                    onTap: _pickDate),
                for (final section
                    in observationScores.map((c) => c.section).toSet())
                  Card(
                      child: ExpansionTile(
                          key: ValueKey('$section-$_stage'),
                          initiallyExpanded: switch (_stage) {
                            'flowering' => section == 'Floraison',
                            'harvest' ||
                            'stored' =>
                              section == 'Récolte et bilan',
                            _ => section == 'Croissance',
                          },
                          title: Text(section),
                          subtitle: Text(
                              '${observationScores.where((c) => c.section == section && _scores.containsKey(c.key)).length} / '
                              '${observationScores.where((c) => c.section == section).length} critères notés'),
                          children: [
                        for (final c in observationScores
                            .where((c) => c.section == section))
                          Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 16),
                              child: Row(children: [
                                Expanded(child: Text(c.label)),
                                const SizedBox(width: 8),
                                DropdownButton<int>(
                                  key: ValueKey('score-${c.key}'),
                                  value: _scores[c.key],
                                  hint: const Text('Non noté'),
                                  items: [
                                    for (var n = 1; n <= 5; n++)
                                      DropdownMenuItem(
                                          value: n, child: Text('$n / 5'))
                                  ],
                                  onChanged: (v) =>
                                      setState(() => _scores[c.key] = v!),
                                ),
                                if (_scores.containsKey(c.key))
                                  IconButton(
                                      tooltip: 'Effacer ${c.label}',
                                      icon: const Icon(Icons.close, size: 18),
                                      onPressed: () => setState(
                                          () => _scores.remove(c.key))),
                              ])),
                      ])),
                Card(
                    child: ExpansionTile(
                        title: const Text('Mesures chiffrées'),
                        children: [
                      for (final c in observationMeasurements)
                        Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                            child: TextField(
                                controller: _measurements[c.key],
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                        decimal: true),
                                decoration: InputDecoration(
                                    labelText: '${c.label} (${c.unit})',
                                    hintText: 'Facultatif, ex. 12,5'))),
                    ])),
                const SizedBox(height: 12),
                TextField(
                    controller: _aromas,
                    maxLines: 2,
                    decoration: const InputDecoration(
                        labelText: 'Profil aromatique',
                        hintText: 'Descripteurs, évolution, particularités…')),
                const SizedBox(height: 12),
                TextField(
                    controller: _notes,
                    minLines: 3,
                    maxLines: 8,
                    decoration: const InputDecoration(
                        labelText: 'Notes et conditions d’observation')),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                    key: ValueKey('decision-$_decision'),
                    initialValue: _decision,
                    decoration:
                        const InputDecoration(labelText: 'Sélection du repère'),
                    items: observationDecisions.entries
                        .map((e) => DropdownMenuItem(
                            value: e.key, child: Text(e.value)))
                        .toList(),
                    onChanged: (v) => setState(() => _decision = v!)),
                if (_error != null)
                  Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(_error!,
                          style: const TextStyle(color: Colors.red))),
                const SizedBox(height: 20),
                FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.check),
                    label: Text(_saving
                        ? 'Enregistrement…'
                        : 'Enregistrer l’observation')),
                const SizedBox(height: 24),
              ],
            )),
      );

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final date = await showDatePicker(
        context: context,
        initialDate: _date.isAfter(now) ? now : _date,
        firstDate: DateTime(2000),
        lastDate: now);
    if (date != null && mounted) setState(() => _date = date);
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final measurements = <String, double>{};
      for (final c in observationMeasurements) {
        final value = NumericInputParser.optionalNonNegative(
            _measurements[c.key]!.text,
            fieldLabel: c.label,
            maximum: c.maximum);
        if (value != null) measurements[c.key] = value;
      }
      final now = DateTime.now();
      final assessment = ObservationAssessment(
        id: widget.existing?.id ?? const Uuid().v4(),
        plantId: widget.plant.id,
        observedAt: _date,
        stage: _stage,
        scores: _scores,
        measurements: measurements,
        aromas: _aromas.text.trim(),
        notes: _notes.text.trim(),
        decision: _decision,
        createdAt: widget.existing?.createdAt ?? now,
      );
      if (_date.isAfter(now))
        throw const FormatException('Choisis une date passée ou aujourd’hui.');
      await context
          .read<ObservationProvider>()
          .save(assessment, editing: widget.existing != null);
      await _draft.clear();
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted)
        setState(() => _error = e is FormatException
            ? e.message
            : 'Enregistrement impossible : $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
