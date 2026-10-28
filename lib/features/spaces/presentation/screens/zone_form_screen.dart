import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../domain/entities/cultivation_zone.dart';
import '../providers/space_provider.dart';

class ZoneFormScreen extends StatefulWidget {
  final CultivationZone? zone;

  const ZoneFormScreen({super.key, this.zone});

  @override
  State<ZoneFormScreen> createState() => _ZoneFormScreenState();
}

class _ZoneFormScreenState extends State<ZoneFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _description;
  late final List<TextEditingController> _numbers;
  late CultivationZoneType _type;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final zone = widget.zone;
    _name = TextEditingController(text: zone?.name ?? '');
    _description = TextEditingController(text: zone?.description ?? '');
    _type = zone?.type ?? CultivationZoneType.custom;
    _numbers = [
      _number(zone?.widthCm),
      _number(zone?.depthCm),
      _number(zone?.heightCm),
    ];
  }

  TextEditingController _number(double? value) => TextEditingController(
        text:
            value == null ? '' : value.toStringAsFixed(value % 1 == 0 ? 0 : 1),
      );

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    for (final controller in _numbers) {
      controller.dispose();
    }
    super.dispose();
  }

  double? _value(int index) =>
      double.tryParse(_numbers[index].text.trim().replaceAll(',', '.'));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title:
            Text(widget.zone == null ? 'Nouvel espace' : 'Modifier l’espace'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Nom'),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Nom obligatoire'
                  : null,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<CultivationZoneType>(
              initialValue: _type,
              decoration: const InputDecoration(labelText: 'Type'),
              items: CultivationZoneType.values
                  .map(
                    (type) => DropdownMenuItem(
                      value: type,
                      child: Text(type.label),
                    ),
                  )
                  .toList(),
              onChanged: (value) => setState(() => _type = value!),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _description,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Description'),
            ),
            const SizedBox(height: 20),
            const Text('Dimensions (cm)',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Row(children: [
              _numeric(0, 'Largeur'),
              const SizedBox(width: 8),
              _numeric(1, 'Profondeur'),
              const SizedBox(width: 8),
              _numeric(2, 'Hauteur'),
            ]),
            const SizedBox(height: 20),
            const Text('Référence climatique',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Card(
              color: const Color(0xFFF1F8E9),
              child: const Padding(
                padding: EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Le statut utilise le couple température + humidité '
                      'dans le tableau VPD de référence.',
                    ),
                    SizedBox(height: 8),
                    Text(
                        'Bleu : faible transpiration · propagation / début végétatif'),
                    Text(
                        'Vert : transpiration saine · fin végétatif / début floraison'),
                    Text('Jaune : forte transpiration · fin floraison'),
                    Text('Rouge : zone de danger ou mesure hors tableau'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save),
              label: const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _numeric(int index, String label) => Expanded(
        child: TextFormField(
          controller: _numbers[index],
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: label),
          validator: _numberValidator,
        ),
      );

  String? _numberValidator(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    return double.tryParse(value.trim().replaceAll(',', '.')) == null
        ? 'Nombre invalide'
        : null;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    // Les anciennes valeurs personnalisées restent conservées dans le JSON
    // local, mais ne pilotent plus le statut climatique.
    final profile = widget.zone?.targetProfile ?? const ClimateTargetProfile();
    final provider = context.read<SpaceProvider>();
    if (widget.zone == null) {
      await provider.createZone(
        name: _name.text,
        type: _type,
        widthCm: _value(0),
        depthCm: _value(1),
        heightCm: _value(2),
        description: _description.text.trim(),
        targetProfile: profile,
      );
    } else {
      await provider.updateZone(
        widget.zone!.copyWith(
          name: _name.text.trim(),
          type: _type,
          widthCm: _value(0),
          depthCm: _value(1),
          heightCm: _value(2),
          description: _description.text.trim(),
          targetProfile: profile,
        ),
      );
    }
    if (mounted) Navigator.pop(context);
  }
}
