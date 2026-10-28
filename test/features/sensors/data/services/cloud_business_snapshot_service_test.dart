import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:garden_journal/core/database/database_helper.dart';
import 'package:garden_journal/features/sensors/data/services/cloud_business_snapshot_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  test('publie seulement les champs de consultation et les liens métier',
      () async {
    final db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    addTearDown(db.close);
    await DatabaseHelper.instance.createSchemaForTesting(db);
    const stamp = '2026-09-20T10:00:00Z';
    await db.insert('groups', {
      'id': 'group-1',
      'name': 'Lot A',
      'created_at': stamp,
    });
    await db.insert('plants', {
      'id': 'plant-1',
      'name': 'Basilic',
      'variety': 'Genovese',
      'potting_date': stamp,
      'culture_type': 'croissance',
      'photo_path': '/private/photo.jpg',
      'notes': 'Note locale',
      'group_id': 'group-1',
      'qr_code': 'private-qr',
      'created_at': stamp,
      'updated_at': stamp,
    });
    final zone = (await db.query('cultivation_zones', limit: 1)).single;
    await db.insert('cultivation_zones', {
      'id': 'group-zone',
      'name': 'Espace du groupe',
      'type': 'indoor',
      'created_at': stamp,
      'updated_at': stamp,
    });
    await db.insert('zone_placements', {
      'id': 'group-placement',
      'zone_id': 'group-zone',
      'group_id': 'group-1',
      'entity_name': 'Lot A',
      'entered_at': 1789898500,
      'created_at': stamp,
      'updated_at': stamp,
    });
    await db.insert('zone_placements', {
      'id': 'placement-1',
      'zone_id': zone['id'],
      'plant_id': 'plant-1',
      'entity_name': 'Basilic',
      'entered_at': 1789898400,
      'created_at': stamp,
      'updated_at': stamp,
    });
    await db.insert('actions', {
      'id': 'action-1',
      'plant_id': 'plant-1',
      'action_type': 'arrosage',
      'timestamp': stamp,
      'quantity': 1.5,
      'quantity_unit': 'L',
      'notes': 'Arrosage du matin',
      'created_at': stamp,
    });

    final snapshot = await CloudBusinessSnapshotService(database: db).build();
    final plant = (snapshot['plants'] as List).single as Map<String, dynamic>;
    final action = (snapshot['actions'] as List).single as Map<String, dynamic>;
    expect(plant['groupName'], 'Lot A');
    // Une affectation directe reste prioritaire sur celle du groupe, même si
    // l'affectation du groupe est plus récente.
    expect(plant['spaceName'], zone['name']);
    expect(DateTime.parse(plant['lastActivityAt'] as String),
        DateTime.parse(stamp));
    expect(action['plantId'], 'plant-1');
    expect(action['quantity'], 1.5);
    final encoded = jsonEncode(snapshot);
    expect(encoded, isNot(contains('/private/photo.jpg')));
    expect(encoded, isNot(contains('private-qr')));
    expect(encoded, isNot(contains('photo_path')));
    expect(encoded, isNot(contains('base_url')));
  });
}
