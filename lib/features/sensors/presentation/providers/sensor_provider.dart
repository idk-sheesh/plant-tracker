import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/repositories/sensor_data_repository.dart';
import '../../data/repositories/sensor_repository.dart';
import '../../data/services/sensor_alert_service.dart';
import '../../data/services/safe_device_control_service.dart';
import '../../domain/entities/device_capability.dart';
import '../../domain/entities/device_health_snapshot.dart';
import '../../domain/entities/sensor_device.dart';
import '../../domain/entities/sensor_measurement.dart';
import '../../domain/entities/sensor_reading.dart';

class SensorProvider extends ChangeNotifier {
  final SensorRepository _remoteRepository;
  final SensorDataRepository _dataRepository;
  final SensorAlertService? _alertService;
  final SafeDeviceControlService? _controlService;

  SensorProvider({
    SensorRepository? remoteRepository,
    SensorDataRepository? dataRepository,
    SensorAlertService? alertService,
    SafeDeviceControlService? controlService,
  })  : _remoteRepository = remoteRepository ?? SensorRepository(),
        _dataRepository = dataRepository ?? SensorDataRepository(),
        _alertService = alertService ??
            (dataRepository == null ? SensorAlertService() : null),
        _controlService = controlService ??
            (dataRepository == null ? SafeDeviceControlService() : null);

  SensorReading? _latest;
  List<SensorReading> _history = [];
  List<DeviceCapability> _capabilities = [];
  List<SensorMeasurement> _measurements = [];
  List<SensorDevice> _devices = [];
  SensorDevice? _currentDevice;
  final Map<String, SensorReading> _latestByZone = {};
  final Map<String, DeviceHealthSnapshot> _healthByDevice = {};
  GrowStage _stage = GrowStage.veg;
  bool _isConnected = false;
  bool _isLoading = false;
  bool _isSyncingAll = false;
  bool _isSettingStage = false;
  String? _error;
  String? _stageError;
  String _espIp = '';
  String _baseUrl = '';
  int _espPort = 80;
  Timer? _timer;
  int _refreshSec = 60;
  Future<void>? _initialization;

  SensorReading? get latest => _latest;
  List<SensorReading> get history => List.unmodifiable(_history);
  List<DeviceCapability> get capabilities => List.unmodifiable(_capabilities);
  List<SensorMeasurement> get measurements => List.unmodifiable(_measurements);
  List<HistoryPoint> get chartHistory =>
      _history.map(HistoryPoint.fromReading).toList(growable: false);
  List<SensorDevice> get devices => List.unmodifiable(_devices);
  SensorDevice? get currentDevice => _currentDevice;
  DeviceHealthSnapshot? healthForDevice(String deviceId) =>
      _healthByDevice[deviceId];
  GrowStage get stage => _stage;
  bool get isConnected => _isConnected;
  bool get isLoading => _isLoading;
  bool get isSyncingAll => _isSyncingAll;
  bool get isSettingStage => _isSettingStage;
  bool get hasActiveOperation => _isLoading || _isSyncingAll || _isSettingStage;
  String? get error => _error;
  String? get stageError => _stageError;
  String get espIp => _espIp;
  String get baseUrl => _baseUrl;
  int get espPort => _espPort;
  bool get isConfigured => _remoteRepository.isConfigured;
  int get refreshInterval => _refreshSec;

  Future<void> initialize() => _initialization ??= _initialize();

  Future<bool> reloadAfterRestore() async {
    stopAutoRefresh();
    _remoteRepository.clearConfiguration();
    _latest = null;
    _history = [];
    _capabilities = [];
    _measurements = [];
    _devices = [];
    _currentDevice = null;
    _latestByZone.clear();
    _healthByDevice.clear();
    _stage = GrowStage.veg;
    _isConnected = false;
    _error = null;
    _stageError = null;
    _espIp = '';
    _baseUrl = '';
    _espPort = 80;
    _initialization = null;
    await initialize();
    _startTimer();
    return _error == null;
  }

  Future<void> _initialize() async {
    try {
      await _reloadDevices();
      await _reloadHealth();
      await _reloadZoneCache();
      if (_devices.isNotEmpty) {
        await _selectDevice(_devices.first, notify: false);
      }
    } catch (error, stackTrace) {
      _error = 'Impossible de charger les capteurs enregistrés';
      _report(error, stackTrace, 'initialisation des capteurs');
    }
    notifyListeners();
  }

