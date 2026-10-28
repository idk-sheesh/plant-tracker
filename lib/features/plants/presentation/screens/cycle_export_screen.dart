import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/services/reproducible_cycle_export_service.dart';
import '../../domain/entities/plant.dart';

class CycleExportScreen extends StatefulWidget {
  final Plant plant;

  const CycleExportScreen({super.key, required this.plant});

  @override
  State<CycleExportScreen> createState() => _CycleExportScreenState();
}

class _CycleExportScreenState extends State<CycleExportScreen> {
  final _service = ReproducibleCycleExportService();
  late DateTime _startDate;
  late DateTime _endDate;
  bool _busy = false;
  String? _error;
  CycleExportResult? _result;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final potting = widget.plant.pottingDate;
    _startDate = DateTime(potting.year, potting.month, potting.day);
    _endDate = DateTime(now.year, now.month, now.day);
    if (_startDate.isAfter(_endDate)) _startDate = _endDate;
  }

  Future<void> _pickStart() async {
    final value = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime(2000),
      lastDate: _endDate,
    );
    if (value != null) setState(() => _startDate = value);
  }

  Future<void> _pickEnd() async {
    final value = await showDatePicker(
      context: context,
      initialDate: _endDate,
      firstDate: _startDate,
      lastDate: DateTime.now(),
    );
    if (value != null) setState(() => _endDate = value);
  }

  Future<void> _export() async {
    setState(() {
      _busy = true;
      _error = null;
      _result = null;
    });
    try {
      final result = await _service.buildExport(
        plantId: widget.plant.id,
        periodStart: _startDate,
        periodEnd: _endDate.add(const Duration(days: 1)),
      );
      ReproducibleCycleExportService.inspect(result.bytes);
      if (!mounted) return;
      setState(() => _result = result);
      await _service.shareExport(result);
    } catch (error) {
      if (mounted) setState(() => _error = 'Export refusé : $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Export de cycle vérifiable')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              widget.plant.name,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 12),
            const Card(
              color: Color(0xFFE8F5E9),
              child: Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  'Le JSON réunit actions, mesures, alertes et commandes dans '
                  'une période explicite. Son SHA-256 permet de détecter toute '
                  'modification. Les photos, chemins locaux, mots de passe et '
                  'clés de confiance OTA sont exclus.',
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _DateCard(
                    label: 'Début inclus',
                    date: _startDate,
                    onTap: _busy ? null : _pickStart,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _DateCard(
                    label: 'Fin incluse',
                    date: _endDate,
                    onTap: _busy ? null : _pickEnd,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              'Les mesures suivent les placements datés de la plante. Un '
              'placement de son groupe actuel est signalé comme tel dans '
              'l’export. Les commandes sont reliées par l’historique de mesure '
              'ou par la zone actuelle de l’appareil.',
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: Colors.red)),
            ],
            if (_result != null) ...[
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Export contrôlé',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 6),
                      SelectableText('SHA-256 : ${_result!.contentSha256}'),
                      const SizedBox(height: 6),
                      Text(_countLabel(_result!.counts)),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _busy ? null : _export,
              icon: _busy
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.verified_outlined),
              label:
                  Text(_busy ? 'Vérification…' : 'Créer et partager le JSON'),
            ),
          ],
        ),
      );

  String _countLabel(Map<String, int> counts) =>
      '${counts['actions']} actions · ${counts['measurements']} mesures · '
      '${counts['alerts']} alertes · '
      '${(counts['commands'] ?? 0) + (counts['automatedCommands'] ?? 0)} commandes';
}

class _DateCard extends StatelessWidget {
  final String label;
  final DateTime date;
  final VoidCallback? onTap;

  const _DateCard({
    required this.label,
    required this.date,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Card(
        child: ListTile(
          onTap: onTap,
          leading: const Icon(Icons.calendar_month_outlined),
          title: Text(label),
          subtitle: Text(DateFormat('dd/MM/yyyy').format(date)),
        ),
      );
}
