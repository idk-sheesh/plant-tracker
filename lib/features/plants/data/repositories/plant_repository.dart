import 'package:sqflite/sqflite.dart';

import '../../../../core/database/database_helper.dart';
import '../../domain/entities/plant.dart';

class PlantRepository {
  final Database? _databaseOverride;

  PlantRepository({Database? database}) : _databaseOverride = database;

  Future<Database> get _database async =>
      _databaseOverride ?? await DatabaseHelper.instance.database;

  Future<List<Plant>> getAllPlants() async {
    final db = await _database;
    final maps = await db.query('plants', orderBy: 'created_at DESC');
    return maps.map(Plant.fromMap).toList(growable: false);
  }

  Future<Plant?> getPlantById(String id) async {
    final db = await _database;
    final maps = await db.query(
      'plants',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return maps.isEmpty ? null : Plant.fromMap(maps.first);
  }

  Future<Plant?> getPlantByQrCode(String qrCode) async {
    final db = await _database;
    final maps = await db.query(
      'plants',
      where: 'qr_code = ?',
      whereArgs: [qrCode],
      limit: 1,
    );
    return maps.isEmpty ? null : Plant.fromMap(maps.first);
  }

  Future<void> insertPlant(Plant plant) async {
    final db = await _database;
    await db.insert(
      'plants',
      plant.toMap(),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  Future<List<String>> updatePlant(Plant plant) async {
    final db = await _database;
    return db.transaction((txn) async {
      final existing = await txn.query(
        'plants',
        columns: const ['photo_path'],
        where: 'id = ?',
        whereArgs: [plant.id],
        limit: 1,
      );
      if (existing.isEmpty) throw StateError('Plante introuvable');
      final oldPath = existing.single['photo_path'] as String?;
      final changed = await txn.update(
        'plants',
        plant.toMap(),
        where: 'id = ?',
        whereArgs: [plant.id],
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
      if (changed != 1) throw StateError('Plante introuvable');
      if (oldPath == null || oldPath == plant.photoPath) return const [];
      return await _isPhotoReferenced(txn, oldPath)
          ? const []
          : <String>[oldPath];
    });
  }

  Future<PlantDeletionResult?> deletePlant(String id) async {
    final db = await _database;
    return db.transaction((txn) async {
      final plantRows = await txn.query(
        'plants',
        columns: const ['photo_path'],
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (plantRows.isEmpty) return null;
      final actionPhotos = await txn.rawQuery(
        '''SELECT action_photos.photo_path FROM action_photos
           JOIN actions ON actions.id = action_photos.action_id
           WHERE actions.plant_id = ?''',
        [id],
      );
      final candidates = <String>{
        if (plantRows.single['photo_path'] case final String path) path,
        ...actionPhotos.map((row) => row['photo_path'] as String),
      };
      final deleted = await txn.delete(
        'plants',
        where: 'id = ?',
        whereArgs: [id],
      );
      if (deleted != 1) throw StateError('Suppression de la plante incomplète');
      final unreferenced = <String>[];
      for (final candidate in candidates) {
        if (!await _isPhotoReferenced(txn, candidate)) {
          unreferenced.add(candidate);
        }
      }
      return PlantDeletionResult(photoPaths: unreferenced);
    });
  }

  Future<void> replacePhotoPath(
    String plantId,
    String oldPath,
    String newPath,
  ) async {
    final db = await _database;
    final changed = await db.update(
      'plants',
      {'photo_path': newPath},
      where: 'id = ? AND photo_path = ?',
      whereArgs: [plantId, oldPath],
    );
    if (changed != 1) throw StateError('Photo de plante non actualisée');
  }

  Future<List<String>> getAllPhotoPaths() async {
    final db = await _database;
    final rows = await db.rawQuery('''
      SELECT photo_path FROM plants WHERE photo_path IS NOT NULL
      UNION
      SELECT photo_path FROM action_photos
    ''');
    return rows.map((row) => row['photo_path'] as String).toList();
  }

  Future<bool> _isPhotoReferenced(
    DatabaseExecutor db,
    String photoPath,
  ) async {
    final count = Sqflite.firstIntValue(
          await db.rawQuery(
            '''SELECT (
              (SELECT COUNT(*) FROM plants WHERE photo_path = ?) +
              (SELECT COUNT(*) FROM action_photos WHERE photo_path = ?) +
              (SELECT COUNT(*) FROM zone_photos WHERE photo_path = ?)
            )''',
            [photoPath, photoPath, photoPath],
          ),
        ) ??
        0;
    return count > 0;
  }
}

class PlantDeletionResult {
  final List<String> photoPaths;

  const PlantDeletionResult({required this.photoPaths});
}
