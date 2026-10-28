import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';

import '../../domain/entities/device_control.dart';
import '../../domain/entities/sensor_device.dart';
import '../repositories/device_control_repository.dart';
import '../repositories/gateway_repository.dart';
import '../repositories/lora_repository.dart';
import '../repositories/sensor_repository.dart';

class SafeDeviceControlService {
  final SensorRepository _remote;
  final DeviceControlRepository _local;
  final GatewayRepository _gatewayRepository;
  final LoRaRepository _loraRepository;
  final Uuid _uuid;
  final DateTime Function() _clock;

  SafeDeviceControlService({
    SensorRepository? remote,
    DeviceControlRepository? local,
    GatewayRepository? gatewayRepository,
    LoRaRepository? loraRepository,
    Uuid uuid = const Uuid(),
    DateTime Function()? clock,
  })  : _remote = remote ?? SensorRepository(),
        _local = local ?? DeviceControlRepository(),
        _gatewayRepository = gatewayRepository ?? GatewayRepository(),
        _loraRepository = loraRepository ?? LoRaRepository(),
        _uuid = uuid,
        _clock = clock ?? DateTime.now;

  Future<DeviceCommand> execute({
    required SensorDevice device,
    required String commandType,
    required Map<String, Object?> params,
    Duration timeToLive = const Duration(seconds: 90),
    bool criticalConfirmed = false,
  }) async {
    final normalized = validateCommand(commandType, params);
    final safetyClass =
        commandType == 'irrigation.pulse' ? 'critical' : 'standard';
    if (safetyClass == 'critical' && !criticalConfirmed) {
      throw const SafeControlException(
        'Confirmation explicite requise pour l’irrigation',
      );
    }
    if (timeToLive <= Duration.zero ||
        timeToLive > const Duration(minutes: 5)) {
      throw const SafeControlException('Expiration de commande invalide');
    }
    final now = _clock();
    final command = DeviceCommand(
      id: _uuid.v4(),
      deviceId: device.id,
      zoneId: device.zoneId,
      commandType: commandType,
      params: normalized,
      idempotencyKey: _uuid.v4(),
      safetyClass: safetyClass,
      requestedAt: now,
      expiresAt: now.add(timeToLive),
      status: 'pending',
      createdAt: now,
      updatedAt: now,
    );
    await _local.insertCommand(command);
    return _dispatch(device, command);
  }

  Future<DeviceCommand> retry({
    required SensorDevice device,
    required DeviceCommand command,
    bool criticalConfirmed = false,
  }) async {
    if (command.deviceId != device.id || command.isFinal) {
      throw const SafeControlException('Commande non rejouable');
    }
    if (!_clock().isBefore(command.expiresAt)) {
      await _local.updateCommand(
        command.id,
        status: 'expired',
        errorCode: 'expired_before_retry',
        updatedAt: _clock(),
      );
      throw const SafeControlException('Commande expirée');
    }
    if (command.safetyClass == 'critical' && !criticalConfirmed) {
      throw const SafeControlException('Confirmation explicite requise');
    }
    validateCommand(command.commandType, command.params);
    return _dispatch(device, command);
  }

  Future<DeviceCommand> _dispatch(
    SensorDevice device,
    DeviceCommand command,
  ) async {
    try {
      final targetNodeId = await _configureTarget(device);
      final response = await _remote.issueCommand({
        'version': 1,
        'commandId': command.id,
        'idempotencyKey': command.idempotencyKey,
        'type': command.commandType,
        'params': command.params,
        'requestedAt': command.requestedAt.toUtc().toIso8601String(),
        'expiresAt': command.expiresAt.toUtc().toIso8601String(),
        if (targetNodeId != null) 'targetNodeId': targetNodeId,
      });
      _validateCommandAck(command, response);
      final ackAt = _safeAckTime(command.requestedAt);
      await _local.updateCommand(
        command.id,
        status: 'acknowledged',
        nodeAckAt: ackAt,
        nodeResponse: Map<String, Object?>.from(response),
        updatedAt: ackAt,
      );
      return (await _local.getCommand(command.id))!;
    } catch (error) {
      final now = _clock();
      final status = now.isBefore(command.expiresAt) ? 'failed' : 'expired';
      await _local.updateCommand(
        command.id,
        status: status,
        errorCode: _errorCode(error),
        updatedAt: now,
      );
      rethrow;
    }
  }

