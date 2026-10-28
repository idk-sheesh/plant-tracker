import 'package:flutter_test/flutter_test.dart';
import 'package:garden_journal/core/database/database_helper.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../support/database_test_utils.dart';

void main() {
  sqfliteFfiInit();

  test('création fraîche v14 ajoute commandes et programmes', () async {
    final db = await openMemoryDatabase();
    addTearDown(db.close);
    await DatabaseHelper.instance.createSchemaForTesting(db);

    expect(await db.query('device_commands'), isEmpty);
    expect(await db.query('node_schedules'), isEmpty);
    expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
  });

  test('migration v13 vers v14 conserve les alertes existantes', () async {
    final db = await openMemoryDatabase();
    addTearDown(db.close);
    await DatabaseHelper.instance.createSchemaForTesting(db);
    await db.execute('DROP TABLE node_schedules');
    await db.execute('DROP TABLE device_commands');
    await db.insert('alert_rules', {
      'id': 'rule-v13',
      'name': 'Règle v13',
      'zone_id': 'zone-main',
      'metric_key': 'temperature_c',
      'comparison': 'gt',
      'threshold_max': 30.0,
      'duration_seconds': 0,
      'hysteresis': 1.0,
      'cooldown_seconds': 900,
      'severity': 'warning',
      'is_enabled': 1,
      'created_at': '2026-07-19T10:00:00Z',
      'updated_at': '2026-07-19T10:00:00Z',
    });

    await DatabaseHelper.instance.upgradeSchemaForTesting(db, 13);

    expect(await db.query('alert_rules'), hasLength(1));
    expect(await db.query('device_commands'), isEmpty);
    expect(await db.query('node_schedules'), isEmpty);
    expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
  });
}
