import 'dart:convert';

class GatewayConfig {
  final String id;
  final String deviceId;
  final String transportMode;
  final String? httpBaseUrl;
  final String? mqttHost;
  final int? mqttPort;
  final bool mqttUseTls;
  final String mqttTopicPrefix;
  final String? mqttUsername;
  final int lastHttpCursor;
  final DateTime? lastMqttAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  const GatewayConfig({
    required this.id,
    required this.deviceId,
    required this.transportMode,
    this.httpBaseUrl,
    this.mqttHost,
    this.mqttPort,
    this.mqttUseTls = true,
    this.mqttTopicPrefix = 'gardenjournal',
    this.mqttUsername,
    this.lastHttpCursor = 0,
    this.lastMqttAt,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get usesHttp => transportMode == 'http' || transportMode == 'hybrid';
  bool get usesMqtt => transportMode == 'mqtt' || transportMode == 'hybrid';

  Map<String, Object?> toMap() => {
        'id': id,
        'device_id': deviceId,
        'transport_mode': transportMode,
        'http_base_url': httpBaseUrl,
        'mqtt_host': mqttHost,
        'mqtt_port': mqttPort,
        'mqtt_use_tls': mqttUseTls ? 1 : 0,
        'mqtt_topic_prefix': mqttTopicPrefix,
        'mqtt_username': mqttUsername,
        'last_http_cursor': lastHttpCursor,
        'last_mqtt_at': lastMqttAt == null ? null : _seconds(lastMqttAt!),
        'created_at': createdAt.toUtc().toIso8601String(),
        'updated_at': updatedAt.toUtc().toIso8601String(),
      };

  factory GatewayConfig.fromMap(Map<String, dynamic> map) => GatewayConfig(
        id: map['id'] as String,
        deviceId: map['device_id'] as String,
        transportMode: map['transport_mode'] as String,
        httpBaseUrl: map['http_base_url'] as String?,
        mqttHost: map['mqtt_host'] as String?,
        mqttPort: map['mqtt_port'] as int?,
        mqttUseTls: map['mqtt_use_tls'] == 1,
        mqttTopicPrefix: map['mqtt_topic_prefix'] as String,
        mqttUsername: map['mqtt_username'] as String?,
        lastHttpCursor: map['last_http_cursor'] as int? ?? 0,
        lastMqttAt: _date(map['last_mqtt_at']),
        createdAt: DateTime.parse(map['created_at'] as String).toLocal(),
        updatedAt: DateTime.parse(map['updated_at'] as String).toLocal(),
      );
}

class GatewayEnvelope {
  final String messageId;
  final String gatewayId;
  final int cursor;
  final DateTime sentAt;
  final List<Map<String, dynamic>> records;
  final Map<String, dynamic> canonicalPayload;

  const GatewayEnvelope({
    required this.messageId,
    required this.gatewayId,
    required this.cursor,
    required this.sentAt,
    required this.records,
    required this.canonicalPayload,
  });

  factory GatewayEnvelope.parse(
    Object? raw, {
    required String expectedGatewayId,
    DateTime? now,
  }) {
    if (raw is! Map) throw const FormatException('Enveloppe gateway invalide');
    final json = Map<String, dynamic>.from(raw);
    if (json['version'] != 1) {
      throw const FormatException('Version gateway non supportée');
    }
    final messageId = _identifier(json['messageId'], 'messageId');
    final gatewayId = _identifier(json['gatewayId'], 'gatewayId');
    if (gatewayId != expectedGatewayId) {
      throw const FormatException('Identité gateway inattendue');
    }
    final cursor = json['cursor'];
    if (cursor is! int || cursor < 0) {
      throw const FormatException('Curseur gateway invalide');
    }
    final sentRaw = json['sentAt'];
    if (sentRaw is! String) throw const FormatException('Date gateway absente');
    final sentAt = DateTime.tryParse(sentRaw)?.toUtc();
    if (sentAt == null) throw const FormatException('Date gateway invalide');
    final reference = (now ?? DateTime.now()).toUtc();
    if (sentAt.isAfter(reference.add(const Duration(minutes: 5))) ||
        sentAt.isBefore(reference.subtract(const Duration(days: 366)))) {
      throw const FormatException('Date gateway hors fenêtre');
    }
    final rawRecords = json['records'];
    if (rawRecords is! List || rawRecords.length > 1000) {
      throw const FormatException('Liste de messages gateway invalide');
    }
    final records = <Map<String, dynamic>>[];
    for (final record in rawRecords) {
      if (record is! Map)
        throw const FormatException('Message gateway invalide');
      records.add(Map<String, dynamic>.from(record));
    }
    return GatewayEnvelope(
      messageId: messageId,
      gatewayId: gatewayId,
      cursor: cursor,
      sentAt: sentAt.toLocal(),
      records: List.unmodifiable(records),
      canonicalPayload: Map.unmodifiable(json),
    );
  }

  String encode() => jsonEncode(canonicalPayload);
}

class GatewayMessageRecord {
  final String id;
  final String gatewayId;
  final String transport;
  final String? topic;
  final String messageId;
  final String payloadHash;
  final DateTime sentAt;
  final DateTime receivedAt;
  final String status;
  final String? errorCode;
  final String payloadJson;
  final DateTime createdAt;

  const GatewayMessageRecord({
    required this.id,
    required this.gatewayId,
    required this.transport,
    this.topic,
    required this.messageId,
    required this.payloadHash,
    required this.sentAt,
    required this.receivedAt,
    required this.status,
    this.errorCode,
    required this.payloadJson,
    required this.createdAt,
  });

  Map<String, Object?> toMap() => {
        'id': id,
        'gateway_id': gatewayId,
        'transport': transport,
        'topic': topic,
        'message_id': messageId,
        'payload_hash': payloadHash,
        'sent_at': _seconds(sentAt),
        'received_at': _seconds(receivedAt),
        'status': status,
        'error_code': errorCode,
        'payload_json': payloadJson,
        'created_at': createdAt.toUtc().toIso8601String(),
      };

  factory GatewayMessageRecord.fromMap(Map<String, dynamic> map) =>
      GatewayMessageRecord(
        id: map['id'] as String,
        gatewayId: map['gateway_id'] as String,
        transport: map['transport'] as String,
        topic: map['topic'] as String?,
        messageId: map['message_id'] as String,
        payloadHash: map['payload_hash'] as String,
        sentAt: _date(map['sent_at'])!,
        receivedAt: _date(map['received_at'])!,
        status: map['status'] as String,
        errorCode: map['error_code'] as String?,
        payloadJson: map['payload_json'] as String,
        createdAt: DateTime.parse(map['created_at'] as String).toLocal(),
      );
}

String _identifier(Object? value, String name) {
  if (value is! String ||
      !RegExp(r'^[A-Za-z0-9][A-Za-z0-9_.:-]{0,127}$').hasMatch(value)) {
    throw FormatException('$name invalide');
  }
  return value;
}

int _seconds(DateTime value) => value.toUtc().millisecondsSinceEpoch ~/ 1000;

DateTime? _date(Object? seconds) => seconds == null
    ? null
    : DateTime.fromMillisecondsSinceEpoch(
        (seconds as int) * 1000,
        isUtc: true,
      ).toLocal();
