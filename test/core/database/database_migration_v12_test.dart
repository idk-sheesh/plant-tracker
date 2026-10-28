import 'package:flutter_test/flutter_test.dart';
import 'package:garden_journal/core/database/database_helper.dart';
import 'package:garden_journal/features/sensors/data/repositories/sensor_data_repository.dart';
import 'package:garden_journal/features/sensors/domain/entities/device_health_snapshot.dart';
import 'package:garden_journal/features/sensors/domain/entities/sensor_device.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../support/database_test_utils.dart';

void main() {
  sqfliteFfiInit();

  test('création fraîche v12 ajoute identité BLE et santé', () async {
    final db = await openMemoryDatabase();
    addTearDown(db.close);

    await DatabaseHelper.instance.createSchemaForTesting(db);

    final columns = await db.rawQuery('PRAGMA table_info(sensor_devices)');
    final names = columns.map((row) => row['name']).toSet();
    expect(
      names,
      containsAll([
        'device_kind',
        'transport',
        'model',
        'hardware_version',
        'ble_device_id',
      ]),
    );
    expect(await db.query('device_health_snapshots'), isEmpty);
  });

  test('migration v11 vers v12 conserve les appareils', () async {
    final db = await openMemoryDatabase();
    addTearDown(db.close);
    await db.execute('''CREATE TABLE sensor_devices (
      id TEXT PRIMARY KEY,
      uid TEXT NOT NULL UNIQUE,
      name TEXT NOT NULL,
      zone_id TEXT,
      base_url TEXT NOT NULL,
      firmware_version TEXT,
      last_seen_at INTEGER,
      last_sync_at INTEGER,
      status TEXT NOT NULL DEFAULT 'unknown',
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL)''');
    await db.insert('sensor_devices', {
      'id': 'node-01',
      'uid': 'node-01',
      'name': 'Nœud v11',
      'base_url': 'http://192.168.1.42',
      'created_at': '2026-07-19T10:00:00Z',
      'updated_at': '2026-07-19T10:00:00Z',
    });

    await DatabaseHelper.instance.upgradeSchemaForTesting(db, 11);

    final row = (await db.query('sensor_devices')).single;
    expect(row['device_kind'], 'sensor');
    expect(row['transport'], 'http');
    expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
  });

  test('persiste la santé et calcule la disponibilité', () async {
    final db = await openMemoryDatabase();
    addTearDown(db.close);
    await DatabaseHelper.instance.createSchemaForTesting(db);
    final repository = SensorDataRepository(database: db);
    final now = DateTime.now();
    final device = SensorDevice(
      id: 'node-health',
      uid: 'node-health',
      name: 'Santé',
      zoneId: 'zone-main',
      baseUrl: 'http://192.168.1.43',
      model: 'GT-01',
      bleDeviceId: 'ble-01',
      createdAt: now,
      updatedAt: now,
    );
    await repository.upsertDevice(device);
    for (var index = 0; index < 2; index++) {
      await repository.recordHealthSnapshot(DeviceHealthSnapshot(
        id: 'health-$index',
        deviceId: device.id,
        observedAt: now.subtract(Duration(minutes: index)),
        isOnline: index == 0,
        batteryPercent: 75,
        rssi: -70,
        missingReadings: index,
        createdAt: now,
      ));
    }

    final latest = await repository.getLatestHealth(device.id);
    final availability = await repository.getAvailabilityPercent(device.id);

    expect(latest?.batteryPercent, 75);
    expect(availability, 50);
    expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
  });
}
