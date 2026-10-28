import 'package:flutter_test/flutter_test.dart';
import 'package:garden_journal/core/database/database_helper.dart';
import 'package:garden_journal/features/sensors/data/repositories/gateway_repository.dart';
import 'package:garden_journal/features/sensors/data/repositories/lora_repository.dart';
import 'package:garden_journal/features/sensors/data/repositories/sensor_data_repository.dart';
import 'package:garden_journal/features/sensors/data/services/lora_gateway_ingest_service.dart';
import 'package:garden_journal/features/sensors/domain/entities/gateway.dart';
import 'package:garden_journal/features/sensors/domain/entities/sensor_device.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../../support/database_test_utils.dart';

void main() {
  sqfliteFfiInit();
  final now = DateTime.utc(2026, 7, 19, 12);

  Future<(Database, GatewayConfig, LoRaGatewayIngestService)> setup({
    bool linkNode = true,
  }) async {
    final db = await openMemoryDatabase();
    await DatabaseHelper.instance.createSchemaForTesting(db);
    final gatewayDevice = SensorDevice(
      id: 'gateway-device',
      uid: 'gateway-uid',
      name: 'Gateway',
      zoneId: 'zone-main',
      baseUrl: 'http://192.168.1.20',
      deviceKind: 'gateway',
      createdAt: now,
      updatedAt: now,
    );
    final node = SensorDevice(
      id: 'node-device',
      uid: 'node-lora',
      name: 'Nœud LoRa',
      zoneId: 'zone-main',
      baseUrl: '',
      transport: 'lora',
      createdAt: now,
      updatedAt: now,
    );
    await db.insert('sensor_devices', gatewayDevice.toMap());
    await db.insert('sensor_devices', node.toMap());
    final config = GatewayConfig(
      id: 'gateway-config',
      deviceId: gatewayDevice.id,
      transportMode: 'http',
      httpBaseUrl: gatewayDevice.baseUrl,
      createdAt: now,
      updatedAt: now,
    );
    await GatewayRepository(database: db).saveConfig(config);
    final lora = LoRaRepository(database: db);
    if (linkNode) {
      await lora.linkNode(
        gatewayId: config.id,
        nodeDeviceId: node.id,
        loraAddress: node.uid,
      );
    }
    return (
      db,
      config,
      LoRaGatewayIngestService(
        loraRepository: lora,
        sensorRepository: SensorDataRepository(database: db),
        clock: () => now,
      ),
    );
  }

  GatewayEnvelope envelope({
    int counter = 1,
    String session = 'session-0001',
    String nodeId = 'node-lora',
    bool authenticated = true,
    Map<String, Object>? measurements,
  }) {
    final payload = {
      'version': 1,
      'messageId': 'message-$session-$counter-$nodeId',
      'gatewayId': 'gateway-uid',
      'cursor': counter,
      'sentAt': now.toIso8601String(),
      'records': [
        {
          'type': 'lora_reading',
          'protocolVersion': 1,
          'authenticated': authenticated,
          'nodeId': nodeId,
          'sessionId': session,
          'frameCounter': counter,
          'sentAt': now.toIso8601String(),
          'rssi': -91,
          'snr': 7.5,
          'measurements': measurements ??
              {
                'air_temp_c': 24.6,
                'air_humidity_pct': 61.0,
                'water_ph': 6.2,
                'battery_v': 4.02,
              },
        }
      ],
    };
    return GatewayEnvelope.parse(
      payload,
      expectedGatewayId: 'gateway-uid',
      now: now,
    );
  }

  test('une trame liée alimente mesures, climat, santé et compteur', () async {
    final (db, config, service) = await setup();
    addTearDown(db.close);

    final result = await service.handleEnvelope(config, envelope());

    expect(result.accepted, 1);
    expect(await db.query('sensor_readings'), hasLength(1));
    expect(await db.query('sensor_measurements'), hasLength(6));
    expect(await db.query('device_health_snapshots'), hasLength(1));
    expect((await db.query('lora_packets')).single['status'], 'accepted');
    expect((await db.query('gateway_nodes')).single['last_frame_counter'], 1);
  });

  test('déduplique un paquet QoS et bloque un compteur rejoué', () async {
    final (db, config, service) = await setup();
    addTearDown(db.close);
    await service.handleEnvelope(config, envelope(counter: 5));

    final duplicate =
        await service.handleEnvelope(config, envelope(counter: 5));
    final replay = await service.handleEnvelope(config, envelope(counter: 4));

    expect(duplicate.duplicates, 1);
    expect(replay.replays, 1);
    expect(await db.query('sensor_readings'), hasLength(1));
    expect(
      (await db.query('lora_packets')).map((row) => row['status']),
      containsAll(['accepted', 'replay']),
    );
  });

  test('met en quarantaine un nœud non associé', () async {
    final (db, config, service) = await setup(linkNode: false);
    addTearDown(db.close);

    final result = await service.handleEnvelope(config, envelope());

    expect(result.unknownNodes, 1);
    expect(await db.query('sensor_measurements'), isEmpty);
    expect((await db.query('lora_packets')).single['status'], 'unknown_node');
  });

  test('mesures génériques seules restent persistées sans inventer du climat',
      () async {
    final (db, config, service) = await setup();
    addTearDown(db.close);

    final result = await service.handleEnvelope(
      config,
      envelope(measurements: {'water_ph': 6.1, 'water_tds_ppm': 820}),
    );

    expect(result.accepted, 1);
    expect(await db.query('sensor_readings'), isEmpty);
    expect(await db.query('sensor_measurements'), hasLength(4));
  });

  test('refuse une trame non authentifiée par la gateway', () async {
    final (db, config, service) = await setup();
    addTearDown(db.close);

    final result = await service.handleEnvelope(
      config,
      envelope(authenticated: false),
    );

    expect(result.rejected, 1);
    expect(await db.query('sensor_measurements'), isEmpty);
  });
}
