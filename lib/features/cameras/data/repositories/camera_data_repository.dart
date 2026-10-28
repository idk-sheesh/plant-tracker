import 'package:sqflite/sqflite.dart';

import '../../../../core/database/database_helper.dart';
import '../../../sensors/domain/entities/sensor_device.dart';
import '../../domain/entities/camera_snapshot.dart';

class CameraDataRepository {
  final DatabaseHelper _databaseHelper;
  final Database? _database;

  CameraDataRepository({
    DatabaseHelper? databaseHelper,
    Database? database,
  })  : _databaseHelper = databaseHelper ?? DatabaseHelper.instance,
        _database = database;

  Future<Database> get _db async => _database ?? await _databaseHelper.database;

  Future<List<SensorDevice>> getCameras() async {
    final db = await _db;
    final rows = await db.query(
      'sensor_devices',
      where: 'device_kind = ?',
      whereArgs: const ['camera'],
      orderBy: 'name ASC',
    );
    return rows.map(SensorDevice.fromMap).toList(growable: false);
  }

  Future<void> upsertCamera(SensorDevice camera) async {
    if (camera.deviceKind != 'camera') {
      throw const FormatException('Type appareil caméra requis');
    }
    final db = await _db;
    await db.transaction((txn) async {
      final existing = await txn.query(
        'sensor_devices',
        columns: const ['id', 'device_kind'],
        where: 'uid = ?',
        whereArgs: [camera.uid],
        limit: 1,
      );
      if (existing.isEmpty) {
        await txn.insert('sensor_devices', camera.toMap());
      } else {
        if (existing.single['device_kind'] != 'camera') {
          throw const FormatException(
            'Cet identifiant appartient déjà à un autre type d’appareil',
          );
        }
        await txn.update(
          'sensor_devices',
          camera.toMap(),
          where: 'uid = ?',
          whereArgs: [camera.uid],
        );
      }
    });
  }

  Future<bool> saveSnapshot(CameraSnapshot snapshot) async {
    final db = await _db;
    final inserted = await db.insert(
      'camera_snapshots',
      snapshot.toMap(),
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    return inserted != 0;
  }

  Future<CameraSnapshot?> getLatestSnapshot(String deviceId) async {
    final db = await _db;
    final rows = await db.query(
      'camera_snapshots',
      where: 'device_id = ?',
      whereArgs: [deviceId],
      orderBy: 'captured_at DESC, id DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : CameraSnapshot.fromMap(rows.first);
  }

  Future<List<CameraSnapshot>> getSavedSnapshots() async {
    final db = await _db;
    final rows = await db.query(
      'camera_snapshots',
      where: 'photo_path IS NOT NULL',
      orderBy: 'captured_at DESC, id DESC',
    );
    return rows.map(CameraSnapshot.fromMap).toList(growable: false);
  }

  Future<bool> deleteSnapshot(String snapshotId) async {
    final db = await _db;
    return await db.delete(
          'camera_snapshots',
          where: 'id = ?',
          whereArgs: [snapshotId],
        ) >
        0;
  }
}
