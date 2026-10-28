import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:garden_journal/core/database/database_helper.dart';
import 'package:garden_journal/features/sensors/data/repositories/device_control_repository.dart';
import 'package:garden_journal/features/sensors/data/repositories/gateway_repository.dart';
import 'package:garden_journal/features/sensors/data/repositories/lora_repository.dart';
import 'package:garden_journal/features/sensors/data/repositories/sensor_repository.dart';
import 'package:garden_journal/features/sensors/data/services/safe_device_control_service.dart';
import 'package:garden_journal/features/sensors/domain/entities/sensor_device.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../../support/database_test_utils.dart';

void main() {
  sqfliteFfiInit();
  final now = DateTime.utc(2026, 7, 19, 12);

  Future<(Database, SensorDevice)> setup() async {
    final db = await openMemoryDatabase();
    await DatabaseHelper.instance.createSchemaForTesting(db);
    final device = SensorDevice(
      id: 'node-control',
      uid: 'node-control',
      name: 'Nœud contrôle',
      zoneId: 'zone-main',
      baseUrl: 'http://192.168.1.42',
      createdAt: now,
      updatedAt: now,
    );
    await db.insert('sensor_devices', device.toMap());
    return (db, device);
  }

  test('acquitte et journalise une commande avec identifiants concordants',
      () async {
    final (db, device) = await setup();
    addTearDown(db.close);
    late Map<String, dynamic> requestBody;
    final service = SafeDeviceControlService(
      local: DeviceControlRepository(database: db),
      remote: SensorRepository(client: MockClient((request) async {
        requestBody = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({
            'commandId': requestBody['commandId'],
            'idempotencyKey': requestBody['idempotencyKey'],
            'status': 'accepted',
          }),
          200,
        );
      })),
      clock: () => now,
    );

    final command = await service.execute(
      device: device,
      commandType: 'fan.set',
      params: const {'percent': 45},
    );

    expect(requestBody['expiresAt'], isNotNull);
    expect(command.status, 'acknowledged');
    expect(command.zoneId, 'zone-main');
    expect(command.nodeAckAt, isNotNull);
    expect(await db.query('device_commands'), hasLength(1));
  });

  test('refuse commande inconnue et irrigation non confirmée avant réseau',
      () async {
    final (db, device) = await setup();
    addTearDown(db.close);
    var calls = 0;
    final service = SafeDeviceControlService(
      local: DeviceControlRepository(database: db),
      remote: SensorRepository(client: MockClient((_) async {
        calls++;
        return http.Response('{}', 200);
      })),
      clock: () => now,
    );

    await expectLater(
      service.execute(
        device: device,
        commandType: 'shell.run',
        params: const {'value': 'rm'},
      ),
      throwsA(isA<SafeControlException>()),
    );
    await expectLater(
      service.execute(
        device: device,
        commandType: 'irrigation.pulse',
        params: const {'durationSeconds': 10, 'maxVolumeMl': 500},
      ),
      throwsA(isA<SafeControlException>()),
    );
    expect(calls, 0);
    expect(await db.query('device_commands'), isEmpty);
  });

  test('un retry conserve exactement la clé d’idempotence', () async {
    final (db, device) = await setup();
    addTearDown(db.close);
    final sentKeys = <String>[];
    var calls = 0;
    final local = DeviceControlRepository(database: db);
    final service = SafeDeviceControlService(
      local: local,
      remote: SensorRepository(client: MockClient((request) async {
        calls++;
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        sentKeys.add(body['idempotencyKey'] as String);
        if (calls == 1) return http.Response('{}', 503);
        return http.Response(
          jsonEncode({
            'commandId': body['commandId'],
            'idempotencyKey': body['idempotencyKey'],
            'status': 'duplicate',
          }),
          200,
        );
      })),
      clock: () => now,
    );

    await expectLater(
      service.execute(
        device: device,
        commandType: 'mist.set',
        params: const {'state': true},
      ),
      throwsException,
    );
    final failed = (await local.getCommands(device.id)).single;
    final retried = await service.retry(device: device, command: failed);

    expect(retried.status, 'acknowledged');
    expect(sentKeys, hasLength(2));
    expect(sentKeys.toSet(), hasLength(1));
    expect(await db.query('device_commands'), hasLength(1));
  });

  test('programme actif seulement si révision et hash sont acquittés',
      () async {
    final (db, device) = await setup();
    addTearDown(db.close);
    late Map<String, dynamic> requestBody;
    final local = DeviceControlRepository(database: db);
    final service = SafeDeviceControlService(
      local: local,
      remote: SensorRepository(client: MockClient((request) async {
        requestBody = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({
            'scheduleId': requestBody['scheduleId'],
            'revision': requestBody['revision'],
            'scheduleHash': requestBody['scheduleHash'],
            'status': 'accepted',
          }),
          200,
        );
      })),
      clock: () => now,
    );

    final schedule = await service.syncSchedule(
      device: device,
      name: 'Lumière matin',
      commandType: 'light.set',
      params: const {'state': true},
      timezone: 'Europe/Berlin',
      daysMask: 127,
      startMinute: 8 * 60,
    );

    expect(schedule.status, 'active');
    expect(schedule.nodeAckHash, schedule.scheduleHash);
    expect(requestBody['scheduleHash'], hasLength(64));
    expect((await local.getSchedules(device.id)).single.status, 'active');
  });

  test('route commandes et programmes LoRa par la gateway HTTP liée', () async {
    final db = await openMemoryDatabase();
    addTearDown(db.close);
    await DatabaseHelper.instance.createSchemaForTesting(db);
    final gatewayDevice = SensorDevice(
      id: 'gateway-control',
      uid: 'gateway-control',
      name: 'Gateway contrôle',
      zoneId: 'zone-main',
      baseUrl: 'http://192.168.1.20',
      deviceKind: 'gateway',
      createdAt: now,
      updatedAt: now,
    );
    final loraDevice = SensorDevice(
      id: 'node-lora-control',
      uid: 'lora-address-42',
      name: 'Nœud LoRa contrôle',
      zoneId: 'zone-main',
      baseUrl: '',
      transport: 'lora',
      createdAt: now,
      updatedAt: now,
    );
    await db.insert('sensor_devices', gatewayDevice.toMap());
    await db.insert('sensor_devices', loraDevice.toMap());
    await db.insert('gateway_configs', {
      'id': 'gateway-config-control',
      'device_id': gatewayDevice.id,
      'transport_mode': 'http',
      'http_base_url': gatewayDevice.baseUrl,
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
    });
    await db.insert('gateway_nodes', {
      'gateway_id': 'gateway-config-control',
      'node_device_id': loraDevice.id,
      'lora_address': loraDevice.uid,
      'joined_at': now.millisecondsSinceEpoch ~/ 1000,
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
    });
    final paths = <String>[];
    final targets = <String>[];
    final remote = SensorRepository(client: MockClient((request) async {
      paths.add(request.url.path);
      expect(request.url.host, '192.168.1.20');
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      targets.add(body['targetNodeId'] as String);
      if (request.url.path == '/commands') {
        return http.Response(
          jsonEncode({
            'commandId': body['commandId'],
            'idempotencyKey': body['idempotencyKey'],
            'status': 'accepted',
          }),
          200,
        );
      }
      return http.Response(
        jsonEncode({
          'scheduleId': body['scheduleId'],
          'revision': body['revision'],
          'scheduleHash': body['scheduleHash'],
          'status': 'accepted',
        }),
        200,
      );
    }));
    final service = SafeDeviceControlService(
      local: DeviceControlRepository(database: db),
      remote: remote,
      gatewayRepository: GatewayRepository(database: db),
      loraRepository: LoRaRepository(database: db),
      clock: () => now,
    );

    await service.execute(
      device: loraDevice,
      commandType: 'fan.set',
      params: const {'percent': 40},
    );
    await service.syncSchedule(
      device: loraDevice,
      name: 'Lumière LoRa',
      commandType: 'light.set',
      params: const {'state': true},
      timezone: 'Europe/Berlin',
      daysMask: 127,
      startMinute: 480,
    );

    expect(paths, ['/commands', '/schedules']);
    expect(targets, everyElement(loraDevice.uid));
  });
}
