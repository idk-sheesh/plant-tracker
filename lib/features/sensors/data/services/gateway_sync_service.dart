import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';

import '../../domain/entities/gateway.dart';
import '../repositories/gateway_repository.dart';
import 'gateway_transport.dart';

typedef GatewayEnvelopeHandler = Future<void> Function(
    GatewayEnvelope envelope);

class GatewaySyncResult {
  final int accepted;
  final int duplicates;
  final int rejected;
  final int cursor;

  const GatewaySyncResult({
    required this.accepted,
    required this.duplicates,
    required this.rejected,
    required this.cursor,
  });
}

class GatewaySyncService {
  final GatewayRepository repository;
  final GatewayHttpSource httpSource;
  final GatewayMqttSource mqttSource;
  final Uuid _uuid;
  final DateTime Function() _clock;

  GatewaySyncService({
    GatewayRepository? repository,
    GatewayHttpSource? httpSource,
    GatewayMqttSource? mqttSource,
    Uuid uuid = const Uuid(),
    DateTime Function()? clock,
  })  : repository = repository ?? GatewayRepository(),
        httpSource = httpSource ?? GatewayHttpTransport(),
        mqttSource = mqttSource ?? GatewayMqttTransport(),
        _uuid = uuid,
        _clock = clock ?? DateTime.now;

  Future<GatewaySyncResult> synchronizeHttp(
    GatewayConfig config, {
    required String gatewayUid,
    required GatewayEnvelopeHandler handler,
  }) async {
    if (!config.usesHttp) {
      throw const GatewayTransportException('Transport HTTP désactivé');
    }
    final rawMessages = await httpSource.fetch(
      config,
      since: config.lastHttpCursor,
    );
    var accepted = 0;
    var duplicates = 0;
    var rejected = 0;
    var cursor = config.lastHttpCursor;
    for (final raw in rawMessages) {
      try {
        final outcome = await ingest(
          config,
          gatewayUid: gatewayUid,
          raw: raw,
          transport: 'http',
          handler: handler,
        );
        cursor = outcome.cursor > cursor ? outcome.cursor : cursor;
        outcome.accepted ? accepted++ : duplicates++;
      } catch (error) {
        rejected++;
        if (error is! GatewayEnvelopeHandledException) {
          await _storeRejected(config, raw, 'http', error);
        }
        // Le curseur ne doit jamais dépasser une enveloppe non appliquée.
        // La prochaine synchronisation reprendra ce message.
        break;
      }
    }
    if (cursor > config.lastHttpCursor) {
      await repository.updateCursor(config.id, cursor);
    }
    return GatewaySyncResult(
      accepted: accepted,
      duplicates: duplicates,
      rejected: rejected,
      cursor: cursor,
    );
  }

  Future<void> startMqtt(
    GatewayConfig config, {
    required String gatewayUid,
    String? password,
    required GatewayEnvelopeHandler handler,
  }) async {
    if (!config.usesMqtt) {
      throw const GatewayTransportException('Transport MQTT désactivé');
    }
    await mqttSource.start(
      config,
      password: password,
      onMessage: (topic, payload) async {
        Object? raw;
        try {
          if (utf8.encode(payload).length > 1024 * 1024) {
            throw const FormatException('Message MQTT trop volumineux');
          }
          raw = jsonDecode(payload);
          await ingest(
            config,
            gatewayUid: gatewayUid,
            raw: raw,
            transport: 'mqtt',
            topic: topic,
            handler: handler,
          );
        } catch (error) {
          if (error is! GatewayEnvelopeHandledException) {
            await _storeRejected(config, raw ?? payload, 'mqtt', error,
                topic: topic);
          }
        }
      },
    );
  }

  Future<_IngestOutcome> ingest(
    GatewayConfig config, {
    required String gatewayUid,
    required Object? raw,
    required String transport,
    String? topic,
    required GatewayEnvelopeHandler handler,
  }) async {
    final envelope = GatewayEnvelope.parse(
      raw,
      expectedGatewayId: gatewayUid,
      now: _clock(),
    );
    final payload = envelope.encode();
    final hash = sha256.convert(utf8.encode(payload)).toString();
    final receivedAt = _clock();
    final record = GatewayMessageRecord(
      id: _uuid.v4(),
      gatewayId: config.id,
      transport: transport,
      topic: topic,
      messageId: envelope.messageId,
      payloadHash: hash,
      sentAt: envelope.sentAt,
      receivedAt: receivedAt,
      status: 'processing',
      payloadJson: payload,
      createdAt: receivedAt,
    );
    final reservedId = await repository.reserveMessage(record);
    if (reservedId == null) {
      return _IngestOutcome(accepted: false, cursor: envelope.cursor);
    }
    try {
      await handler(envelope);
      await repository.finishMessage(reservedId, status: 'accepted');
      return _IngestOutcome(accepted: true, cursor: envelope.cursor);
    } catch (error) {
      await repository.finishMessage(
        reservedId,
        status: 'rejected',
        errorCode: error.runtimeType.toString(),
      );
      throw GatewayEnvelopeHandledException(error);
    }
  }

  Future<void> _storeRejected(
    GatewayConfig config,
    Object? raw,
    String transport,
    Object error, {
    String? topic,
  }) async {
    final payload = raw is String ? raw : jsonEncode(raw);
    final bounded = payload.length > 1024 * 1024
        ? payload.substring(0, 1024 * 1024)
        : payload;
    final hash = sha256.convert(utf8.encode(bounded)).toString();
    final now = _clock();
    final record = GatewayMessageRecord(
      id: _uuid.v4(),
      gatewayId: config.id,
      transport: transport,
      topic: topic,
      messageId: 'invalid-${hash.substring(0, 32)}',
      payloadHash: hash,
      sentAt: now,
      receivedAt: now,
      status: 'rejected',
      errorCode: error.runtimeType.toString(),
      payloadJson: bounded,
      createdAt: now,
    );
    await repository.storeRejectedMessage(record);
  }

  Future<void> close() => mqttSource.close();
}

class _IngestOutcome {
  final bool accepted;
  final int cursor;

  const _IngestOutcome({required this.accepted, required this.cursor});
}

class GatewayEnvelopeHandledException implements Exception {
  final Object cause;

  const GatewayEnvelopeHandledException(this.cause);

  @override
  String toString() => cause.toString();
}
