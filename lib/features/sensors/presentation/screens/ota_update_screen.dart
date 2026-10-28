import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/repositories/ota_repository.dart';
import '../../data/services/ota_update_service.dart';
import '../../domain/entities/ota_update.dart';
import '../../domain/entities/sensor_device.dart';

class OtaUpdateScreen extends StatefulWidget {
  final SensorDevice device;

  const OtaUpdateScreen({super.key, required this.device});

  @override
  State<OtaUpdateScreen> createState() => _OtaUpdateScreenState();
}

class _OtaUpdateScreenState extends State<OtaUpdateScreen> {
  final _repository = OtaRepository();
  late final OtaUpdateService _service =
      OtaUpdateService(repository: _repository);
  final _manifestUrl = TextEditingController();
  OtaDeviceState? _state;
  List<OtaUpdateRecord> _updates = const [];
  bool _loading = true;
  bool _busy = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final state = await _repository.getDeviceState(widget.device.id);
    final updates = await _repository.getUpdates(widget.device.id);
    if (!mounted) return;
    setState(() {
      _state = state;
      _updates = updates;
      _loading = false;
    });
  }

  Future<void> _syncState() async {
    await _run(() async {
      _state = await _service.synchronizeDeviceState(widget.device);
      _message = 'État OTA vérifié auprès du nœud';
    });
  }

  Future<void> _verify() async {
    final uri = Uri.tryParse(_manifestUrl.text.trim());
    if (uri == null) {
      setState(() => _message = 'URL de manifest invalide');
      return;
    }
    await _run(() async {
      final update = await _service.verifyAndRecord(widget.device, uri);
      _updates = [update, ..._updates];
      _message = 'Signature et firmware vérifiés; aucune installation lancée';
    });
  }

  Future<void> _install(OtaUpdateRecord update) async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Confirmer la mise à jour OTA'),
            content: Text(
              'Installer ${update.version} (build ${update.buildNumber}) sur '
              '${widget.device.name} ? Le nœud doit vérifier à nouveau la '
              'signature et disposer d’un rollback opérationnel.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Annuler'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Demander l’installation'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;
    await _run(() async {
      await _service.requestInstall(
        widget.device,
        update,
        confirmed: true,
      );
      _message = 'Demande acquittée; installation exécutée par le nœud';
    });
  }

  Future<void> _refresh(OtaUpdateRecord update) async {
    await _run(() async {
      final refreshed = await _service.refreshStatus(widget.device, update);
      _message = 'Statut : ${refreshed.status}';
    });
  }

  Future<void> _run(Future<void> Function() operation) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await operation();
      await _load();
    } catch (error) {
      if (mounted) setState(() => _message = 'OTA refusée : $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text('OTA signée · ${widget.device.name}')),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (OtaRepository.buildKeyId.isEmpty)
                    const Card(
                      color: Color(0xFFFFEBEE),
                      child: Padding(
                        padding: EdgeInsets.all(12),
                        child: Text(
                          'Aucune clé publique OTA n’est intégrée à ce build. '
                          'La vérification est donc volontairement bloquée.',
                        ),
                      ),
                    ),
                  _stateCard(),
                  FilledButton.icon(
                    onPressed: _busy ? null : _syncState,
                    icon: const Icon(Icons.sync_lock),
                    label: const Text('Lire les capacités OTA du nœud'),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _manifestUrl,
                    keyboardType: TextInputType.url,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      labelText: 'Manifest signé HTTPS',
                      hintText: 'https://firmware.example/manifest.json',
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: _busy || OtaRepository.buildKeyId.isEmpty
                        ? null
                        : _verify,
                    icon: const Icon(Icons.verified_user_outlined),
                    label: const Text('Vérifier sans installer'),
                  ),
                  if (_message != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(_message!),
                    ),
                  const Divider(height: 32),
                  const Text(
                    'Historique OTA',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  if (_updates.isEmpty)
                    const ListTile(title: Text('Aucune mise à jour vérifiée'))
                  else
                    ..._updates.map(_updateTile),
                ],
              ),
      );

  Widget _stateCard() => Card(
        child: ListTile(
          leading: const Icon(Icons.memory),
          title: Text(
            _state == null
                ? 'État du firmware inconnu'
                : '${_state!.currentVersion ?? 'version inconnue'} · build ${_state!.currentBuild}',
          ),
          subtitle: Text(
            _state == null
                ? 'Lecture du nœud obligatoire avant toute vérification.'
                : 'Build maximal accepté ${_state!.highestAcceptedBuild} · '
                    'rollback ${_state!.rollbackSupported ? 'oui' : 'non'}',
          ),
        ),
      );

  Widget _updateTile(OtaUpdateRecord update) => Card(
        child: ListTile(
          leading: Icon(
            update.status == 'succeeded'
                ? Icons.check_circle
                : update.status == 'failed'
                    ? Icons.error
                    : Icons.system_update,
          ),
          title: Text('${update.version} · build ${update.buildNumber}'),
          subtitle: Text(
            '${update.status} · clé ${update.keyId}\n'
            '${DateFormat('dd/MM/yyyy HH:mm').format(update.createdAt)}',
          ),
          isThreeLine: true,
          trailing: update.status == 'verified' ||
                  (update.status == 'failed' && update.requestedAt == null)
              ? IconButton(
                  tooltip: 'Installer',
                  onPressed: _busy ? null : () => _install(update),
                  icon: const Icon(Icons.install_mobile),
                )
              : update.status == 'requested' ||
                      update.status == 'downloading' ||
                      update.status == 'installing'
                  ? IconButton(
                      tooltip: 'Actualiser le statut',
                      onPressed: _busy ? null : () => _refresh(update),
                      icon: const Icon(Icons.refresh),
                    )
                  : null,
        ),
      );

  @override
  void dispose() {
    _service.close();
    _manifestUrl.dispose();
    super.dispose();
  }
}
