import 'package:flutter_test/flutter_test.dart';
import 'package:garden_journal/core/database/database_helper.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../support/database_test_utils.dart';

void main() {
  sqfliteFfiInit();

  test('création fraîche v17 ajoute confiance, état et audit OTA', () async {
    final db = await openMemoryDatabase();
    addTearDown(db.close);
    await DatabaseHelper.instance.createSchemaForTesting(db);

    expect(await db.query('ota_trusted_keys'), isEmpty);
    expect(await db.query('ota_device_states'), isEmpty);
    expect(await db.query('ota_updates'), isEmpty);
    expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
  });

  test('migration v16 vers v17 conserve les associations LoRa', () async {
    final db = await openMemoryDatabase();
    addTearDown(db.close);
    await DatabaseHelper.instance.createSchemaForTesting(db);
    await db.execute('DROP TABLE ota_updates');
    await db.execute('DROP TABLE ota_device_states');
    await db.execute('DROP TABLE ota_trusted_keys');
    await db.insert('sensor_devices', {
      'id': 'gateway',
      'uid': 'gateway',
      'name': 'Gateway',
      'zone_id': 'zone-main',
      'base_url': 'http://192.168.1.20',
      'device_kind': 'gateway',
      'created_at': '2026-07-19T10:00:00Z',
      'updated_at': '2026-07-19T10:00:00Z',
    });
    await db.insert('sensor_devices', {
      'id': 'node',
      'uid': 'node',
      'name': 'Nœud',
      'zone_id': 'zone-main',
      'base_url': '',
      'transport': 'lora',
      'created_at': '2026-07-19T10:00:00Z',
      'updated_at': '2026-07-19T10:00:00Z',
    });
    await db.insert('gateway_configs', {
      'id': 'config',
      'device_id': 'gateway',
      'transport_mode': 'http',
      'http_base_url': 'http://192.168.1.20',
      'created_at': '2026-07-19T10:00:00Z',
      'updated_at': '2026-07-19T10:00:00Z',
    });
    await db.insert('gateway_nodes', {
      'gateway_id': 'config',
      'node_device_id': 'node',
      'lora_address': 'node',
      'joined_at': 1784455200,
      'created_at': '2026-07-19T10:00:00Z',
      'updated_at': '2026-07-19T10:00:00Z',
    });

    await DatabaseHelper.instance.upgradeSchemaForTesting(db, 16);

    expect(await db.query('gateway_nodes'), hasLength(1));
    expect(await db.query('ota_updates'), isEmpty);
    expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
  });
}
