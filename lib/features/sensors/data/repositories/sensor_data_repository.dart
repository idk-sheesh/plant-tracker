import 'package:sqflite/sqflite.dart';

import '../../../../core/database/database_helper.dart';
import '../../domain/entities/device_capability.dart';
import '../../domain/entities/device_health_snapshot.dart';
import '../../domain/entities/sensor_device.dart';
import '../../domain/entities/sensor_measurement.dart';
import '../../domain/entities/sensor_reading.dart';

class SensorDataRepository {
  final DatabaseHelper _databaseHelper;
  final Database? _database;

  SensorDataRepository({
    DatabaseHelper? databaseHelper,
    Database? database,
  })  : _databaseHelper = databaseHelper ?? DatabaseHelper.instance,
        _database = database;

  Future<Database> get _db async {
    if (_database != null) return _database;
    return _databaseHelper.database;
  }

  Future<List<SensorDevice>> getDevices({String? deviceKind}) async {
    final db = await _db;
    final rows = await db.query(
      'sensor_devices',
      where: deviceKind == null ? null : 'device_kind = ?',
      whereArgs: deviceKind == null ? null : [deviceKind],
      orderBy: 'COALESCE(last_seen_at, 0) DESC, name ASC',
    );
    return rows.map(SensorDevice.fromMap).toList();
  }

  Future<SensorDevice?> getDeviceByUid(String uid) async {
    final db = await _db;
    final rows = await db.query(
      'sensor_devices',
      where: 'uid = ?',
      whereArgs: [uid],
      limit: 1,
    );
    return rows.isEmpty ? null : SensorDevice.fromMap(rows.first);
  }

