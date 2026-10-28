import 'package:flutter_test/flutter_test.dart';
import 'package:garden_journal/core/database/database_helper.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../support/database_test_utils.dart';

void main() {
  sqfliteFfiInit();

  test('création fraîche v19 ajoute l’audit des exports de cycle', () async {
    final db = await openMemoryDatabase();
    addTearDown(db.close);
    await DatabaseHelper.instance.createSchemaForTesting(db);

    expect(await db.query('cycle_exports'), isEmpty);
    final commandColumns =
        await db.rawQuery('PRAGMA table_info(device_commands)');
    expect(commandColumns.map((row) => row['name']), contains('zone_id'));
    expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
  });

  test('migration v18 vers v19 conserve les règles automatiques', () async {
    final db = await openMemoryDatabase();
    addTearDown(db.close);
    await DatabaseHelper.instance.createSchemaForTesting(db);
    await db.execute('DROP TABLE cycle_exports');
    await db.insert('sensor_devices', {
      'id': 'node-v19',
      'uid': 'node-v19',
      'name': 'Nœud v19',
      'zone_id': 'zone-collection',
      'base_url': 'http://192.168.1.42',
      'created_at': '2026-07-19T10:00:00Z',
      'updated_at': '2026-07-19T10:00:00Z',
    });
    await db.insert('automation_rules', {
      'id': 'rule-v18',
      'device_id': 'node-v19',
      'name': 'Ventilation',
      'condition_json':
          '{"metric":"temperature_c","comparison":"gt","value":28}',
      'action_type': 'fan.set',
      'action_params_json': '{"percent":50}',
      'duration_seconds': 60,
      'cooldown_seconds': 900,
      'max_runs_per_day': 10,
      'revision': 1,
      'rule_hash': 'a' * 64,
      'is_enabled': 1,
      'status': 'active',
      'node_ack_at': 1784455200,
      'node_ack_hash': 'a' * 64,
      'created_at': '2026-07-19T10:00:00Z',
      'updated_at': '2026-07-19T10:00:00Z',
    });

    await DatabaseHelper.instance.upgradeSchemaForTesting(db, 18);

    expect(await db.query('automation_rules'), hasLength(1));
    expect(await db.query('cycle_exports'), isEmpty);
    expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
  });
}
