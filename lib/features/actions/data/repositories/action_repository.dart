import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/database/database_helper.dart';
import '../../../../core/utils/numeric_input_parser.dart';
import '../../domain/entities/plant_action.dart';
import '../../domain/entities/action_home_summary.dart';
export '../../domain/entities/action_home_summary.dart';

class ActionRepository {
  final Database? _databaseOverride;
  final Uuid _uuid;

  ActionRepository({Database? database, Uuid? uuid})
      : _databaseOverride = database,
        _uuid = uuid ?? const Uuid();

  Future<Database> get _database async =>
      _databaseOverride ?? await DatabaseHelper.instance.database;

  Future<Map<String, ActionHomeSummary>> getHomeSummaries() async {
    final db = await _database;
    final rows = await db.rawQuery('''
      SELECT
        plant_id,
        MAX(CASE
          WHEN (status IS NULL OR status != 'planned')
            AND (action_type = 'arrosage'
              OR (action_type = 'nutriments' AND is_watering_combined = 1))
          THEN timestamp
        END) AS last_water_at,
        MAX(CASE
          WHEN (status IS NULL OR status != 'planned')
          THEN timestamp
        END) AS last_activity_at,
        MAX(CASE WHEN (status IS NULL OR status != 'planned')
          AND action_type = 'observation' THEN timestamp END) AS last_observation_at,
        MAX(CASE WHEN (status IS NULL OR status != 'planned')
          AND action_type = 'floraison' THEN timestamp END) AS last_flowering_at
      FROM actions
      GROUP BY plant_id
    ''');
    return {
      for (final row in rows)
        row['plant_id'] as String: ActionHomeSummary.fromMap(row),
    };
  }

  Future<Map<String, DateTime>> getLatestFloweringStarts(
    Iterable<String> plantIds,
  ) async {
    final ids = plantIds.toSet().toList(growable: false);
    if (ids.isEmpty) return const {};

    final db = await _database;
    final starts = <String, DateTime>{};
    const batchSize = 400;
    for (var offset = 0; offset < ids.length; offset += batchSize) {
      final end =
          offset + batchSize < ids.length ? offset + batchSize : ids.length;
      final batch = ids.sublist(offset, end);
      final placeholders = List.filled(batch.length, '?').join(',');
      final rows = await db.query(
        'actions',
        columns: const ['plant_id', 'timestamp'],
        where: '''plant_id IN ($placeholders)
          AND action_type = ?
          AND (status IS NULL OR status != ?)''',
        whereArgs: [...batch, 'floraison', 'planned'],
      );
      for (final row in rows) {
        final plantId = row['plant_id'] as String;
        final timestamp = DateTime.parse(row['timestamp'] as String);
        final current = starts[plantId];
        if (current == null || timestamp.isAfter(current)) {
          starts[plantId] = timestamp;
        }
      }
    }
    return starts;
  }

  Future<List<PlantAction>> getActionsForPlant(
    String plantId, {
    int? limit,
    int offset = 0,
  }) async {
    if ((limit != null && (limit < 1 || limit > 500)) ||
        offset < 0 ||
        (limit == null && offset != 0)) {
      throw ArgumentError('Pagination d’historique invalide');
    }
    final db = await _database;
    final maps = await db.query(
      'actions',
      where: '''plant_id = ? OR
        (action_type = 'bouturage' AND parent_plant_id = ?)''',
      whereArgs: [plantId, plantId],
      orderBy: 'timestamp DESC',
      limit: limit,
      offset: offset,
    );
    final photosByAction = await _getPhotosForActions(
      db,
      maps.map((map) => map['id'] as String).toList(growable: false),
    );
    return maps
        .map(
          (map) => PlantAction.fromMap(
            map,
            photos: photosByAction[map['id']] ?? const [],
          ),
        )
        .toList(growable: false);
  }

