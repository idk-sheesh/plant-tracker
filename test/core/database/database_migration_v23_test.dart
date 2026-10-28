import 'package:flutter_test/flutter_test.dart';
import 'package:garden_journal/core/database/database_helper.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../support/database_test_utils.dart';

void main() {
  sqfliteFfiInit();

  test('création fraîche v23 ajoute le chemin facultatif des photos caméra',
      () async {
    final db = await openMemoryDatabase();
    addTearDown(db.close);
    await DatabaseHelper.instance.createSchemaForTesting(db);

    final columns = await db.rawQuery('PRAGMA table_info(camera_snapshots)');
    expect(columns.map((row) => row['name']), contains('photo_path'));
  });

  test('migration v22 vers v23 conserve les clichés existants', () async {
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
    await db.execute('''CREATE TABLE camera_snapshots (
      id TEXT PRIMARY KEY,
      device_id TEXT NOT NULL,
      zone_id TEXT,
      captured_at INTEGER NOT NULL,
      sha256 TEXT NOT NULL,
      size_bytes INTEGER NOT NULL,
      created_at TEXT NOT NULL
    )''');
    await db.insert('camera_snapshots', {
      'id': 'snap-v22',
      'device_id': 'cam-01',
      'zone_id': 'zone-main',
      'captured_at': 1787227200,
      'sha256': 'a' * 64,
      'size_bytes': 2048,
      'created_at': '2026-08-20T12:00:00Z',
    });

    await DatabaseHelper.instance.upgradeSchemaForTesting(db, 22);
    await DatabaseHelper.instance.upgradeSchemaForTesting(db, 22);

    final columns = await db.rawQuery('PRAGMA table_info(camera_snapshots)');
    expect(columns.map((row) => row['name']), contains('photo_path'));
    final snapshot = (await db.query('camera_snapshots')).single;
    expect(snapshot['id'], 'snap-v22');
    expect(snapshot['photo_path'], isNull);
  });
}
