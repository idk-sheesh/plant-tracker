import 'package:flutter_test/flutter_test.dart';
import 'package:garden_journal/core/database/database_helper.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../support/database_test_utils.dart';

void main() {
  sqfliteFfiInit();

  test('création fraîche v22 ajoute les métadonnées caméra', () async {
    final db = await openMemoryDatabase();
    addTearDown(db.close);
    await DatabaseHelper.instance.createSchemaForTesting(db);

    final tables = await db.query(
      'sqlite_master',
      columns: const ['name'],
      where: 'type = ? AND name = ?',
      whereArgs: const ['table', 'camera_snapshots'],
    );
    expect(tables, hasLength(1));
    final columns = await db.rawQuery('PRAGMA table_info(camera_snapshots)');
    expect(
      columns.map((row) => row['name']),
      containsAll(['device_id', 'zone_id', 'captured_at', 'sha256']),
    );
  });

  test('migration v21 vers v22 conserve les appareils et ajoute les photos',
      () async {
    final db = await openMemoryDatabase();
    addTearDown(db.close);
    await db.execute('''CREATE TABLE cultivation_zones (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL
    )''');
    await db.execute('''CREATE TABLE sensor_devices (
      id TEXT PRIMARY KEY,
      uid TEXT NOT NULL UNIQUE,
      name TEXT NOT NULL,
      zone_id TEXT,
      FOREIGN KEY (zone_id) REFERENCES cultivation_zones(id)
    )''');
    await db.insert('cultivation_zones', {'id': 'zone-main', 'name': 'Serre'});
    await db.insert('sensor_devices', {
      'id': 'cam-01',
      'uid': 'cam-01',
      'name': 'Caméra',
      'zone_id': 'zone-main',
    });

    await DatabaseHelper.instance.upgradeSchemaForTesting(db, 21);
    await DatabaseHelper.instance.upgradeSchemaForTesting(db, 21);
    await db.insert('camera_snapshots', {
      'id': 'snap_1',
      'device_id': 'cam-01',
      'zone_id': 'zone-main',
      'captured_at': 1787227200,
      'sha256': List.filled(64, 'a').join(),
      'size_bytes': 2048,
      'created_at': '2026-08-20T12:00:00Z',
    });

    expect((await db.query('sensor_devices')).single['name'], 'Caméra');
    expect((await db.query('camera_snapshots')).single['device_id'], 'cam-01');
  });

  test('migration v22 tolère une base partielle sans tables parentes',
      () async {
    final db = await openMemoryDatabase();
    addTearDown(db.close);
    await db.execute('CREATE TABLE partial_state (id TEXT PRIMARY KEY)');

    await DatabaseHelper.instance.upgradeSchemaForTesting(db, 21);

    final cameraTables = await db.query(
      'sqlite_master',
      where: 'type = ? AND name = ?',
      whereArgs: const ['table', 'camera_snapshots'],
    );
    expect(cameraTables, isEmpty);
  });
}
