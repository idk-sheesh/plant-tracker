import 'package:flutter_test/flutter_test.dart';
import 'package:garden_journal/core/database/database_helper.dart';
import 'package:garden_journal/features/plants/data/repositories/plant_repository.dart';
import 'package:garden_journal/features/plants/domain/entities/plant.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../../support/database_test_utils.dart';

void main() {
  sqfliteFfiInit();

  late Database db;
  late PlantRepository repository;

  setUp(() async {
    db = await openMemoryDatabase();
    await DatabaseHelper.instance.createSchemaForTesting(db);
    repository = PlantRepository(database: db);
  });

  tearDown(() => db.close());

  test('copyWith peut réellement effacer les champs nullable', () {
    final plant = _plant(
      id: 'plant-1',
      photo: '/managed/old.jpg',
      variety: 'Variété',
      notes: 'Note',
      groupId: 'group-1',
    );

    final cleared = plant.copyWith(
      variety: null,
      potSize: null,
      photoPath: null,
      notes: null,
      groupId: null,
    );

    expect(cleared.variety, isNull);
    expect(cleared.potSize, isNull);
    expect(cleared.photoPath, isNull);
    expect(cleared.notes, isNull);
    expect(cleared.groupId, isNull);
  });

  test('mise à jour retourne uniquement ancienne photo devenue orpheline',
      () async {
    await repository.insertPlant(_plant(id: 'plant-1', photo: '/old.jpg'));

    final removed = await repository.updatePlant(
      _plant(id: 'plant-1', photo: '/new.jpg'),
    );

    expect(removed, ['/old.jpg']);
    expect((await repository.getPlantById('plant-1'))?.photoPath, '/new.jpg');
  });

  test('photo partagée reste conservée lors du remplacement', () async {
    await repository.insertPlant(_plant(id: 'plant-1', photo: '/shared.jpg'));
    await repository.insertPlant(_plant(id: 'plant-2', photo: '/shared.jpg'));

    final removed = await repository.updatePlant(
      _plant(id: 'plant-1', photo: null),
    );

    expect(removed, isEmpty);
  });

  test('une photo référencée par un espace survit au retrait de la plante',
      () async {
    await repository.insertPlant(_plant(id: 'plant-1', photo: '/shared.jpg'));
    await db.insert('zone_photos', {
      'id': 'space-photo',
      'zone_id': 'zone-main',
      'photo_path': '/shared.jpg',
      'captured_at': 1791288000,
      'created_at': '2026-10-06T12:00:00Z',
    });
    expect(await repository.updatePlant(_plant(id: 'plant-1', photo: null)),
        isEmpty);
    await repository.updatePlant(_plant(id: 'plant-1', photo: '/shared.jpg'));
    expect((await repository.deletePlant('plant-1'))!.photoPaths, isEmpty);
    expect(await db.query('zone_photos'), hasLength(1));
  });
}

Plant _plant({
  required String id,
  String? photo,
  String? variety,
  String? notes,
  String? groupId,
}) {
  final now = DateTime.utc(2026, 1, 1);
  return Plant(
    id: id,
    name: 'Plant $id',
    variety: variety,
    pottingDate: now,
    cultureType: 'indoor',
    potSize: '5 L',
    photoPath: photo,
    notes: notes,
    groupId: groupId,
    qrCode: 'plant:$id',
    createdAt: now,
    updatedAt: now,
  );
}
