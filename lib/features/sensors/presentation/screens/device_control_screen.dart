import 'package:flutter/material.dart';
import '../../../../core/utils/numeric_input_parser.dart';
import 'package:intl/intl.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../data/repositories/device_control_repository.dart';
import '../../data/services/safe_device_control_service.dart';
import '../../domain/entities/device_control.dart';
import '../../domain/entities/sensor_device.dart';
import 'automation_rules_screen.dart';

class DeviceControlScreen extends StatefulWidget {
  final SensorDevice device;

  const DeviceControlScreen({super.key, required this.device});

  @override
  State<DeviceControlScreen> createState() => _DeviceControlScreenState();
}

class _DeviceControlScreenState extends State<DeviceControlScreen> {
  final _repository = DeviceControlRepository();
  final _service = SafeDeviceControlService();
  List<DeviceCommand> _commands = const [];
  List<NodeSchedule> _schedules = const [];
  bool _loading = true;
  bool _sending = false;
  double _fanPercent = 50;
  final _pulseSeconds = TextEditingController(text: '10');
  final _maxVolume = TextEditingController(text: '500');
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final values = await Future.wait([
        _repository.getCommands(widget.device.id),
        _repository.getSchedules(widget.device.id),
      ]);
      if (!mounted) return;
      setState(() {
        _commands = values[0] as List<DeviceCommand>;
        _schedules = values[1] as List<NodeSchedule>;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Contrôles indisponibles : $error';
        });
      }
    }
  }

  Future<void> _execute(
    String type,
    Map<String, Object?> params, {
    bool confirmed = false,
  }) async {
    if (_sending) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await _service.execute(
        device: widget.device,
        commandType: type,
        params: params,
        criticalConfirmed: confirmed,
      );
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Commande acquittée par le nœud')),
        );
      }
    } catch (error) {
      if (mounted) setState(() => _error = 'Commande non acquittée : $error');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _confirmIrrigation() async {
    final seconds = int.tryParse(_pulseSeconds.text.trim());
    final volume = NumericInputParser.tryParse(_maxVolume.text);
    if (seconds == null || volume == null) {
      setState(() => _error = 'Durée ou volume invalide');
      return;
    }
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Confirmer l’irrigation'),
            content: Text(
              'Le nœud activera la sortie au maximum $seconds s, avec une '
              'limite déclarée de ${volume.toStringAsFixed(0)} ml. Continuer ?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Annuler'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Confirmer'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;
    await _execute(
      'irrigation.pulse',
      {'durationSeconds': seconds, 'maxVolumeMl': volume},
      confirmed: true,
    );
  }

  Future<void> _addSchedule() async {
    final draft = await showDialog<_ScheduleDraft>(
      context: context,
      builder: (_) => const _ScheduleDialog(),
    );
    if (draft == null) return;
    var confirmed = draft.commandType != 'irrigation.pulse';
    if (!confirmed && mounted) {
      confirmed = await showDialog<bool>(
            context: context,
            builder: (_) => AlertDialog(
              title: const Text('Programme d’irrigation'),
              content: const Text(
                'Ce programme sera stocké et exécuté par le nœud. Confirmer '
                'la durée et la limite de volume avant transmission.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Annuler'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Transmettre'),
                ),
              ],
            ),
          ) ??
          false;
    }
    if (!confirmed) return;
    setState(() => _sending = true);
    try {
      await _service.syncSchedule(
        device: widget.device,
        name: draft.name,
        commandType: draft.commandType,
        params: draft.params,
        timezone: tz.local.name == 'local' ? 'UTC' : tz.local.name,
        daysMask: draft.daysMask,
        startMinute: draft.time.hour * 60 + draft.time.minute,
        criticalConfirmed: confirmed,
      );
      await _load();
    } catch (error) {
      if (mounted) setState(() => _error = 'Programme refusé : $error');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _toggleSchedule(NodeSchedule schedule, bool enabled) async {
    var criticalConfirmed =
        schedule.commandType != 'irrigation.pulse' || !enabled;
    if (!criticalConfirmed) {
      criticalConfirmed = await showDialog<bool>(
            context: context,
            builder: (_) => AlertDialog(
              title: const Text('Réactiver l’irrigation'),
              content: const Text(
                'Confirmer la réactivation de ce programme critique sur le nœud.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Annuler'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Réactiver'),
                ),
              ],
            ),
          ) ??
          false;
    }
    if (!criticalConfirmed) return;
    setState(() => _sending = true);
    try {
      await _service.syncSchedule(
        device: widget.device,
        previous: schedule,
        name: schedule.name,
        commandType: schedule.commandType,
        params: schedule.params,
        timezone: schedule.timezone,
        daysMask: schedule.daysMask,
        startMinute: schedule.startMinute,
        isEnabled: enabled,
        criticalConfirmed: criticalConfirmed,
      );
      await _load();
    } catch (error) {
      if (mounted) setState(() => _error = 'Programme non modifié : $error');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Contrôles · ${widget.device.name}'),
        actions: [
          IconButton(
            tooltip: 'Règles IF / AND / OR',
            icon: const Icon(Icons.account_tree_outlined),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => AutomationRulesScreen(device: widget.device),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _sending ? null : _addSchedule,
        icon: const Icon(Icons.schedule),
        label: const Text('Programme'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
              children: [
                const Card(
                  color: Color(0xFFE8F5E9),
                  child: Padding(
                    padding: EdgeInsets.all(12),
                    child: Text(
                      'Chaque commande expire, possède une clé d’idempotence '
                      'et n’est marquée réussie qu’après un accusé cohérent.',
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
                _standardControls(),
                const SizedBox(height: 12),
                _irrigation(),
                const SizedBox(height: 16),
                _section('Programmes exécutés sur le nœud'),
                if (_schedules.isEmpty)
                  const ListTile(title: Text('Aucun programme transmis'))
                else
                  ..._schedules.map((schedule) => Card(
                        child: SwitchListTile(
                          value:
                              schedule.isEnabled && schedule.status == 'active',
                          onChanged: _sending
                              ? null
                              : (value) => _toggleSchedule(schedule, value),
                          title:
                              Text('${schedule.timeLabel} · ${schedule.name}'),
                          subtitle: Text(
                            '${schedule.commandType} · rév. ${schedule.revision} · ${schedule.status}',
                          ),
                        ),
                      )),
                const SizedBox(height: 16),
                _section('Journal des commandes'),
                if (_commands.isEmpty)
                  const ListTile(title: Text('Aucune commande enregistrée'))
                else
                  ..._commands.take(30).map((command) => ListTile(
                        leading: Icon(
                          command.status == 'acknowledged'
                              ? Icons.verified_outlined
                              : Icons.error_outline,
                          color: command.status == 'acknowledged'
                              ? Colors.green
                              : Colors.orange,
                        ),
                        title: Text(command.commandType),
                        subtitle: Text(
                          '${DateFormat('dd/MM HH:mm:ss').format(command.requestedAt)} · ${command.status}',
                        ),
                      )),
              ],
            ),
    );
  }

  Widget _standardControls() => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Commandes standard',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              Wrap(spacing: 8, children: [
                OutlinedButton(
                  onPressed: _sending
                      ? null
                      : () => _execute('light.set', {'state': true}),
                  child: const Text('Lumière ON'),
                ),
                OutlinedButton(
                  onPressed: _sending
                      ? null
                      : () => _execute('light.set', {'state': false}),
                  child: const Text('Lumière OFF'),
                ),
              ]),
              Text('Ventilation ${_fanPercent.round()} %'),
              Slider(
                value: _fanPercent,
                min: 0,
                max: 100,
                divisions: 20,
                onChanged: _sending
                    ? null
                    : (value) => setState(() => _fanPercent = value),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: _sending
                      ? null
                      : () => _execute('fan.set', {'percent': _fanPercent}),
                  child: const Text('Appliquer la ventilation'),
                ),
              ),
            ],
          ),
        ),
      );

  Widget _irrigation() => Card(
        color: Colors.orange.shade50,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Commande critique · irrigation',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              TextField(
                controller: _pulseSeconds,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Durée (1–120 s)'),
              ),
              TextField(
                controller: _maxVolume,
                keyboardType: TextInputType.number,
                decoration:
                    const InputDecoration(labelText: 'Volume maximal (ml)'),
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: _sending ? null : _confirmIrrigation,
                icon: const Icon(Icons.warning_amber),
                label: const Text('Vérifier et confirmer'),
              ),
            ],
          ),
        ),
      );

  Widget _section(String value) => Text(
        value,
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
      );

  @override
  void dispose() {
    _pulseSeconds.dispose();
    _maxVolume.dispose();
    super.dispose();
  }
}

