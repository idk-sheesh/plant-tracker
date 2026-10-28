import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../../core/services/form_draft_store.dart';
import '../../../../core/widgets/form_draft_banner.dart';
import '../../data/services/cloud_credential_store.dart';
import '../../domain/entities/cloud_telemetry.dart';
import '../providers/cloud_provider.dart';
import '../providers/sensor_provider.dart';
import 'cloud_safety_screen.dart';

class CloudScreen extends StatefulWidget {
  final CloudCredentialStore? credentialStore;

  const CloudScreen({super.key, this.credentialStore});

  @override
  State<CloudScreen> createState() => _CloudScreenState();
}

class _CloudScreenState extends State<CloudScreen> {
  final _baseUrlController = TextEditingController();
  final _tokenController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _selectedLocalByCloudId = <String, String>{};
  late final FormDraftSession _draftSession;
  bool _draftRestored = false;
  bool _rememberCredentials = false;

  CloudCredentialStore get _credentialStore =>
      widget.credentialStore ?? SecureCloudCredentialStore();

  @override
  void initState() {
    super.initState();
    _draftSession = FormDraftSession(
      key: 'cloud-connection',
      snapshot: _draftSnapshot,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_restoreDraft());
      unawaited(_restoreSavedCredentials());
    });
  }

  @override
  void dispose() {
    _draftSession.dispose();
    _baseUrlController.dispose();
    _tokenController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Map<String, dynamic> _draftSnapshot() => {
        'version': 1,
        'baseUrl': _baseUrlController.text,
        'username': _usernameController.text,
      };

  Future<void> _restoreDraft() async {
    final draft = await _draftSession.restore();
    if (!mounted) return;
    if (draft != null && draft['version'] == 1) {
      setState(() {
        if (!_rememberCredentials) {
          _baseUrlController.text = draft['baseUrl'] as String? ?? '';
          _usernameController.text = draft['username'] as String? ?? '';
        }
        _draftRestored = true;
      });
    }
    _draftSession.start();
  }

  Future<void> _restoreSavedCredentials() async {
    try {
      final credentials = await _credentialStore.read();
      if (!mounted || credentials == null) return;
      setState(() {
        _baseUrlController.text = credentials.baseUrl;
        _usernameController.text = credentials.username;
        _passwordController.text = credentials.password;
        _rememberCredentials = true;
      });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Identifiants mémorisés illisibles.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Synchronisation'),
        actions: [
          IconButton(
            tooltip: 'Abandonner le brouillon de connexion',
            icon: const Icon(Icons.delete_outline),
            onPressed: _discardDraft,
          ),
          IconButton(
            tooltip: 'Sécurité des données',
            icon: const Icon(Icons.shield_outlined),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const CloudSafetyScreen()),
            ),
          ),
        ],
      ),
      body: Consumer<CloudProvider>(
        builder: (context, cloud, _) => RefreshIndicator(
          onRefresh:
              cloud.isConfigured ? () => _syncMyData(cloud) : () async {},
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: [
              if (!cloud.isConfigured) ...[
                _introCard(),
                const SizedBox(height: 12),
                _connectionCard(cloud),
              ] else ...[
                _sessionCard(cloud),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Mes données dans le hub',
                            style: TextStyle(
                                fontSize: 18, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 8),
                        const Text(
                            'Synchronisation automatique après connexion, au retour dans l’application et chaque minute tant qu’elle est ouverte. '
                            'Envoie une copie des plantes, actions, groupes et espaces. '
                            'Récupère aussi les nouvelles mesures des appareils associés. '
                            'Le téléphone garde les originaux. Les photos et secrets ne sont pas envoyés.'),
                        const SizedBox(height: 12),
                        SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: cloud.isBusy
                                  ? null
                                  : () => _syncMyData(cloud),
                              icon: cloud.isBusy
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2))
                                  : const Icon(Icons.sync),
                              label: const Text('Synchroniser mes données'),
                            )),
                        if (cloud.lastBusinessPublication != null)
                          Text('Dernière publication depuis cette session : '
                              '${DateFormat('dd/MM/yyyy HH:mm').format(cloud.lastBusinessPublication!.toLocal())}'),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _deviceSettings(cloud),
              ],
              if (cloud.error != null) ...[
                const SizedBox(height: 12),
                _messageCard(
                  icon: Icons.error_outline,
                  color: const Color(0xFFC62828),
                  text: cloud.error!,
                ),
              ],
              if (cloud.message != null) ...[
                const SizedBox(height: 12),
                _messageCard(
                  icon: Icons.check_circle_outline,
                  color: const Color(0xFF2E7D32),
                  text: cloud.message!,
                ),
              ],
              const SizedBox(height: 24),
              _safetyShortcut(context),
              const SizedBox(height: 72),
            ],
          ),
        ),
      ),
    );
  }

  Widget _introCard() => Card(
        color: const Color(0xFFE8F5E9),
        child: const Padding(
          padding: EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.cloud_done_outlined, color: Color(0xFF2E7D32)),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Le cloud complète le stockage local',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 10),
              Text(
                'Les plantes, actions, photos et mesures déjà dans le téléphone '
                'ne sont jamais supprimées par une synchronisation cloud.',
              ),
            ],
          ),
        ),
      );

  Widget _connectionCard(CloudProvider cloud) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Connexion à l’API',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              const Text(
                'La connexion lance automatiquement la synchronisation du journal et des mesures associées. '
                'Cette session reste en mémoire. Le token n’est pas écrit dans '
                'la base GardenJournal ni dans les sauvegardes.',
              ),
              const SizedBox(height: 16),
              FormDraftBanner(
                restored: _draftRestored,
                containsSensitiveField: true,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _baseUrlController,
                keyboardType: TextInputType.url,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'URL API HTTPS',
                  hintText: 'https://api.example.invalid',
                  prefixIcon: Icon(Icons.link),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              const Text('Mon compte',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              TextField(
                controller: _usernameController,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'Nom d’utilisateur',
                  prefixIcon: Icon(Icons.person_outline),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _passwordController,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                decoration: const InputDecoration(
                  labelText: 'Mot de passe',
                  prefixIcon: Icon(Icons.lock_outline),
                  border: OutlineInputBorder(),
                ),
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('Mémoriser ce compte'),
                subtitle: const Text(
                  'URL, nom et mot de passe dans le coffre sécurisé du téléphone, '
                  'hors des sauvegardes GardenJournal.',
                ),
                value: _rememberCredentials,
                onChanged: (value) async {
                  setState(() => _rememberCredentials = value);
                  if (!value) await _forgetSavedCredentials();
                },
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: cloud.isBusy ? null : () => _login(cloud),
                      icon: const Icon(Icons.login),
                      label: const Text('Se connecter'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: cloud.isBusy ? null : () => _register(cloud),
                      child: const Text('Créer un compte'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: const Text('Connexion avec un token'),
                children: [
                  TextField(
                    controller: _tokenController,
                    obscureText: true,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: const InputDecoration(
                      labelText: 'Token de session utilisateur',
                      prefixIcon: Icon(Icons.key_outlined),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: cloud.isBusy ? null : () => _connect(cloud),
                      icon: const Icon(Icons.login),
                      label: const Text('Se connecter avec le token'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );

  Widget _sessionCard(CloudProvider cloud) => Card(
        child: ListTile(
          leading: const CircleAvatar(
            backgroundColor: Color(0xFFE8F5E9),
            child: Icon(Icons.cloud_done, color: Color(0xFF2E7D32)),
          ),
          title: const Text('Session cloud active'),
          subtitle: Text(cloud.account?.username ?? cloud.baseUrl),
          trailing: PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'refresh') cloud.refreshCloudDevices();
              if (value == 'disconnect') unawaited(cloud.disconnect());
              if (value == 'forget') _forgetSavedCredentials();
              if (value == 'provision') _provision(cloud);
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'refresh', child: Text('Actualiser')),
              PopupMenuItem(
                value: 'provision',
                child: Text('Provisionner un ESP32'),
              ),
              PopupMenuItem(value: 'disconnect', child: Text('Déconnecter')),
              PopupMenuItem(
                value: 'forget',
                child: Text('Oublier les identifiants'),
              ),
            ],
          ),
        ),
      );

  Widget _emptyCloudDevices() => const Card(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Column(
            children: [
              Icon(Icons.sensors_off_outlined, size: 42),
              SizedBox(height: 8),
              Text('Aucun appareil cloud associé à ce compte.'),
            ],
          ),
        ),
      );

  Widget _deviceSettings(CloudProvider cloud) => Card(
        child: ExpansionTile(
          leading: const Icon(Icons.sensors_outlined),
          title: const Text('Appareils et mesures'),
          subtitle: Text(cloud.cloudDevices.isEmpty
              ? 'Aucun appareil distant'
              : '${cloud.cloudDevices.length} appareil(s) · associations et historique'),
          childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
          children: [
            if (cloud.cloudDevices.isEmpty)
              _emptyCloudDevices()
            else
              ...cloud.cloudDevices.map(
                (device) => _CloudDeviceCard(
                  key: ValueKey(device.id),
                  cloudDevice: device,
                  selectedLocalId: _selectedLocalByCloudId[device.id],
                  onLocalChanged: (value) => setState(() {
                    _selectedLocalByCloudId[device.id] = value;
                  }),
                  onLink: (localId) => _link(cloud, device, localId),
                  onSync: (localId) => _sync(cloud, device, localId),
                  onBackfill: (localId) => _backfill(cloud, device, localId),
                ),
              ),
          ],
        ),
      );

  Widget _messageCard({
    required IconData icon,
    required Color color,
    required String text,
  }) =>
      Card(
        child: ListTile(
          leading: Icon(icon, color: color),
          title: Text(text),
        ),
      );

  Widget _safetyShortcut(BuildContext context) => OutlinedButton.icon(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const CloudSafetyScreen()),
        ),
        icon: const Icon(Icons.shield_outlined),
        label: const Text('Voir le protocole avant mise à jour / reflash'),
      );

  Future<void> _discardDraft() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Abandonner la connexion ?'),
        content: const Text(
          'L’URL et le nom d’utilisateur non enregistrés seront supprimés.',
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
    _passwordController.clear();
    _tokenController.clear();
    await _draftSession.clear();
    if (mounted) Navigator.pop(context);
  }

  Future<void> _login(CloudProvider cloud) async {
    FocusManager.instance.primaryFocus?.unfocus();
    final baseUrl = _baseUrlController.text;
    final username = _usernameController.text;
    final password = _passwordController.text;
    try {
      final connected = await cloud.login(
        baseUrl: baseUrl,
        username: username,
        password: password,
      );
      if (!connected) return;
      if (mounted) await context.read<SensorProvider>().refreshFromLocalCache();
      try {
        if (_rememberCredentials) {
          await _credentialStore.write(CloudCredentials(
            baseUrl: baseUrl,
            username: username,
            password: password,
          ));
        } else {
          await _credentialStore.delete();
        }
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Connexion réussie, mémorisation impossible.'),
            ),
          );
        }
      }
      await _draftSession.checkpoint();
    } finally {
      if (mounted) _passwordController.clear();
    }
  }

  Future<void> _forgetSavedCredentials() async {
    try {
      await _credentialStore.delete();
      if (mounted) setState(() => _rememberCredentials = false);
    } catch (_) {
      if (mounted) {
        setState(() => _rememberCredentials = true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Effacement des identifiants impossible.')),
        );
      }
    }
  }

  Future<void> _register(CloudProvider cloud) async {
    FocusManager.instance.primaryFocus?.unfocus();
    final password = _passwordController.text;
    final registered = await cloud.registerAccount(
      baseUrl: _baseUrlController.text,
      username: _usernameController.text,
      password: password,
    );
    _passwordController.clear();
    if (registered && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Compte créé. Connecte-toi maintenant.')),
      );
    }
  }

  Future<void> _provision(CloudProvider cloud) async {
    final nameController = TextEditingController(text: 'ESP32 GardenJournal');
    final firmwareController = TextEditingController();
    try {
      final values = await showDialog<Map<String, String>>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Provisionner un ESP32'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'Nom'),
              ),
              TextField(
                controller: firmwareController,
                decoration: const InputDecoration(
                  labelText: 'Version firmware (facultatif)',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, {
                'name': nameController.text,
                'firmware': firmwareController.text,
              }),
              child: const Text('Créer'),
            ),
          ],
        ),
      );
      if (values == null || !mounted) return;
      final provisioned = await cloud.provisionDevice(
        name: values['name'],
        firmwareVersion: values['firmware'],
      );
      if (provisioned == null || !mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Token ESP32 — à conserver maintenant'),
          content: SelectableText(
            '${provisioned.device.name ?? provisioned.device.id}\n\n'
            '${provisioned.deviceToken}\n\n'
            'Ce token ne sera plus réaffiché. Copie-le dans la configuration '
            'sécurisée du firmware, jamais dans Git ou les logs.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('J’ai copié le token'),
            ),
          ],
        ),
      );
    } finally {
      nameController.dispose();
      firmwareController.dispose();
    }
  }

  Future<void> _connect(CloudProvider cloud) async {
    FocusManager.instance.primaryFocus?.unfocus();
    final connected = await cloud.connect(
      baseUrl: _baseUrlController.text,
      accessToken: _tokenController.text,
    );
    if (connected) {
      if (!mounted) return;
      _tokenController.clear();
      await context.read<SensorProvider>().refreshFromLocalCache();
      await _draftSession.checkpoint();
    }
  }

  Future<void> _syncMyData(CloudProvider cloud) async {
    await cloud.synchronizeMyData();
    if (mounted) await context.read<SensorProvider>().refreshFromLocalCache();
  }

  Future<void> _link(
    CloudProvider cloud,
    CloudDeviceSummary device,
    String localId,
  ) async {
    await cloud.linkCloudDevice(device, localId.isEmpty ? null : localId);
    if (localId.isNotEmpty && cloud.error == null && mounted) {
      await _syncMyData(cloud);
    }
  }

  Future<void> _sync(
    CloudProvider cloud,
    CloudDeviceSummary device,
    String localId,
  ) async {
    final result = await cloud.synchronize(device, localId);
    if (result != null && mounted) {
      await context.read<SensorProvider>().refreshFromLocalCache();
    }
  }

  Future<void> _backfill(
    CloudProvider cloud,
    CloudDeviceSummary device,
    String localId,
  ) async {
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Rattraper 5 jours ?'),
        content: const Text(
          'Les mesures locales des 5 derniers jours seront envoyées au cloud. '
          'Les données locales resteront intactes. Cette opération est limitée '
          'à l’appareil et au compte actuellement connectés.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Envoyer'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final result = await cloud.backfillHistorical(device, localId);
    if (result != null && mounted) {
      await context.read<SensorProvider>().refreshFromLocalCache();
    }
  }
}

