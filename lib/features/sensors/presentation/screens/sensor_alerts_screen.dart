import 'package:flutter/material.dart';
import '../../../../core/utils/numeric_input_parser.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../../spaces/domain/entities/cultivation_zone.dart';
import '../../../spaces/presentation/providers/space_provider.dart';
import '../../data/repositories/sensor_alert_repository.dart';
import '../../domain/entities/sensor_alert.dart';
import '../../domain/entities/sensor_device.dart';
import '../providers/sensor_provider.dart';

class SensorAlertsScreen extends StatefulWidget {
  const SensorAlertsScreen({super.key});

  @override
  State<SensorAlertsScreen> createState() => _SensorAlertsScreenState();
}

class _SensorAlertsScreenState extends State<SensorAlertsScreen> {
  final _repository = SensorAlertRepository();
  List<SensorAlertRule> _rules = const [];
  List<SensorAlertEvent> _events = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final values = await Future.wait([
        _repository.getRules(),
        _repository.getEvents(),
      ]);
      if (!mounted) return;
      setState(() {
        _rules = values[0] as List<SensorAlertRule>;
        _events = values[1] as List<SensorAlertEvent>;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Alertes indisponibles : $error';
      });
    }
  }

  Future<void> _addRule() async {
    final sensors = context.read<SensorProvider>();
    final spaces = context.read<SpaceProvider>();
    final rule = await showDialog<SensorAlertRule>(
      context: context,
      builder: (_) => _AlertRuleDialog(
        devices: sensors.devices,
        zones: spaces.zones,
      ),
    );
    if (rule == null) return;
    try {
      await _repository.saveRule(rule);
      await _load();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Règle refusée : $error')),
        );
      }
    }
  }

  Future<void> _toggle(SensorAlertRule rule, bool enabled) async {
    final now = DateTime.now();
    await _repository.saveRule(SensorAlertRule(
      id: rule.id,
      name: rule.name,
      zoneId: rule.zoneId,
      deviceId: rule.deviceId,
      metricKey: rule.metricKey,
      comparison: rule.comparison,
      thresholdMin: rule.thresholdMin,
      thresholdMax: rule.thresholdMax,
      durationSeconds: rule.durationSeconds,
      hysteresis: rule.hysteresis,
      cooldownSeconds: rule.cooldownSeconds,
      severity: rule.severity,
      isEnabled: enabled,
      createdAt: rule.createdAt,
      updatedAt: now,
    ));
    await _load();
  }

  Future<void> _acknowledge(SensorAlertEvent event) async {
    await _repository.acknowledge(event.id, DateTime.now());
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final active = _events.where((item) => item.isActive).toList();
    final history = _events.where((item) => !item.isActive).toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Alertes capteurs'),
        actions: [
          IconButton(
            tooltip: 'Actualiser',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addRule,
        icon: const Icon(Icons.add_alert_outlined),
        label: const Text('Règle'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
                children: [
                  if (_error != null)
                    Card(
                      color: Colors.red.shade50,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(_error!),
                      ),
                    ),
                  _title('Actives', active.length),
                  if (active.isEmpty)
                    const ListTile(title: Text('Aucune alerte active'))
                  else
                    ...active.map((event) => _eventTile(event, active: true)),
                  const SizedBox(height: 12),
                  _title('Règles persistantes', _rules.length),
                  if (_rules.isEmpty)
                    const ListTile(title: Text('Aucune règle configurée'))
                  else
                    ..._rules.map(_ruleTile),
                  const SizedBox(height: 12),
                  _title('Historique résolu', history.length),
                  if (history.isEmpty)
                    const ListTile(title: Text('Aucun événement résolu'))
                  else
                    ...history.take(50).map((event) => _eventTile(event)),
                ],
              ),
            ),
    );
  }

  Widget _title(String label, int count) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
        child: Text(
          '$label ($count)',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
      );

  Widget _eventTile(SensorAlertEvent event, {bool active = false}) => Card(
        color:
            event.severity == 'critical' && active ? Colors.red.shade50 : null,
        child: ListTile(
          leading: Icon(
            active ? Icons.warning_amber : Icons.check_circle_outline,
            color: active ? Colors.orange.shade800 : Colors.green,
          ),
          title: Text(event.message),
          subtitle: Text(
            'Début ${DateFormat('dd/MM HH:mm').format(event.startedAt)}'
            '${event.resolvedAt == null ? '' : ' · fin ${DateFormat('dd/MM HH:mm').format(event.resolvedAt!)}'}',
          ),
          trailing: active && !event.isAcknowledged
              ? TextButton(
                  onPressed: () => _acknowledge(event),
                  child: const Text('Acquitter'),
                )
              : event.isAcknowledged
                  ? const Icon(Icons.done_all)
                  : null,
        ),
      );

  Widget _ruleTile(SensorAlertRule rule) => Card(
        child: SwitchListTile(
          value: rule.isEnabled,
          onChanged: (value) => _toggle(rule, value),
          secondary: const Icon(Icons.rule),
          title: Text(rule.name),
          subtitle: Text(
            '${rule.metricKey} · ${_comparisonLabel(rule)} · '
            '${rule.durationSeconds}s · hyst. ${rule.hysteresis}',
          ),
        ),
      );

  String _comparisonLabel(SensorAlertRule rule) => switch (rule.comparison) {
        'gt' => '> ${rule.thresholdMax}',
        'lt' => '< ${rule.thresholdMin}',
        'outside' => 'hors ${rule.thresholdMin}–${rule.thresholdMax}',
        'stale' => 'données absentes',
        _ => rule.comparison,
      };
}

