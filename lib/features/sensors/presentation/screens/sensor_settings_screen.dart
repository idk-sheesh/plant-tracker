import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/services/form_draft_store.dart';
import '../../../../core/widgets/form_draft_banner.dart';
import '../../../spaces/presentation/providers/space_provider.dart';
import '../../domain/entities/device_capability.dart';
import '../../domain/entities/sensor_measurement.dart';
import '../providers/sensor_provider.dart';

class SensorSettingsScreen extends StatefulWidget {
  final String? initialZoneId;

  const SensorSettingsScreen({super.key, this.initialZoneId});

  @override
  State<SensorSettingsScreen> createState() => _SensorSettingsScreenState();
}

class _SensorSettingsScreenState extends State<SensorSettingsScreen> {
  final _url = TextEditingController();
  final _name = TextEditingController();
  late final SensorProvider _sensors;
  String? _zoneId;
  bool _busy = false;
  bool? _testResult;
  FormDraftSession? _draftSession;
  bool _draftRestored = false;

  @override
  void initState() {
    super.initState();
    _sensors = context.read<SensorProvider>();
    _zoneId = widget.initialZoneId;
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    await _sensors.initialize();
    final device = widget.initialZoneId == null
        ? _sensors.currentDevice
        : _sensors.deviceForZone(widget.initialZoneId!);
    if (device != null) {
      await _sensors.selectDevice(device);
      _name.text = device.name;
      _url.text = device.baseUrl;
      _zoneId = device.zoneId;
    } else {
      _name.text = 'Capteur ESP32';
    }
    _draftSession = FormDraftSession(
      key: 'sensor-settings-${device?.id ?? widget.initialZoneId ?? 'new'}',
      snapshot: _draftSnapshot,
    );
    final draft = await _draftSession!.restore();
    if (!mounted) return;
    if (draft != null && draft['version'] == 1) {
      _name.text = draft['name'] as String? ?? _name.text;
      _url.text = draft['url'] as String? ?? _url.text;
      _zoneId = draft['zoneId'] as String?;
      _draftRestored = true;
    }
    _draftSession!.start();
    setState(() {});
  }

  @override
  void dispose() {
    _draftSession?.dispose();
    _url.dispose();
    _name.dispose();
    super.dispose();
  }

  Map<String, dynamic> _draftSnapshot() => {
        'version': 1,
        'name': _name.text,
        'url': _url.text,
        'zoneId': _zoneId,
      };

  @override
  Widget build(BuildContext context) {
    final spaces = context.watch<SpaceProvider>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nœud capteur'),
        actions: [
          IconButton(
            tooltip: 'Abandonner le brouillon',
            onPressed: _draftSession == null ? null : _discardDraft,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          FormDraftBanner(restored: _draftRestored),
          const SizedBox(height: 16),
          const Text(
            'Le nœud reste autonome. GardenJournal synchronise et affiche les '
            'mesures sans devenir la boucle de sécurité du matériel.',
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _name,
            decoration: const InputDecoration(
              labelText: 'Nom',
              prefixIcon: Icon(Icons.sensors),
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            key: ValueKey(_zoneId),
            initialValue: _zoneId,
            decoration: const InputDecoration(
              labelText: 'Espace associé',
              prefixIcon: Icon(Icons.location_on_outlined),
            ),
            items: spaces.zones
                .map(
                  (zone) => DropdownMenuItem(
                    value: zone.id,
                    child: Text(zone.name, overflow: TextOverflow.ellipsis),
                  ),
                )
                .toList(),
            onChanged: (value) => setState(() => _zoneId = value),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _url,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'Adresse locale',
              hintText: 'http://192.168.1.42',
              prefixIcon: Icon(Icons.router_outlined),
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _busy ? null : _test,
            icon: const Icon(Icons.network_check),
            label: const Text('Tester GET /status'),
          ),
          if (_testResult != null)
            ListTile(
              leading: Icon(
                _testResult! ? Icons.check_circle : Icons.error,
                color: _testResult! ? Colors.green : Colors.red,
              ),
              title: Text(_testResult!
                  ? 'Nœud joignable'
                  : 'Nœud inaccessible ou réponse invalide'),
            ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _busy ? null : _save,
            icon: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.sync),
            label: const Text('Enregistrer et synchroniser'),
          ),
          Consumer<SensorProvider>(
            builder: (_, sensors, __) => _CapabilitiesCard(
              capabilities: sensors.capabilities,
              measurements: sensors.measurements,
              visible: sensors.currentDevice != null ||
                  sensors.capabilities.isNotEmpty ||
                  sensors.measurements.isNotEmpty,
            ),
          ),
          const SizedBox(height: 24),
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Contrat : GET /status, GET /readings?since=<timestamp>, '
                'POST /config. Si /readings n’est pas encore disponible, '
                'la mesure live reste enregistrée.',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _discardDraft() async {
    final session = _draftSession;
    if (session == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Abandonner les modifications ?'),
        content: const Text('Les paramètres non enregistrés seront supprimés.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Continuer'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Abandonner'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await session.clear();
    if (mounted) Navigator.pop(context);
  }

  Future<void> _test() async {
    if (!_sensors.configureBaseUrl(_url.text)) {
      setState(() => _testResult = false);
      return;
    }
    setState(() => _busy = true);
    final result = await _sensors.testConnection();
    if (mounted)
      setState(() {
        _busy = false;
        _testResult = result;
      });
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty || _zoneId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nom et espace obligatoires.')),
      );
      return;
    }
    if (!_sensors.configureBaseUrl(_url.text)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Adresse locale invalide.')),
      );
      return;
    }
    setState(() => _busy = true);
    final saved = await _sensors.saveCurrentDevice(
      name: _name.text,
      zoneId: _zoneId!,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (!saved) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_sensors.error ?? 'Échec de synchronisation')),
      );
      return;
    }
    await _draftSession?.clear();
    if (!mounted) return;
    Navigator.pop(context);
  }
}

class _CapabilitiesCard extends StatelessWidget {
  final List<DeviceCapability> capabilities;
  final List<SensorMeasurement> measurements;
  final bool visible;

  const _CapabilitiesCard({
    required this.capabilities,
    required this.measurements,
    required this.visible,
  });

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();
    final latestByKey = <String, SensorMeasurement>{};
    for (final measurement in measurements) {
      latestByKey[measurement.capabilityKey] = measurement;
    }
    return Card(
      margin: const EdgeInsets.only(top: 24),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text(
                'Capacités et mesures génériques',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            if (capabilities.isEmpty)
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Text(
                  'Aucune capacité générique déclarée par ce nœud.',
                ),
              )
            else
              ...capabilities.map((capability) {
                final latest = latestByKey[capability.key];
                final type = switch (capability.valueType) {
                  SensorValueType.number => 'Nombre',
                  SensorValueType.boolean => 'Oui/non',
                  SensorValueType.text => 'Texte',
                };
                final access =
                    capability.isWritable ? 'lecture / écriture' : 'lecture';
                return ListTile(
                  dense: true,
                  leading: Icon(
                    capability.isWritable ? Icons.tune : Icons.monitor_heart,
                  ),
                  title: Text(
                    capability.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    '$type · ${capability.unit ?? 'sans unité'} · $access',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: latest == null
                      ? const Text('—')
                      : ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 110),
                          child: Text(
                            latest.displayValue,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.end,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                );
              }),
          ],
        ),
      ),
    );
  }
}
