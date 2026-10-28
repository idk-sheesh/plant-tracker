import 'package:flutter_test/flutter_test.dart';
import 'package:garden_journal/core/database/database_helper.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../support/database_test_utils.dart';

void main() {
  sqfliteFfiInit();

  test('création fraîche v20 ajoute l’état cloud sans toucher aux actions',
      () async {
    final db = await openMemoryDatabase();
    addTearDown(db.close);
    await DatabaseHelper.instance.createSchemaForTesting(db);

    final deviceColumns =
        await db.rawQuery('PRAGMA table_info(sensor_devices)');
    final readingColumns =
        await db.rawQuery('PRAGMA table_info(sensor_readings)');
    expect(
      deviceColumns.map((row) => row['name']),
      containsAll([
        'cloud_device_id',
        'cloud_cursor',
        'cloud_last_sync_at',
        'cloud_last_error',
        'cloud_last_error_at',
        'cloud_last_contact_at',
      ]),
    );
    expect(
      readingColumns.map((row) => row['name']),
      containsAll(['remote_event_id', 'source_sequence']),
    );
    expect(await db.query('actions'), isEmpty);
  });

  test('migration v19 vers v20 est additive et idempotente', () async {
    final db = await openMemoryDatabase();
    addTearDown(db.close);
    await db.execute('''CREATE TABLE sensor_devices (
      id TEXT PRIMARY KEY, uid TEXT NOT NULL UNIQUE, name TEXT NOT NULL,
      zone_id TEXT, base_url TEXT NOT NULL, firmware_version TEXT,
      last_seen_at INTEGER, last_sync_at INTEGER,
      status TEXT NOT NULL DEFAULT 'unknown',
      device_kind TEXT NOT NULL DEFAULT 'sensor', transport TEXT NOT NULL DEFAULT 'http',
      model TEXT, hardware_version TEXT, ble_device_id TEXT,
      created_at TEXT NOT NULL, updated_at TEXT NOT NULL)''');
    await db.execute('''CREATE TABLE sensor_readings (
      id TEXT PRIMARY KEY, device_id TEXT NOT NULL, zone_id TEXT,
      measured_at INTEGER NOT NULL, temperature_c REAL NOT NULL,
      humidity_percent REAL NOT NULL, vpd_kpa REAL NOT NULL,
      dew_point_c REAL, mist_on INTEGER NOT NULL DEFAULT 0,
      fan_percent REAL, light_on INTEGER, water_low INTEGER, rssi INTEGER,
      created_at TEXT NOT NULL)''');

    await db.insert('sensor_devices', {
      'id': 'greenhouse-01',
      'uid': 'greenhouse-01',
      'name': 'Serre existante',
      'base_url': 'http://192.168.1.42',
      'created_at': '2026-07-20T10:00:00Z',
      'updated_at': '2026-07-20T10:00:00Z',
    });
    await db.insert('sensor_readings', {
      'id': 'greenhouse-01-1783947600',
      'device_id': 'greenhouse-01',
      'measured_at': 1783947600,
      'temperature_c': 24.6,
      'humidity_percent': 57.2,
      'vpd_kpa': 1.28,
      'created_at': '2026-07-20T10:00:00Z',
    });

    await DatabaseHelper.instance.upgradeSchemaForTesting(db, 19);
    await DatabaseHelper.instance.upgradeSchemaForTesting(db, 19);

    final device = await db.rawQuery('PRAGMA table_info(sensor_devices)');
    final reading = await db.rawQuery('PRAGMA table_info(sensor_readings)');
    expect(device.where((row) => row['name'] == 'cloud_cursor'), hasLength(1));
    expect(
      reading.where((row) => row['name'] == 'remote_event_id'),
      hasLength(1),
    );
    final preserved = (await db.query('sensor_readings')).single;
    expect(preserved['id'], 'greenhouse-01-1783947600');
    expect(preserved['temperature_c'], 24.6);
    expect(preserved['remote_event_id'], isNull);
    expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
  });
}
