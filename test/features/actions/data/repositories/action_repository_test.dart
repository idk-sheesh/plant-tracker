import 'package:flutter_test/flutter_test.dart';
import 'package:garden_journal/core/database/database_helper.dart';
import 'package:garden_journal/features/actions/data/repositories/action_repository.dart';
import 'package:garden_journal/features/actions/domain/entities/plant_action.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../../support/database_test_utils.dart';

void main() {
  sqfliteFfiInit();

  late Database db;
  late ActionRepository repository;

  setUp(() async {
    db = await openMemoryDatabase();
    await DatabaseHelper.instance.createSchemaForTesting(db);
    await db.insert('plants', _plant('plant-1'));
    repository = ActionRepository(database: db);
  });

  tearDown(() => db.close());

  test('copyWith permet de vider les valeurs optionnelles', () {
    final action = _action(
      id: 'nullable',
      type: 'recolte',
      fresh: 10,
      stored: 5,
      waste: 1,
      product: 'Produit',
    ).copyWith(notes: 'Note');

    final cleared = action.copyWith(
      productUsed: null,
      notes: null,
      harvestWeightFresh: null,
      harvestWeightStored: null,
      harvestWeightWaste: null,
      completedAt: null,
    );

    expect(cleared.productUsed, isNull);
    expect(cleared.notes, isNull);
    expect(cleared.harvestWeightFresh, isNull);
    expect(cleared.harvestWeightStored, isNull);
    expect(cleared.harvestWeightWaste, isNull);
    expect(cleared.completedAt, isNull);
  });

  test('action, photos et récolte sont insérées atomiquement', () async {
    final action = _action(
      id: 'harvest-1',
      type: 'recolte',
      photos: const ['/managed/one.jpg', '/managed/two.jpg'],
      fresh: 120.5,
      stored: 42.5,
      waste: 8,
    );

    await repository.insertAction(action);

    expect(await db.query('actions'), hasLength(1));
    expect(await db.query('action_photos'), hasLength(2));
    expect((await db.query('plants')).single['is_harvested'], 1);
    final loaded = await repository.getActionById(action.id);
    expect(loaded?.harvestWeightFresh, 120.5);
    expect(loaded?.photoPaths, hasLength(2));
  });

  test('échec photo annule action et état de récolte', () async {
    final action = _action(
      id: 'invalid-photo',
      type: 'recolte',
      photos: const [''],
      fresh: 10,
    );

    await expectLater(repository.insertAction(action), throwsFormatException);

    expect(await db.query('actions'), isEmpty);
    expect(await db.query('action_photos'), isEmpty);
    expect((await db.query('plants')).single['is_harvested'], 0);
  });

  test('suppression de la dernière récolte réactive la plante', () async {
    final first = _action(id: 'harvest-1', type: 'recolte');
    final second = _action(id: 'harvest-2', type: 'recolte');
    await repository.insertAction(first);
    await repository.insertAction(second);

    await repository.deleteAction(first.id);
    expect((await db.query('plants')).single['is_harvested'], 1);

    await repository.deleteAction(second.id);
    expect((await db.query('plants')).single['is_harvested'], 0);
  });

  test('modifier le type persiste et recalcule l’état de récolte', () async {
    final harvest = _action(
      id: 'harvest-edited',
      type: 'recolte',
      fresh: 80,
      stored: 25,
    );
    await repository.insertAction(harvest);
    expect((await db.query('plants')).single['is_harvested'], 1);

    final edited = harvest.copyWith(
      actionType: 'observation',
      harvestWeightFresh: null,
      harvestWeightStored: null,
    );
    await repository.updateAction(edited);

    final loaded = await repository.getActionById(harvest.id);
    expect(loaded?.actionType, 'observation');
    expect(loaded?.harvestWeightFresh, isNull);
    expect(loaded?.harvestWeightStored, isNull);
    expect((await db.query('plants')).single['is_harvested'], 0);
  });

  test('une action mort archive la plante sans supprimer son historique',
      () async {
    await db.insert('zone_placements', {
      'id': 'placement-death-1',
      'zone_id': 'zone-collection',
      'plant_id': 'plant-1',
      'entity_name': 'Plant 1',
      'entered_at': DateTime.utc(2026, 1, 1).millisecondsSinceEpoch ~/ 1000,
      'created_at': '2026-01-01T00:00:00Z',
      'updated_at': '2026-01-01T00:00:00Z',
    });
    final death = _action(id: 'death-1', type: 'mort');

    await repository.insertAction(death);

    expect((await db.query('plants')).single['is_dead'], 1);
    expect(await db.query('actions'), hasLength(1));
    expect((await db.query('zone_placements')).single['exited_at'], isNotNull);

    await repository.deleteAction(death.id);
    expect((await db.query('plants')).single['is_dead'], 0);
  });

  test('rempotage met à jour pot et contenant dans la transaction', () async {
    final action = _action(
      id: 'repot-1',
      type: 'rempotage',
      product: '18 L',
      repotContainerType: 'pot_tissu',
    );

    await repository.insertAction(action);

    final plant = (await db.query('plants')).single;
    expect(plant['pot_size'], '18 L');
    expect(plant['container_type'], 'pot_tissu');
  });

  test('rempotage en plein sol efface le volume de pot', () async {
    await db.update(
      'plants',
      {'pot_size': '12L', 'container_type': 'pot'},
      where: 'id = ?',
      whereArgs: ['plant-1'],
    );

    await repository.insertAction(
      _action(
        id: 'repot-ground-1',
        type: 'rempotage',
        repotContainerType: 'plein_sol',
      ),
    );

    final plant = (await db.query('plants')).single;
    expect(plant['pot_size'], isNull);
    expect(plant['container_type'], 'plein_sol');
  });

  test('lecture paginée charge les photos en groupe', () async {
    for (var index = 0; index < 3; index++) {
      await repository.insertAction(
        _action(
          id: 'action-$index',
          type: 'observation',
          photos: ['/managed/$index.jpg'],
          timestamp: DateTime.utc(2026, 1, index + 1),
        ),
      );
    }

    final page = await repository.getActionsForPlant('plant-1', limit: 2);

    expect(page, hasLength(2));
    expect(page.first.id, 'action-2');
    expect(page.first.photoPaths, ['/managed/2.jpg']);
  });

  test('lecture par défaut ne tronque pas l historique à 100 actions',
      () async {
    final batch = db.batch();
    for (var index = 0; index < 125; index++) {
      batch.insert(
        'actions',
        _action(
          id: 'history-$index',
          type: 'observation',
          timestamp: DateTime.utc(2026, 1, 1).add(Duration(hours: index)),
        ).toMap(),
      );
    }
    await batch.commit(noResult: true);

    final history = await repository.getActionsForPlant('plant-1');

    expect(history, hasLength(125));
    expect(history.first.id, 'history-124');
    expect(history.last.id, 'history-0');
  });

  test('le bouturage relié apparaît aussi dans l’historique de la mère',
      () async {
    await db.insert('plants', _plant('parent-1'));
    final cutting = _action(id: 'cutting-1', type: 'bouturage').copyWith(
      parentPlantId: 'parent-1',
      quantity: 3,
    );
    await repository.insertAction(cutting);

    final cuttingHistory = await repository.getActionsForPlant('plant-1');
    final parentHistory = await repository.getActionsForPlant('parent-1');

    expect(cuttingHistory.map((action) => action.id), contains(cutting.id));
    expect(parentHistory.map((action) => action.id), contains(cutting.id));
    expect(parentHistory.single.parentPlantId, 'parent-1');
  });

  test('lecture des actions planifiées est filtrée et chronologique', () async {
    final later = _action(
      id: 'planned-later',
      type: 'observation',
      timestamp: DateTime.utc(2026, 3, 2),
    ).copyWith(status: 'planned', completedAt: null);
    final earlier = _action(
      id: 'planned-earlier',
      type: 'arrosage',
      photos: const ['/managed/planned.jpg'],
      timestamp: DateTime.utc(2026, 3, 1),
    ).copyWith(status: 'planned', completedAt: null);
    await repository.insertAction(later);
    await repository.insertAction(
      _action(id: 'done', type: 'observation'),
    );
    await repository.insertAction(earlier);

    final planned = await repository.getPlannedActions();

    expect(planned.map((action) => action.id), [earlier.id, later.id]);
    expect(planned.first.photoPaths, ['/managed/planned.jpg']);
  });

  test(
      'ne nettoie une photo modifiée que lorsque sa dernière référence disparaît',
      () async {
    const shared = '/managed/shared.jpg';
    final first = _action(
      id: 'shared-first',
      type: 'observation',
      photos: const [shared],
    );
    final second = _action(
      id: 'shared-second',
      type: 'observation',
      photos: const [shared],
    );
    await repository.insertAction(first);
    await repository.insertAction(second);

    expect(await repository.updateAction(first.copyWith(photoPaths: const [])),
        isEmpty);
    expect(
      await repository.updateAction(second.copyWith(photoPaths: const [])),
      [shared],
    );
  });

  test('conserve une photo d’action encore utilisée comme photo de plante',
      () async {
    const shared = '/managed/plant-cover.jpg';
    await db.update(
      'plants',
      {'photo_path': shared},
      where: 'id = ?',
      whereArgs: ['plant-1'],
    );
    final action = _action(
      id: 'plant-cover-action',
      type: 'observation',
      photos: const [shared],
    );
    await repository.insertAction(action);

    expect(
      await repository.updateAction(action.copyWith(photoPaths: const [])),
      isEmpty,
    );
  });

  test('retourne la derniere floraison terminee des plantes demandees',
      () async {
    await db.insert('plants', _plant('plant-2'));
    await repository.insertAction(
      _action(
        id: 'flower-old',
        type: 'floraison',
        timestamp: DateTime.utc(2026, 1, 10),
      ),
    );
    await repository.insertAction(
      _action(
        id: 'flower-latest',
        type: 'floraison',
        timestamp: DateTime.utc(2026, 2, 10),
      ),
    );
    await repository.insertAction(
      _action(
        id: 'flower-planned',
        type: 'floraison',
        timestamp: DateTime.utc(2026, 3, 10),
      ).copyWith(status: 'planned', completedAt: null),
    );
    await repository.insertAction(
      _action(
        id: 'flower-other-plant',
        type: 'floraison',
        timestamp: DateTime.utc(2026, 2, 15),
      ).copyWith(plantId: 'plant-2'),
    );

    final starts = await repository.getLatestFloweringStarts(
      const ['plant-1', 'plant-2', 'plant-without-flowering'],
    );

    expect(starts['plant-1'], DateTime.utc(2026, 2, 10));
    expect(starts['plant-2'], DateTime.utc(2026, 2, 15));
    final summaries = await repository.getHomeSummaries();
    expect(summaries['plant-1']!.lastFloweringAt, DateTime.utc(2026, 2, 10));
    expect(summaries['plant-1']!.lastObservationAt, isNull);
    expect(starts, isNot(contains('plant-without-flowering')));
    expect(await repository.getLatestFloweringStarts(const []), isEmpty);
  });

  test('suppression plante cascade actions et photos', () async {
    await repository.insertAction(
      _action(
        id: 'action-cascade',
        type: 'observation',
        photos: const ['/managed/cascade.jpg'],
      ),
    );

    await db.delete('plants', where: 'id = ?', whereArgs: ['plant-1']);

    expect(await db.query('actions'), isEmpty);
    expect(await db.query('action_photos'), isEmpty);
    expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
  });
}

Map<String, Object?> _plant(String id) => {
      'id': id,
      'name': 'Plante test',
      'potting_date': '2026-01-01T00:00:00Z',
      'culture_type': 'indoor',
      'qr_code': 'plant:$id',
      'created_at': '2026-01-01T00:00:00Z',
      'updated_at': '2026-01-01T00:00:00Z',
    };

PlantAction _action({
  required String id,
  required String type,
  List<String> photos = const [],
  double? fresh,
  double? stored,
  double? waste,
  String? product,
  String? repotContainerType,
  DateTime? timestamp,
}) {
  final time = timestamp ?? DateTime.utc(2026, 2, 1);
  return PlantAction(
    id: id,
    plantId: 'plant-1',
    actionType: type,
    timestamp: time,
    createdAt: time,
    completedAt: time,
    photoPaths: photos,
    harvestWeightFresh: fresh,
    harvestWeightStored: stored,
    harvestWeightWaste: waste,
    productUsed: product,
    repotContainerType: repotContainerType,
  );
}