  Future<NodeSchedule> syncSchedule({
    required SensorDevice device,
    NodeSchedule? previous,
    required String name,
    required String commandType,
    required Map<String, Object?> params,
    required String timezone,
    required int daysMask,
    required int startMinute,
    bool isEnabled = true,
    bool criticalConfirmed = false,
  }) async {
    final normalized = validateCommand(commandType, params);
    if (commandType == 'irrigation.pulse' && !criticalConfirmed) {
      throw const SafeControlException(
        'Confirmation explicite requise pour ce programme',
      );
    }
    final normalizedName = name.trim();
    if (normalizedName.isEmpty || normalizedName.length > 120) {
      throw const SafeControlException('Nom de programme invalide');
    }
    if (!_validTimezone(timezone) || daysMask < 1 || daysMask > 127) {
      throw const SafeControlException('Calendrier ou fuseau invalide');
    }
    if (startMinute < 0 || startMinute > 1439) {
      throw const SafeControlException('Heure de programme invalide');
    }
    if (previous != null && previous.deviceId != device.id) {
      throw const SafeControlException('Programme associé à un autre nœud');
    }
    final now = _clock();
    final id = previous?.id ?? _uuid.v4();
    final revision = (previous?.revision ?? 0) + 1;
    final canonical = <String, Object?>{
      'version': 1,
      'scheduleId': id,
      'revision': revision,
      'name': normalizedName,
      'timezone': timezone,
      'daysMask': daysMask,
      'startMinute': startMinute,
      'enabled': isEnabled,
      'command': {
        'type': commandType,
        'params': normalized,
      },
    };
    final hash = sha256.convert(utf8.encode(jsonEncode(canonical))).toString();
    var schedule = NodeSchedule(
      id: id,
      deviceId: device.id,
      name: normalizedName,
      commandType: commandType,
      timezone: timezone,
      daysMask: daysMask,
      startMinute: startMinute,
      params: normalized,
      revision: revision,
      scheduleHash: hash,
      isEnabled: isEnabled,
      status: 'pending',
      createdAt: previous?.createdAt ?? now,
      updatedAt: now,
    );
    await _local.saveSchedule(schedule);
    try {
      final targetNodeId = await _configureTarget(device);
      final response = await _remote.syncSchedule({
        ...canonical,
        'scheduleHash': hash,
        if (targetNodeId != null) 'targetNodeId': targetNodeId,
      });
      _validateScheduleAck(schedule, response);
      final ackAt = _safeAckTime(now);
      schedule = NodeSchedule(
        id: schedule.id,
        deviceId: schedule.deviceId,
        name: schedule.name,
        commandType: schedule.commandType,
        timezone: schedule.timezone,
        daysMask: schedule.daysMask,
        startMinute: schedule.startMinute,
        params: schedule.params,
        revision: schedule.revision,
        scheduleHash: schedule.scheduleHash,
        isEnabled: schedule.isEnabled,
        status: isEnabled ? 'active' : 'disabled',
        nodeAckAt: ackAt,
        nodeAckHash: hash,
        createdAt: schedule.createdAt,
        updatedAt: ackAt,
      );
      await _local.saveSchedule(schedule);
      return schedule;
    } catch (error) {
      schedule = NodeSchedule(
        id: schedule.id,
        deviceId: schedule.deviceId,
        name: schedule.name,
        commandType: schedule.commandType,
        timezone: schedule.timezone,
        daysMask: schedule.daysMask,
        startMinute: schedule.startMinute,
        params: schedule.params,
        revision: schedule.revision,
        scheduleHash: schedule.scheduleHash,
        isEnabled: schedule.isEnabled,
        status: 'failed',
        lastError: _errorCode(error),
        createdAt: schedule.createdAt,
        updatedAt: _clock(),
      );
      await _local.saveSchedule(schedule);
      rethrow;
    }
  }

