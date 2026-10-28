import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';

import '../../domain/entities/automation_rule.dart';
import '../../domain/entities/ota_update.dart' show canonicalJson;
import '../../domain/entities/sensor_device.dart';
import '../repositories/automation_repository.dart';
import '../repositories/gateway_repository.dart';
import '../repositories/lora_repository.dart';
import '../repositories/sensor_repository.dart';
import 'safe_device_control_service.dart';

class AutomationRuleService {
  final AutomationRepository repository;
  final SensorRepository remote;
  final GatewayRepository gatewayRepository;
  final LoRaRepository loraRepository;
  final Uuid _uuid;
  final DateTime Function() _clock;

  AutomationRuleService({
    AutomationRepository? repository,
    SensorRepository? remote,
    GatewayRepository? gatewayRepository,
    LoRaRepository? loraRepository,
    Uuid uuid = const Uuid(),
    DateTime Function()? clock,
  })  : repository = repository ?? AutomationRepository(),
        remote = remote ?? SensorRepository(),
        gatewayRepository = gatewayRepository ?? GatewayRepository(),
        loraRepository = loraRepository ?? LoRaRepository(),
        _uuid = uuid,
        _clock = clock ?? DateTime.now;

  Future<AutomationRule> synchronize({
    required SensorDevice device,
    AutomationRule? previous,
    required String name,
    required Map<String, Object?> condition,
    required String actionType,
    required Map<String, Object?> actionParams,
    required int durationSeconds,
    required int cooldownSeconds,
    required int maxRunsPerDay,
    bool isEnabled = true,
  }) async {
    final normalizedName = name.trim();
    if (normalizedName.isEmpty || normalizedName.length > 120) {
      throw const AutomationRuleException('Nom de règle invalide');
    }
    final normalizedCondition = validateCondition(condition);
    final normalizedAction =
        SafeDeviceControlService.validateCommand(actionType, actionParams);
    if (!const {'mist.set', 'fan.set', 'light.set'}.contains(actionType)) {
      throw const AutomationRuleException(
        'Action critique interdite dans une règle automatique',
      );
    }
    if (durationSeconds < 0 ||
        durationSeconds > 86400 ||
        cooldownSeconds < 0 ||
        cooldownSeconds > 604800 ||
        maxRunsPerDay < 1 ||
        maxRunsPerDay > 100) {
      throw const AutomationRuleException('Bornes temporelles invalides');
    }
    if (previous != null && previous.deviceId != device.id) {
      throw const AutomationRuleException('Règle liée à un autre nœud');
    }
    final id = previous?.id ?? _uuid.v4();
    final revision = (previous?.revision ?? 0) + 1;
    final canonical = <String, Object?>{
      'version': 1,
      'ruleId': id,
      'revision': revision,
      'name': normalizedName,
      'enabled': isEnabled,
      'condition': normalizedCondition,
      'durationSeconds': durationSeconds,
      'cooldownSeconds': cooldownSeconds,
      'maxRunsPerDay': maxRunsPerDay,
      'action': {'type': actionType, 'params': normalizedAction},
    };
    final hash =
        sha256.convert(utf8.encode(canonicalJson(canonical))).toString();
    final now = _clock();
    var rule = AutomationRule(
      id: id,
      deviceId: device.id,
      name: normalizedName,
      condition: normalizedCondition,
      actionType: actionType,
      actionParams: normalizedAction,
      durationSeconds: durationSeconds,
      cooldownSeconds: cooldownSeconds,
      maxRunsPerDay: maxRunsPerDay,
      revision: revision,
      ruleHash: hash,
      isEnabled: isEnabled,
      status: 'pending',
      createdAt: previous?.createdAt ?? now,
      updatedAt: now,
    );
    await repository.saveRule(rule);
    try {
      final targetNodeId = await _configureTarget(device);
      final response = await remote.syncAutomationRule({
        ...canonical,
        'ruleHash': hash,
        if (targetNodeId != null) 'targetNodeId': targetNodeId,
      });
      if (response['ruleId'] != id ||
          response['revision'] != revision ||
          response['ruleHash'] != hash ||
          response['status'] != 'accepted') {
        throw const AutomationRuleException('Accusé de règle incohérent');
      }
      final ackAt = _safeTime(now);
      rule = AutomationRule(
        id: rule.id,
        deviceId: rule.deviceId,
        name: rule.name,
        condition: rule.condition,
        actionType: rule.actionType,
        actionParams: rule.actionParams,
        durationSeconds: rule.durationSeconds,
        cooldownSeconds: rule.cooldownSeconds,
        maxRunsPerDay: rule.maxRunsPerDay,
        revision: rule.revision,
        ruleHash: rule.ruleHash,
        isEnabled: rule.isEnabled,
        status: isEnabled ? 'active' : 'disabled',
        nodeAckAt: ackAt,
        nodeAckHash: hash,
        createdAt: rule.createdAt,
        updatedAt: ackAt,
      );
      await repository.saveRule(rule);
      return rule;
    } catch (error) {
      rule = AutomationRule(
        id: rule.id,
        deviceId: rule.deviceId,
        name: rule.name,
        condition: rule.condition,
        actionType: rule.actionType,
        actionParams: rule.actionParams,
        durationSeconds: rule.durationSeconds,
        cooldownSeconds: rule.cooldownSeconds,
        maxRunsPerDay: rule.maxRunsPerDay,
        revision: rule.revision,
        ruleHash: rule.ruleHash,
        isEnabled: rule.isEnabled,
        status: 'failed',
        lastError: error.runtimeType.toString(),
        createdAt: rule.createdAt,
        updatedAt: _clock(),
      );
      await repository.saveRule(rule);
      rethrow;
    }
  }

