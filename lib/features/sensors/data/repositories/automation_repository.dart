import 'package:sqflite/sqflite.dart';

import '../../../../core/database/database_helper.dart';
import '../../domain/entities/automation_rule.dart';

class AutomationRepository {
  final DatabaseHelper _databaseHelper;
  final Database? _database;

  AutomationRepository({DatabaseHelper? databaseHelper, Database? database})
      : _databaseHelper = databaseHelper ?? DatabaseHelper.instance,
        _database = database;

  Future<Database> get _db async {
    if (_database != null) return _database;
    return _databaseHelper.database;
  }

  Future<void> saveRule(AutomationRule rule) async {
    final db = await _db;
    await db.insert(
      'automation_rules',
      rule.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<AutomationRule>> getRules(String deviceId) async {
    final db = await _db;
    final rows = await db.query(
      'automation_rules',
      where: 'device_id = ?',
      whereArgs: [deviceId],
      orderBy: 'name COLLATE NOCASE ASC',
    );
    return rows.map(AutomationRule.fromMap).toList();
  }
}
