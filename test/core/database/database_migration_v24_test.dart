import 'package:flutter_test/flutter_test.dart';
import 'package:garden_journal/core/database/database_helper.dart';

import '../../support/database_test_utils.dart';

void main() {
  test('v24 crée les photos des espaces sans appareil caméra', () async {
    final db = await openMemoryDatabase();
    addTearDown(db.close);
    await DatabaseHelper.instance.createSchemaForTesting(db);
    await db.insert('cultivation_zones', {
      'id': 'zone',
      'name': 'Serre',
      'type': 'main',
      'created_at': '2026-10-06T12:00:00Z',
      'updated_at': '2026-10-06T12:00:00Z',
    });
    await db.insert('zone_photos', {
      'id': 'photo',
      'zone_id': 'zone',
      'photo_path': 'managed.jpg',
      'captured_at': 100,
      'caption': 'Avant taille',
      'created_at': '2026-10-06T12:00:00Z'
    });
    expect(await db.query('sensor_devices'), isEmpty);
    expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
  });

  test('upgrade v23 répété préserve les zones et les photos existantes',
      () async {
    final db = await openMemoryDatabase();
    addTearDown(db.close);
    await db.execute('''CREATE TABLE cultivation_zones (
      id TEXT PRIMARY KEY, name TEXT NOT NULL)''');
    await db.insert(
        'cultivation_zones', {'id': 'old-zone', 'name': 'Ancienne serre'});
    await DatabaseHelper.instance.upgradeSchemaForTesting(db, 23);
    await db.insert('zone_photos', {
      'id': 'photo',
      'zone_id': 'old-zone',
      'photo_path': 'managed.jpg',
      'captured_at': 100,
      'created_at': '2026-10-06T12:00:00Z'
    });
    await DatabaseHelper.instance.upgradeSchemaForTesting(db, 23);
    expect(
        (await db.query('cultivation_zones')).single['name'], 'Ancienne serre');
    expect((await db.query('zone_photos')).single['id'], 'photo');
    expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
  });
}