  SensorDevice? deviceForZone(String zoneId) {
    for (final device in _devices) {
      if (device.zoneId == zoneId) return device;
    }
    return null;
  }

  SensorDevice? deviceByUid(String uid) {
    for (final device in _devices) {
      if (device.uid == uid || device.id == uid) return device;
    }
    return null;
  }

  Future<void> refreshDevices() async {
    await _reloadDevices();
    await _reloadHealth();
    notifyListeners();
  }

  Future<void> refreshFromLocalCache() async {
    final currentId = _currentDevice?.id;
    await _reloadDevices();
    await _reloadHealth();
    await _reloadZoneCache();
    if (currentId != null) {
      final current = _devices.where((device) => device.id == currentId);
      if (current.isNotEmpty) {
        await _selectDevice(current.first, notify: false);
      }
    }
    notifyListeners();
  }

  Future<double?> availabilityForDevice(
    String deviceId, {
    Duration period = const Duration(hours: 24),
  }) {
    return _dataRepository.getAvailabilityPercent(
      deviceId,
      period: period,
    );
  }

  SensorReading? latestForZone(String zoneId) => _latestByZone[zoneId];

  bool isZoneDataStale(
    String zoneId, {
    Duration threshold = const Duration(minutes: 5),
  }) {
    final reading = latestForZone(zoneId);
    return reading == null ||
        DateTime.now().difference(reading.timestamp) > threshold;
  }

  bool hasCurrentReadingForZone(String zoneId) {
    final device = deviceForZone(zoneId);
    if (device == null || isZoneDataStale(zoneId)) return false;
    if (device.isOnline) return true;
    if (!device.hasCloudLink || device.cloudLastError != null) return false;
    final contact = device.cloudLastContactAt;
    final sync = device.cloudLastSyncAt;
    if (contact == null || sync == null) return false;
    final now = DateTime.now();
    return !contact.isAfter(now.add(const Duration(minutes: 1))) &&
        !sync.isAfter(now.add(const Duration(minutes: 1))) &&
        now.difference(contact) <= const Duration(minutes: 5) &&
        now.difference(sync) <= const Duration(minutes: 5);
  }

  Future<List<SensorReading>> historyForZone(
    String zoneId,
    Duration period,
  ) {
    return _dataRepository.getReadingsForZoneSince(
      zoneId,
      DateTime.now().subtract(period),
    );
  }

  Future<List<SensorMeasurement>> measurementsForZone(
    String zoneId,
    Duration period,
  ) {
    return _dataRepository.getMeasurementsForZoneSince(
      zoneId,
      DateTime.now().subtract(period),
    );
  }

  Future<List<SensorMeasurement>> measurementsForZoneSince(
    String zoneId,
    DateTime since,
  ) =>
      _dataRepository.getMeasurementsForZoneSince(zoneId, since);

  VpdStatus vpdStatus(double vpd) {
    if (vpd < _stage.vpdMin) return VpdStatus.tooLow;
    if (vpd > _stage.vpdMax) return VpdStatus.tooHigh;
    return VpdStatus.ideal;
  }

  bool configure(String ip, {int port = 80}) {
    _espIp = ip.trim();
    _espPort = port;
    _remoteRepository.configure(_espIp, port: port);
    final configured = _remoteRepository.isConfigured;
    _baseUrl = configured ? _remoteRepository.baseUrl ?? '' : '';
    _error = configured ? null : 'Adresse ESP32 invalide';
    notifyListeners();
    return configured;
  }

  bool configureBaseUrl(String value) {
    final configured = _remoteRepository.configureBaseUrl(value);
    _baseUrl = configured ? _remoteRepository.baseUrl ?? '' : '';
    _espIp = configured ? Uri.parse(_baseUrl).host : value.trim();
    _espPort = configured ? Uri.parse(_baseUrl).port : 80;
    _error = configured ? null : 'Adresse ESP32 invalide';
    notifyListeners();
    return configured;
  }

  Future<void> selectDevice(SensorDevice device) => _selectDevice(device);

