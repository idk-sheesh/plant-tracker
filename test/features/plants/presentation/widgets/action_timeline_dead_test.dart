import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garden_journal/features/actions/data/repositories/action_repository.dart';
import 'package:garden_journal/features/actions/domain/entities/plant_action.dart';
import 'package:garden_journal/features/actions/presentation/providers/action_provider.dart';
import 'package:garden_journal/features/plants/data/repositories/plant_repository.dart';
import 'package:garden_journal/features/plants/domain/entities/plant.dart';
import 'package:garden_journal/features/plants/presentation/providers/plant_provider.dart';
import 'package:garden_journal/features/plants/presentation/widgets/action_timeline.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('l action plante morte reste visible dans l historique',
      (tester) async {
    final now = DateTime.utc(2026, 8, 26, 10);
    final provider = ActionProvider(
      repository: _ActionRepository([
        PlantAction(
          id: 'death-1',
          plantId: 'plant-1',
          actionType: 'mort',
          timestamp: now,
          createdAt: now,
          completedAt: now,
        ),
      ]),
    );
    await provider.loadActionsForPlant('plant-1');

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: provider,
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ActionTimeline(plantId: 'plant-1'),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Plante morte'), findsOneWidget);
  });

  testWidgets('une plante morte est absente des cibles d un arrosage copie',
      (tester) async {
    final now = DateTime.utc(2026, 8, 28, 10);
    final actionProvider = ActionProvider(
      repository: _ActionRepository([
        PlantAction(
          id: 'watering-1',
          plantId: 'source',
          actionType: 'arrosage',
          timestamp: now,
          createdAt: now,
          completedAt: now,
        ),
      ]),
    );
    final plantProvider = PlantProvider(
      repository: _PlantRepository([
        _plant('source', 'Source', now),
        _plant('active', 'Cible active', now),
        _plant('dead', 'Cible morte', now, isDead: true),
        _plant('harvested', 'Cible récoltée', now, isHarvested: true),
      ]),
    );
    await actionProvider.loadActionsForPlant('source');
    await plantProvider.loadPlants();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: actionProvider),
          ChangeNotifierProvider.value(value: plantProvider),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ActionTimeline(plantId: 'source'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.more_horiz));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Copier vers plantes'));
    await tester.pumpAndSettle();

    expect(find.text('Cible active'), findsOneWidget);
    expect(find.text('Cible morte'), findsNothing);
    expect(find.text('Cible récoltée'), findsNothing);
  });
}

Plant _plant(
  String id,
  String name,
  DateTime now, {
  bool isDead = false,
  bool isHarvested = false,
}) =>
    Plant(
      id: id,
      name: name,
      pottingDate: now,
      cultureType: 'Terre',
      qrCode: 'plant:$id',
      createdAt: now,
      updatedAt: now,
      isDead: isDead,
      isHarvested: isHarvested,
    );

class _ActionRepository extends ActionRepository {
  final List<PlantAction> values;

  _ActionRepository(this.values);

  @override
  Future<List<PlantAction>> getActionsForPlant(
    String plantId, {
    int? limit,
    int offset = 0,
  }) async =>
      values.where((action) => action.plantId == plantId).toList();
}

class _PlantRepository extends PlantRepository {
  final List<Plant> values;

  _PlantRepository(this.values);

  @override
  Future<List<Plant>> getAllPlants() async => values;
}
