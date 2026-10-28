import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/services/form_draft_store.dart';
import '../../../../core/widgets/form_draft_banner.dart';
import '../../../scanner/domain/qr_payload_parser.dart';
import '../../../spaces/presentation/providers/space_provider.dart';
import '../../data/repositories/sensor_data_repository.dart';
import '../../data/services/ble_provisioning_service.dart';
import '../../domain/entities/sensor_device.dart';
import '../providers/sensor_provider.dart';
import 'device_health_screen.dart';

class DeviceProvisioningScreen extends StatefulWidget {
  final QrPayload identity;

  const DeviceProvisioningScreen({super.key, required this.identity});

  @override
  State<DeviceProvisioningScreen> createState() =>
      _DeviceProvisioningScreenState();
}

class _DeviceProvisioningScreenState extends State<DeviceProvisioningScreen> {
  final _name = TextEditingController();
  final _ssid = TextEditingController();
  final _password = TextEditingController();
  final _gateway = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  final _ble = BleProvisioningService();
  final _data = SensorDataRepository();
  String? _zoneId;
  bool _busy = false;
  String? _error;
  late final FormDraftSession _draftSession;
  bool _draftRestored = false;

  @override
  void initState() {
    super.initState();
    _name.text = widget.identity.model == null
        ? widget.identity.deviceId
        : '${widget.identity.model} ${widget.identity.deviceId}';
    _draftSession = FormDraftSession(
      key: 'provision-${widget.identity.deviceId}',
      snapshot: _draftSnapshot,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _restoreDraft());
  }

  @override
  void dispose() {
    _draftSession.dispose();
    _name.dispose();
    _ssid.dispose();
    _password.dispose();
    _gateway.dispose();
    super.dispose();
  }

  Map<String, dynamic> _draftSnapshot() => {
        'version': 1,
        'name': _name.text,
        'ssid': _ssid.text,
        'gateway': _gateway.text,
        'zoneId': _zoneId,
      };

  Future<void> _restoreDraft() async {
    final draft = await _draftSession.restore();
    if (!mounted) return;
    if (draft != null && draft['version'] == 1) {
      setState(() {
        _name.text = draft['name'] as String? ?? _name.text;
        _ssid.text = draft['ssid'] as String? ?? '';
        _gateway.text = draft['gateway'] as String? ?? '';
        _zoneId = draft['zoneId'] as String?;
        _draftRestored = true;
      });
    }
    _draftSession.start();
  }

  @override
  Widget build(BuildContext context) {
    final spaces = context.watch<SpaceProvider>();
    final isGateway = widget.identity.entityType == QrEntityType.gateway;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Associer un appareil'),
        actions: [
          IconButton(
            tooltip: 'Abandonner le brouillon',
            onPressed: _busy ? null : _discardDraft,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            FormDraftBanner(
              restored: _draftRestored,
              containsSensitiveField: true,
            ),
            const SizedBox(height: 12),
            Card(
              color: const Color(0xFFE8F5E9),
              child: ListTile(
                leading: Icon(isGateway ? Icons.router : Icons.sensors),
                title: Text(widget.identity.deviceId),
                subtitle: Text(
                  '${widget.identity.model ?? 'Modèle non déclaré'} · '
                  'jeton temporaire validé',
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Nom dans l’app'),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Nom obligatoire'
                  : null,
            ),
            const SizedBox(height: 12),
            if (!isGateway)
              DropdownButtonFormField<String>(
                initialValue: _zoneId,
                decoration: const InputDecoration(labelText: 'Espace associé'),
                items: spaces.zones
                    .map(
                      (zone) => DropdownMenuItem(
                        value: zone.id,
                        child: Text(
                          zone.name,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (value) => setState(() => _zoneId = value),
                validator: (value) =>
                    value == null ? 'Espace obligatoire pour un nœud' : null,
              ),
            if (!isGateway) const SizedBox(height: 12),
            TextFormField(
              controller: _ssid,
              decoration: const InputDecoration(labelText: 'Réseau Wi-Fi'),
              autocorrect: false,
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'SSID obligatoire'
                  : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _password,
              decoration: const InputDecoration(
                labelText: 'Mot de passe Wi-Fi',
                helperText: 'Transmis au nœud, jamais enregistré par l’app.',
              ),
              obscureText: true,
              enableSuggestions: false,
              autocorrect: false,
              validator: (value) => value == null || value.length < 8
                  ? '8 caractères minimum'
                  : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _gateway,
              decoration: const InputDecoration(
                labelText: 'Passerelle locale (optionnel)',
                hintText: 'http://192.168.1.10',
              ),
              keyboardType: TextInputType.url,
              autocorrect: false,
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(_error!, style: const TextStyle(color: Colors.red)),
              ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _busy ? null : _provision,
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.bluetooth_searching),
              label: const Text('Configurer par BLE'),
            ),
            const SizedBox(height: 12),
            const Text(
              'Le nœud doit exiger BLE Secure Connections et confirmer le '
              'jeton temporaire du QR. Aucun secret Wi-Fi n’est placé dans le QR.',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _discardDraft() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Abandonner cette association ?'),
        content: const Text(
          'Les paramètres non enregistrés seront supprimés.',
        ),
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
    _password.clear();
    await _draftSession.clear();
    if (mounted) Navigator.pop(context);
  }

  Future<void> _provision() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final gateway = _gateway.text.trim();
      final result = await _ble.provision(BleProvisioningRequest(
        identity: widget.identity,
        wifiSsid: _ssid.text,
        wifiPassword: _password.text,
        gatewayUrl: gateway.isEmpty ? null : gateway,
      ));
      final existing = await _data.getDeviceByUid(result.deviceId);
      final now = DateTime.now();
      final device = SensorDevice(
        id: existing?.id ?? result.deviceId,
        uid: result.deviceId,
        name: _name.text.trim(),
        zoneId: _zoneId,
        baseUrl: result.baseUrl ?? gateway,
        firmwareVersion: result.firmwareVersion ?? existing?.firmwareVersion,
        status: 'provisioned',
        deviceKind: widget.identity.entityType == QrEntityType.gateway
            ? 'gateway'
            : 'sensor',
        transport: widget.identity.transport ??
            (result.baseUrl == null ? 'ble' : 'http'),
        model: widget.identity.model,
        hardwareVersion: existing?.hardwareVersion,
        bleDeviceId: result.bleDeviceId,
        createdAt: existing?.createdAt ?? now,
        updatedAt: now,
      );
      await _data.upsertDevice(device);
      await _draftSession.clear();
      _password.clear();
      if (!mounted) return;
      await context.read<SensorProvider>().refreshDevices();
      if (!mounted) return;
      await Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => DeviceHealthScreen(initialDeviceId: device.id),
        ),
      );
    } on BleProvisioningException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (error, stackTrace) {
      FlutterError.reportError(FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'gardenjournal BLE',
        context: ErrorDescription('association sécurisée d’un appareil'),
      ));
      if (mounted) {
        setState(() => _error = 'Association impossible, réessayez.');
      }
    } finally {
      _password.clear();
      if (mounted) setState(() => _busy = false);
    }
  }
}
