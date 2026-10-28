import 'package:flutter_test/flutter_test.dart';
import 'package:garden_journal/core/database/database_helper.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../support/database_test_utils.dart';

void main() {
  sqfliteFfiInit();

  test('création fraîche v13 ajoute calibrations et alertes persistantes',
      () async {
    final db = await openMemoryDatabase();
    addTearDown(db.close);

    await DatabaseHelper.instance.createSchemaForTesting(db);

    for (final table in const [
      'calibration_records',
      'alert_rules',
      'alert_evaluation_states',
      'alert_events',
    ]) {
      expect(await db.query(table), isEmpty, reason: table);
    }
    expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
  });

  test('migration v12 vers v13 est additive et conserve les mesures', () async {
    final db = await openMemoryDatabase();
    addTearDown(db.close);
    await DatabaseHelper.instance.createSchemaForTesting(db);
    await db.execute('DROP TABLE alert_events');
    await db.execute('DROP TABLE alert_evaluation_states');
    await db.execute('DROP TABLE alert_rules');
    await db.execute('DROP TABLE calibration_records');
    await db.insert('sensor_devices', {
      'id': 'node-v12',
      'uid': 'node-v12',
      'name': 'Nœud v12',
      'zone_id': 'zone-main',
      'base_url': 'http://192.168.1.42',
      'created_at': '2026-07-19T10:00:00Z',
      'updated_at': '2026-07-19T10:00:00Z',
    });
    await db.insert('sensor_readings', {
      'id': 'reading-v12',
      'device_id': 'node-v12',
      'zone_id': 'zone-main',
      'measured_at': 1784455200,
      'temperature_c': 24.0,
      'humidity_percent': 55.0,
      'vpd_kpa': 1.2,
      'mist_on': 0,
      'created_at': '2026-07-19T10:00:00Z',
    });

    await DatabaseHelper.instance.upgradeSchemaForTesting(db, 12);

    expect(await db.query('sensor_readings'), hasLength(1));
    expect(await db.query('calibration_records'), isEmpty);
    expect(await db.query('alert_events'), isEmpty);
    expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
  });
}
