import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/database/database_helper.dart';
import '../../domain/entities/zone_placement.dart';

class ZonePlacementRepository {
  static const _selectPlacements = '''
    SELECT placement.id,
           placement.zone_id,
           placement.plant_id,
           placement.group_id,
           CASE
             WHEN placement.plant_id IS NOT NULL
               THEN COALESCE(plant.name, placement.entity_name)
             WHEN placement.group_id IS NOT NULL
               THEN COALESCE(plant_group.name, placement.entity_name)
             ELSE placement.entity_name
           END AS entity_name,
           placement.entered_at,
           placement.exited_at,
           placement.note,
           placement.created_at,
           placement.updated_at
      FROM zone_placements AS placement
      LEFT JOIN plants AS plant ON plant.id = placement.plant_id
      LEFT JOIN groups AS plant_group ON plant_group.id = placement.group_id
  ''';

  final DatabaseHelper _databaseHelper;
  final Database? _database;
  final Uuid _uuid;

  ZonePlacementRepository({
    DatabaseHelper? databaseHelper,
    Database? database,
    Uuid uuid = const Uuid(),
  })  : _databaseHelper = databaseHelper ?? DatabaseHelper.instance,
        _database = database,
        _uuid = uuid;

  Future<Database> get _db async {
    if (_database != null) return _database;
    return _databaseHelper.database;
  }

  Future<List<ZonePlacement>> getActive() async {
    final db = await _db;
    final rows = await db.rawQuery(
      '''$_selectPlacements
         WHERE placement.exited_at IS NULL
         ORDER BY placement.entered_at DESC''',
    );
    return rows.map(ZonePlacement.fromMap).toList();
  }

  Future<int> closePlacementsForEndedPlants() async {
    final db = await _db;
    final nowIso = DateTime.now().toUtc().toIso8601String();
    return db.rawUpdate(
      '''UPDATE zone_placements
         SET exited_at = CASE
               WHEN entered_at > COALESCE(
                 (SELECT CAST(strftime('%s', plant.updated_at) AS INTEGER)
                    FROM plants AS plant
                   WHERE plant.id = zone_placements.plant_id),
                 entered_at
               ) THEN entered_at
               ELSE COALESCE(
                 (SELECT CAST(strftime('%s', plant.updated_at) AS INTEGER)
                    FROM plants AS plant
                   WHERE plant.id = zone_placements.plant_id),
                 entered_at
               )
             END,
             updated_at = ?
         WHERE exited_at IS NULL
           AND plant_id IN (
             SELECT id FROM plants
              WHERE is_dead = 1 OR is_harvested = 1
           )''',
      [nowIso],
    );
  }

  Future<List<ZonePlacement>> getForZone(String zoneId) async {
    final db = await _db;
    final rows = await db.rawQuery(
      '''$_selectPlacements
         WHERE placement.zone_id = ?
         ORDER BY placement.entered_at DESC''',
      [zoneId],
    );
    return rows.map(ZonePlacement.fromMap).toList();
  }

  Future<List<ZonePlacement>> getForPlant(String plantId) async {
    final db = await _db;
    final rows = await db.rawQuery(
      '''$_selectPlacements
         WHERE placement.plant_id = ?
         ORDER BY placement.entered_at DESC''',
      [plantId],
    );
    return rows.map(ZonePlacement.fromMap).toList();
  }

  Future<List<ZonePlacement>> getForGroup(String groupId) async {
    final db = await _db;
    final rows = await db.rawQuery(
      '''$_selectPlacements
         WHERE placement.group_id = ?
         ORDER BY placement.entered_at DESC''',
      [groupId],
    );
    return rows.map(ZonePlacement.fromMap).toList();
  }

  Future<void> closePlacement(
    ZonePlacement placement, {
    DateTime? exitedAt,
  }) async {
    if (!placement.isActive) return;
    final db = await _db;
    final exited = (exitedAt ?? DateTime.now()).toUtc();
    if (exited.isBefore(placement.enteredAt.toUtc())) {
      throw ArgumentError.value(exitedAt, 'exitedAt',
          'La date de sortie ne peut pas précéder la date d’entrée');
    }
    final changed = await db.update(
      'zone_placements',
      {
        'exited_at': exited.millisecondsSinceEpoch ~/ 1000,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'id = ? AND exited_at IS NULL',
      whereArgs: [placement.id],
    );
    if (changed != 1) {
      throw StateError('Placement déjà clôturé ou introuvable');
    }
  }

  Future<ZonePlacement> movePlant({
    required String plantId,
    required String plantName,
    required String zoneId,
    DateTime? enteredAt,
    String? note,
  }) {
    return _move(
      plantId: plantId,
      entityName: plantName,
      zoneId: zoneId,
      enteredAt: enteredAt,
      note: note,
    );
  }

  Future<ZonePlacement> moveGroup({
    required String groupId,
    required String groupName,
    required String zoneId,
    DateTime? enteredAt,
    String? note,
  }) {
    return _move(
      groupId: groupId,
      entityName: groupName,
      zoneId: zoneId,
      enteredAt: enteredAt,
      note: note,
    );
  }

  Future<ZonePlacement> _move({
    String? plantId,
    String? groupId,
    required String entityName,
    required String zoneId,
    DateTime? enteredAt,
    String? note,
  }) async {
    if ((plantId == null) == (groupId == null)) {
      throw ArgumentError('Un placement vise une plante ou un groupe');
    }
    final db = await _db;
    final entered = (enteredAt ?? DateTime.now()).toUtc();
    final enteredSeconds = entered.millisecondsSinceEpoch ~/ 1000;
    final nowIso = DateTime.now().toUtc().toIso8601String();
    final placement = ZonePlacement(
      id: _uuid.v4(),
      zoneId: zoneId,
      plantId: plantId,
      groupId: groupId,
      entityName: entityName,
      enteredAt: entered,
      note: note,
      createdAt: DateTime.parse(nowIso),
      updatedAt: DateTime.parse(nowIso),
    );

    await db.transaction((txn) async {
      final column = plantId != null ? 'plant_id' : 'group_id';
      final entityId = plantId ?? groupId;
      final active = await txn.query(
        'zone_placements',
        columns: const ['entered_at'],
        where: '$column = ? AND exited_at IS NULL',
        whereArgs: [entityId],
        limit: 1,
      );
      if (active.isNotEmpty &&
          enteredSeconds < (active.first['entered_at'] as int)) {
        throw StateError(
          'La date d’entrée précède le placement actuellement actif',
        );
      }
      await txn.update(
        'zone_placements',
        {'exited_at': enteredSeconds, 'updated_at': nowIso},
        where: '$column = ? AND exited_at IS NULL',
        whereArgs: [entityId],
      );
      await txn.insert('zone_placements', placement.toMap());
    });
    return placement;
  }
}
