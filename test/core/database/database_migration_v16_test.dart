import 'package:flutter_test/flutter_test.dart';
import 'package:garden_journal/core/database/database_helper.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../support/database_test_utils.dart';

void main() {
  sqfliteFfiInit();

  test('création fraîche v16 ajoute associations et paquets LoRa', () async {
    final db = await openMemoryDatabase();
    addTearDown(db.close);
    await DatabaseHelper.instance.createSchemaForTesting(db);

    expect(await db.query('gateway_nodes'), isEmpty);
    expect(await db.query('lora_packets'), isEmpty);
    expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
  });

  test('migration v15 vers v16 conserve la configuration gateway', () async {
    final db = await openMemoryDatabase();
    addTearDown(db.close);
    await DatabaseHelper.instance.createSchemaForTesting(db);
    await db.execute('DROP TABLE lora_packets');
    await db.execute('DROP TABLE gateway_nodes');
    await db.insert('sensor_devices', {
      'id': 'gateway-v15',
      'uid': 'gateway-v15',
      'name': 'Gateway v15',
      'zone_id': 'zone-main',
      'base_url': 'http://192.168.1.20',
      'device_kind': 'gateway',
      'created_at': '2026-07-19T10:00:00Z',
      'updated_at': '2026-07-19T10:00:00Z',
    });
    await db.insert('gateway_configs', {
      'id': 'config-v15',
      'device_id': 'gateway-v15',
      'transport_mode': 'http',
      'http_base_url': 'http://192.168.1.20',
      'created_at': '2026-07-19T10:00:00Z',
      'updated_at': '2026-07-19T10:00:00Z',
    });

    await DatabaseHelper.instance.upgradeSchemaForTesting(db, 15);

    expect(await db.query('gateway_configs'), hasLength(1));
    expect(await db.query('gateway_nodes'), isEmpty);
    expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
  });
}