class _ScheduleDraft {
  final String name;
  final String commandType;
  final Map<String, Object?> params;
  final int daysMask;
  final TimeOfDay time;

  const _ScheduleDraft({
    required this.name,
    required this.commandType,
    required this.params,
    required this.daysMask,
    required this.time,
  });
}

class _ScheduleDialog extends StatefulWidget {
  const _ScheduleDialog();

  @override
  State<_ScheduleDialog> createState() => _ScheduleDialogState();
}

class _ScheduleDialogState extends State<_ScheduleDialog> {
  final _name = TextEditingController(text: 'Programme quotidien');
  final _value = TextEditingController(text: '1');
  final _volume = TextEditingController(text: '500');
  String _type = 'light.set';
  int _daysMask = 127;
  TimeOfDay _time = const TimeOfDay(hour: 8, minute: 0);

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Programme du nœud'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Nom'),
              maxLength: 120,
            ),
            DropdownButtonFormField<String>(
              initialValue: _type,
              decoration: const InputDecoration(labelText: 'Commande'),
              items: const [
                DropdownMenuItem(value: 'light.set', child: Text('Lumière')),
                DropdownMenuItem(value: 'fan.set', child: Text('Ventilation')),
                DropdownMenuItem(
                    value: 'irrigation.pulse', child: Text('Irrigation')),
              ],
              onChanged: (value) => setState(() {
                _type = value!;
                _value.text = value == 'fan.set'
                    ? '50'
                    : value == 'irrigation.pulse'
                        ? '10'
                        : '1';
              }),
            ),
            TextField(
              controller: _value,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                  labelText: switch (_type) {
                'fan.set' => 'Pourcentage',
                'irrigation.pulse' => 'Durée (s)',
                _ => 'État (1 = ON, 0 = OFF)',
              }),
            ),
            if (_type == 'irrigation.pulse')
              TextField(
                controller: _volume,
                keyboardType: TextInputType.number,
                decoration:
                    const InputDecoration(labelText: 'Volume maximal (ml)'),
              ),
            ListTile(
              title: const Text('Heure locale du nœud'),
              trailing: Text(_time.format(context)),
              onTap: () async {
                final selected =
                    await showTimePicker(context: context, initialTime: _time);
                if (selected != null) setState(() => _time = selected);
              },
            ),
            Wrap(
              spacing: 4,
              children: List.generate(7, (index) {
                const labels = ['L', 'M', 'M', 'J', 'V', 'S', 'D'];
                final bit = 1 << index;
                return FilterChip(
                  label: Text(labels[index]),
                  selected: _daysMask & bit != 0,
                  onSelected: (selected) => setState(() {
                    selected ? _daysMask |= bit : _daysMask &= ~bit;
                  }),
                );
              }),
            ),
          ]),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler'),
          ),
          FilledButton(onPressed: _submit, child: const Text('Transmettre')),
        ],
      );

  void _submit() {
    final name = _name.text.trim();
    if (name.isEmpty || _daysMask == 0) return;
    Map<String, Object?> params;
    if (_type == 'fan.set') {
      final value = NumericInputParser.tryParse(_value.text);
      if (value == null) return;
      params = {'percent': value};
    } else if (_type == 'irrigation.pulse') {
      final seconds = int.tryParse(_value.text.trim());
      final volume = NumericInputParser.tryParse(_volume.text);
      if (seconds == null || volume == null) return;
      params = {'durationSeconds': seconds, 'maxVolumeMl': volume};
    } else {
      if (_value.text.trim() != '0' && _value.text.trim() != '1') return;
      params = {'state': _value.text.trim() == '1'};
    }
    try {
      SafeDeviceControlService.validateCommand(_type, params);
    } catch (_) {
      return;
    }
    Navigator.pop(
      context,
      _ScheduleDraft(
        name: name,
        commandType: _type,
        params: params,
        daysMask: _daysMask,
        time: _time,
      ),
    );
  }

  @override
  void dispose() {
    _name.dispose();
    _value.dispose();
    _volume.dispose();
    super.dispose();
  }
}