  Future<PlantAction?> getActionById(String actionId) async {
    final db = await _database;
    final maps = await db.query(
      'actions',
      where: 'id = ?',
      whereArgs: [actionId],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    final photos = await _getPhotosForActions(db, [actionId]);
    return PlantAction.fromMap(maps.first, photos: photos[actionId]);
  }

  Future<List<PlantAction>> getPlannedActions() async {
    final db = await _database;
    final maps = await db.query(
      'actions',
      where: 'status = ?',
      whereArgs: const ['planned'],
      orderBy: 'timestamp ASC',
    );
    final photos = await _getPhotosForActions(
      db,
      maps.map((map) => map['id'] as String).toList(growable: false),
    );
    return maps
        .map(
          (map) => PlantAction.fromMap(
            map,
            photos: photos[map['id'] as String],
          ),
        )
        .toList(growable: false);
  }

  Future<Map<String, List<String>>> _getPhotosForActions(
    DatabaseExecutor db,
    List<String> actionIds,
  ) async {
    if (actionIds.isEmpty) return const {};
    final grouped = <String, List<String>>{};
    const batchSize = 400;
    for (var offset = 0; offset < actionIds.length; offset += batchSize) {
      final end = offset + batchSize < actionIds.length
          ? offset + batchSize
          : actionIds.length;
      final batch = actionIds.sublist(offset, end);
      final placeholders = List.filled(batch.length, '?').join(',');
      final rows = await db.rawQuery(
        '''SELECT action_id, photo_path FROM action_photos
           WHERE action_id IN ($placeholders)
           ORDER BY created_at ASC''',
        batch,
      );
      for (final row in rows) {
        grouped
            .putIfAbsent(row['action_id'] as String, () => <String>[])
            .add(row['photo_path'] as String);
      }
    }
    return grouped;
  }

  Future<void> insertAction(PlantAction action) async {
    _validateAction(action);
    final db = await _database;
    await db.transaction((txn) async {
      await txn.insert(
        'actions',
        action.toMap(),
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
      await _insertPhotos(txn, action);
      await _applyBusinessEffects(txn, action);
    });
  }

  Future<void> addPhotoToAction(
    String actionId,
    String plantId,
    String photoPath,
  ) async {
    final db = await _database;
    await db.transaction((txn) async {
      final action = await txn.query(
        'actions',
        columns: const ['plant_id'],
        where: 'id = ?',
        whereArgs: [actionId],
        limit: 1,
      );
      if (action.isEmpty) throw StateError('Action introuvable');
      if (action.single['plant_id'] != plantId) {
        throw StateError('La photo ne correspond pas à la plante de l’action');
      }
      await _insertPhoto(txn, actionId, plantId, photoPath);
    });
  }

  Future<bool> deletePhoto(String actionId, String path) async {
    final db = await _database;
    return await db.delete(
          'action_photos',
          where: 'action_id = ? AND photo_path = ?',
          whereArgs: [actionId, path],
        ) >
        0;
  }

  Future<void> replacePhotoPath(
    String actionId,
    String oldPath,
    String newPath,
  ) async {
    final db = await _database;
    final changed = await db.update(
      'action_photos',
      {'photo_path': newPath},
      where: 'action_id = ? AND photo_path = ?',
      whereArgs: [actionId, oldPath],
    );
    if (changed != 1) throw StateError('Photo d’action non actualisée');
  }

  Future<List<String>> updateAction(PlantAction action) async {
    _validateAction(action);
    final db = await _database;
    return db.transaction((txn) async {
      final previousRows = await txn.query(
        'actions',
        columns: const ['plant_id'],
        where: 'id = ?',
        whereArgs: [action.id],
        limit: 1,
      );
      if (previousRows.isEmpty) throw StateError('Action introuvable');
      final previousPlantId = previousRows.single['plant_id'] as String;
      final previousPhotos =
          (await _getPhotosForActions(txn, [action.id]))[action.id] ??
              const <String>[];

      final updated = await txn.update(
        'actions',
        action.toMap(),
        where: 'id = ?',
        whereArgs: [action.id],
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
      if (updated != 1) throw StateError('Mise à jour de l’action incomplète');
      await txn.delete(
        'action_photos',
        where: 'action_id = ?',
        whereArgs: [action.id],
      );
      await _insertPhotos(txn, action);
      await _applyBusinessEffects(txn, action);
      if (previousPlantId != action.plantId) {
        await _recalculatePlantEndState(txn, previousPlantId);
      }
      final unreferenced = <String>[];
      for (final path in previousPhotos.toSet()) {
        if (!action.photoPaths.contains(path) &&
            !await _isPhotoReferenced(txn, path)) {
          unreferenced.add(path);
        }
      }
      return unreferenced;
    });
  }

  Future<ActionDeletionResult?> deleteAction(String id) async {
    final db = await _database;
    return db.transaction((txn) async {
      final rows = await txn.query(
        'actions',
        columns: const ['plant_id'],
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (rows.isEmpty) return null;
      final plantId = rows.single['plant_id'] as String;
      final photos = (await _getPhotosForActions(txn, [id]))[id] ?? const [];
      final deleted = await txn.delete(
        'actions',
        where: 'id = ?',
        whereArgs: [id],
      );
      if (deleted != 1) throw StateError('Suppression de l’action incomplète');
      await _recalculatePlantEndState(txn, plantId);
      final unreferenced = <String>[];
      for (final path in photos) {
        if (!await _isPhotoReferenced(txn, path)) unreferenced.add(path);
      }
      return ActionDeletionResult(
        plantId: plantId,
        photoPaths: unreferenced,
      );
    });
  }

  Future<void> _insertPhotos(
    DatabaseExecutor db,
    PlantAction action,
  ) async {
    for (final path in action.photoPaths) {
      await _insertPhoto(db, action.id, action.plantId, path);
    }
  }

  Future<void> _insertPhoto(
    DatabaseExecutor db,
    String actionId,
    String plantId,
    String photoPath,
  ) async {
    if (photoPath.trim().isEmpty) {
      throw const FormatException('Chemin de photo vide');
    }
    await db.insert(
      'action_photos',
      {
        'id': _uuid.v4(),
        'action_id': actionId,
        'plant_id': plantId,
        'photo_path': photoPath,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
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

  Future<void> _applyBusinessEffects(
    DatabaseExecutor db,
    PlantAction action,
  ) async {
    final product = action.productUsed?.trim();
    final container = action.repotContainerType?.trim();
    if (action.isDone &&
        action.actionType == 'rempotage' &&
        (product?.isNotEmpty == true || container?.isNotEmpty == true)) {
      final updates = <String, Object?>{
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };
      if (container == 'plein_sol') {
        updates['pot_size'] = null;
      } else if (product?.isNotEmpty == true) {
        updates['pot_size'] = product;
      }
      if (container?.isNotEmpty == true) {
        updates['container_type'] = container;
      }
      final changed = await db.update(
        'plants',
        updates,
        where: 'id = ?',
        whereArgs: [action.plantId],
      );
      if (changed != 1) throw StateError('Plante de rempotage introuvable');
    }
    if (action.isDone &&
        (action.actionType == 'recolte' || action.actionType == 'mort')) {
      await _closeDirectPlantPlacements(db, action);
    }
    await _recalculatePlantEndState(db, action.plantId);
  }

  Future<void> _closeDirectPlantPlacements(
    DatabaseExecutor db,
    PlantAction action,
  ) async {
    final exitedAt = action.timestamp.toUtc().millisecondsSinceEpoch ~/ 1000;
    final updatedAt = DateTime.now().toUtc().toIso8601String();
    await db.rawUpdate(
      '''UPDATE zone_placements
         SET exited_at = CASE
               WHEN entered_at > ? THEN entered_at
               ELSE ?
             END,
             updated_at = ?
         WHERE plant_id = ? AND exited_at IS NULL''',
      [exitedAt, exitedAt, updatedAt, action.plantId],
    );
  }

  Future<void> _recalculatePlantEndState(
    DatabaseExecutor db,
    String plantId,
  ) async {
    final count = Sqflite.firstIntValue(
          await db.rawQuery(
            '''SELECT COUNT(*) FROM actions
               WHERE plant_id = ? AND action_type = 'recolte'
                 AND (status IS NULL OR status != 'planned')''',
            [plantId],
          ),
        ) ??
        0;
    final deadCount = Sqflite.firstIntValue(
          await db.rawQuery(
            '''SELECT COUNT(*) FROM actions
               WHERE plant_id = ? AND action_type = 'mort'
                 AND (status IS NULL OR status != 'planned')''',
            [plantId],
          ),
        ) ??
        0;
    final changed = await db.update(
      'plants',
      {
        'is_harvested': count > 0 ? 1 : 0,
        'is_dead': deadCount > 0 ? 1 : 0,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [plantId],
    );
    if (changed != 1) throw StateError('Plante de l’action introuvable');
  }

  void _validateAction(PlantAction action) {
    if (action.id.trim().isEmpty ||
        action.plantId.trim().isEmpty ||
        action.actionType.trim().isEmpty) {
      throw const FormatException('Action incomplète');
    }
    NumericInputParser.validateNonNegative(
      action.harvestWeightFresh,
      fieldLabel: 'Poids récolté',
    );
    NumericInputParser.validateNonNegative(
      action.harvestWeightStored,
      fieldLabel: 'Poids conservé',
    );
    NumericInputParser.validateNonNegative(
      action.harvestWeightWaste,
      fieldLabel: 'Poids écarté',
    );
  }
}

class ActionDeletionResult {
  final String plantId;
  final List<String> photoPaths;

  const ActionDeletionResult({
    required this.plantId,
    required this.photoPaths,
  });
}
