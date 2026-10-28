import 'package:flutter/material.dart';
import '../../../../core/utils/numeric_input_parser.dart';

import '../../data/repositories/automation_repository.dart';
import '../../data/services/automation_rule_service.dart';
import '../../domain/entities/automation_rule.dart';
import '../../domain/entities/sensor_device.dart';

class AutomationRulesScreen extends StatefulWidget {
  final SensorDevice device;

  const AutomationRulesScreen({super.key, required this.device});

  @override
  State<AutomationRulesScreen> createState() => _AutomationRulesScreenState();
}

class _AutomationRulesScreenState extends State<AutomationRulesScreen> {
  final _repository = AutomationRepository();
  final _service = AutomationRuleService();
  List<AutomationRule> _rules = const [];
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final rules = await _repository.getRules(widget.device.id);
    if (mounted) {
      setState(() {
        _rules = rules;
        _loading = false;
      });
    }
  }

  Future<void> _add() async {
    final draft = await showDialog<_RuleDraft>(
      context: context,
      builder: (_) => const _RuleDialog(),
    );
    if (draft == null) return;
    await _sync(
      name: draft.name,
      condition: draft.condition,
      actionType: draft.actionType,
      actionParams: draft.actionParams,
      durationSeconds: draft.durationSeconds,
      cooldownSeconds: draft.cooldownSeconds,
      maxRunsPerDay: draft.maxRunsPerDay,
    );
  }

  Future<void> _toggle(AutomationRule rule, bool enabled) => _sync(
        previous: rule,
        name: rule.name,
        condition: rule.condition,
        actionType: rule.actionType,
        actionParams: rule.actionParams,
        durationSeconds: rule.durationSeconds,
        cooldownSeconds: rule.cooldownSeconds,
        maxRunsPerDay: rule.maxRunsPerDay,
        isEnabled: enabled,
      );

  Future<void> _sync({
    AutomationRule? previous,
    required String name,
    required Map<String, Object?> condition,
    required String actionType,
    required Map<String, Object?> actionParams,
    required int durationSeconds,
    required int cooldownSeconds,
    required int maxRunsPerDay,
    bool isEnabled = true,
  }) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _service.synchronize(
        device: widget.device,
        previous: previous,
        name: name,
        condition: condition,
        actionType: actionType,
        actionParams: actionParams,
        durationSeconds: durationSeconds,
        cooldownSeconds: cooldownSeconds,
        maxRunsPerDay: maxRunsPerDay,
        isEnabled: isEnabled,
      );
      await _load();
    } catch (error) {
      if (mounted) setState(() => _error = 'Règle refusée : $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text('Règles · ${widget.device.name}')),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _busy ? null : _add,
          icon: const Icon(Icons.add),
          label: const Text('IF / AND / OR'),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
                children: [
                  const Card(
                    color: Color(0xFFE3F2FD),
                    child: Padding(
                      padding: EdgeInsets.all(12),
                      child: Text(
                        'Les conditions et limites sont transmises au nœud. '
                        'L’app ne doit pas rester ouverte. Irrigation et autres '
                        'actions critiques sont interdites ici.',
                      ),
                    ),
                  ),
                  if (_error != null)
                    Card(
                      color: Colors.red.shade50,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(_error!),
                      ),
                    ),
                  if (_rules.isEmpty)
                    const ListTile(title: Text('Aucune règle automatique'))
                  else
                    ..._rules.map((rule) => Card(
                          child: SwitchListTile(
                            value: rule.isEnabled && rule.status == 'active',
                            onChanged:
                                _busy ? null : (value) => _toggle(rule, value),
                            secondary: const Icon(Icons.account_tree_outlined),
                            title: Text(rule.name),
                            subtitle: Text(
                              '${_conditionLabel(rule.condition)} → '
                              '${rule.actionType} · max ${rule.maxRunsPerDay}/j · '
                              'rév. ${rule.revision} · ${rule.status}',
                            ),
                          ),
                        )),
                ],
              ),
      );

  String _conditionLabel(Map<String, Object?> condition) {
    final op = condition['op'];
    if (op != null) {
      final children = condition['conditions'] as List;
      return 'IF ${children.length} conditions ${op.toString().toUpperCase()}';
    }
    return 'IF ${condition['metric']} ${condition['comparison']}';
  }
}

class _RuleDraft {
  final String name;
  final Map<String, Object?> condition;
  final String actionType;
  final Map<String, Object?> actionParams;
  final int durationSeconds;
  final int cooldownSeconds;
  final int maxRunsPerDay;

  const _RuleDraft({
    required this.name,
    required this.condition,
    required this.actionType,
    required this.actionParams,
    required this.durationSeconds,
    required this.cooldownSeconds,
    required this.maxRunsPerDay,
  });
}

class _RuleDialog extends StatefulWidget {
  const _RuleDialog();

  @override
  State<_RuleDialog> createState() => _RuleDialogState();
}

