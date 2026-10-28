import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../../../core/database/database_helper.dart';
import '../../domain/entities/device_control.dart';

class DeviceControlRepository {
  final DatabaseHelper _databaseHelper;
  final Database? _database;

  DeviceControlRepository({
    DatabaseHelper? databaseHelper,
    Database? database,
  })  : _databaseHelper = databaseHelper ?? DatabaseHelper.instance,
        _database = database;

  Future<Database> get _db async {
    if (_database != null) return _database;
    return _databaseHelper.database;
  }

  Future<void> insertCommand(DeviceCommand command) async {
    final db = await _db;
    await db.insert(
      'device_commands',
      command.toMap(),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  Future<void> updateCommand(
    String id, {
    required String status,
    DateTime? nodeAckAt,
    Map<String, Object?>? nodeResponse,
    String? errorCode,
    required DateTime updatedAt,
  }) async {
    final db = await _db;
    final changed = await db.update(
      'device_commands',
      {
        'status': status,
        'node_ack_at': nodeAckAt == null
            ? null
            : nodeAckAt.toUtc().millisecondsSinceEpoch ~/ 1000,
        'node_response_json':
            nodeResponse == null ? null : jsonEncode(nodeResponse),
        'error_code': errorCode,
        'updated_at': updatedAt.toUtc().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    if (changed != 1) throw StateError('Commande locale introuvable');
  }

  Future<DeviceCommand?> getCommand(String id) async {
    final db = await _db;
    final rows = await db.query(
      'device_commands',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : DeviceCommand.fromMap(rows.single);
  }

  Future<List<DeviceCommand>> getCommands(String deviceId,
      {int limit = 100}) async {
    final db = await _db;
    final rows = await db.query(
      'device_commands',
      where: 'device_id = ?',
      whereArgs: [deviceId],
      orderBy: 'requested_at DESC',
      limit: limit,
    );
    return rows.map(DeviceCommand.fromMap).toList();
  }

  Future<void> saveSchedule(NodeSchedule schedule) async {
    final db = await _db;
    await db.insert(
      'node_schedules',
      schedule.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<NodeSchedule?> getSchedule(String id) async {
    final db = await _db;
    final rows = await db.query(
      'node_schedules',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : NodeSchedule.fromMap(rows.single);
  }

  Future<List<NodeSchedule>> getSchedules(String deviceId) async {
    final db = await _db;
    final rows = await db.query(
      'node_schedules',
      where: 'device_id = ?',
      whereArgs: [deviceId],
      orderBy: 'start_minute ASC, name COLLATE NOCASE ASC',
    );
    return rows.map(NodeSchedule.fromMap).toList();
  }
}