  static Map<String, Object?> validateCondition(
    Map<String, Object?> raw, {
    int depth = 0,
    List<int>? counter,
  }) {
    final count = counter ?? [0];
    count[0]++;
    if (depth > 4 || count[0] > 20) {
      throw const AutomationRuleException('Condition trop complexe');
    }
    if (raw['op'] != null) {
      final op = raw['op'];
      final children = raw['conditions'];
      if (!const {'and', 'or'}.contains(op) ||
          children is! List ||
          children.length < 2 ||
          children.length > 10) {
        throw const AutomationRuleException('Groupe AND/OR invalide');
      }
      return {
        'op': op,
        'conditions': [
          for (final child in children)
            if (child is Map)
              validateCondition(
                Map<String, Object?>.from(child),
                depth: depth + 1,
                counter: count,
              )
            else
              throw const AutomationRuleException('Condition enfant invalide'),
        ],
      };
    }
    final metric = raw['metric'];
    final comparison = raw['comparison'];
    if (metric is! String ||
        !RegExp(r'^[A-Za-z][A-Za-z0-9_.-]{0,79}$').hasMatch(metric) ||
        !const {'gt', 'lt', 'between', 'eq'}.contains(comparison)) {
      throw const AutomationRuleException('Condition simple invalide');
    }
    final hysteresis = raw['hysteresis'] ?? 0;
    if (hysteresis is! num ||
        !hysteresis.toDouble().isFinite ||
        hysteresis < 0 ||
        hysteresis > 10000) {
      throw const AutomationRuleException('Hystérésis invalide');
    }
    if (comparison == 'between') {
      final minimum = raw['min'];
      final maximum = raw['max'];
      if (minimum is! num ||
          maximum is! num ||
          !minimum.toDouble().isFinite ||
          !maximum.toDouble().isFinite ||
          minimum >= maximum) {
        throw const AutomationRuleException('Intervalle invalide');
      }
      return {
        'metric': metric,
        'comparison': comparison,
        'min': minimum.toDouble(),
        'max': maximum.toDouble(),
        'hysteresis': hysteresis.toDouble(),
      };
    }
    final value = raw['value'];
    if (comparison == 'eq') {
      if (value is! bool && (value is! num || !value.toDouble().isFinite)) {
        throw const AutomationRuleException('Valeur EQ invalide');
      }
    } else if (value is! num || !value.toDouble().isFinite) {
      throw const AutomationRuleException('Seuil invalide');
    }
    return {
      'metric': metric,
      'comparison': comparison,
      'value': value is num ? value.toDouble() : value,
      'hysteresis': hysteresis.toDouble(),
    };
  }

  Future<String?> _configureTarget(SensorDevice device) async {
    if (device.transport != 'lora') {
      if (!remote.configureBaseUrl(device.baseUrl)) {
        throw const AutomationRuleException('Adresse locale du nœud invalide');
      }
      return null;
    }
    final link = await loraRepository.getLinkForNode(device.id);
    final gateway =
        link == null ? null : await gatewayRepository.getConfig(link.gatewayId);
    if (gateway == null ||
        !gateway.usesHttp ||
        !remote.configureBaseUrl(gateway.httpBaseUrl ?? '')) {
      throw const AutomationRuleException('Gateway HTTP LoRa requise');
    }
    return device.uid;
  }

  DateTime _safeTime(DateTime minimum) {
    final value = _clock();
    return value.isBefore(minimum) ? minimum : value;
  }
}

class AutomationRuleException implements Exception {
  final String message;

  const AutomationRuleException(this.message);

  @override
  String toString() => message;
}