  static Map<String, Object?> validateCommand(
    String commandType,
    Map<String, Object?> params,
  ) {
    void exactKeys(Set<String> expected) {
      if (params.keys.toSet().difference(expected).isNotEmpty ||
          expected.difference(params.keys.toSet()).isNotEmpty) {
        throw const SafeControlException('Paramètres de commande invalides');
      }
    }

    switch (commandType) {
      case 'mist.set':
      case 'light.set':
        exactKeys({'state'});
        if (params['state'] is! bool) {
          throw const SafeControlException('État booléen requis');
        }
        return {'state': params['state']};
      case 'fan.set':
        exactKeys({'percent'});
        final percent = params['percent'];
        if (percent is! num ||
            !percent.toDouble().isFinite ||
            percent < 0 ||
            percent > 100) {
          throw const SafeControlException('Ventilation limitée à 0–100 %');
        }
        return {'percent': percent.toDouble()};
      case 'irrigation.pulse':
        exactKeys({'durationSeconds', 'maxVolumeMl'});
        final duration = params['durationSeconds'];
        final volume = params['maxVolumeMl'];
        if (duration is! int || duration < 1 || duration > 120) {
          throw const SafeControlException('Impulsion limitée à 1–120 s');
        }
        if (volume is! num ||
            !volume.toDouble().isFinite ||
            volume <= 0 ||
            volume > 5000) {
          throw const SafeControlException('Volume maximal invalide');
        }
        return {
          'durationSeconds': duration,
          'maxVolumeMl': volume.toDouble(),
        };
      default:
        throw const SafeControlException('Commande non autorisée');
    }
  }

  Future<String?> _configureTarget(SensorDevice device) async {
    if (device.transport != 'lora') {
      if (!_remote.configureBaseUrl(device.baseUrl)) {
        throw const SafeControlException('Adresse locale du nœud invalide');
      }
      return null;
    }
    final link = await _loraRepository.getLinkForNode(device.id);
    final gateway = link == null
        ? null
        : await _gatewayRepository.getConfig(link.gatewayId);
    if (gateway == null ||
        !gateway.usesHttp ||
        !_remote.configureBaseUrl(gateway.httpBaseUrl ?? '')) {
      throw const SafeControlException('Gateway HTTP LoRa requise');
    }
    return device.uid;
  }

  static void _validateCommandAck(
    DeviceCommand command,
    Map<String, dynamic> response,
  ) {
    if (response['commandId'] != command.id ||
        response['idempotencyKey'] != command.idempotencyKey ||
        !const {'accepted', 'duplicate'}.contains(response['status'])) {
      throw const SafeControlException('Accusé de commande incohérent');
    }
  }

  static void _validateScheduleAck(
    NodeSchedule schedule,
    Map<String, dynamic> response,
  ) {
    if (response['scheduleId'] != schedule.id ||
        response['revision'] != schedule.revision ||
        response['scheduleHash'] != schedule.scheduleHash ||
        response['status'] != 'accepted') {
      throw const SafeControlException('Accusé de programme incohérent');
    }
  }

  DateTime _safeAckTime(DateTime notBefore) {
    final value = _clock();
    return value.isBefore(notBefore) ? notBefore : value;
  }

  static bool _validTimezone(String value) {
    if (value == 'UTC') return true;
    return value.length <= 64 &&
        RegExp(r'^[A-Za-z_]+(?:/[A-Za-z0-9_+\-]+)+$').hasMatch(value);
  }

  static String _errorCode(Object error) {
    final value = error.runtimeType.toString();
    return value.length <= 120 ? value : value.substring(0, 120);
  }
}

class SafeControlException implements Exception {
  final String message;

  const SafeControlException(this.message);

  @override
  String toString() => message;
}
