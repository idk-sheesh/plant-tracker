import 'package:sqflite/sqflite.dart';

import '../../../../core/database/database_helper.dart';
import '../../domain/entities/calibration_record.dart';

/// Append-only storage for calibrations acknowledged by a sensor node.
class CalibrationRepository {
  final DatabaseHelper _databaseHelper;
  final Database? _database;

  CalibrationRepository({
    DatabaseHelper? databaseHelper,
    Database? database,
  })  : _databaseHelper = databaseHelper ?? DatabaseHelper.instance,
        _database = database;

  Future<Database> get _db async {
    if (_database != null) return _database;
    return _databaseHelper.database;
  }

  Future<void> insert(CalibrationRecord record) async {
    final db = await _db;
    await db.insert(
      'calibration_records',
      record.toMap(),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  Future<List<CalibrationRecord>> getForDevice(
    String deviceId, {
    String? capabilityKey,
  }) async {
    final db = await _db;
    final rows = await db.query(
      'calibration_records',
      where: capabilityKey == null
          ? 'device_id = ?'
          : 'device_id = ? AND capability_key = ?',
      whereArgs: capabilityKey == null
          ? <Object?>[deviceId]
          : <Object?>[deviceId, capabilityKey],
      orderBy: 'calibrated_at DESC',
    );
    return rows.map(CalibrationRecord.fromMap).toList();
  }

  Future<CalibrationRecord?> getLatest(
    String deviceId,
    String capabilityKey,
  ) async {
    final records = await getForDevice(
      deviceId,
      capabilityKey: capabilityKey,
    );
    return records.isEmpty ? null : records.first;
  }
}