  Future<SensorDevice?> getDeviceById(String id) async {
    final db = await _db;
    final rows = await db.query(
      'sensor_devices',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : SensorDevice.fromMap(rows.first);
  }

  Future<void> upsertDevice(SensorDevice device) async {
    final db = await _db;
    await db.transaction((txn) async {
      final existing = await txn.query(
        'sensor_devices',
        columns: const ['id'],
        where: 'uid = ?',
        whereArgs: [device.uid],
        limit: 1,
      );
      if (existing.isEmpty) {
        await txn.insert('sensor_devices', device.toMap());
      } else {
        await txn.update(
          'sensor_devices',
          device.toMap(),
          where: 'uid = ?',
          whereArgs: [device.uid],
        );
      }
    });
  }

  Future<void> updateDeviceStatus(
    String deviceId,
    String status, {
    DateTime? lastSeenAt,
    DateTime? lastSyncAt,
  }) async {
    final db = await _db;
    int? seconds(DateTime? value) =>
        value?.toUtc().millisecondsSinceEpoch == null
            ? null
            : value!.toUtc().millisecondsSinceEpoch ~/ 1000;
    await db.update(
      'sensor_devices',
      {
        'status': status,
        if (lastSeenAt != null) 'last_seen_at': seconds(lastSeenAt),
        if (lastSyncAt != null) 'last_sync_at': seconds(lastSyncAt),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [deviceId],
    );
  }

  Future<void> linkCloudDevice(
    String deviceId,
    String? cloudDeviceId,
  ) async {
    final normalized = cloudDeviceId?.trim();
    if (normalized != null && (normalized.isEmpty || normalized.length > 80)) {
      throw const FormatException('Identifiant cloud invalide');
    }
    final db = await _db;
    await db.update(
      'sensor_devices',
      {
        'cloud_device_id': normalized?.isEmpty == true ? null : normalized,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [deviceId],
    );
  }

  Future<void> recordCloudSyncSuccess(
    String deviceId, {
    required String cloudDeviceId,
    String? cursor,
    DateTime? lastContactAt,
  }) async {
    final db = await _db;
    final now = DateTime.now().toUtc();
    await db.update(
      'sensor_devices',
      {
        'cloud_device_id': cloudDeviceId,
        'cloud_cursor': cursor,
        'cloud_last_sync_at': now.millisecondsSinceEpoch ~/ 1000,
        'cloud_last_error': null,
        'cloud_last_error_at': null,
        if (lastContactAt != null)
          'cloud_last_contact_at':
              lastContactAt.toUtc().millisecondsSinceEpoch ~/ 1000,
        'updated_at': now.toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [deviceId],
    );
  }

  Future<void> recordCloudSyncFailure(
    String deviceId,
    String error, {
    DateTime? at,
  }) async {
    final db = await _db;
    final now = (at ?? DateTime.now()).toUtc();
    final normalized = error.trim();
    await db.update(
      'sensor_devices',
      {
        'cloud_last_error':
            normalized.length > 500 ? normalized.substring(0, 500) : normalized,
        'cloud_last_error_at': now.millisecondsSinceEpoch ~/ 1000,
        'updated_at': now.toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [deviceId],
    );
  }

  Future<void> recordHealthSnapshot(DeviceHealthSnapshot snapshot) async {
    final db = await _db;
    await db.insert(
      'device_health_snapshots',
      snapshot.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<DeviceHealthSnapshot?> getLatestHealth(String deviceId) async {
    final db = await _db;
    final rows = await db.query(
      'device_health_snapshots',
      where: 'device_id = ?',
      whereArgs: [deviceId],
      orderBy: 'observed_at DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : DeviceHealthSnapshot.fromMap(rows.first);
  }

  Future<List<DeviceHealthSnapshot>> getHealthHistory(
    String deviceId, {
    Duration period = const Duration(hours: 24),
  }) async {
    final db = await _db;
    final since =
        DateTime.now().subtract(period).toUtc().millisecondsSinceEpoch ~/ 1000;
    final rows = await db.query(
      'device_health_snapshots',
      where: 'device_id = ? AND observed_at >= ?',
      whereArgs: [deviceId, since],
      orderBy: 'observed_at ASC',
    );
    return rows.map(DeviceHealthSnapshot.fromMap).toList();
  }

  Future<double?> getAvailabilityPercent(
    String deviceId, {
    Duration period = const Duration(hours: 24),
  }) async {
    final db = await _db;
    final since =
        DateTime.now().subtract(period).toUtc().millisecondsSinceEpoch ~/ 1000;
    final rows = await db.rawQuery(
      'SELECT AVG(is_online) * 100.0 AS availability '
      'FROM device_health_snapshots '
      'WHERE device_id = ? AND observed_at >= ?',
      [deviceId, since],
    );
    return (rows.first['availability'] as num?)?.toDouble();
  }

  Future<int> getLastMeasuredAtSeconds(String deviceId) async {
    final db = await _db;
    final rows = await db.rawQuery(
      'SELECT MAX(measured_at) AS measured_at '
      'FROM sensor_readings WHERE device_id = ?',
      [deviceId],
    );
    return rows.first['measured_at'] as int? ?? 0;
  }

  Future<int> insertReadings(
    SensorDevice device,
    Iterable<SensorReading> readings, {
    bool markLocalOnline = true,
  }) async {
    final normalized = readings
        .map(
          (reading) => reading.copyWith(
            deviceId: device.id,
            zoneId: device.zoneId,
          ),
        )
        .toList();
    if (normalized.isEmpty) return 0;

    final db = await _db;
    var inserted = 0;
    await db.transaction((txn) async {
      final declaredCapabilities = <String, DeviceCapability>{};
      final measurements = <SensorMeasurement>[];
      for (final reading in normalized) {
        for (final capability in reading.capabilities) {
          final normalizedCapability = capability.copyWith(deviceId: device.id);
          final previous = declaredCapabilities[normalizedCapability.key];
          if (previous != null &&
              previous.valueType != normalizedCapability.valueType) {
            throw FormatException(
              'Types contradictoires pour ${normalizedCapability.key}',
            );
          }
          declaredCapabilities[normalizedCapability.key] = normalizedCapability;
        }
        measurements.addAll(
          reading.measurements.map(
            (measurement) => measurement.copyWith(
              deviceId: device.id,
              zoneId: device.zoneId,
            ),
          ),
        );
      }
      for (final capability in declaredCapabilities.values) {
        await _ensureCapability(txn, capability, updateMetadata: true);
      }
      for (final measurement in measurements) {
        await _ensureCapability(
          txn,
          declaredCapabilities[measurement.capabilityKey] ??
              DeviceCapability.inferred(
                deviceId: device.id,
                key: measurement.capabilityKey,
                valueType: measurement.valueType,
                unit: measurement.unit,
                now: measurement.createdAt,
              ),
          updateMetadata: false,
        );
        await txn.insert(
          'sensor_measurements',
          measurement.toMap(),
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }

      final timestamps = normalized
          .map((reading) => reading.timestampSeconds)
          .toList(growable: false);
      final minimum = timestamps.reduce((a, b) => a < b ? a : b);
      final maximum = timestamps.reduce((a, b) => a > b ? a : b);
      final existingRows = await txn.query(
        'sensor_readings',
        columns: const ['measured_at', 'remote_event_id'],
        where: 'device_id = ? AND measured_at BETWEEN ? AND ?',
        whereArgs: [device.id, minimum, maximum],
      );
      final existing =
          existingRows.map((row) => row['measured_at'] as int).toSet();
      final existingRemoteEvents = existingRows
          .map((row) => row['remote_event_id'] as String?)
          .whereType<String>()
          .toSet();
      final allRemoteRows = await txn.query(
        'sensor_readings',
        columns: const ['remote_event_id'],
        where: 'device_id = ? AND remote_event_id IS NOT NULL',
        whereArgs: [device.id],
      );
      existingRemoteEvents.addAll(
        allRemoteRows
            .map((row) => row['remote_event_id'] as String?)
            .whereType<String>(),
      );
      for (final reading in normalized) {
        if (existing.contains(reading.timestampSeconds) ||
            (reading.remoteEventId != null &&
                existingRemoteEvents.contains(reading.remoteEventId))) {
          continue;
        }
        await txn.insert(
          'sensor_readings',
          reading.toMap(),
          conflictAlgorithm: ConflictAlgorithm.abort,
        );
        existing.add(reading.timestampSeconds);
        if (reading.remoteEventId != null) {
          existingRemoteEvents.add(reading.remoteEventId!);
        }
        inserted++;
      }
      final lastSeen = normalized
          .map((reading) => reading.timestampSeconds)
          .reduce((a, b) => a > b ? a : b);
      final now = DateTime.now();
      final existingDevice = await txn.query(
        'sensor_devices',
        columns: const ['last_seen_at'],
        where: 'id = ?',
        whereArgs: [device.id],
        limit: 1,
      );
      if (existingDevice.isEmpty) {
        throw StateError('Capteur introuvable pendant la synchro');
      }
      final previousLastSeen = existingDevice.single['last_seen_at'] as int?;
      final changed = await txn.update(
        'sensor_devices',
        {
          'last_seen_at':
              previousLastSeen != null && previousLastSeen > lastSeen
                  ? previousLastSeen
                  : lastSeen,
          if (markLocalOnline) ...{
            'last_sync_at': now.toUtc().millisecondsSinceEpoch ~/ 1000,
            'status': 'online',
          },
          'updated_at': now.toUtc().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [device.id],
      );
      if (changed != 1)
        throw StateError('Capteur introuvable pendant la synchro');
    });
    return inserted;
  }

  Future<int> insertMeasurements(
    SensorDevice device,
    Iterable<SensorMeasurement> values, {
    Iterable<DeviceCapability> capabilities = const [],
  }) async {
    final measurements = values
        .map((item) => item.copyWith(
              deviceId: device.id,
              zoneId: device.zoneId,
            ))
        .toList();
    if (measurements.isEmpty) return 0;
    final declared = {
      for (final capability in capabilities)
        capability.key: capability.copyWith(deviceId: device.id),
    };
    final db = await _db;
    var inserted = 0;
    await db.transaction((txn) async {
      for (final measurement in measurements) {
        final capability = declared[measurement.capabilityKey] ??
            DeviceCapability.inferred(
              deviceId: device.id,
              key: measurement.capabilityKey,
              valueType: measurement.valueType,
              unit: measurement.unit,
              now: measurement.createdAt,
            );
        await _ensureCapability(txn, capability,
            updateMetadata: declared.containsKey(measurement.capabilityKey));
        final id = await txn.insert(
          'sensor_measurements',
          measurement.toMap(),
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
        if (id != 0) inserted++;
      }
      final lastSeen = measurements
          .map((item) => item.timestampSeconds)
          .reduce((a, b) => a > b ? a : b);
      await txn.update(
        'sensor_devices',
        {
          'last_seen_at': lastSeen,
          'last_sync_at': DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000,
          'status': 'online',
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [device.id],
      );
    });
    return inserted;
  }

  Future<void> _ensureCapability(
    DatabaseExecutor txn,
    DeviceCapability capability, {
    required bool updateMetadata,
  }) async {
    final existing = await txn.query(
      'sensor_device_capabilities',
      columns: const ['value_type'],
      where: 'device_id = ? AND capability_key = ?',
      whereArgs: [capability.deviceId, capability.key],
      limit: 1,
    );
    if (existing.isEmpty) {
      await txn.insert(
        'sensor_device_capabilities',
        capability.toMap(),
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
      return;
    }
    if (existing.single['value_type'] != capability.valueType.wireValue) {
      throw FormatException(
        'Type de capacité modifié pour ${capability.key}',
      );
    }
    if (updateMetadata) {
      await txn.update(
        'sensor_device_capabilities',
        capability.toMap(),
        where: 'device_id = ? AND capability_key = ?',
        whereArgs: [capability.deviceId, capability.key],
      );
    }
  }

  Future<List<DeviceCapability>> getCapabilitiesForDevice(
    String deviceId,
  ) async {
    final db = await _db;
    final rows = await db.query(
      'sensor_device_capabilities',
      where: 'device_id = ?',
      whereArgs: [deviceId],
      orderBy: 'display_name COLLATE NOCASE ASC',
    );
    return rows.map(DeviceCapability.fromMap).toList();
  }

  Future<List<SensorMeasurement>> getMeasurementsForDevice(
    String deviceId, {
    int limit = 288,
  }) async {
    final db = await _db;
    final rows = await db.query(
      'sensor_measurements',
      where: 'device_id = ?',
      whereArgs: [deviceId],
      orderBy: 'measured_at DESC, capability_key ASC',
      limit: limit,
    );
    return rows.reversed.map(SensorMeasurement.fromMap).toList();
  }

  Future<List<SensorMeasurement>> getMeasurementsForZoneSince(
    String zoneId,
    DateTime since,
  ) async {
    final db = await _db;
    final rows = await db.query(
      'sensor_measurements',
      where: 'zone_id = ? AND measured_at >= ?',
      whereArgs: [
        zoneId,
        since.toUtc().millisecondsSinceEpoch ~/ 1000,
      ],
      orderBy: 'measured_at ASC, capability_key ASC',
    );
    return rows.map(SensorMeasurement.fromMap).toList();
  }

  Future<List<SensorReading>> getReadingsForDevice(
    String deviceId, {
    int limit = 288,
  }) async {
    final db = await _db;
    final rows = await db.query(
      'sensor_readings',
      where: 'device_id = ?',
      whereArgs: [deviceId],
      orderBy: 'measured_at DESC',
      limit: limit,
    );
    return rows.reversed.map(SensorReading.fromMap).toList();
  }

  Future<List<SensorReading>> getReadingsForZone(
    String zoneId, {
    int limit = 288,
  }) async {
    final db = await _db;
    final rows = await db.query(
      'sensor_readings',
      where: 'zone_id = ?',
      whereArgs: [zoneId],
      orderBy: 'measured_at DESC',
      limit: limit,
    );
    return rows.reversed.map(SensorReading.fromMap).toList();
  }

  Future<List<SensorReading>> getReadingsForZoneSince(
    String zoneId,
    DateTime since,
  ) async {
    final db = await _db;
    final rows = await db.query(
      'sensor_readings',
      where: 'zone_id = ? AND measured_at >= ?',
      whereArgs: [
        zoneId,
        since.toUtc().millisecondsSinceEpoch ~/ 1000,
      ],
      orderBy: 'measured_at ASC',
    );
    return rows.map(SensorReading.fromMap).toList();
  }

  Future<SensorReading?> getLatestForZone(String zoneId) async {
    final db = await _db;
    final rows = await db.query(
      'sensor_readings',
      where: 'zone_id = ?',
      whereArgs: [zoneId],
      orderBy: 'measured_at DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : SensorReading.fromMap(rows.first);
  }
}