class _AlertRuleDialog extends StatefulWidget {
  final List<SensorDevice> devices;
  final List<CultivationZone> zones;

  const _AlertRuleDialog({required this.devices, required this.zones});

  @override
  State<_AlertRuleDialog> createState() => _AlertRuleDialogState();
}

class _AlertRuleDialogState extends State<_AlertRuleDialog> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _metric = TextEditingController(text: 'temperature_c');
  final _minimum = TextEditingController();
  final _maximum = TextEditingController(text: '30');
  final _duration = TextEditingController(text: '300');
  final _hysteresis = TextEditingController(text: '1');
  final _cooldown = TextEditingController(text: '900');
  String _targetType = 'device';
  String? _targetId;
  String _comparison = 'gt';
  String _severity = 'warning';

  @override
  void initState() {
    super.initState();
    _targetId = widget.devices.firstOrNull?.id ?? widget.zones.firstOrNull?.id;
    if (widget.devices.isEmpty) _targetType = 'zone';
  }

  @override
  Widget build(BuildContext context) {
    final targetItems = _targetType == 'device'
        ? widget.devices
            .map((item) => DropdownMenuItem(
                  value: item.id,
                  child: Text(item.name),
                ))
            .toList()
        : widget.zones
            .map((item) => DropdownMenuItem(
                  value: item.id,
                  child: Text(item.name),
                ))
            .toList();
    return AlertDialog(
      title: const Text('Nouvelle règle'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _name,
                  decoration: const InputDecoration(labelText: 'Nom'),
                  maxLength: 120,
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Nom obligatoire'
                      : null,
                ),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'device', label: Text('Appareil')),
                    ButtonSegment(value: 'zone', label: Text('Zone')),
                  ],
                  selected: {_targetType},
                  onSelectionChanged: (values) => setState(() {
                    _targetType = values.first;
                    _targetId = _targetType == 'device'
                        ? widget.devices.firstOrNull?.id
                        : widget.zones.firstOrNull?.id;
                  }),
                ),
                DropdownButtonFormField<String>(
                  initialValue:
                      targetItems.any((item) => item.value == _targetId)
                          ? _targetId
                          : null,
                  decoration: const InputDecoration(labelText: 'Cible'),
                  items: targetItems,
                  onChanged: (value) => _targetId = value,
                  validator: (value) =>
                      value == null ? 'Cible obligatoire' : null,
                ),
                TextFormField(
                  controller: _metric,
                  decoration: const InputDecoration(
                    labelText: 'Clé de mesure',
                    hintText: 'temperature_c, humidity_percent, vpd_kpa…',
                  ),
                  enabled: _comparison != 'stale',
                  validator: (value) => _comparison != 'stale' &&
                          (value == null || value.trim().isEmpty)
                      ? 'Mesure obligatoire'
                      : null,
                ),
                DropdownButtonFormField<String>(
                  initialValue: _comparison,
                  decoration: const InputDecoration(labelText: 'Condition'),
                  items: const [
                    DropdownMenuItem(value: 'gt', child: Text('Supérieur à')),
                    DropdownMenuItem(value: 'lt', child: Text('Inférieur à')),
                    DropdownMenuItem(
                        value: 'outside', child: Text('Hors intervalle')),
                    DropdownMenuItem(
                        value: 'stale', child: Text('Données absentes')),
                  ],
                  onChanged: (value) => setState(() {
                    _comparison = value!;
                    if (value == 'stale') _metric.text = 'data_age';
                  }),
                ),
                if (_comparison == 'lt' || _comparison == 'outside')
                  _number(_minimum, 'Seuil minimum'),
                if (_comparison == 'gt' || _comparison == 'outside')
                  _number(_maximum, 'Seuil maximum'),
                _number(_duration, 'Durée avant déclenchement (s)',
                    integer: true),
                if (_comparison != 'stale') _number(_hysteresis, 'Hystérésis'),
                _number(_cooldown, 'Délai entre notifications (s)',
                    integer: true),
                DropdownButtonFormField<String>(
                  initialValue: _severity,
                  decoration: const InputDecoration(labelText: 'Sévérité'),
                  items: const [
                    DropdownMenuItem(value: 'info', child: Text('Information')),
                    DropdownMenuItem(
                        value: 'warning', child: Text('Avertissement')),
                    DropdownMenuItem(
                        value: 'critical', child: Text('Critique')),
                  ],
                  onChanged: (value) => _severity = value!,
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Créer')),
      ],
    );
  }

  Widget _number(
    TextEditingController controller,
    String label, {
    bool integer = false,
  }) =>
      TextFormField(
        controller: controller,
        decoration: InputDecoration(labelText: label),
        keyboardType: TextInputType.numberWithOptions(
          decimal: !integer,
          signed: !integer,
        ),
        validator: (value) {
          final normalized = value?.trim() ?? '';
          final parsed = integer
              ? int.tryParse(normalized)?.toDouble()
              : NumericInputParser.tryParse(normalized);
          return parsed == null || !parsed.isFinite || parsed < 0
              ? 'Valeur positive requise'
              : null;
        },
      );

  void _submit() {
    if (!_formKey.currentState!.validate() || _targetId == null) return;
    final now = DateTime.now();
    Navigator.pop(
      context,
      SensorAlertRule(
        id: const Uuid().v4(),
        name: _name.text.trim(),
        zoneId: _targetType == 'zone' ? _targetId : null,
        deviceId: _targetType == 'device' ? _targetId : null,
        metricKey: _metric.text.trim(),
        comparison: _comparison,
        thresholdMin: _comparison == 'lt' || _comparison == 'outside'
            ? NumericInputParser.parse(_minimum.text)
            : null,
        thresholdMax: _comparison == 'gt' || _comparison == 'outside'
            ? NumericInputParser.parse(_maximum.text)
            : null,
        durationSeconds: int.parse(_duration.text.trim()),
        hysteresis: _comparison == 'stale'
            ? 0
            : NumericInputParser.parse(_hysteresis.text),
        cooldownSeconds: int.parse(_cooldown.text.trim()),
        severity: _severity,
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  @override
  void dispose() {
    _name.dispose();
    _metric.dispose();
    _minimum.dispose();
    _maximum.dispose();
    _duration.dispose();
    _hysteresis.dispose();
    _cooldown.dispose();
    super.dispose();
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
