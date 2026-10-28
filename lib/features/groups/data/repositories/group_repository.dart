import 'package:sqflite/sqflite.dart';

import '../../../../core/database/database_helper.dart';
import '../models/plant_group.dart';

class GroupRepository {
  final Database? _databaseOverride;

  GroupRepository({Database? database}) : _databaseOverride = database;

  Future<Database> get _database async =>
      _databaseOverride ?? await DatabaseHelper.instance.database;

  Future<List<PlantGroup>> getAllGroups() async {
    final db = await _database;
    final maps = await db.query('groups', orderBy: 'created_at DESC');
    // Le provider ajoute localement les nouveaux groupes après le chargement.
    return maps.map(PlantGroup.fromMap).toList();
  }

  Future<PlantGroup?> getGroupById(String id) async {
    final db = await _database;
    final maps = await db.query(
      'groups',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return maps.isEmpty ? null : PlantGroup.fromMap(maps.first);
  }

  Future<void> insertGroup(PlantGroup group) async {
    final db = await _database;
    await db.insert(
      'groups',
      group.toMap(),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  Future<void> updateGroup(PlantGroup group) async {
    final db = await _database;
    final changed = await db.update(
      'groups',
      group.toMap(),
      where: 'id = ?',
      whereArgs: [group.id],
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
    if (changed != 1) throw StateError('Groupe introuvable');
  }

  Future<void> deleteGroup(String id) async {
    final db = await _database;
    await db.transaction((txn) async {
      // La suppression d'un groupe ne doit jamais supprimer les plantes ni
      // leur historique : on retire seulement leur rattachement.
      await txn.update(
        'plants',
        {'group_id': null},
        where: 'group_id = ?',
        whereArgs: [id],
      );
      await txn.update(
        'groups',
        {'parent_group_id': null},
        where: 'parent_group_id = ?',
        whereArgs: [id],
      );
      final deleted = await txn.delete(
        'groups',
        where: 'id = ?',
        whereArgs: [id],
      );
      if (deleted != 1) throw StateError('Groupe introuvable');
    });
  }
}
