import 'package:sqflite/sqflite.dart';

import '../../../../core/database/database_helper.dart';
import '../../domain/entities/zone_photo.dart';

class ZonePhotoRepository {
  final Database? _databaseOverride;
  ZonePhotoRepository({Database? database}) : _databaseOverride = database;

  Future<Database> get _db async =>
      _databaseOverride ?? await DatabaseHelper.instance.database;

  Future<List<ZonePhoto>> getForZone(String zoneId) async {
    final rows = await (await _db).query('zone_photos',
        where: 'zone_id = ?',
        whereArgs: [zoneId],
        orderBy: 'captured_at DESC, created_at DESC');
    return rows.map(ZonePhoto.fromMap).toList();
  }

  Future<void> insert(ZonePhoto photo) async {
    await (await _db).insert('zone_photos', photo.toMap(),
        conflictAlgorithm: ConflictAlgorithm.abort);
  }
}
