import 'package:sqflite/sqflite.dart';

import '../../../../core/database/database_helper.dart';
import '../../domain/entities/cultivation_zone.dart';

class CultivationZoneRepository {
  final DatabaseHelper _databaseHelper;
  final Database? _database;

  CultivationZoneRepository({
    DatabaseHelper? databaseHelper,
    Database? database,
  })  : _databaseHelper = databaseHelper ?? DatabaseHelper.instance,
        _database = database;

  Future<Database> get _db async {
    if (_database != null) return _database;
    return _databaseHelper.database;
  }

  Future<List<CultivationZone>> getAll() async {
    final db = await _db;
    final rows = await db.query('cultivation_zones', orderBy: 'name ASC');
    return rows.map(CultivationZone.fromMap).toList();
  }

  Future<CultivationZone?> getById(String id) async {
    final db = await _db;
    final rows = await db.query(
      'cultivation_zones',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : CultivationZone.fromMap(rows.first);
  }

  Future<void> insert(CultivationZone zone) async {
    final db = await _db;
    await db.insert(
      'cultivation_zones',
      zone.toMap(),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  Future<void> update(CultivationZone zone) async {
    final db = await _db;
    final changed = await db.update(
      'cultivation_zones',
      zone.toMap(),
      where: 'id = ?',
      whereArgs: [zone.id],
    );
    if (changed != 1) throw StateError('Espace de culture introuvable');
  }

  Future<void> delete(String id) async {
    final db = await _db;
    final deleted =
        await db.delete('cultivation_zones', where: 'id = ?', whereArgs: [id]);
    if (deleted != 1) throw StateError('Espace de culture introuvable');
  }
}
