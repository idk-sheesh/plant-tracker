import 'dart:convert';

class DeviceCommand {
  final String id;
  final String deviceId;
  final String? zoneId;
  final String commandType;
  final Map<String, Object?> params;
  final String idempotencyKey;
  final String safetyClass;
  final DateTime requestedAt;
  final DateTime expiresAt;
  final String status;
  final DateTime? nodeAckAt;
  final Map<String, Object?>? nodeResponse;
  final String? errorCode;
  final DateTime createdAt;
  final DateTime updatedAt;

  const DeviceCommand({
    required this.id,
    required this.deviceId,
    this.zoneId,
    required this.commandType,
    required this.params,
    required this.idempotencyKey,
    required this.safetyClass,
    required this.requestedAt,
    required this.expiresAt,
    required this.status,
    this.nodeAckAt,
    this.nodeResponse,
    this.errorCode,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isFinal => const {
        'acknowledged',
        'rejected',
        'expired',
      }.contains(status);

  Map<String, Object?> toMap() => {
        'id': id,
        'device_id': deviceId,
        'zone_id': zoneId,
        'command_type': commandType,
        'params_json': jsonEncode(params),
        'idempotency_key': idempotencyKey,
        'safety_class': safetyClass,
        'requested_at': _seconds(requestedAt),
        'expires_at': _seconds(expiresAt),
        'status': status,
        'node_ack_at': nodeAckAt == null ? null : _seconds(nodeAckAt!),
        'node_response_json':
            nodeResponse == null ? null : jsonEncode(nodeResponse),
        'error_code': errorCode,
        'created_at': createdAt.toUtc().toIso8601String(),
        'updated_at': updatedAt.toUtc().toIso8601String(),
      };

  factory DeviceCommand.fromMap(Map<String, dynamic> map) => DeviceCommand(
        id: map['id'] as String,
        deviceId: map['device_id'] as String,
        zoneId: map['zone_id'] as String?,
        commandType: map['command_type'] as String,
        params: Map<String, Object?>.from(
          jsonDecode(map['params_json'] as String) as Map,
        ),
        idempotencyKey: map['idempotency_key'] as String,
        safetyClass: map['safety_class'] as String,
        requestedAt: _date(map['requested_at'])!,
        expiresAt: _date(map['expires_at'])!,
        status: map['status'] as String,
        nodeAckAt: _date(map['node_ack_at']),
        nodeResponse: map['node_response_json'] == null
            ? null
            : Map<String, Object?>.from(
                jsonDecode(map['node_response_json'] as String) as Map,
              ),
        errorCode: map['error_code'] as String?,
        createdAt: DateTime.parse(map['created_at'] as String).toLocal(),
        updatedAt: DateTime.parse(map['updated_at'] as String).toLocal(),
      );
}

class NodeSchedule {
  final String id;
  final String deviceId;
  final String name;
  final String commandType;
  final String timezone;
  final int daysMask;
  final int startMinute;
  final Map<String, Object?> params;
  final int revision;
  final String scheduleHash;
  final bool isEnabled;
  final String status;
  final DateTime? nodeAckAt;
  final String? nodeAckHash;
  final String? lastError;
  final DateTime createdAt;
  final DateTime updatedAt;

  const NodeSchedule({
    required this.id,
    required this.deviceId,
    required this.name,
    required this.commandType,
    required this.timezone,
    required this.daysMask,
    required this.startMinute,
    required this.params,
    required this.revision,
    required this.scheduleHash,
    required this.isEnabled,
    required this.status,
    this.nodeAckAt,
    this.nodeAckHash,
    this.lastError,
    required this.createdAt,
    required this.updatedAt,
  });

  String get timeLabel => '${(startMinute ~/ 60).toString().padLeft(2, '0')}:'
      '${(startMinute % 60).toString().padLeft(2, '0')}';

  Map<String, Object?> toMap() => {
        'id': id,
        'device_id': deviceId,
        'name': name,
        'command_type': commandType,
        'timezone': timezone,
        'days_mask': daysMask,
        'start_minute': startMinute,
        'params_json': jsonEncode(params),
        'revision': revision,
        'schedule_hash': scheduleHash,
        'is_enabled': isEnabled ? 1 : 0,
        'status': status,
        'node_ack_at': nodeAckAt == null ? null : _seconds(nodeAckAt!),
        'node_ack_hash': nodeAckHash,
        'last_error': lastError,
        'created_at': createdAt.toUtc().toIso8601String(),
        'updated_at': updatedAt.toUtc().toIso8601String(),
      };

  factory NodeSchedule.fromMap(Map<String, dynamic> map) => NodeSchedule(
        id: map['id'] as String,
        deviceId: map['device_id'] as String,
        name: map['name'] as String,
        commandType: map['command_type'] as String,
        timezone: map['timezone'] as String,
        daysMask: map['days_mask'] as int,
        startMinute: map['start_minute'] as int,
        params: Map<String, Object?>.from(
          jsonDecode(map['params_json'] as String) as Map,
        ),
        revision: map['revision'] as int,
        scheduleHash: map['schedule_hash'] as String,
        isEnabled: map['is_enabled'] == 1,
        status: map['status'] as String,
        nodeAckAt: _date(map['node_ack_at']),
        nodeAckHash: map['node_ack_hash'] as String?,
        lastError: map['last_error'] as String?,
        createdAt: DateTime.parse(map['created_at'] as String).toLocal(),
        updatedAt: DateTime.parse(map['updated_at'] as String).toLocal(),
      );
}

int _seconds(DateTime value) => value.toUtc().millisecondsSinceEpoch ~/ 1000;

DateTime? _date(Object? seconds) => seconds == null
    ? null
    : DateTime.fromMillisecondsSinceEpoch(
        (seconds as int) * 1000,
        isUtc: true,
      ).toLocal();
