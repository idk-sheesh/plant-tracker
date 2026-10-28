import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

import '../../domain/entities/gateway.dart';

abstract interface class GatewayHttpSource {
  Future<List<Object?>> fetch(GatewayConfig config, {required int since});
}

class GatewayHttpTransport implements GatewayHttpSource {
  final http.Client _client;
  final bool _ownsClient;

  GatewayHttpTransport({http.Client? client})
      : _client = client ?? http.Client(),
        _ownsClient = client == null;

  @override
  Future<List<Object?>> fetch(
    GatewayConfig config, {
    required int since,
  }) async {
    final base = validateGatewayHttpUrl(config.httpBaseUrl);
    final uri = base.replace(
      path: '/gateway/messages',
      queryParameters: {'since': since.toString()},
    );
    final response = await _client.get(
      uri,
      headers: const {'Accept': 'application/json'},
    ).timeout(const Duration(seconds: 12));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw GatewayTransportException(
          'HTTP ${response.statusCode} /gateway/messages');
    }
    if (response.bodyBytes.length > 5 * 1024 * 1024) {
      throw const GatewayTransportException('Réponse gateway trop volumineuse');
    }
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    final values = switch (decoded) {
      List<dynamic> list => list,
      Map<dynamic, dynamic> map when map['messages'] is List =>
        map['messages'] as List<dynamic>,
      _ => throw const GatewayTransportException(
          'Réponse /gateway/messages invalide',
        ),
    };
    if (values.length > 1000) {
      throw const GatewayTransportException('Trop de messages gateway');
    }
    return List<Object?>.from(values);
  }

  void close() {
    if (_ownsClient) _client.close();
  }
}

abstract interface class GatewayMqttSource {
  Future<void> start(
    GatewayConfig config, {
    String? password,
    required Future<void> Function(String topic, String payload) onMessage,
  });

  Future<void> close();
}

class GatewayMqttTransport implements GatewayMqttSource {
  MqttServerClient? _client;
  StreamSubscription<List<MqttReceivedMessage<MqttMessage>>>? _subscription;

  @override
  Future<void> start(
    GatewayConfig config, {
    String? password,
    required Future<void> Function(String topic, String payload) onMessage,
  }) async {
    await close();
    final host = validateGatewayHost(config.mqttHost);
    final topicPrefix = validateTopicPrefix(config.mqttTopicPrefix);
    final port = config.mqttPort ?? (config.mqttUseTls ? 8883 : 1883);
    final clientId = 'gt-${config.id.hashCode.abs().toRadixString(16)}';
    final client = MqttServerClient.withPort(host, clientId, port)
      ..logging(on: false)
      ..setProtocolV311()
      ..keepAlivePeriod = 30
      ..connectTimeoutPeriod = 5000
      ..secure = config.mqttUseTls
      ..connectionMessage = MqttConnectMessage()
          .withClientIdentifier(clientId)
          .startClean()
          .withWillQos(MqttQos.atLeastOnce);
    _client = client;
    final status = await client.connect(config.mqttUsername, password);
    if (status?.state != MqttConnectionState.connected) {
      client.disconnect();
      _client = null;
      throw GatewayTransportException('Connexion MQTT refusée: $status');
    }
    final topic = '$topicPrefix/${config.deviceId}/messages';
    final subscription = client.subscribe(topic, MqttQos.atLeastOnce);
    if (subscription == null) {
      await close();
      throw const GatewayTransportException('Abonnement MQTT refusé');
    }
    final updates = client.updates;
    if (updates == null) {
      await close();
      throw const GatewayTransportException('Flux MQTT indisponible');
    }
    _subscription = updates.listen((messages) {
      for (final message in messages) {
        final published = message.payload;
        if (published is! MqttPublishMessage) continue;
        final bytes = published.payload.message;
        if (bytes.length > 1024 * 1024) continue;
        final payload = MqttPublishPayload.bytesToStringAsString(bytes);
        unawaited(onMessage(message.topic, payload));
      }
    });
  }

  @override
  Future<void> close() async {
    await _subscription?.cancel();
    _subscription = null;
    _client?.disconnect();
    _client = null;
  }
}

Uri validateGatewayHttpUrl(String? raw) {
  final value = raw?.trim();
  final uri = value == null ? null : Uri.tryParse(value);
  if (uri == null ||
      !const {'http', 'https'}.contains(uri.scheme) ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      (uri.path.isNotEmpty && uri.path != '/') ||
      uri.hasQuery ||
      uri.hasFragment ||
      !_isLocalHost(uri.host)) {
    throw const FormatException('URL HTTP locale de gateway invalide');
  }
  return uri.replace(path: '');
}

String validateGatewayHost(String? raw) {
  final value = raw?.trim() ?? '';
  if (value.isEmpty || value.length > 253 || !_isLocalHost(value)) {
    throw const FormatException('Hôte MQTT local invalide');
  }
  return value;
}

String validateTopicPrefix(String raw) {
  final value = raw.trim();
  if (!RegExp(r'^[A-Za-z0-9_-]{1,64}$').hasMatch(value)) {
    throw const FormatException('Préfixe MQTT invalide');
  }
  return value;
}

bool _isLocalHost(String host) {
  final normalized = host.toLowerCase();
  if (normalized == 'localhost' || normalized == '127.0.0.1') return true;
  if (normalized.endsWith('.local')) return true;
  final parts = normalized.split('.');
  if (parts.length != 4) return false;
  final values = parts.map(int.tryParse).toList();
  if (values.any((item) => item == null || item < 0 || item > 255)) {
    return false;
  }
  final first = values[0]!;
  final second = values[1]!;
  return first == 10 ||
      first == 127 ||
      first == 192 && second == 168 ||
      first == 172 && second >= 16 && second <= 31;
}

class GatewayTransportException implements Exception {
  final String message;

  const GatewayTransportException(this.message);

  @override
  String toString() => message;
}
