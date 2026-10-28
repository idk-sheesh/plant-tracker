import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garden_journal/features/actions/data/repositories/action_repository.dart';
import 'package:garden_journal/features/actions/presentation/providers/action_provider.dart';
import 'package:garden_journal/features/groups/presentation/providers/group_provider.dart';
import 'package:garden_journal/features/plants/data/repositories/plant_repository.dart';
import 'package:garden_journal/features/plants/domain/entities/plant.dart';
import 'package:garden_journal/features/plants/presentation/providers/plant_provider.dart';
import 'package:garden_journal/features/plants/presentation/screens/home_screen.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('dehors reste dans actives sauf rappel explicitement activé',
      (tester) async {
    final now = DateTime.now();
    final plantProvider = PlantProvider(
        repository: _HomePlantRepository([
      _plant('rain', 'Sous la pluie', now).copyWith(location: 'outdoor'),
      _plant('roof', 'Sous abri', now)
          .copyWith(location: 'outdoor', wateringReminder: true),
    ]));
    final actionProvider =
        ActionProvider(repository: _HomeActionRepository({}));
    await plantProvider.loadPlants();
    await tester.pumpWidget(MultiProvider(providers: [
      ChangeNotifierProvider.value(value: plantProvider),
      ChangeNotifierProvider.value(value: actionProvider),
      ChangeNotifierProvider(create: (_) => GroupProvider()),
    ], child: const MaterialApp(home: HomeScreen())));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Masquer les plantes a suivre (1)'));
    await tester.pump();
    expect(find.text('Sous abri'), findsNothing);
    expect(find.text('Sous la pluie'), findsOneWidget);
    expect(find.text('Rappel désactivé'), findsOneWidget);
  });
  testWidgets('les sections a suivre et actives peuvent etre repliees',
      (tester) async {
    final now = DateTime.now();
    final plants = [
      _plant('follow-up', 'Bouture a suivre', now),
      _plant('active', 'Plante active', now),
    ];
    final plantProvider = PlantProvider(
      repository: _HomePlantRepository(plants),
    );
    final actionProvider = ActionProvider(
      repository: _HomeActionRepository({
        'active': ActionHomeSummary(
          plantId: 'active',
          lastWaterAt: now,
          lastActivityAt: now,
        ),
      }),
    );

    await plantProvider.loadPlants();
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: plantProvider),
          ChangeNotifierProvider.value(value: actionProvider),
          ChangeNotifierProvider(create: (_) => GroupProvider()),
        ],
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Bouture a suivre'), findsOneWidget);
    expect(find.text('Plante active'), findsOneWidget);

    await tester.tap(find.text('Masquer les plantes a suivre (1)'));
    await tester.pump();
    expect(find.text('Bouture a suivre'), findsNothing);
    expect(find.text('Voir les plantes a suivre (1)'), findsOneWidget);

    await tester.ensureVisible(find.text('Masquer les plantes actives (1)'));
    await tester.tap(find.text('Masquer les plantes actives (1)'));
    await tester.pump();
    expect(find.text('Plante active'), findsNothing);
    expect(find.text('Voir les plantes actives (1)'), findsOneWidget);
  });
}

Plant _plant(String id, String name, DateTime now) => Plant(
      id: id,
      name: name,
      pottingDate: now.subtract(const Duration(days: 10)),
      cultureType: 'Terre',
      potSize: '5L',
      qrCode: 'plant:$id',
      createdAt: now,
      updatedAt: now,
    );

class _HomePlantRepository extends PlantRepository {
  final List<Plant> values;

  _HomePlantRepository(this.values);

  @override
  Future<List<Plant>> getAllPlants() async => values;
}

class _HomeActionRepository extends ActionRepository {
  final Map<String, ActionHomeSummary> values;

  _HomeActionRepository(this.values);

  @override
  Future<Map<String, ActionHomeSummary>> getHomeSummaries() async => values;
}
