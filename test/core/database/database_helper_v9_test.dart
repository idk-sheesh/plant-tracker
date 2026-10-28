import 'package:flutter_test/flutter_test.dart';
import 'package:garden_journal/core/database/database_helper.dart';
import 'package:garden_journal/features/sensors/data/repositories/sensor_data_repository.dart';
import 'package:garden_journal/features/sensors/domain/entities/sensor_device.dart';
import 'package:garden_journal/features/sensors/domain/entities/sensor_reading.dart';
import 'package:garden_journal/features/spaces/data/repositories/zone_placement_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../support/database_test_utils.dart' show createLegacySchema;

void main() {
  sqfliteFfiInit();

  Future<Database> openMemoryDatabase() async {
    final db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    await db.execute('PRAGMA foreign_keys = ON');
    return db;
  }

  test('création fraîche v11 ajoute cinq zones sans doublon', () async {
    final db = await openMemoryDatabase();
    addTearDown(db.close);

    await DatabaseHelper.instance.createSchemaForTesting(db);

    final zones = await db.query('cultivation_zones');
    expect(zones, hasLength(5));
    expect(
      zones.map((zone) => zone['type']),
      containsAll(['collection', 'cutting', 'nursery', 'main', 'storage']),
    );
  });

  test('migration v8 conserve appareil et relevé avec zone figée', () async {
    final db = await openMemoryDatabase();
    addTearDown(db.close);
    await createLegacySchema(db, 8, withData: false);
    await db.insert('groups', {
      'id': 'group-1',
      'name': 'Ancienne serre',
      'color': 0,
      'created_at': '2026-01-01T00:00:00Z',
    });
    await db.insert('devices', {
      'id': 'greenhouse-01',
      'name': 'ESP v8',
      'zone_id': 'group-1',
      'ip_address': '192.168.1.42',
      'last_seen_at': 1783947600,
    });
    await db.insert('sensor_readings', {
      'id': 'greenhouse-01-1783947600',
      'device_id': 'greenhouse-01',
      'measured_at': 1783947600,
      'temperature': 24.6,
      'humidity': 57.2,
      'vpd': 1.28,
      'mist_on': 1,
      'fan_percent': 30.0,
    });

    await DatabaseHelper.instance.upgradeSchemaForTesting(db, 8);

    final devices = await db.query('sensor_devices');
    final readings = await db.query('sensor_readings');
    expect(devices.single['uid'], 'greenhouse-01');
    expect(devices.single['zone_id'], 'legacy-group-group-1');
    expect(readings.single['temperature_c'], 24.6);
    expect(readings.single['zone_id'], 'legacy-group-group-1');
    expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
  });

  test('déplacement ferme atomiquement le placement actif précédent', () async {
    final db = await openMemoryDatabase();
    addTearDown(db.close);
    await DatabaseHelper.instance.createSchemaForTesting(db);
    await db.insert('plants', _plant('plant-1'));
    final repository = ZonePlacementRepository(database: db);
    final firstDate = DateTime.utc(2026, 7, 14, 8);
    final secondDate = DateTime.utc(2026, 7, 14, 10);

    await repository.movePlant(
      plantId: 'plant-1',
      plantName: 'Plante test',
      zoneId: 'zone-cutting',
      enteredAt: firstDate,
    );
    await repository.movePlant(
      plantId: 'plant-1',
      plantName: 'Plante test',
      zoneId: 'zone-nursery',
      enteredAt: secondDate,
    );

    final history = await repository.getForPlant('plant-1');
    final active = history.where((placement) => placement.isActive).toList();
    expect(history, hasLength(2));
    expect(active.single.zoneId, 'zone-nursery');
    expect(
      history
          .firstWhere((placement) => placement.zoneId == 'zone-cutting')
          .exitedAt
          ?.toUtc(),
      secondDate,
    );
  });

  test('clôture explicitement un placement actif sans supprimer son historique',
      () async {
    final db = await openMemoryDatabase();
    addTearDown(db.close);
    await DatabaseHelper.instance.createSchemaForTesting(db);
    await db.insert('plants', _plant('plant-close'));
    final repository = ZonePlacementRepository(database: db);
    final enteredAt = DateTime.utc(2026, 7, 14, 8);
    final exitedAt = DateTime.utc(2026, 7, 14, 18);

    await repository.movePlant(
      plantId: 'plant-close',
      plantName: 'Plante à clôturer',
      zoneId: 'zone-main',
      enteredAt: enteredAt,
    );
    final active = (await repository.getForPlant('plant-close')).single;

    await repository.closePlacement(active, exitedAt: exitedAt);

    final history = await repository.getForPlant('plant-close');
    expect(history, hasLength(1));
    expect(history.single.isActive, isFalse);
    expect(history.single.exitedAt?.toUtc(), exitedAt);
    expect(await repository.getActive(), isEmpty);
  });

  test('réconcilie les anciens placements actifs des plantes en fin de cycle',
      () async {
    final db = await openMemoryDatabase();
    addTearDown(db.close);
    await DatabaseHelper.instance.createSchemaForTesting(db);
    await db.insert(
      'plants',
      _plant('plant-ended')
        ..['is_dead'] = 1
        ..['updated_at'] = '2026-07-14T18:00:00Z',
    );
    final repository = ZonePlacementRepository(database: db);
    await repository.movePlant(
      plantId: 'plant-ended',
      plantName: 'Plante terminée',
      zoneId: 'zone-main',
      enteredAt: DateTime.utc(2026, 7, 14, 8),
    );

    final changed = await repository.closePlacementsForEndedPlants();

    expect(changed, 1);
    expect(await repository.getActive(), isEmpty);
    final history = await repository.getForPlant('plant-ended');
    expect(history.single.exitedAt?.toUtc(), DateTime.utc(2026, 7, 14, 18));
  });

  test('upsert des relevés empêche les doublons appareil timestamp', () async {
    final db = await openMemoryDatabase();
    addTearDown(db.close);
    await DatabaseHelper.instance.createSchemaForTesting(db);
    final repository = SensorDataRepository(database: db);
    final now = DateTime.utc(2026, 7, 14, 10);
    final device = SensorDevice(
      id: 'greenhouse-main-01',
      uid: 'greenhouse-main-01',
      name: 'Serre de tomates',
      zoneId: 'zone-main',
      baseUrl: 'http://192.168.1.42',
      createdAt: now,
      updatedAt: now,
    );
    final reading = SensorReading(
      deviceId: device.id,
      temperature: 24.6,
      humidity: 57.2,
      vpd: 1.28,
      timestamp: now,
      mistOn: true,
    );
    await repository.upsertDevice(device);

    final first = await repository.insertReadings(device, [reading]);
    final second = await repository.insertReadings(device, [reading]);
    final rows = await db.query('sensor_readings');

    expect(first, 1);
    expect(second, 0);
    expect(rows, hasLength(1));
    expect(rows.single['zone_id'], 'zone-main');
    expect((await repository.getDevices()).single.zoneId, 'zone-main');
  });

  test('persiste capacités et mesures génériques sans doublon', () async {
    final db = await openMemoryDatabase();
    addTearDown(db.close);
    await DatabaseHelper.instance.createSchemaForTesting(db);
    final repository = SensorDataRepository(database: db);
    final now = DateTime.utc(2026, 7, 14, 10);
    final device = SensorDevice(
      id: 'greenhouse-generic-01',
      uid: 'greenhouse-generic-01',
      name: 'Serre générique',
      zoneId: 'zone-main',
      baseUrl: 'http://192.168.1.43',
      createdAt: now,
      updatedAt: now,
    );
    final reading = SensorReading.fromJson({
      'deviceId': device.uid,
      'timestamp': now.millisecondsSinceEpoch ~/ 1000,
      'temperature': 24.6,
      'humidity': 57.2,
      'capabilities': {
        'water_ph': {
          'type': 'number',
          'label': 'pH eau',
          'unit': 'pH',
          'min': 0,
          'max': 14,
        },
      },
      'measurements': {
        'water_ph': 6.2,
        'reservoir_low': false,
      },
    }, now: DateTime.utc(2026, 7, 14, 11));
    await repository.upsertDevice(device);

    expect(await repository.insertReadings(device, [reading]), 1);
    expect(await repository.insertReadings(device, [reading]), 0);

    final capabilities = await repository.getCapabilitiesForDevice(device.id);
    final measurements = await repository.getMeasurementsForDevice(device.id);
    expect(capabilities, hasLength(2));
    expect(measurements, hasLength(2));
    expect(
      capabilities
          .singleWhere((item) => item.key == 'reservoir_low')
          .displayName,
      'reservoir_low',
    );
    expect(
      measurements
          .singleWhere((item) => item.capabilityKey == 'water_ph')
          .numericValue,
      6.2,
    );
    expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
  });

  test('un groupe ne peut avoir qu’un placement actif', () async {
    final db = await openMemoryDatabase();
    addTearDown(db.close);
    await DatabaseHelper.instance.createSchemaForTesting(db);
    await db.insert('groups', {
      'id': 'group-1',
      'name': 'Lot boutures',
      'color': 0,
      'created_at': '2026-01-01T00:00:00Z',
    });
    final repository = ZonePlacementRepository(database: db);

    await repository.moveGroup(
      groupId: 'group-1',
      groupName: 'Lot boutures',
      zoneId: 'zone-cutting',
    );
    await repository.moveGroup(
      groupId: 'group-1',
      groupName: 'Lot boutures',
      zoneId: 'zone-nursery',
    );

    final history = await repository.getForGroup('group-1');
    expect(history, hasLength(2));
    expect(
        history.where((item) => item.isActive).single.zoneId, 'zone-nursery');
  });
  test('space placements resolve current names and keep snapshots', () async {
    final db = await openMemoryDatabase();
    addTearDown(db.close);
    await DatabaseHelper.instance.createSchemaForTesting(db);
    await db.insert('plants', _plant('plant-rename')..['name'] = 'FJ');
    await db.insert('groups', {
      'id': 'group-rename',
      'name': 'Lot FJ',
      'color': 0,
      'created_at': '2026-01-01T00:00:00Z',
    });
    final repository = ZonePlacementRepository(database: db);

    await repository.movePlant(
      plantId: 'plant-rename',
      plantName: 'FJ',
      zoneId: 'zone-main',
    );
    await repository.moveGroup(
      groupId: 'group-rename',
      groupName: 'Lot FJ',
      zoneId: 'zone-main',
    );
    await db.update(
      'plants',
      {'name': 'Tomate cerise'},
      where: 'id = ?',
      whereArgs: ['plant-rename'],
    );
    await db.update(
      'groups',
      {'name': 'Lot Tomate cerise'},
      where: 'id = ?',
      whereArgs: ['group-rename'],
    );

    final active = await repository.getActive();
    expect(
      active.singleWhere((item) => item.plantId != null).entityName,
      'Tomate cerise',
    );
    expect(
      active.singleWhere((item) => item.groupId != null).entityName,
      'Lot Tomate cerise',
    );
    expect(
      (await repository.getForPlant('plant-rename')).single.entityName,
      'Tomate cerise',
    );
    expect(
      (await repository.getForGroup('group-rename')).single.entityName,
      'Lot Tomate cerise',
    );
    expect(
      (await repository.getForZone('zone-main')).map((item) => item.entityName),
      containsAll(['Tomate cerise', 'Lot Tomate cerise']),
    );

    final stored = await db.query(
      'zone_placements',
      columns: const ['entity_name'],
      where: 'plant_id = ?',
      whereArgs: ['plant-rename'],
    );
    expect(stored.single['entity_name'], 'FJ');

    await db.delete(
      'plants',
      where: 'id = ?',
      whereArgs: ['plant-rename'],
    );
    expect(
      (await repository.getForZone('zone-main'))
          .singleWhere((item) => item.groupId == null)
          .entityName,
      'FJ',
    );
  });
}

Map<String, Object?> _plant(String id) => {
      'id': id,
      'name': 'Plante test',
      'potting_date': '2026-01-01T00:00:00Z',
      'culture_type': 'indoor',
      'qr_code': 'plant:$id',
      'created_at': '2026-01-01T00:00:00Z',
      'updated_at': '2026-01-01T00:00:00Z',
    };
