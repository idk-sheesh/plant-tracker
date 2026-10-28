import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garden_journal/features/actions/data/repositories/action_repository.dart';
import 'package:garden_journal/features/actions/domain/entities/plant_action.dart';
import 'package:garden_journal/features/actions/presentation/providers/action_provider.dart';
import 'package:garden_journal/features/groups/data/models/plant_group.dart';
import 'package:garden_journal/features/groups/data/repositories/group_repository.dart';
import 'package:garden_journal/features/groups/presentation/providers/group_provider.dart';
import 'package:garden_journal/features/plants/data/repositories/plant_repository.dart';
import 'package:garden_journal/features/plants/domain/entities/plant.dart';
import 'package:garden_journal/features/plants/presentation/providers/plant_provider.dart';

void main() {
  late FlutterExceptionHandler? previousErrorHandler;

  setUp(() {
    previousErrorHandler = FlutterError.onError;
    FlutterError.onError = (_) {};
  });

  tearDown(() => FlutterError.onError = previousErrorHandler);

  test('PlantProvider sort toujours du chargement et expose l’erreur',
      () async {
    final provider = PlantProvider(repository: _FailingPlantRepository());
    await provider.loadPlants();
    expect(provider.isLoading, isFalse);
    expect(provider.hasLoaded, isFalse);
    expect(provider.error, isNotNull);
  });

  test('GroupProvider sort toujours du chargement et expose l’erreur',
      () async {
    final provider = GroupProvider(repository: _FailingGroupRepository());
    await provider.loadGroups();
    expect(provider.isLoading, isFalse);
    expect(provider.hasLoaded, isFalse);
    expect(provider.error, isNotNull);
  });

  test('ActionProvider sort toujours du chargement et expose l’erreur',
      () async {
    final provider = ActionProvider(repository: _FailingActionRepository());
    await provider.loadActionsForPlant('plant-1');
    expect(provider.isLoading, isFalse);
    expect(provider.error, isNotNull);
    expect(provider.getActionsForPlant('plant-1'), isEmpty);
  });

  test('ActionProvider vide son cache après une restauration', () async {
    final repository = _ReloadActionRepository();
    final provider = ActionProvider(repository: repository);
    await provider.loadActionsForPlant('plant-1');
    expect(provider.getActionsForPlant('plant-1'), hasLength(1));

    repository.actions = [];
    final reloaded = await provider.reloadAfterRestore(
      reconcileNotifications: false,
    );

    expect(reloaded, isTrue);
    expect(provider.getActionsForPlant('plant-1'), isEmpty);
  });

  test('ActionProvider charge la vue globale des actions planifiées', () async {
    final now = DateTime.utc(2026, 8, 28);
    final provider = ActionProvider(
      repository: _PlannedActionRepository([
        PlantAction(
          id: 'planned-1',
          plantId: 'plant-1',
          actionType: 'arrosage',
          timestamp: now,
          createdAt: now,
          status: 'planned',
        ),
      ]),
    );

    await provider.loadPlannedActions();

    expect(provider.isPlannedLoading, isFalse);
    expect(provider.plannedError, isNull);
    expect(provider.plannedActions.single.id, 'planned-1');
  });

  test('ActionProvider peut modifier la liste planifiée chargée depuis SQLite',
      () async {
    final now = DateTime.utc(2026, 8, 28);
    final existing = PlantAction(
      id: 'planned-1',
      plantId: 'plant-1',
      actionType: 'rempotage',
      timestamp: now,
      createdAt: now,
      status: 'planned',
    );
    final repository = _PlannedActionRepository(
      List<PlantAction>.of([existing], growable: false),
    );
    final provider = ActionProvider(repository: repository);

    await provider.loadPlannedActions();
    final updated = existing.copyWith(
      timestamp: now.add(const Duration(days: 1)),
    );
    await provider.updateAction(updated);

    expect(provider.plannedActions, [updated]);
  });

  test('PlantProvider réussit une nouvelle tentative et distingue liste vide',
      () async {
    final repository = _RetryPlantRepository();
    final provider = PlantProvider(repository: repository);
    await provider.loadPlants();
    expect(provider.error, isNotNull);

    await provider.loadPlants();
    expect(provider.isLoading, isFalse);
    expect(provider.hasLoaded, isTrue);
    expect(provider.error, isNull);
    expect(provider.plants, isEmpty);
  });

  test('échec de suppression conserve la plante et expose l’erreur', () async {
    final repository = _DeleteFailPlantRepository();
    final provider = PlantProvider(repository: repository);
    await provider.loadPlants();

    await expectLater(provider.deletePlant('plant-1'), throwsStateError);

    expect(provider.plants, hasLength(1));
    expect(provider.error, contains('Suppression'));
  });
}

class _FailingPlantRepository extends PlantRepository {
  @override
  Future<List<Plant>> getAllPlants() => Future.error(StateError('db down'));
}

class _FailingGroupRepository extends GroupRepository {
  @override
  Future<List<PlantGroup>> getAllGroups() =>
      Future.error(StateError('db down'));
}

class _FailingActionRepository extends ActionRepository {
  @override
  Future<List<PlantAction>> getActionsForPlant(
    String plantId, {
    int? limit,
    int offset = 0,
  }) =>
      Future.error(StateError('db down'));
}

class _ReloadActionRepository extends ActionRepository {
  List<PlantAction> actions = [
    PlantAction(
      id: 'action-before-restore',
      plantId: 'plant-1',
      actionType: 'observation',
      timestamp: DateTime.utc(2026, 1, 2),
      createdAt: DateTime.utc(2026, 1, 2),
    ),
  ];

  @override
  Future<List<PlantAction>> getActionsForPlant(
    String plantId, {
    int? limit,
    int offset = 0,
  }) async =>
      actions;

  @override
  Future<Map<String, ActionHomeSummary>> getHomeSummaries() async => const {};

  @override
  Future<List<PlantAction>> getPlannedActions() async => const [];
}

class _PlannedActionRepository extends ActionRepository {
  final List<PlantAction> values;

  _PlannedActionRepository(this.values);

  @override
  Future<List<PlantAction>> getPlannedActions() async => values;

  @override
  Future<List<String>> updateAction(PlantAction action) async => const [];

  @override
  Future<Map<String, ActionHomeSummary>> getHomeSummaries() async => const {};
}

class _RetryPlantRepository extends PlantRepository {
  var attempts = 0;

  @override
  Future<List<Plant>> getAllPlants() async {
    attempts++;
    if (attempts == 1) throw StateError('db down');
    return const [];
  }
}

class _DeleteFailPlantRepository extends PlantRepository {
  final Plant plant = Plant(
    id: 'plant-1',
    name: 'Plant test',
    pottingDate: DateTime.utc(2026, 1, 1),
    cultureType: 'Terre',
    qrCode: 'plant:plant-1',
    createdAt: DateTime.utc(2026, 1, 1),
    updatedAt: DateTime.utc(2026, 1, 1),
  );

  @override
  Future<List<Plant>> getAllPlants() async => [plant];

  @override
  Future<PlantDeletionResult?> deletePlant(String id) =>
      Future.error(StateError('delete failed'));
}
