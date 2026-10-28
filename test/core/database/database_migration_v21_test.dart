import 'package:flutter_test/flutter_test.dart';
import 'package:garden_journal/core/database/database_helper.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../support/database_test_utils.dart';

void main() {
  sqfliteFfiInit();

  test('creation fraiche v21 ajoute le statut plante morte', () async {
    final db = await openMemoryDatabase();
    addTearDown(db.close);
    await DatabaseHelper.instance.createSchemaForTesting(db);

    final columns = await db.rawQuery('PRAGMA table_info(plants)');
    expect(columns.map((row) => row['name']), contains('is_dead'));
  });

  test('migration v20 vers v21 conserve les plantes existantes', () async {
    final db = await openMemoryDatabase();
    addTearDown(db.close);
    await db.execute('''CREATE TABLE plants (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      is_harvested INTEGER NOT NULL DEFAULT 0
    )''');
    await db.insert('plants', {
      'id': 'plant-1',
      'name': 'Plante conservee',
      'is_harvested': 0,
    });

    await DatabaseHelper.instance.upgradeSchemaForTesting(db, 20);
    await DatabaseHelper.instance.upgradeSchemaForTesting(db, 20);

    final plant = (await db.query('plants')).single;
    expect(plant['name'], 'Plante conservee');
    expect(plant['is_dead'], 0);
  });

  test('migration v21 tolere une base partielle sans table plants', () async {
    final db = await openMemoryDatabase();
    addTearDown(db.close);
    await db.execute('CREATE TABLE partial_state (id TEXT PRIMARY KEY)');

    await DatabaseHelper.instance.upgradeSchemaForTesting(db, 20);

    final tables = await db.query(
      'sqlite_master',
      columns: const ['name'],
      where: 'type = ?',
      whereArgs: const ['table'],
    );
    expect(tables.map((row) => row['name']), contains('partial_state'));
  });
}
