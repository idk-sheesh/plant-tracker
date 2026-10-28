import 'package:flutter_test/flutter_test.dart';
import 'package:garden_journal/core/database/database_helper.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../support/database_test_utils.dart';

void main() {
  sqfliteFfiInit();

  test('création fraîche v11 ajoute mesures et capacités génériques', () async {
    final db = await openMemoryDatabase();
    addTearDown(db.close);

    await DatabaseHelper.instance.createSchemaForTesting(db);

    final tables = await db.query(
      'sqlite_master',
      columns: const ['name'],
      where: "type = 'table'",
    );
    final names = tables.map((row) => row['name']).toSet();
    expect(names, contains('sensor_device_capabilities'));
    expect(names, contains('sensor_measurements'));
    expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
  });

  test('migration v10 est additive et conserve les relevés existants',
      () async {
    final db = await openMemoryDatabase();
    addTearDown(db.close);
    await db.execute('''CREATE TABLE cultivation_zones (
      id TEXT PRIMARY KEY)''');
    await db.execute('''CREATE TABLE sensor_devices (
      id TEXT PRIMARY KEY)''');
    await db.execute('''CREATE TABLE sensor_readings (
      id TEXT PRIMARY KEY,
      device_id TEXT NOT NULL,
      measured_at INTEGER NOT NULL,
      temperature_c REAL NOT NULL,
      humidity_percent REAL NOT NULL,
      vpd_kpa REAL NOT NULL)''');
    await db.insert('sensor_devices', {'id': 'greenhouse-01'});
    await db.insert('sensor_readings', {
      'id': 'reading-1',
      'device_id': 'greenhouse-01',
      'measured_at': 1783947600,
      'temperature_c': 24.6,
      'humidity_percent': 57.2,
      'vpd_kpa': 1.28,
    });

    await DatabaseHelper.instance.upgradeSchemaForTesting(db, 10);
    await DatabaseHelper.instance.upgradeSchemaForTesting(db, 10);

    expect(await db.query('sensor_readings'), hasLength(1));
    expect(await db.query('sensor_device_capabilities'), isEmpty);
    expect(await db.query('sensor_measurements'), isEmpty);
    expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
  });
}