class _RuleDialogState extends State<_RuleDialog> {
  final _name = TextEditingController(text: 'Régulation climat');
  final _metric1 = TextEditingController(text: 'temperature_c');
  final _value1 = TextEditingController(text: '28');
  final _metric2 = TextEditingController(text: 'humidity_percent');
  final _value2 = TextEditingController(text: '45');
  final _actionValue = TextEditingController(text: '1');
  final _duration = TextEditingController(text: '300');
  final _cooldown = TextEditingController(text: '900');
  final _maxRuns = TextEditingController(text: '10');
  String _op = 'and';
  String _comparison1 = 'gt';
  String _comparison2 = 'lt';
  String _action = 'light.set';

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Règle IF / AND / OR'),
        content: SizedBox(
          width: 430,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Nom'),
                maxLength: 120,
              ),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'and', label: Text('AND')),
                  ButtonSegment(value: 'or', label: Text('OR')),
                ],
                selected: {_op},
                onSelectionChanged: (values) =>
                    setState(() => _op = values.first),
              ),
              const SizedBox(height: 8),
              _clause(_metric1, _value1, _comparison1,
                  (value) => setState(() => _comparison1 = value)),
              _clause(_metric2, _value2, _comparison2,
                  (value) => setState(() => _comparison2 = value)),
              DropdownButtonFormField<String>(
                initialValue: _action,
                decoration: const InputDecoration(labelText: 'Alors'),
                items: const [
                  DropdownMenuItem(
                      value: 'light.set', child: Text('Lumière ON/OFF')),
                  DropdownMenuItem(
                      value: 'fan.set', child: Text('Ventilation %')),
                ],
                onChanged: (value) => setState(() {
                  _action = value!;
                  _actionValue.text = value == 'fan.set' ? '50' : '1';
                }),
              ),
              TextField(
                controller: _actionValue,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: _action == 'fan.set'
                      ? 'Pourcentage 0–100'
                      : 'État (1 = ON, 0 = OFF)',
                ),
              ),
              _integer(_duration, 'Condition vraie pendant (s)'),
              _integer(_cooldown, 'Cooldown (s)'),
              _integer(_maxRuns, 'Exécutions maximales / jour'),
            ]),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler'),
          ),
          FilledButton(onPressed: _submit, child: const Text('Transmettre')),
        ],
      );

  Widget _clause(
    TextEditingController metric,
    TextEditingController value,
    String comparison,
    ValueChanged<String> onComparison,
  ) =>
      Row(children: [
        Expanded(
          flex: 3,
          child: TextField(
            controller: metric,
            decoration: const InputDecoration(labelText: 'Mesure'),
          ),
        ),
        const SizedBox(width: 6),
        DropdownButton<String>(
          value: comparison,
          items: const [
            DropdownMenuItem(value: 'gt', child: Text('>')),
            DropdownMenuItem(value: 'lt', child: Text('<')),
          ],
          onChanged: (item) => onComparison(item!),
        ),
        const SizedBox(width: 6),
        Expanded(
          flex: 2,
          child: TextField(
            controller: value,
            keyboardType: const TextInputType.numberWithOptions(
              decimal: true,
              signed: true,
            ),
            decoration: const InputDecoration(labelText: 'Seuil'),
          ),
        ),
      ]);

  Widget _integer(TextEditingController controller, String label) => TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(labelText: label),
      );

  void _submit() {
    final first = NumericInputParser.tryParse(_value1.text);
    final second = NumericInputParser.tryParse(_value2.text);
    final duration = int.tryParse(_duration.text.trim());
    final cooldown = int.tryParse(_cooldown.text.trim());
    final maxRuns = int.tryParse(_maxRuns.text.trim());
    if (_name.text.trim().isEmpty ||
        first == null ||
        second == null ||
        duration == null ||
        cooldown == null ||
        maxRuns == null) {
      return;
    }
    final actionParams = <String, Object?>{};
    if (_action == 'fan.set') {
      final percent = NumericInputParser.tryParse(_actionValue.text);
      if (percent == null) return;
      actionParams['percent'] = percent;
    } else {
      if (!const {'0', '1'}.contains(_actionValue.text.trim())) return;
      actionParams['state'] = _actionValue.text.trim() == '1';
    }
    final condition = <String, Object?>{
      'op': _op,
      'conditions': [
        {
          'metric': _metric1.text.trim(),
          'comparison': _comparison1,
          'value': first,
          'hysteresis': 0.5,
        },
        {
          'metric': _metric2.text.trim(),
          'comparison': _comparison2,
          'value': second,
          'hysteresis': 1.0,
        },
      ],
    };
    try {
      AutomationRuleService.validateCondition(condition);
    } catch (_) {
      return;
    }
    Navigator.pop(
      context,
      _RuleDraft(
        name: _name.text.trim(),
        condition: condition,
        actionType: _action,
        actionParams: actionParams,
        durationSeconds: duration,
        cooldownSeconds: cooldown,
        maxRunsPerDay: maxRuns,
      ),
    );
  }

  @override
  void dispose() {
    for (final controller in [
      _name,
      _metric1,
      _value1,
      _metric2,
      _value2,
      _actionValue,
      _duration,
      _cooldown,
      _maxRuns,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }
}
