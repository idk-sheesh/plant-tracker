import 'dart:convert';

class AutomationRule {
  final String id;
  final String deviceId;
  final String name;
  final Map<String, Object?> condition;
  final String actionType;
  final Map<String, Object?> actionParams;
  final int durationSeconds;
  final int cooldownSeconds;
  final int maxRunsPerDay;
  final int revision;
  final String ruleHash;
  final bool isEnabled;
  final String status;
  final DateTime? nodeAckAt;
  final String? nodeAckHash;
  final String? lastError;
  final DateTime createdAt;
  final DateTime updatedAt;

  const AutomationRule({
    required this.id,
    required this.deviceId,
    required this.name,
    required this.condition,
    required this.actionType,
    required this.actionParams,
    required this.durationSeconds,
    required this.cooldownSeconds,
    required this.maxRunsPerDay,
    required this.revision,
    required this.ruleHash,
    required this.isEnabled,
    required this.status,
    this.nodeAckAt,
    this.nodeAckHash,
    this.lastError,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, Object?> toMap() => {
        'id': id,
        'device_id': deviceId,
        'name': name,
        'condition_json': jsonEncode(condition),
        'action_type': actionType,
        'action_params_json': jsonEncode(actionParams),
        'duration_seconds': durationSeconds,
        'cooldown_seconds': cooldownSeconds,
        'max_runs_per_day': maxRunsPerDay,
        'revision': revision,
        'rule_hash': ruleHash,
        'is_enabled': isEnabled ? 1 : 0,
        'status': status,
        'node_ack_at': nodeAckAt == null
            ? null
            : nodeAckAt!.toUtc().millisecondsSinceEpoch ~/ 1000,
        'node_ack_hash': nodeAckHash,
        'last_error': lastError,
        'created_at': createdAt.toUtc().toIso8601String(),
        'updated_at': updatedAt.toUtc().toIso8601String(),
      };

  factory AutomationRule.fromMap(Map<String, dynamic> map) => AutomationRule(
        id: map['id'] as String,
        deviceId: map['device_id'] as String,
        name: map['name'] as String,
        condition: Map<String, Object?>.from(
          jsonDecode(map['condition_json'] as String) as Map,
        ),
        actionType: map['action_type'] as String,
        actionParams: Map<String, Object?>.from(
          jsonDecode(map['action_params_json'] as String) as Map,
        ),
        durationSeconds: map['duration_seconds'] as int,
        cooldownSeconds: map['cooldown_seconds'] as int,
        maxRunsPerDay: map['max_runs_per_day'] as int,
        revision: map['revision'] as int,
        ruleHash: map['rule_hash'] as String,
        isEnabled: map['is_enabled'] == 1,
        status: map['status'] as String,
        nodeAckAt: map['node_ack_at'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(
                (map['node_ack_at'] as int) * 1000,
                isUtc: true,
              ).toLocal(),
        nodeAckHash: map['node_ack_hash'] as String?,
        lastError: map['last_error'] as String?,
        createdAt: DateTime.parse(map['created_at'] as String).toLocal(),
        updatedAt: DateTime.parse(map['updated_at'] as String).toLocal(),
      );
}
