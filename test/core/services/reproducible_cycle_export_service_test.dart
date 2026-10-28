import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:garden_journal/core/database/database_helper.dart';
import 'package:garden_journal/core/services/reproducible_cycle_export_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../support/database_test_utils.dart';

void main() {
  sqfliteFfiInit();
  final start = DateTime.utc(2026, 7, 1);
  final end = DateTime.utc(2026, 7, 10);
  final inside = DateTime.utc(2026, 7, 5, 12);
  int seconds(DateTime value) => value.millisecondsSinceEpoch ~/ 1000;

  Future<Database> setup() async {
    final db = await openMemoryDatabase();
    await DatabaseHelper.instance.createSchemaForTesting(db);
    await db.insert('groups', {
      'id': 'group-cycle',
      'name': 'Lot cycle',
      'color': 1,
      'created_at': '2026-06-01T00:00:00Z',
    });
    await db.insert('plants', {
      'id': 'plant-cycle',
      'name': 'Plante cycle',
      'potting_date': '2026-06-01T00:00:00Z',
      'culture_type': 'indoor',
      'group_id': 'group-cycle',
      'qr_code': 'plant:plant-cycle',
      'created_at': '2026-06-01T00:00:00Z',
      'updated_at': '2026-07-01T00:00:00Z',
    });
    await db.insert('zone_placements', {
      'id': 'placement-cycle',
      'zone_id': 'zone-collection',
      'plant_id': 'plant-cycle',
      'entity_name': 'Plante cycle',
      'entered_at': seconds(DateTime.utc(2026, 6, 25)),
      'exited_at': seconds(DateTime.utc(2026, 7, 8)),
      'created_at': '2026-06-25T00:00:00Z',
      'updated_at': '2026-07-08T00:00:00Z',
    });
    await db.insert('sensor_devices', {
      'id': 'node-cycle',
      'uid': 'node-cycle',
      'name': 'Nœud cycle',
      'zone_id': 'zone-collection',
      'base_url': 'http://192.168.1.42',
      'firmware_version': '1.2.3',
      'model': 'GT-S3',
      'created_at': '2026-06-01T00:00:00Z',
      'updated_at': '2026-07-01T00:00:00Z',
    });
    await db.insert('sensor_device_capabilities', {
      'device_id': 'node-cycle',
      'capability_key': 'ph',
      'display_name': 'pH',
      'value_type': 'number',
      'minimum_value': 0.0,
      'maximum_value': 14.0,
      'is_writable': 0,
      'metadata_json': '{}',
      'updated_at': '2026-07-01T00:00:00Z',
    });
    await db.insert('actions', {
      'id': 'action-inside',
      'plant_id': 'plant-cycle',
      'action_type': 'arrosage',
      'timestamp': inside.toIso8601String(),
      'quantity': 2.0,
      'quantity_unit': 'L',
      'notes': 'Action incluse',
      'created_at': inside.toIso8601String(),
    });
    await db.insert('action_photos', {
      'id': 'photo-private',
      'action_id': 'action-inside',
      'plant_id': 'plant-cycle',
      'photo_path': r'C:\private\photo.jpg',
      'created_at': inside.toIso8601String(),
    });
    await db.insert('actions', {
      'id': 'action-end-excluded',
      'plant_id': 'plant-cycle',
      'action_type': 'observation',
      'timestamp': end.toIso8601String(),
      'created_at': end.toIso8601String(),
    });
    await db.insert('sensor_readings', {
      'id': 'climate-inside',
      'device_id': 'node-cycle',
      'zone_id': 'zone-collection',
      'measured_at': seconds(inside),
      'temperature_c': 26.0,
      'humidity_percent': 58.0,
      'vpd_kpa': 1.35,
      'mist_on': 0,
      'created_at': inside.toIso8601String(),
    });
    await db.insert('sensor_measurements', {
      'id': 'ph-inside',
      'device_id': 'node-cycle',
      'zone_id': 'zone-collection',
      'capability_key': 'ph',
      'measured_at': seconds(inside.add(const Duration(minutes: 1))),
      'value_type': 'number',
      'numeric_value': 6.2,
      'quality': 'calibrated',
      'created_at': inside.toIso8601String(),
    });
    await db.insert('alert_events', {
      'id': 'alert-inside',
      'rule_id': 'rule-snapshot',
      'device_id': 'node-cycle',
      'zone_id': 'zone-collection',
      'metric_key': 'temperature_c',
      'severity': 'warning',
      'message': 'Température haute',
      'observed_value': 30.0,
      'started_at': seconds(inside),
      'last_observed_at': seconds(inside.add(const Duration(minutes: 5))),
      'resolved_at': seconds(inside.add(const Duration(minutes: 10))),
      'created_at': inside.toIso8601String(),
    });
    await db.insert('device_commands', {
      'id': 'command-inside',
      'device_id': 'node-cycle',
      'zone_id': 'zone-collection',
      'command_type': 'fan.set',
      'params_json': '{"percent":50}',
      'idempotency_key': 'idempotency-cycle',
      'safety_class': 'standard',
      'requested_at': seconds(inside),
      'expires_at': seconds(inside.add(const Duration(minutes: 1))),
      'status': 'acknowledged',
      'node_ack_at': seconds(inside.add(const Duration(seconds: 1))),
      'node_response_json': '{"internal":"not exported"}',
      'created_at': inside.toIso8601String(),
      'updated_at': inside.toIso8601String(),
    });
    await db.insert('automation_executions', {
      'id': 'automatic-inside',
      'rule_id': 'rule-snapshot',
      'device_id': 'node-cycle',
      'executed_at': seconds(inside.add(const Duration(minutes: 2))),
      'command_id': 'node-command-1',
      'observed_values_json': '{"temperature_c":30}',
      'status': 'acknowledged',
      'created_at': inside.toIso8601String(),
    });
    await db.insert('calibration_records', {
      'id': 'calibration-cycle',
      'device_id': 'node-cycle',
      'capability_key': 'ph',
      'calibration_type': 'two_point',
      'calibrated_at': seconds(DateTime.utc(2026, 6, 30)),
      'reference_values_json': '[4.0,7.0]',
      'coefficients_json': '{"slope":1.0,"offset":0.0}',
      'node_ack_at': seconds(DateTime.utc(2026, 6, 30, 0, 0, 1)),
      'node_config_hash': 'b' * 64,
      'created_at': '2026-06-30T00:00:01Z',
    });
    return db;
  }

  test('combine les quatre familles, bornes et preuves de reproduction',
      () async {
    final db = await setup();
    addTearDown(db.close);
    var clockCalls = 0;
    final service = ReproducibleCycleExportService(
      database: db,
      clock: () => DateTime.utc(2026, 7, 19, 12, clockCalls++),
    );

    final first = await service.buildExport(
      plantId: 'plant-cycle',
      periodStart: start,
      periodEnd: end,
    );
    final second = await service.buildExport(
      plantId: 'plant-cycle',
      periodStart: start,
      periodEnd: end,
    );
    final inspection = ReproducibleCycleExportService.inspect(first.bytes);
    final decoded =
        jsonDecode(utf8.decode(first.bytes)) as Map<String, dynamic>;
    final content = decoded['content'] as Map<String, dynamic>;

    expect(first.contentSha256, second.contentSha256);
    expect(inspection.contentSha256, first.contentSha256);
    expect(first.counts, {
      'actions': 1,
      'measurements': 2,
      'alerts': 1,
      'commands': 1,
      'automatedCommands': 1,
      'calibrations': 1,
    });
    expect((content['actions'] as List).single['photoCount'], 1);
    expect((content['commands'] as List).single['zoneAssociation'],
        'zone_snapshot');
    expect(jsonEncode(decoded), isNot(contains(r'C:\private')));
    expect(jsonEncode(decoded), isNot(contains('node_response_json')));
    expect(jsonEncode(decoded), isNot(contains('base_url')));
    expect(await db.query('cycle_exports'), hasLength(2));

    final chronology = (content['chronology'] as List)
        .map((item) => (item as Map<String, dynamic>)['at'] as String)
        .toList();
    expect(chronology, orderedEquals([...chronology]..sort()));
  });

  test('détecte toute altération du contenu', () async {
    final db = await setup();
    addTearDown(db.close);
    final result =
        await ReproducibleCycleExportService(database: db).buildExport(
      plantId: 'plant-cycle',
      periodStart: start,
      periodEnd: end,
      recordAudit: false,
    );
    final decoded =
        jsonDecode(utf8.decode(result.bytes)) as Map<String, dynamic>;
    final content = decoded['content'] as Map<String, dynamic>;
    final actions = content['actions'] as List<dynamic>;
    (actions.single as Map<String, dynamic>)['quantity'] = 999;
    final tampered = Uint8List.fromList(utf8.encode(jsonEncode(decoded)));

    expect(
      () => ReproducibleCycleExportService.inspect(tampered),
      throwsA(isA<CycleExportException>()),
    );
  });

  test('signale explicitement un placement hérité du groupe actuel', () async {
    final db = await setup();
    addTearDown(db.close);
    await db.delete('zone_placements');
    await db.insert('zone_placements', {
      'id': 'group-placement',
      'zone_id': 'zone-collection',
      'group_id': 'group-cycle',
      'entity_name': 'Lot cycle',
      'entered_at': seconds(DateTime.utc(2026, 6, 25)),
      'created_at': '2026-06-25T00:00:00Z',
      'updated_at': '2026-06-25T00:00:00Z',
    });

    final result =
        await ReproducibleCycleExportService(database: db).buildExport(
      plantId: 'plant-cycle',
      periodStart: start,
      periodEnd: end,
      recordAudit: false,
    );
    final decoded =
        jsonDecode(utf8.decode(result.bytes)) as Map<String, dynamic>;
    final content = decoded['content'] as Map<String, dynamic>;
    final selection = content['selection'] as Map<String, dynamic>;
    final placements = selection['placements'] as List<dynamic>;

    expect(
        (placements.single as Map<String, dynamic>)['source'], 'current_group');
  });
}
