import '../../../../core/database/database_helper.dart';
import 'package:sqflite/sqflite.dart';

/// Builds a privacy-limited, consistent read of the local cultivation journal.
/// Photos, file paths, QR payloads, device credentials and sensor settings stay
/// on the phone. Nothing is uploaded until the user presses Publish.
class CloudBusinessSnapshotService {
  final Database? database;

  const CloudBusinessSnapshotService({this.database});

  Future<Map<String, dynamic>> build() async {
    final db = database ?? await DatabaseHelper.instance.database;
    return db.transaction((txn) async {
      final plants = await txn.rawQuery('''
        SELECT p.id, p.name, p.variety, p.culture_type, p.is_harvested,
          p.is_dead, p.potting_date, p.created_at, p.updated_at, p.notes,
          g.name AS group_name, z.name AS space_name
        FROM plants p LEFT JOIN groups g ON g.id = p.group_id
        LEFT JOIN zone_placements pp ON pp.plant_id = p.id
          AND pp.exited_at IS NULL
        LEFT JOIN zone_placements gp ON gp.group_id = p.group_id
          AND gp.exited_at IS NULL
        LEFT JOIN cultivation_zones z ON z.id = COALESCE(pp.zone_id, gp.zone_id)
        ORDER BY p.id
      ''');
      final actions = await txn.rawQuery('''
        SELECT id, plant_id, action_type, timestamp, status, quantity,
          quantity_unit, ph, tds, product_used, pruning_type, notes,
          harvest_weight_fresh, harvest_weight_stored, harvest_weight_waste
        FROM actions ORDER BY id
      ''');
      final lastActivity = <String, DateTime>{};
      for (final action in actions) {
        if ((action['status'] as String? ?? 'done') == 'planned') continue;
        final plantId = action['plant_id'] as String;
        final timestamp = DateTime.parse(action['timestamp'] as String);
        final previous = lastActivity[plantId];
        if (previous == null || timestamp.isAfter(previous)) {
          lastActivity[plantId] = timestamp;
        }
      }
      return {
        'schemaVersion': 1,
        'generatedAt': DateTime.now().toUtc().toIso8601String(),
        'plants': [
          for (final p in plants)
            {
              'id': p['id'],
              'name': p['name'],
              'variety': p['variety'],
              'groupName': p['group_name'],
              'spaceName': p['space_name'],
              'cultureType': p['culture_type'],
              'status': p['is_dead'] == 1
                  ? 'dead'
                  : p['is_harvested'] == 1
                      ? 'harvested'
                      : 'active',
              'pottingDate': _utc(p['potting_date']),
              'createdAt': _utc(p['created_at']),
              'updatedAt': _utc(p['updated_at']),
              'lastActivityAt':
                  lastActivity[p['id']]?.toUtc().toIso8601String(),
              'notes': p['notes'],
            },
        ],
        'actions': [
          for (final a in actions)
            {
              'id': a['id'],
              'plantId': a['plant_id'],
              'type': a['action_type'],
              'timestamp': _utc(a['timestamp']),
              'status': a['status'] ?? 'done',
              'quantity': a['quantity'],
              'quantityUnit': a['quantity_unit'],
              'ph': a['ph'],
              'tds': a['tds'],
              'productUsed': a['product_used'],
              'pruningType': a['pruning_type'],
              'notes': a['notes'],
              'harvestWeightFresh': a['harvest_weight_fresh'],
              'harvestWeightStored': a['harvest_weight_stored'],
              'harvestWeightWaste': a['harvest_weight_waste'],
            },
        ],
      };
    });
  }

  static String _utc(Object? value) =>
      DateTime.parse(value as String).toUtc().toIso8601String();
}