  Future<void> _selectDevice(
    SensorDevice device, {
    bool notify = true,
  }) async {
    _currentDevice = device;
    configureBaseUrl(device.baseUrl);
    _history = await _dataRepository.getReadingsForDevice(device.id);
    _capabilities = await _dataRepository.getCapabilitiesForDevice(device.id);
    _measurements = await _dataRepository.getMeasurementsForDevice(device.id);
    _latest = _history.isEmpty ? null : _history.last;
    if (notify) notifyListeners();
  }

  Future<bool> setStage(GrowStage value) async {
    if (_isSettingStage) return false;
    final previous = _stage;
    _stage = value;
    _stageError = null;
    if (!isConfigured) {
      notifyListeners();
      return true;
    }
    _isSettingStage = true;
    notifyListeners();
    try {
      await _remoteRepository.updateConfig({'mode': value.apiValue});
      return true;
    } catch (error, stackTrace) {
      _stage = previous;
      _stageError = 'Le stade n’a pas été transmis au capteur';
      _report(error, stackTrace, 'mise à jour du stade ESP32');
      return false;
    } finally {
      _isSettingStage = false;
      notifyListeners();
    }
  }

  void setRefreshInterval(int seconds) {
    _refreshSec = seconds;
    _startTimer();
    notifyListeners();
  }

