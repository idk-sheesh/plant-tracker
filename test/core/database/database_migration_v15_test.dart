import 'package:flutter_test/flutter_test.dart';
import 'package:garden_journal/core/database/database_helper.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../support/database_test_utils.dart';

void main() {
  sqfliteFfiInit();

  test('création fraîche v15 ajoute configuration et journal gateway',
      () async {
    final db = await openMemoryDatabase();
    addTearDown(db.close);
    await DatabaseHelper.instance.createSchemaForTesting(db);

    expect(await db.query('gateway_configs'), isEmpty);
    expect(await db.query('gateway_messages'), isEmpty);
    expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
  });

  test('migration v14 vers v15 conserve le journal des commandes', () async {
    final db = await openMemoryDatabase();
    addTearDown(db.close);
    await DatabaseHelper.instance.createSchemaForTesting(db);
    await db.execute('DROP TABLE gateway_messages');
    await db.execute('DROP TABLE gateway_configs');
    await db.insert('device_commands', {
      'id': 'command-v14',
      'device_id': 'node-v14',
      'command_type': 'mist.set',
      'params_json': '{"state":true}',
      'idempotency_key': 'idem-v14',
      'safety_class': 'standard',
      'requested_at': 1784455200,
      'expires_at': 1784455290,
      'status': 'failed',
      'created_at': '2026-07-19T10:00:00Z',
      'updated_at': '2026-07-19T10:00:00Z',
    });

    await DatabaseHelper.instance.upgradeSchemaForTesting(db, 14);

    expect(await db.query('device_commands'), hasLength(1));
    expect(await db.query('gateway_configs'), isEmpty);
    expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
  });
}
