import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:sqflite/sqflite.dart';

import '../../data/repositories/cloud_auth_repository.dart';
import '../../data/repositories/cloud_sensor_repository.dart';
import '../../data/repositories/sensor_data_repository.dart';
import '../../data/services/cloud_sensor_sync_service.dart';
import '../../data/services/cloud_business_snapshot_service.dart';
import '../../domain/entities/cloud_telemetry.dart';
import '../../domain/entities/sensor_device.dart';

class CloudProvider extends ChangeNotifier {
  final SensorDataRepository _dataRepository;
  final CloudSensorRepository Function(Uri, String) _remoteFactory;
  final Future<Map<String, dynamic>> Function() _buildSnapshot;

  CloudSensorRepository? _remoteRepository;
  CloudSensorSyncService? _syncService;
  String _baseUrl = '';
  CloudAccount? _account;
  DateTime? _lastBusinessPublication;
  List<CloudDeviceSummary> _cloudDevices = [];
  List<SensorDevice> _localDevices = [];
  final Map<String, CloudSyncResult> _lastResults = {};
  bool _isBusy = false;
  String? _error;
  String? _message;

  CloudProvider({
    SensorDataRepository? dataRepository,
    CloudSensorRepository Function(Uri, String)? remoteFactory,
    Future<Map<String, dynamic>> Function()? buildSnapshot,
  })  : _dataRepository = dataRepository ?? SensorDataRepository(),
        _remoteFactory = remoteFactory ??
            ((uri, token) =>
                CloudSensorRepository(baseUri: uri, accessToken: token)),
        _buildSnapshot =
            buildSnapshot ?? const CloudBusinessSnapshotService().build;

  bool get isConfigured => _remoteRepository != null;
  String get baseUrl => _baseUrl;
  CloudAccount? get account => _account;
  DateTime? get lastBusinessPublication => _lastBusinessPublication;
  List<CloudDeviceSummary> get cloudDevices => List.unmodifiable(_cloudDevices);
  List<SensorDevice> get localDevices => List.unmodifiable(_localDevices);
  bool get isBusy => _isBusy;
  String? get error => _error;
  String? get message => _message;

  SensorDevice? linkedLocalDevice(CloudDeviceSummary cloudDevice) {
    final linked = _localDevices.where(
      (device) => device.cloudDeviceId == cloudDevice.id,
    );
    return linked.isEmpty ? null : linked.first;
  }

  CloudSyncResult? lastResultFor(String cloudDeviceId) =>
      _lastResults[cloudDeviceId];