  Future<bool> testConnection() async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final status = await _remoteRepository.fetchStatus();
      _latest = status;
      _capabilities = status.capabilities;
      _measurements = status.measurements;
      _syncStage(status);
      _isConnected = true;
      return true;
    } catch (error, stackTrace) {
      _isConnected = false;
      _error = 'Impossible de joindre l’ESP32 à $_baseUrl';
      _report(error, stackTrace, 'test de connexion ESP32');
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> saveCurrentDevice({
    required String name,
    required String zoneId,
  }) async {
    if (!isConfigured) {
      _error = 'Adresse ESP32 invalide';
      notifyListeners();
      return false;
    }
    if (name.trim().isEmpty || zoneId.isEmpty) {
      _error = 'Le nom et la zone du capteur sont obligatoires';
      notifyListeners();
      return false;
    }

    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final status = await _remoteRepository.fetchStatus();
      if (status.deviceId.trim().isEmpty) {
        throw const FormatException('deviceId absent de /status');
      }
      final existing = await _dataRepository.getDeviceByUid(status.deviceId);
      final now = DateTime.now();
      final device = SensorDevice(
        id: existing?.id ?? status.deviceId,
        uid: status.deviceId,
        name: name.trim(),
        zoneId: zoneId,
        baseUrl: _remoteRepository.baseUrl!,
        firmwareVersion: status.firmwareVersion ?? existing?.firmwareVersion,
        lastSeenAt: status.timestamp,
        lastSyncAt: existing?.lastSyncAt,
        status: 'online',
        createdAt: existing?.createdAt ?? now,
        updatedAt: now,
      );
      await _dataRepository.upsertDevice(device);
      _currentDevice = device;
      await _synchronize(device, status: status);
      await _reloadDevices();
      await _reloadZoneCache();
      _isConnected = true;
      return true;
    } catch (error, stackTrace) {
      _isConnected = false;
      _error = 'Synchronisation impossible: $error';
      _report(error, stackTrace, 'enregistrement d’un capteur');
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> fetchNow() async {
    if (!isConfigured || _isLoading) return;
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final device = _currentDevice;
      if (device == null) {
        final status = await _remoteRepository.fetchStatus();
        _latest = status;
        _syncStage(status);
      } else {
        await _synchronize(device);
        await _reloadDevices();
        await _reloadZoneCache();
      }
      _isConnected = true;
    } catch (error, stackTrace) {
      _isConnected = false;
      _error = 'Capteur inaccessible, dernières données conservées';
      _report(error, stackTrace, 'synchronisation du capteur courant');
      final device = _currentDevice;
      if (device != null) {
        await _dataRepository.updateDeviceStatus(device.id, 'offline');
        await _recordHealth(
          device,
          isOnline: false,
          errorCode: error.runtimeType.toString(),
        );
        await _alertService?.evaluateOffline(device);
        await _reloadDevices();
        await _reloadHealth();
      }
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> syncAllDevices({Set<String> skipDeviceIds = const {}}) async {
    if (_isSyncingAll) return;
    await initialize();
    _isSyncingAll = true;
    _error = null;
    notifyListeners();
    final originalId = _currentDevice?.id;
    var failedDevices = 0;
    try {
      for (final device in List<SensorDevice>.from(_devices)) {
        if (skipDeviceIds.contains(device.id)) continue;
        if (!configureBaseUrl(device.baseUrl)) {
          failedDevices++;
          await _alertService?.evaluateOffline(device);
          continue;
        }
        try {
          await _synchronize(device);
        } catch (error, stackTrace) {
          failedDevices++;
          _report(error, stackTrace, 'synchronisation d’un capteur');
          await _dataRepository.updateDeviceStatus(device.id, 'offline');
          await _recordHealth(
            device,
            isOnline: false,
            errorCode: error.runtimeType.toString(),
          );
          await _alertService?.evaluateOffline(device);
        }
      }
      await _reloadDevices();
      await _reloadHealth();
      await _reloadZoneCache();
      if (originalId != null) {
        final original =
            _devices.where((item) => item.id == originalId).firstOrNull;
        if (original != null) await _selectDevice(original, notify: false);
      }
      if (failedDevices > 0) {
        _error = '$failedDevices capteur(s) non synchronisé(s)';
      }
    } finally {
      _isSyncingAll = false;
      notifyListeners();
    }
  }

  Future<void> _synchronize(
    SensorDevice device, {
    SensorReading? status,
  }) async {
    final since = await _dataRepository.getLastMeasuredAtSeconds(device.id);
    List<SensorReading> readings;
    try {
      readings = await _remoteRepository.fetchReadings(since: since);
    } on SensorHistoryUnavailableException {
      readings = [];
    }
    if (_remoteRepository.lastBatchDiagnostics case final diagnostics?) {
      _error = '${diagnostics.rejected} mesure(s) invalide(s) ignorée(s)';
    }
    final currentStatus = status ?? await _remoteRepository.fetchStatus();
    _validateDeviceId(currentStatus.deviceId, device.uid);

    final normalized = <SensorReading>[];
    for (final reading in readings) {
      if (reading.deviceId.isNotEmpty && reading.deviceId != device.uid)
        continue;
      normalized.add(
        reading.copyWith(deviceId: device.id, zoneId: device.zoneId),
      );
    }
    normalized.add(
      currentStatus.copyWith(deviceId: device.id, zoneId: device.zoneId),
    );

    await _dataRepository.insertReadings(device, normalized);
    for (final reading in normalized) {
      await _alertService?.evaluateReading(device, reading);
    }
    final now = DateTime.now();
    final lastSeen = normalized
        .map((reading) => reading.timestamp)
        .reduce((a, b) => a.isAfter(b) ? a : b);
    final updatedDevice = device.copyWith(
      firmwareVersion: currentStatus.firmwareVersion,
      lastSeenAt: lastSeen,
      lastSyncAt: now,
      status: 'online',
      updatedAt: now,
    );
    await _dataRepository.upsertDevice(updatedDevice);
    await _recordHealth(
      updatedDevice,
      status: currentStatus,
      isOnline: true,
    );

    if (_currentDevice?.id == device.id) {
      _currentDevice = updatedDevice;
      _history = await _dataRepository.getReadingsForDevice(device.id);
      _capabilities = await _dataRepository.getCapabilitiesForDevice(device.id);
      _measurements = await _dataRepository.getMeasurementsForDevice(device.id);
      _latest = _history.isEmpty ? currentStatus : _history.last;
    }
    if (device.zoneId != null) {
      _latestByZone[device.zoneId!] =
          normalized.reduce((a, b) => a.timestamp.isAfter(b.timestamp) ? a : b);
    }
    _syncStage(currentStatus);
  }

  void _validateDeviceId(String received, String expected) {
    if (received.isNotEmpty && received != expected) {
      throw FormatException(
        'deviceId inattendu ($received au lieu de $expected)',
      );
    }
  }

  void _syncStage(SensorReading reading) {
    if (reading.stageName != null) {
      _stage = GrowStageExt.fromEspName(reading.stageName);
    }
  }

  Future<void> _reloadDevices() async {
    _devices = await _dataRepository.getDevices(deviceKind: 'sensor');
    final currentId = _currentDevice?.id;
    if (currentId == null) return;
    for (final device in _devices) {
      if (device.id == currentId) {
        _currentDevice = device;
        return;
      }
    }
  }

  Future<void> _reloadZoneCache() async {
    _latestByZone.clear();
    for (final device in _devices) {
      final zoneId = device.zoneId;
      if (zoneId == null || _latestByZone.containsKey(zoneId)) continue;
      final reading = await _dataRepository.getLatestForZone(zoneId);
      if (reading != null) _latestByZone[zoneId] = reading;
    }
  }

  Future<void> _reloadHealth() async {
    _healthByDevice.clear();
    for (final device in _devices) {
      final health = await _dataRepository.getLatestHealth(device.id);
      if (health != null) _healthByDevice[device.id] = health;
    }
  }

  Future<void> _recordHealth(
    SensorDevice device, {
    SensorReading? status,
    required bool isOnline,
    String? errorCode,
  }) async {
    double? numericMetric(String key) {
      for (final measurement in status?.measurements ?? const []) {
        if (measurement.capabilityKey == key) {
          return measurement.numericValue;
        }
      }
      return null;
    }

    final observedAt = DateTime.now();
    final previous = _healthByDevice[device.id];
    final snapshot = DeviceHealthSnapshot(
      id: '${device.id}-${observedAt.toUtc().millisecondsSinceEpoch ~/ 1000}',
      deviceId: device.id,
      observedAt: observedAt,
      isOnline: isOnline,
      batteryPercent:
          numericMetric('battery_percent') ?? previous?.batteryPercent,
      batteryVoltage: numericMetric('battery_v') ?? previous?.batteryVoltage,
      rssi: status?.rssi ?? previous?.rssi,
      snr: numericMetric('snr_db') ?? previous?.snr,
      uptimeSeconds:
          numericMetric('uptime_seconds')?.round() ?? previous?.uptimeSeconds,
      freeHeapBytes:
          numericMetric('free_heap_bytes')?.round() ?? previous?.freeHeapBytes,
      missingReadings: numericMetric('missing_readings')?.round() ?? 0,
      firmwareVersion: status?.firmwareVersion ?? device.firmwareVersion,
      lastError: isOnline ? null : errorCode,
      createdAt: observedAt,
    );
    await _dataRepository.recordHealthSnapshot(snapshot);
    _healthByDevice[device.id] = snapshot;
  }

  Future<List<SensorReading>> loadHistoryForZone(
    String zoneId, {
    int limit = 288,
  }) {
    return _dataRepository.getReadingsForZone(zoneId, limit: limit);
  }

  void startAutoRefresh() => _startTimer();

  void _startTimer() {
    _timer?.cancel();
    if (_devices.isEmpty && !isConfigured) return;
    _timer = Timer.periodic(
      Duration(seconds: _refreshSec),
      (_) =>
          unawaited(syncAllDevices().catchError((Object error, StackTrace st) {
        _report(error, st, 'rafraîchissement automatique des capteurs');
      })),
    );
  }

  void stopAutoRefresh() {
    _timer?.cancel();
    _timer = null;
  }

  Future<bool> setMist(bool enabled) async {
    final device = _currentDevice;
    final controls = _controlService;
    if (device == null || controls == null) return false;
    await controls.execute(
      device: device,
      commandType: 'mist.set',
      params: {'state': enabled},
    );
    await fetchNow();
    return true;
  }

  Future<bool> sendCommand(
    String command, {
    Map<String, dynamic>? params,
  }) {
    if (command == 'mist' && params?['state'] is bool) {
      return setMist(params!['state'] as bool);
    }
    throw const SafeControlException('Commande provider non autorisée');
  }

  String buildAdvice() {
    final reading = _latest;
    if (reading == null) return 'Aucune donnée disponible.';
    final band = VpdChart.classify(
      temperature: reading.temperature,
      humidity: reading.humidity,
    );
    if (band.isDanger) {
      return 'Grille historique indicative : ${band.shortLabel.toLowerCase()} pour ce couple '
          'température / humidité.';
    }
    return 'Grille historique indicative : ${band.shortLabel.toLowerCase()} '
        '(${band.detail.toLowerCase()}).';
  }

  @override
  void dispose() {
    _timer?.cancel();
    _remoteRepository.close();
    super.dispose();
  }

  void _report(Object error, StackTrace stackTrace, String operation) {
    FlutterError.reportError(FlutterErrorDetails(
      exception: error,
      stack: stackTrace,
      library: 'gardenjournal sensors',
      context: ErrorDescription(operation),
    ));
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
