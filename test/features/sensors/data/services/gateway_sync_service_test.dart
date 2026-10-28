import 'package:flutter_test/flutter_test.dart';
import 'package:garden_journal/core/database/database_helper.dart';
import 'package:garden_journal/features/sensors/data/repositories/gateway_repository.dart';
import 'package:garden_journal/features/sensors/data/services/gateway_sync_service.dart';
import 'package:garden_journal/features/sensors/data/services/gateway_transport.dart';
import 'package:garden_journal/features/sensors/domain/entities/gateway.dart';
import 'package:garden_journal/features/sensors/domain/entities/sensor_device.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../../support/database_test_utils.dart';

void main() {
  sqfliteFfiInit();
  final now = DateTime.utc(2026, 7, 19, 12);

  Map<String, dynamic> envelope({String id = 'msg-1', int cursor = 1}) => {
        'version': 1,
        'messageId': id,
        'gatewayId': 'gateway-uid',
        'cursor': cursor,
        'sentAt': now.toIso8601String(),
        'records': [
          {'type': 'sensor_reading', 'nodeId': 'node-1'}
        ],
      };

  Future<(Database, GatewayConfig)> setup() async {
    final db = await openMemoryDatabase();
    await DatabaseHelper.instance.createSchemaForTesting(db);
    final device = SensorDevice(
      id: 'gateway-device',
      uid: 'gateway-uid',
      name: 'Gateway',
      zoneId: 'zone-main',
      baseUrl: 'http://192.168.1.20',
      deviceKind: 'gateway',
      createdAt: now,
      updatedAt: now,
    );
    await db.insert('sensor_devices', device.toMap());
    final config = GatewayConfig(
      id: 'gateway-config',
      deviceId: device.id,
      transportMode: 'hybrid',
      httpBaseUrl: device.baseUrl,
      mqttHost: '192.168.1.20',
      mqttPort: 8883,
      mqttUseTls: true,
      createdAt: now,
      updatedAt: now,
    );
    await GatewayRepository(database: db).saveConfig(config);
    return (db, config);
  }

  test('HTTP accepte, déduplique, rejette et avance le curseur', () async {
    final (db, config) = await setup();
    addTearDown(db.close);
    var handled = 0;
    final service = GatewaySyncService(
      repository: GatewayRepository(database: db),
      httpSource: _FakeHttpSource([
        envelope(),
        envelope(),
        {...envelope(id: 'bad'), 'gatewayId': 'other-gateway'},
      ]),
      mqttSource: _FakeMqttSource(),
      clock: () => now,
    );

    final result = await service.synchronizeHttp(
      config,
      gatewayUid: 'gateway-uid',
      handler: (_) async => handled++,
    );

    expect(result.accepted, 1);
    expect(result.duplicates, 1);
    expect(result.rejected, 1);
    expect(result.cursor, 1);
    expect(handled, 1);
    final messages =
        await GatewayRepository(database: db).getMessages(config.id);
    expect(messages.where((item) => item.status == 'accepted'), hasLength(1));
    expect(messages.where((item) => item.status == 'rejected'), hasLength(1));
  });

  test('MQTT ne persiste pas le mot de passe et déduplique QoS 1', () async {
    final (db, config) = await setup();
    addTearDown(db.close);
    final mqtt = _FakeMqttSource(payloads: [envelope(), envelope()]);
    var handled = 0;
    final service = GatewaySyncService(
      repository: GatewayRepository(database: db),
      httpSource: _FakeHttpSource(const []),
      mqttSource: mqtt,
      clock: () => now,
    );

    await service.startMqtt(
      config,
      gatewayUid: 'gateway-uid',
      password: 'secret-memory-only',
      handler: (_) async => handled++,
    );
    await Future<void>.delayed(Duration.zero);

    expect(mqtt.passwordSeen, 'secret-memory-only');
    expect(handled, 1);
    final row = (await db.query('gateway_configs')).single;
    expect(row.keys, isNot(contains('mqtt_password')));
    expect(row.values, isNot(contains('secret-memory-only')));
  });

  test('reprend un message après une erreur temporaire sans sauter le suivant',
      () async {
    final (db, config) = await setup();
    addTearDown(db.close);
    final source = _FakeHttpSource([
      envelope(id: 'retry-1', cursor: 1),
      envelope(id: 'after-retry', cursor: 2),
    ]);
    final service = GatewaySyncService(
      repository: GatewayRepository(database: db),
      httpSource: source,
      mqttSource: _FakeMqttSource(),
      clock: () => now,
    );
    var firstAttempt = true;
    final first = await service.synchronizeHttp(
      config,
      gatewayUid: 'gateway-uid',
      handler: (_) async {
        if (firstAttempt) {
          firstAttempt = false;
          throw StateError('indisponible');
        }
      },
    );

    expect(first.cursor, 0);
    expect(first.rejected, 1);
    expect(
      await GatewayRepository(database: db)
          .getMessage(config.id, 'after-retry'),
      isNull,
    );

    final handled = <String>[];
    final second = await service.synchronizeHttp(
      config,
      gatewayUid: 'gateway-uid',
      handler: (message) async => handled.add(message.messageId),
    );

    expect(handled, ['retry-1', 'after-retry']);
    expect(second.accepted, 2);
    expect(second.cursor, 2);
    expect(
      (await GatewayRepository(database: db).getMessage(config.id, 'retry-1'))
          ?.status,
      'accepted',
    );
  });

  test('refuse URL et broker publics', () {
    expect(
      () => validateGatewayHttpUrl('https://example.com'),
      throwsFormatException,
    );
    expect(() => validateGatewayHost('8.8.8.8'), throwsFormatException);
    expect(validateGatewayHost('gateway.local'), 'gateway.local');
  });
}

class _FakeHttpSource implements GatewayHttpSource {
  final List<Object?> values;

  const _FakeHttpSource(this.values);

  @override
  Future<List<Object?>> fetch(GatewayConfig config,
          {required int since}) async =>
      values;
}

class _FakeMqttSource implements GatewayMqttSource {
  final List<Map<String, dynamic>> payloads;
  String? passwordSeen;

  _FakeMqttSource({this.payloads = const []});

  @override
  Future<void> start(
    GatewayConfig config, {
    String? password,
    required Future<void> Function(String topic, String payload) onMessage,
  }) async {
    passwordSeen = password;
    for (final payload in payloads) {
      await onMessage(
        'gardenjournal/${config.deviceId}/messages',
        _encode(payload),
      );
    }
  }

  @override
  Future<void> close() async {}

  static String _encode(Map<String, dynamic> value) {
    final sentAt = value['sentAt'];
    final records = value['records'];
    return '{"version":1,"messageId":"${value['messageId']}",'
        '"gatewayId":"${value['gatewayId']}","cursor":${value['cursor']},'
        '"sentAt":"$sentAt","records":${_records(records)}}';
  }

  static String _records(Object? value) {
    if (value is! List || value.isEmpty) return '[]';
    final record = value.first as Map;
    return '[{"type":"${record['type']}","nodeId":"${record['nodeId']}"}]';
  }
}
