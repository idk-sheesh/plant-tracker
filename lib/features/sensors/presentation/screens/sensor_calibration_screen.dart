import 'package:flutter/material.dart';
import '../../../../core/utils/numeric_input_parser.dart';
import 'package:intl/intl.dart';

import '../../data/repositories/calibration_repository.dart';
import '../../data/repositories/sensor_data_repository.dart';
import '../../data/services/sensor_calibration_service.dart';
import '../../domain/entities/calibration_record.dart';
import '../../domain/entities/device_capability.dart';
import '../../domain/entities/sensor_device.dart';

class SensorCalibrationScreen extends StatefulWidget {
  final SensorDevice device;

  const SensorCalibrationScreen({super.key, required this.device});

  @override
  State<SensorCalibrationScreen> createState() =>
      _SensorCalibrationScreenState();
}

class _SensorCalibrationScreenState extends State<SensorCalibrationScreen> {
  final _data = SensorDataRepository();
  final _records = CalibrationRepository();
  final _service = SensorCalibrationService();
  final _formKey = GlobalKey<FormState>();
  final _references = TextEditingController();
  final _slope = TextEditingController(text: '1');
  final _offset = TextEditingController(text: '0');
  final _temperature = TextEditingController();
  final _operator = TextEditingController();
  final _lot = TextEditingController();
  final _notes = TextEditingController();
  List<DeviceCapability> _capabilities = const [];
  List<CalibrationRecord> _history = const [];
  String? _capabilityKey;
  String _type = 'single_point';
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final capabilities =
          await _data.getCapabilitiesForDevice(widget.device.id);
      final numeric = capabilities
          .where((item) => item.valueType == SensorValueType.number)
          .toList();
      final history = await _records.getForDevice(widget.device.id);
      if (!mounted) return;
      setState(() {
        _capabilities = numeric;
        _capabilityKey = numeric.any((item) => item.key == _capabilityKey)
            ? _capabilityKey
            : numeric.firstOrNull?.key;
        _history = history;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Chargement impossible : $error';
      });
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate() || _capabilityKey == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final rawReferences =
          _references.text.split(';').map(NumericInputParser.parse).toList();
      final record = await _service.calibrate(
        device: widget.device,
        capabilityKey: _capabilityKey!,
        calibrationType: _type,
        referenceValues: {
          for (var index = 0; index < rawReferences.length; index++)
            'point${index + 1}': rawReferences[index],
        },
        coefficients: {
          'slope': NumericInputParser.parse(_slope.text),
          'offset': NumericInputParser.parse(_offset.text),
        },
        temperatureC: _optionalDouble(_temperature.text),
        operatorName: _operator.text,
        solutionLot: _lot.text,
        notes: _notes.text,
      );
      if (!mounted) return;
      setState(() => _history = [record, ..._history]);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Calibration acquittée et archivée')),
      );
    } catch (error) {
      if (mounted) setState(() => _error = 'Calibration refusée : $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Calibration · ${widget.device.name}')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_error != null)
                  Card(
                    color: Colors.red.shade50,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(_error!),
                    ),
                  ),
                if (_capabilities.isEmpty)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        'Le nœud ne déclare aucune capacité numérique. '
                        'Synchronise-le avant de le calibrer.',
                      ),
                    ),
                  )
                else
                  _form(),
                const SizedBox(height: 16),
                const Text(
                  'Historique immuable',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 8),
                if (_history.isEmpty)
                  const Text('Aucune calibration acquittée.')
                else
                  ..._history.map(_recordTile),
              ],
            ),
    );
  }

  Widget _form() => Form(
        key: _formKey,
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                DropdownButtonFormField<String>(
                  initialValue: _capabilityKey,
                  decoration: const InputDecoration(labelText: 'Mesure'),
                  items: _capabilities
                      .map((item) => DropdownMenuItem(
                            value: item.key,
                            child: Text(item.displayName),
                          ))
                      .toList(),
                  onChanged: (value) => setState(() => _capabilityKey = value),
                ),
                DropdownButtonFormField<String>(
                  initialValue: _type,
                  decoration: const InputDecoration(labelText: 'Méthode'),
                  items: const [
                    DropdownMenuItem(
                        value: 'single_point', child: Text('1 point')),
                    DropdownMenuItem(
                        value: 'two_point', child: Text('2 points')),
                    DropdownMenuItem(
                        value: 'three_point', child: Text('3 points')),
                  ],
                  onChanged: (value) => setState(() => _type = value!),
                ),
                TextFormField(
                  controller: _references,
                  decoration: const InputDecoration(
                    labelText: 'Références séparées par ;',
                    hintText: '4,01 ; 7,00',
                  ),
                  keyboardType: TextInputType.text,
                  validator: _validateReferences,
                ),
                Row(children: [
                  Expanded(child: _numberField(_slope, 'Pente')),
                  const SizedBox(width: 12),
                  Expanded(child: _numberField(_offset, 'Décalage')),
                ]),
                _numberField(
                  _temperature,
                  'Température de calibration (°C, optionnel)',
                  optional: true,
                ),
                TextFormField(
                  controller: _operator,
                  decoration: const InputDecoration(labelText: 'Opérateur'),
                  maxLength: 120,
                ),
                TextFormField(
                  controller: _lot,
                  decoration: const InputDecoration(labelText: 'Lot solution'),
                  maxLength: 120,
                ),
                TextFormField(
                  controller: _notes,
                  decoration: const InputDecoration(labelText: 'Notes'),
                  maxLength: 2000,
                  maxLines: 2,
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _saving ? null : _submit,
                    icon: _saving
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.science_outlined),
                    label: const Text('Envoyer puis archiver l’acquittement'),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'Aucun enregistrement local n’est créé si le nœud refuse '
                    'ou ne répond pas.',
                    style: TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                ),
              ],
            ),
          ),
        ),
      );

  Widget _numberField(
    TextEditingController controller,
    String label, {
    bool optional = false,
  }) =>
      TextFormField(
        controller: controller,
        decoration: InputDecoration(labelText: label),
        keyboardType: const TextInputType.numberWithOptions(
          decimal: true,
          signed: true,
        ),
        validator: (value) {
          if (optional && (value == null || value.trim().isEmpty)) return null;
          final parsed = NumericInputParser.tryParse(value ?? '');
          return parsed == null || !parsed.isFinite ? 'Nombre invalide' : null;
        },
      );

  String? _validateReferences(String? value) {
    final expected = switch (_type) {
      'single_point' => 1,
      'two_point' => 2,
      _ => 3,
    };
    final parts = value?.split(';') ?? const [];
    if (parts.length != expected ||
        parts.any((item) => NumericInputParser.tryParse(item) == null)) {
      return '$expected référence(s) requise(s), séparées par ;';
    }
    return null;
  }

  Widget _recordTile(CalibrationRecord record) => Card(
        child: ListTile(
          leading: const Icon(Icons.verified_outlined),
          title: Text('${record.capabilityKey} · ${record.calibrationType}'),
          subtitle: Text(
            '${DateFormat('dd/MM/yyyy HH:mm').format(record.calibratedAt)}\n'
            'SHA-256 ${record.nodeConfigHash.substring(0, 12)}…',
          ),
          isThreeLine: true,
        ),
      );

  static double? _optionalDouble(String value) {
    final normalized = value.trim();
    return normalized.isEmpty ? null : NumericInputParser.parse(normalized);
  }

  @override
  void dispose() {
    _references.dispose();
    _slope.dispose();
    _offset.dispose();
    _temperature.dispose();
    _operator.dispose();
    _lot.dispose();
    _notes.dispose();
    super.dispose();
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