class _CloudDeviceCard extends StatelessWidget {
  final CloudDeviceSummary cloudDevice;
  final String? selectedLocalId;
  final ValueChanged<String> onLocalChanged;
  final ValueChanged<String> onLink;
  final ValueChanged<String> onSync;
  final ValueChanged<String> onBackfill;

  const _CloudDeviceCard({
    super.key,
    required this.cloudDevice,
    required this.selectedLocalId,
    required this.onLocalChanged,
    required this.onLink,
    required this.onSync,
    required this.onBackfill,
  });

  @override
  Widget build(BuildContext context) {
    final cloud = context.watch<CloudProvider>();
    final linked = cloud.linkedLocalDevice(cloudDevice);
    final selected = selectedLocalId ?? linked?.id ?? '';
    final lastContact = cloudDevice.lastContactAt;
    final result = cloud.lastResultFor(cloudDevice.id);
    final options = <DropdownMenuItem<String>>[
      const DropdownMenuItem(value: '', child: Text('Non associé')),
      ...cloud.localDevices.map(
        (device) => DropdownMenuItem(
          value: device.id,
          child: Text(device.name, overflow: TextOverflow.ellipsis),
        ),
      ),
    ];
    final validSelected =
        options.any((item) => item.value == selected) ? selected : '';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.sensors_outlined, color: Color(0xFF2E7D32)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    cloudDevice.name ?? cloudDevice.id,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text('ID distant : ${cloudDevice.id}'),
            if (cloudDevice.firmwareVersion != null)
              Text('Firmware : ${cloudDevice.firmwareVersion}'),
            Text(
              lastContact == null
                  ? 'Dernier contact : inconnu'
                  : 'Dernier contact : ${DateFormat('dd/MM/yyyy HH:mm').format(lastContact.toLocal())}',
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              key: ValueKey('${cloudDevice.id}-$validSelected'),
              initialValue: validSelected,
              decoration: const InputDecoration(
                labelText: 'Nœud local correspondant',
                border: OutlineInputBorder(),
              ),
              items: options,
              onChanged:
                  cloud.isBusy ? null : (value) => onLocalChanged(value ?? ''),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: cloud.isBusy ? null : () => onLink(validSelected),
                  icon: const Icon(Icons.link),
                  label: const Text('Enregistrer le lien'),
                ),
                if (validSelected.isNotEmpty)
                  FilledButton.tonalIcon(
                    onPressed:
                        cloud.isBusy ? null : () => onSync(validSelected),
                    icon: const Icon(Icons.sync),
                    label: const Text('Synchroniser'),
                  ),
                if (validSelected.isNotEmpty)
                  OutlinedButton.icon(
                    onPressed:
                        cloud.isBusy ? null : () => onBackfill(validSelected),
                    icon: const Icon(Icons.history),
                    label: const Text('Rattraper 5 jours'),
                  ),
              ],
            ),
            if (result != null) ...[
              const SizedBox(height: 10),
              Text(
                'Dernière reprise : ${result.inserted} nouvelle(s) mesure(s), '
                '${result.received} reçue(s)',
                style: const TextStyle(color: Color(0xFF2E7D32)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
