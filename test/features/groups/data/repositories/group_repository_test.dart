import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:garden_journal/core/database/database_helper.dart';
import 'package:garden_journal/features/groups/data/models/plant_group.dart';
import 'package:garden_journal/features/groups/data/repositories/group_repository.dart';
import 'package:garden_journal/features/groups/presentation/providers/group_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../../support/database_test_utils.dart';

void main() {
  sqfliteFfiInit();

  test('creation d’un groupe le rend visible dans le provider et SQLite',
      () async {
    final db = await openMemoryDatabase();
    addTearDown(db.close);
    await DatabaseHelper.instance.createSchemaForTesting(db);
    final provider = GroupProvider(repository: GroupRepository(database: db));
    await provider.loadGroups();

    final group = await provider.createGroup(
      name: 'Nouvelle session',
      color: Colors.green,
    );

    expect(group.name, 'Nouvelle session');
    expect(provider.getGroupById(group.id), isNotNull);
    expect(await db.query('groups', where: 'id = ?', whereArgs: [group.id]),
        hasLength(1));
  });

  test('suppression parent persiste enfants détachés après réouverture',
      () async {
    final directory =
        await Directory.systemTemp.createTemp('gardenjournal-group-');
    addTearDown(() => directory.delete(recursive: true));
    final dbPath = '${directory.path}${Platform.pathSeparator}groups.sqlite';
    var db = await databaseFactoryFfi.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    await db.execute('PRAGMA foreign_keys = ON');
    await DatabaseHelper.instance.createSchemaForTesting(db);
    final repository = GroupRepository(database: db);
    final now = DateTime.utc(2026, 1, 1);
    await repository.insertGroup(
      PlantGroup(
        id: 'parent',
        name: 'Parent',
        color: Colors.green,
        createdAt: now,
      ),
    );
    for (final id in const ['child-1', 'child-2']) {
      await repository.insertGroup(
        PlantGroup(
          id: id,
          name: id,
          color: Colors.lightGreen,
          createdAt: now,
          parentGroupId: 'parent',
        ),
      );
    }
    await db.insert('plants', {
      'id': 'plant-1',
      'name': 'Plante',
      'potting_date': now.toIso8601String(),
      'culture_type': 'indoor',
      'group_id': 'parent',
      'qr_code': 'plant:plant-1',
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
    });
    await db.insert('actions', {
      'id': 'action-1',
      'plant_id': 'plant-1',
      'action_type': 'observation',
      'timestamp': now.toIso8601String(),
      'created_at': now.toIso8601String(),
    });
    await db.insert('action_photos', {
      'id': 'photo-1',
      'action_id': 'action-1',
      'plant_id': 'plant-1',
      'photo_path': '/tmp/photo.jpg',
      'created_at': now.toIso8601String(),
    });

    await repository.deleteGroup('parent');
    await db.close();
    db = await databaseFactoryFfi.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    addTearDown(db.close);
    await db.execute('PRAGMA foreign_keys = ON');

    final children = await db.query('groups', orderBy: 'id');
    expect(children, hasLength(2));
    expect(children.every((row) => row['parent_group_id'] == null), isTrue);
    expect((await db.query('plants')).single['group_id'], isNull);
    expect(await db.query('actions'), hasLength(1));
    expect(await db.query('action_photos'), hasLength(1));
    expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
  });
}
