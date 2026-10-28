import 'package:flutter_test/flutter_test.dart';
import 'package:garden_journal/core/database/database_helper.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../support/database_test_utils.dart';

void main() {
  sqfliteFfiInit();

  for (final sourceVersion in const [1, 2, 4, 6, 7, 8]) {
    test('migration v$sourceVersion vers v10 conserve les données', () async {
      final db = await openMemoryDatabase();
      addTearDown(db.close);
      await createLegacySchema(db, sourceVersion);

      await _upgradeInTransaction(db, sourceVersion);

      expect(await db.query('groups'), hasLength(2));
      expect(await db.query('plants'), hasLength(1));
      expect(await db.query('actions'), hasLength(1));
      expect(
        await db.query('action_photos'),
        hasLength(sourceVersion >= 4 ? 1 : 0),
      );
      expect((await db.query('plants')).single['is_harvested'], 1);
      expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
      final actionColumns = await db.rawQuery('PRAGMA table_info(actions)');
      expect(actionColumns.map((row) => row['name']),
          contains('harvest_weight_fresh'));
      expect(actionColumns.map((row) => row['name']),
          contains('repot_container_type'));
      final indexes = await db.query('sqlite_master', where: "type = 'index'");
      expect(
        indexes.map((row) => row['name']),
        containsAll([
          'idx_plants_group_id',
          'idx_actions_plant_timestamp',
          'idx_action_photos_action_id',
        ]),
      );
      if (sourceVersion == 8) {
        expect(await db.query('sensor_devices'), hasLength(1));
        expect(await db.query('sensor_readings'), hasLength(1));
      }
    });
  }

  test('migration partielle conserve les colonnes v10 déjà présentes',
      () async {
    final db = await openMemoryDatabase();
    addTearDown(db.close);
    await createLegacySchema(db, 7);
    await db
        .execute('ALTER TABLE actions ADD COLUMN harvest_weight_fresh REAL');
    await db
        .execute('ALTER TABLE actions ADD COLUMN repot_container_type TEXT');
    await db.update('actions', {
      'harvest_weight_fresh': 120.5,
      'repot_container_type': 'pot_tissu',
    });

    await _upgradeInTransaction(db, 7);

    final action = (await db.query('actions')).single;
    expect(action['harvest_weight_fresh'], 120.5);
    expect(action['repot_container_type'], 'pot_tissu');
  });

  test('table temporaire interrompue est reconstruite sans perte', () async {
    final db = await openMemoryDatabase();
    addTearDown(db.close);
    await createLegacySchema(db, 8);
    await db.execute('CREATE TABLE sensor_readings_v9 (id TEXT PRIMARY KEY)');
    await db.insert('sensor_readings_v9', {'id': 'stale'});

    await _upgradeInTransaction(db, 8);

    expect(await db.query('sensor_readings'), hasLength(1));
    expect(
      await db.query(
        'sqlite_master',
        where: "type = 'table' AND name = 'sensor_readings_v9'",
      ),
      isEmpty,
    );
  });

  test('doublons capteur provoquent un rollback sans suppression source',
      () async {
    final db = await openMemoryDatabase();
    addTearDown(db.close);
    await createLegacySchema(
      db,
      8,
      allowDuplicateSensorTimestamp: true,
    );
    await db.insert('sensor_readings', {
      'id': 'reading-duplicate',
      'device_id': 'sensor-1',
      'measured_at': 1783947600,
      'temperature': 25.0,
      'humidity': 56.0,
      'vpd': 1.3,
    });

    await expectLater(_upgradeInTransaction(db, 8), throwsA(isA<Exception>()));

    expect(await db.query('sensor_readings'), hasLength(2));
    final columns = await db.rawQuery('PRAGMA table_info(sensor_readings)');
    expect(columns.map((row) => row['name']), contains('temperature'));
    expect(columns.map((row) => row['name']), isNot(contains('temperature_c')));
  });

  test('relation orpheline provoque un rollback complet', () async {
    final db = await openMemoryDatabase();
    addTearDown(db.close);
    await createLegacySchema(db, 8, withData: false);
    await db.execute('PRAGMA foreign_keys = OFF');
    await db.insert('actions', {
      'id': 'orphan',
      'plant_id': 'missing',
      'action_type': 'observation',
      'timestamp': '2026-01-01T00:00:00Z',
      'created_at': '2026-01-01T00:00:00Z',
    });
    await db.execute('PRAGMA foreign_keys = ON');

    await expectLater(_upgradeInTransaction(db, 8), throwsStateError);

    expect(await db.query('actions'), hasLength(1));
    expect(
      await db.query(
        'sqlite_master',
        where: "type = 'table' AND name = 'actions_v10'",
      ),
      isEmpty,
    );
  });
}

Future<void> _upgradeInTransaction(Database db, int oldVersion) async {
  await db.execute('BEGIN IMMEDIATE');
  try {
    await DatabaseHelper.instance.upgradeSchemaForTesting(db, oldVersion);
    await db.execute('COMMIT');
  } catch (error, stackTrace) {
    await db.execute('ROLLBACK');
    Error.throwWithStackTrace(error, stackTrace);
  }
}
