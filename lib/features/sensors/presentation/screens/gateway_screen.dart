import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/services/form_draft_store.dart';
import '../../../../core/widgets/form_draft_banner.dart';
import '../../data/repositories/gateway_repository.dart';
import '../../data/repositories/lora_repository.dart';
import '../../data/repositories/sensor_data_repository.dart';
import '../../data/services/gateway_sync_service.dart';
import '../../data/services/gateway_transport.dart';
import '../../data/services/lora_gateway_ingest_service.dart';
import '../../domain/entities/gateway.dart';
import '../../domain/entities/sensor_device.dart';
import '../providers/sensor_provider.dart';

class GatewayScreen extends StatefulWidget {
  const GatewayScreen({super.key});

  @override
  State<GatewayScreen> createState() => _GatewayScreenState();
}

class _GatewayScreenState extends State<GatewayScreen> {
  final _repository = GatewayRepository();
  final _loraRepository = LoRaRepository();
  final _sensorRepository = SensorDataRepository();
  final _loraIngest = LoRaGatewayIngestService();
  late final GatewaySyncService _sync =
      GatewaySyncService(repository: _repository);
  final _http = TextEditingController();
  final _mqttHost = TextEditingController();
  final _mqttPort = TextEditingController(text: '8883');
  final _topicPrefix = TextEditingController(text: 'gardenjournal');
  final _username = TextEditingController();
  final _password = TextEditingController();
  SensorDevice? _gateway;
  GatewayConfig? _config;
  List<GatewayNodeLink> _links = const [];
  String _mode = 'hybrid';
  bool _tls = true;
  bool _loading = true;
  bool _busy = false;
  bool _mqttRunning = false;
  String? _message;
  FormDraftSession? _draftSession;
  bool _draftRestored = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loading) _load();
  }

  Future<void> _load() async {
    final devices = context.read<SensorProvider>().devices;
    final gateways =
        devices.where((item) => item.deviceKind == 'gateway').toList();
    final gateway = gateways.firstOrNull;
    final config = gateway == null
        ? null
        : await _repository.getConfigForDevice(gateway.id);
    final links = config == null
        ? const <GatewayNodeLink>[]
        : await _loraRepository.getLinks(config.id);
    if (!mounted) return;
    setState(() {
      _gateway = gateway;
      _config = config;
      _links = links;
      _mode = config?.transportMode ?? 'hybrid';
      _http.text = config?.httpBaseUrl ?? gateway?.baseUrl ?? '';
      _mqttHost.text = config?.mqttHost ?? gateway?.ipAddress ?? '';
      _mqttPort.text = '${config?.mqttPort ?? 8883}';
      _topicPrefix.text = config?.mqttTopicPrefix ?? 'gardenjournal';
      _username.text = config?.mqttUsername ?? '';
      _tls = config?.mqttUseTls ?? true;
      _loading = false;
    });
    _draftSession = FormDraftSession(
      key: 'gateway-${gateway?.id ?? 'new'}',
      snapshot: _draftSnapshot,
    );
    final draft = await _draftSession!.restore();
    if (!mounted) return;
    if (draft != null && draft['version'] == 1) {
      setState(() {
        _http.text = draft['http'] as String? ?? _http.text;
        _mqttHost.text = draft['mqttHost'] as String? ?? _mqttHost.text;
        _mqttPort.text = draft['mqttPort'] as String? ?? _mqttPort.text;
        _topicPrefix.text =
            draft['topicPrefix'] as String? ?? _topicPrefix.text;
        _username.text = draft['username'] as String? ?? _username.text;
        _mode = draft['mode'] as String? ?? _mode;
        _tls = draft['tls'] as bool? ?? _tls;
        _draftRestored = true;
      });
    }
    _draftSession!.start();
  }

  Map<String, dynamic> _draftSnapshot() => {
        'version': 1,
        'http': _http.text,
        'mqttHost': _mqttHost.text,
        'mqttPort': _mqttPort.text,
        'topicPrefix': _topicPrefix.text,
        'username': _username.text,
        'mode': _mode,
        'tls': _tls,
      };

  Future<GatewayConfig?> _save() async {
    final gateway = _gateway;
    if (gateway == null) return null;
    try {
      if (_mode != 'mqtt') validateGatewayHttpUrl(_http.text);
      if (_mode != 'http') {
        validateGatewayHost(_mqttHost.text);
        validateTopicPrefix(_topicPrefix.text);
      }
      final port = _mode == 'http' ? null : int.tryParse(_mqttPort.text.trim());
      if (_mode != 'http' && (port == null || port < 1 || port > 65535)) {
        throw const FormatException('Port MQTT invalide');
      }
      final now = DateTime.now();
      final config = GatewayConfig(
        id: _config?.id ?? const Uuid().v4(),
        deviceId: gateway.id,
        transportMode: _mode,
        httpBaseUrl: _mode == 'mqtt' ? null : _http.text.trim(),
        mqttHost: _mode == 'http' ? null : _mqttHost.text.trim(),
        mqttPort: port,
        mqttUseTls: _tls,
        mqttTopicPrefix: _topicPrefix.text.trim(),
        mqttUsername:
            _username.text.trim().isEmpty ? null : _username.text.trim(),
        lastHttpCursor: _config?.lastHttpCursor ?? 0,
        lastMqttAt: _config?.lastMqttAt,
        createdAt: _config?.createdAt ?? now,
        updatedAt: now,
      );
      await _repository.saveConfig(config);
      _config = config;
      await _draftSession?.checkpoint();
      return config;
    } catch (error) {
      if (mounted) setState(() => _message = 'Configuration refusée : $error');
      return null;
    }
  }

  Future<void> _syncHttp() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    final config = await _save();
    try {
      if (config == null || _gateway == null) return;
      final result = await _sync.synchronizeHttp(
        config,
        gatewayUid: _gateway!.uid,
        handler: (envelope) async {
          await _loraIngest.handleEnvelope(config, envelope);
        },
      );
      final refreshed = await _repository.getConfigForDevice(_gateway!.id);
      if (mounted) {
        setState(() {
          _config = refreshed;
          _message = '${result.accepted} accepté(s), '
              '${result.duplicates} doublon(s), ${result.rejected} rejeté(s)';
        });
      }
    } catch (error) {
      if (mounted) setState(() => _message = 'HTTP gateway en échec : $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggleMqtt() async {
    if (_mqttRunning) {
      await _sync.close();
      if (mounted) setState(() => _mqttRunning = false);
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    final config = await _save();
    try {
      if (config == null || _gateway == null) return;
      await _sync.startMqtt(
        config,
        gatewayUid: _gateway!.uid,
        password: _password.text.isEmpty ? null : _password.text,
        handler: (envelope) async {
          await _loraIngest.handleEnvelope(config, envelope);
        },
      );
      if (mounted) {
        setState(() {
          _mqttRunning = true;
          _message = 'MQTT connecté; écoute QoS 1 active';
        });
      }
    } catch (error) {
      if (mounted) setState(() => _message = 'MQTT en échec : $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _linkNode() async {
    final config = await _save();
    if (config == null) return;
    final linkedIds = _links.map((item) => item.nodeDeviceId).toSet();
    final devices = context
        .read<SensorProvider>()
        .devices
        .where((item) =>
            item.deviceKind != 'gateway' && !linkedIds.contains(item.id))
        .toList();
    final selected = await showDialog<SensorDevice>(
      context: context,
      builder: (_) => SimpleDialog(
        title: const Text('Associer un nœud LoRa'),
        children: devices.isEmpty
            ? const [
                Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('Aucun nœud disponible. Scanne d’abord son QR.'),
                )
              ]
            : devices
                .map((device) => SimpleDialogOption(
                      onPressed: () => Navigator.pop(context, device),
                      child: ListTile(
                        leading: const Icon(Icons.sensors),
                        title: Text(device.name),
                        subtitle: Text(device.uid),
                      ),
                    ))
                .toList(),
      ),
    );
    if (selected == null) return;
    try {
      await _loraRepository.linkNode(
        gatewayId: config.id,
        nodeDeviceId: selected.id,
        loraAddress: selected.uid,
      );
      await _sensorRepository.upsertDevice(
        selected.copyWith(transport: 'lora', updatedAt: DateTime.now()),
      );
      await context.read<SensorProvider>().refreshDevices();
      final links = await _loraRepository.getLinks(config.id);
      if (mounted) setState(() => _links = links);
    } catch (error) {
      if (mounted)
        setState(() => _message = 'Association LoRa refusée : $error');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Passerelle HTTP / MQTT'),
          actions: [
            IconButton(
              tooltip: 'Abandonner le brouillon',
              onPressed: _draftSession == null ? null : _discardDraft,
              icon: const Icon(Icons.delete_outline),
            ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _gateway == null
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'Aucune passerelle enregistrée. Scanne un QR de type '
                        'gateway et termine son provisioning BLE.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      FormDraftBanner(
                        restored: _draftRestored,
                        containsSensitiveField: true,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _gateway!.name,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 12),
                      SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(value: 'http', label: Text('HTTP')),
                          ButtonSegment(value: 'mqtt', label: Text('MQTT')),
                          ButtonSegment(
                              value: 'hybrid', label: Text('Hybride')),
                        ],
                        selected: {_mode},
                        onSelectionChanged: (values) =>
                            setState(() => _mode = values.first),
                      ),
                      if (_mode != 'mqtt') ...[
                        TextField(
                          controller: _http,
                          decoration: const InputDecoration(
                            labelText: 'URL HTTP locale',
                            hintText: 'http://192.168.1.20',
                          ),
                        ),
                        FilledButton.icon(
                          onPressed: _busy ? null : _syncHttp,
                          icon: const Icon(Icons.sync),
                          label: const Text('Reprendre l’historique HTTP'),
                        ),
                      ],
                      if (_mode != 'http') ...[
                        TextField(
                          controller: _mqttHost,
                          decoration: const InputDecoration(
                              labelText: 'Hôte MQTT local'),
                        ),
                        TextField(
                          controller: _mqttPort,
                          keyboardType: TextInputType.number,
                          decoration:
                              const InputDecoration(labelText: 'Port MQTT'),
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          value: _tls,
                          onChanged: (value) => setState(() => _tls = value),
                          title: const Text('TLS'),
                          subtitle: const Text(
                              'Recommandé; certificat système vérifié'),
                        ),
                        TextField(
                          controller: _topicPrefix,
                          decoration: const InputDecoration(
                              labelText: 'Préfixe de topic'),
                        ),
                        TextField(
                          controller: _username,
                          decoration: const InputDecoration(
                              labelText: 'Utilisateur (optionnel)'),
                        ),
                        TextField(
                          controller: _password,
                          obscureText: true,
                          decoration: const InputDecoration(
                            labelText: 'Mot de passe (mémoire uniquement)',
                          ),
                        ),
                        FilledButton.icon(
                          onPressed: _busy ? null : _toggleMqtt,
                          icon: Icon(
                              _mqttRunning ? Icons.stop : Icons.play_arrow),
                          label: Text(
                              _mqttRunning ? 'Arrêter MQTT' : 'Démarrer MQTT'),
                        ),
                      ],
                      if (!_tls && _mode != 'http')
                        const Card(
                          color: Color(0xFFFFF3E0),
                          child: Padding(
                            padding: EdgeInsets.all(12),
                            child: Text(
                                'MQTT sans TLS est réservé au réseau local de test.'),
                          ),
                        ),
                      if (_message != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(_message!),
                        ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Nœuds LoRa autorisés',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                          TextButton.icon(
                            onPressed: _busy ? null : _linkNode,
                            icon: const Icon(Icons.add_link),
                            label: const Text('Associer'),
                          ),
                        ],
                      ),
                      if (_links.isEmpty)
                        const ListTile(
                          title: Text('Aucun nœud LoRa autorisé'),
                          subtitle: Text(
                              'Les trames inconnues seront mises en quarantaine.'),
                        )
                      else
                        ..._links.map((link) {
                          final device = context
                              .read<SensorProvider>()
                              .devices
                              .where((item) => item.id == link.nodeDeviceId)
                              .firstOrNull;
                          return ListTile(
                            leading: const Icon(Icons.cell_tower),
                            title: Text(device?.name ?? link.loraAddress),
                            subtitle: Text(
                              '${link.loraAddress} · compteur ${link.lastFrameCounter}',
                            ),
                          );
                        }),
                      const Padding(
                        padding: EdgeInsets.only(top: 12),
                        child: Text(
                          'Le secret MQTT n’est jamais sauvegardé. HTTP sert à '
                          'rattraper les messages; MQTT fournit le direct.',
                          style: TextStyle(color: Colors.black54, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
      );

  Future<void> _discardDraft() async {
    final session = _draftSession;
    if (session == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Abandonner les modifications ?'),
        content: const Text(
          'Les paramètres de connexion non enregistrés seront supprimés.',
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
    await session.clear();
    if (mounted) Navigator.pop(context);
  }

  @override
  void dispose() {
    unawaited(_sync.close());
    _draftSession?.dispose();
    _http.dispose();
    _mqttHost.dispose();
    _mqttPort.dispose();
    _topicPrefix.dispose();
    _username.dispose();
    _password.dispose();
    super.dispose();
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
