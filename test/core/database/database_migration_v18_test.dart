import 'package:flutter_test/flutter_test.dart';
import 'package:garden_journal/core/database/database_helper.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../support/database_test_utils.dart';

void main() {
  sqfliteFfiInit();

  test('création fraîche v18 ajoute règles et journal d’exécution', () async {
    final db = await openMemoryDatabase();
    addTearDown(db.close);
    await DatabaseHelper.instance.createSchemaForTesting(db);

    expect(await db.query('automation_rules'), isEmpty);
    expect(await db.query('automation_executions'), isEmpty);
    expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
  });

  test('migration v17 vers v18 conserve l’état OTA', () async {
    final db = await openMemoryDatabase();
    addTearDown(db.close);
    await DatabaseHelper.instance.createSchemaForTesting(db);
    await db.execute('DROP TABLE automation_executions');
    await db.execute('DROP TABLE automation_rules');
    await db.insert('sensor_devices', {
      'id': 'node-v18',
      'uid': 'node-v18',
      'name': 'Nœud v18',
      'zone_id': 'zone-main',
      'base_url': 'http://192.168.1.42',
      'created_at': '2026-07-19T10:00:00Z',
      'updated_at': '2026-07-19T10:00:00Z',
    });
    await db.insert('ota_device_states', {
      'device_id': 'node-v18',
      'current_version': '1.4.0',
      'current_build': 14,
      'highest_accepted_build': 14,
      'last_known_good_build': 13,
      'hardware_model': 'GT-S3',
      'bootloader_version': '1.2.0',
      'rollback_supported': 1,
      'updated_at': '2026-07-19T10:00:00Z',
    });

    await DatabaseHelper.instance.upgradeSchemaForTesting(db, 17);

    expect(await db.query('ota_device_states'), hasLength(1));
    expect(await db.query('automation_rules'), isEmpty);
    expect(await db.query('automation_executions'), isEmpty);
    expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
  });
}