  Future<bool> connect({
    required String baseUrl,
    required String accessToken,
  }) async {
    if (_isBusy) return false;
    final normalizedUrl = baseUrl.trim();
    final normalizedToken = accessToken.trim();
    _setBusy(true);
    _error = null;
    _message = null;
    CloudSensorRepository? candidate;
    try {
      final uri = Uri.tryParse(normalizedUrl);
      if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
        throw const FormatException('L’API cloud doit utiliser HTTPS');
      }
      candidate = _remoteFactory(uri, normalizedToken);
      final account = await candidate.fetchAccount();
      final devices = await candidate.fetchDevices();
      _remoteRepository?.close();
      _remoteRepository = candidate;
      candidate = null;
      _syncService = CloudSensorSyncService(
        remote: _remoteRepository!,
        data: _dataRepository,
      );
      _baseUrl = normalizedUrl;
      _account = account;
      _cloudDevices = devices;
      await _reloadLocalDevices();
      _message = '${devices.length} appareil(s) cloud chargé(s)';
    } catch (error) {
      _error = _safeError(error);
      return false;
    } finally {
      candidate?.close();
      _setBusy(false);
    }
    await synchronizeMyData();
    return true;
  }

  Future<bool> login({
    required String baseUrl,
    required String username,
    required String password,
  }) async {
    if (_isBusy) return false;
    CloudAuthRepository? auth;
    _setBusy(true);
    _error = null;
    _message = null;
    try {
      final uri = Uri.tryParse(baseUrl.trim());
      if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
        throw const FormatException('L’API cloud doit utiliser HTTPS');
      }
      auth = CloudAuthRepository(baseUri: uri);
      final session = await auth.login(
        username: username,
        password: password,
      );
      _setBusy(false);
      return await connect(
        baseUrl: baseUrl,
        accessToken: session.sessionToken,
      );
    } catch (error) {
      _error = _safeError(error);
      notifyListeners();
      return false;
    } finally {
      auth?.close();
      _setBusy(false);
    }
  }

  Future<bool> registerAccount({
    required String baseUrl,
    required String username,
    required String password,
  }) async {
    CloudAuthRepository? auth;
    _setBusy(true);
    _error = null;
    _message = null;
    try {
      final uri = Uri.tryParse(baseUrl.trim());
      if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
        throw const FormatException('L’API cloud doit utiliser HTTPS');
      }
      auth = CloudAuthRepository(baseUri: uri);
      await auth.register(username: username, password: password);
      _message = 'Compte cloud créé. Tu peux maintenant te connecter.';
      return true;
    } catch (error) {
      _error = _safeError(error);
      return false;
    } finally {
      auth?.close();
      _setBusy(false);
    }
  }

  Future<CloudProvisionedDevice?> provisionDevice({
    String? name,
    String? firmwareVersion,
  }) async {
    final remote = _remoteRepository;
    if (remote == null || _isBusy) return null;
    _setBusy(true);
    _error = null;
    _message = null;
    try {
      final result = await remote.createDevice(
        name: name,
        firmwareVersion: firmwareVersion,
      );
      _cloudDevices = await remote.fetchDevices();
      _message =
          'Appareil créé. Le token ne sera plus affiché après cet écran.';
      return result;
    } catch (error) {
      _error = _safeError(error);
      return null;
    } finally {
      _setBusy(false);
    }
  }

  Future<void> refreshCloudDevices() async {
    final remote = _remoteRepository;
    if (remote == null || _isBusy) return;
    _setBusy(true);
    _error = null;
    _message = null;
    try {
      _cloudDevices = await remote.fetchDevices();
      await _reloadLocalDevices();
      _message = '${_cloudDevices.length} appareil(s) cloud chargé(s)';
    } catch (error) {
      _error = _safeError(error);
    } finally {
      _setBusy(false);
    }
  }

  Future<void> linkCloudDevice(
    CloudDeviceSummary cloudDevice,
    String? localDeviceId,
  ) async {
    _setBusy(true);
    _error = null;
    _message = null;
    try {
      final previous = _localDevices.where(
        (device) => device.cloudDeviceId == cloudDevice.id,
      );
      for (final device in previous) {
        await _dataRepository.linkCloudDevice(device.id, null);
      }
      if (localDeviceId != null && localDeviceId.isNotEmpty) {
        await _dataRepository.linkCloudDevice(localDeviceId, cloudDevice.id);
      }
      await _reloadLocalDevices();
      _message = localDeviceId == null || localDeviceId.isEmpty
          ? 'Appareil cloud dissocié'
          : 'Appareil cloud associé';
    } catch (error) {
      _error = _safeError(error);
    } finally {
      _setBusy(false);
    }
  }

  Future<CloudSyncResult?> synchronize(
    CloudDeviceSummary cloudDevice,
    String localDeviceId,
  ) async {
    final sync = _syncService;
    if (sync == null || _isBusy) return null;
    final local = _localDevices.where((device) => device.id == localDeviceId);
    if (local.isEmpty) {
      _error = 'Associe d’abord l’appareil cloud à un nœud local';
      notifyListeners();
      return null;
    }
    _setBusy(true);
    _error = null;
    _message = null;
    try {
      final result = await sync.synchronize(local.first);
      _lastResults[cloudDevice.id] = result;
      await _reloadLocalDevices();
      _message = '${result.inserted} nouvelle(s) mesure(s) synchronisée(s)';
      return result;
    } catch (error) {
      _error = _safeError(error);
      return null;
    } finally {
      _setBusy(false);
    }
  }

  Future<int> synchronizeLinkedDevices() async {
    return (await synchronizeLinkedDeviceIds()).length;
  }

  Future<Set<String>> synchronizeLinkedDeviceIds() async {
    if (_isBusy) return <String>{};
    final remoteById = {
      for (final device in _cloudDevices) device.id: device,
    };
    final linked = _localDevices
        .where((device) =>
            device.cloudDeviceId != null &&
            remoteById.containsKey(device.cloudDeviceId))
        .toList(growable: false);
    final synchronized = <String>{};
    for (final local in linked) {
      final remote = remoteById[local.cloudDeviceId]!;
      final result = await synchronize(remote, local.id);
      if (result != null) synchronized.add(local.id);
    }
    return synchronized;
  }

  Future<CloudBackfillResult?> backfillHistorical(
    CloudDeviceSummary cloudDevice,
    String localDeviceId,
  ) async {
    final remote = _remoteRepository;
    if (remote == null || _isBusy) return null;
    final local = _localDevices.where((device) => device.id == localDeviceId);
    if (local.isEmpty) {
      _error = 'Associe d’abord l’appareil cloud à un nœud local';
      notifyListeners();
      return null;
    }
    _setBusy(true);
    _error = null;
    _message = null;
    try {
      final cutoff = DateTime.now().subtract(const Duration(days: 5));
      final readings = (await _dataRepository.getReadingsForDevice(
        localDeviceId,
        limit: 10000,
      ))
          .where((reading) => !reading.timestamp.isBefore(cutoff))
          .toList(growable: false);
      final result = await remote.uploadHistoricalReadings(
        cloudDevice.id,
        readings,
      );
      _message = result.rejected == 0
          ? '${result.accepted} mesure(s) historique(s) envoyée(s)'
          : '${result.accepted} envoyée(s), ${result.rejected} rejetée(s) : vérifier les détails';
      return result;
    } catch (error) {
      _error = _safeError(error);
      return null;
    } finally {
      _setBusy(false);
    }
  }

  Future<bool> publishBusinessSnapshot() async {
    final remote = _remoteRepository;
    if (remote == null || _isBusy) return false;
    _setBusy(true);
    _error = null;
    _message = null;
    try {
      final snapshot = await _buildSnapshot();
      final publishedAt = await remote.publishBusinessSnapshot(snapshot);
      _lastBusinessPublication = publishedAt;
      final plants = (snapshot['plants'] as List).length;
      final actions = (snapshot['actions'] as List).length;
      _message =
          '$plants plante(s) et $actions action(s) publiées en lecture seule';
      return true;
    } catch (error) {
      _error = error is DatabaseException
          ? 'Impossible de préparer les données locales. Aucune publication effectuée.'
          : _safeError(error);
      return false;
    } finally {
      _setBusy(false);
    }
  }

  /// Publishes the journal and catches up measurements independently. A failed
  /// stage must not hide another failure or prevent the remaining devices.
  Future<Set<String>> synchronizeMyData() async {
    final remote = _remoteRepository;
    final sync = _syncService;
    if (remote == null || sync == null || _isBusy) return <String>{};
    _setBusy(true);
    _error = null;
    _message = null;
    final failures = <String>[];
    final synchronized = <String>{};
    var published = false;
    var inserted = 0;
    try {
      try {
        final snapshot = await _buildSnapshot();
        final publishedAt = await remote.publishBusinessSnapshot(snapshot);
        if (_remoteRepository != remote) return synchronized;
        _lastBusinessPublication = publishedAt;
        published = true;
      } catch (error) {
        failures.add(error is DatabaseException
            ? 'Journal : impossible de préparer les données locales.'
            : 'Journal : ${_safeError(error)}');
      }
      if (_remoteRepository != remote) return synchronized;
      await _reloadLocalDevices();
      final remoteIds = _cloudDevices.map((device) => device.id).toSet();
      for (final local in _localDevices.toList()) {
        if (!remoteIds.contains(local.cloudDeviceId)) continue;
        try {
          final result = await sync.synchronize(local);
          if (_remoteRepository != remote) return synchronized;
          _lastResults[local.cloudDeviceId!] = result;
          synchronized.add(local.id);
          inserted += result.inserted;
        } catch (error) {
          failures.add('Mesures de ${local.name} : ${_safeError(error)}');
        }
        if (_remoteRepository != remote) return synchronized;
      }
      await _reloadLocalDevices();
      _message = '${published ? 'Journal envoyé. ' : ''}'
          '${synchronized.length} appareil(s) synchronisé(s), '
          '$inserted nouvelle(s) mesure(s).';
    } catch (error) {
      failures.add(_safeError(error));
    } finally {
      if (_remoteRepository == remote) {
        _error = failures.isEmpty ? null : failures.join('\n');
      }
      _setBusy(false);
    }
    return synchronized;
  }

  Future<void> disconnect() async {
    final remote = _remoteRepository;
    _remoteRepository = null;
    _syncService = null;
    _baseUrl = '';
    _account = null;
    _lastBusinessPublication = null;
    _cloudDevices = [];
    _localDevices = [];
    _lastResults.clear();
    _error = null;
    _message = 'Session cloud fermée';
    notifyListeners();
    if (remote != null) {
      try {
        await remote.logout();
      } catch (_) {
        // Keep the local session closed even if the API is unavailable.
      } finally {
        remote.close();
      }
    }
  }

  Future<void> _reloadLocalDevices() async {
    _localDevices = await _dataRepository.getDevices(deviceKind: 'sensor');
  }

  void _setBusy(bool value) {
    _isBusy = value;
    notifyListeners();
  }

  String _safeError(Object error) {
    if (error is CloudApiException) {
      if (error.statusCode == 401 || error.statusCode == 403) {
        return 'Session expirée ou accès refusé. Reconnecte-toi au hub.';
      }
      return 'API cloud indisponible (HTTP ${error.statusCode})';
    }
    if (error is TimeoutException) {
      return 'Le hub met trop de temps à répondre. Nouvelle tentative automatique au prochain passage.';
    }
    if (error is SocketException || error is http.ClientException) {
      return 'Hub inaccessible. Vérifie la connexion Internet et l’adresse du serveur. La synchronisation reprendra automatiquement.';
    }
    if (error is FormatException) return error.message;
    return 'Synchronisation impossible pour le moment. Réessaie dans quelques instants.';
  }

  @override
  void dispose() {
    _remoteRepository?.close();
    super.dispose();
  }
}
