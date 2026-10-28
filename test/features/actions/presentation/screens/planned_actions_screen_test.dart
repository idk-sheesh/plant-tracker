import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:garden_journal/features/actions/data/repositories/action_repository.dart';
import 'package:garden_journal/features/actions/domain/entities/plant_action.dart';
import 'package:garden_journal/features/actions/presentation/providers/action_provider.dart';
import 'package:garden_journal/features/actions/presentation/screens/planned_actions_screen.dart';
import 'package:garden_journal/features/plants/data/repositories/plant_repository.dart';
import 'package:garden_journal/features/plants/domain/entities/plant.dart';
import 'package:garden_journal/features/plants/presentation/providers/plant_provider.dart';
import 'package:garden_journal/features/plants/presentation/screens/add_action_screen.dart';
import 'package:garden_journal/features/spaces/presentation/providers/space_provider.dart';
import '../../../../support/memory_form_draft_store.dart';

void main() {
  final now = DateTime.now();
  final plant = Plant(
      id: 'p',
      name: 'Une plante au nom particulièrement long pour le petit écran',
      location: 'outdoor',
      pottingDate: now,
      cultureType: 'Terre',
      qrCode: 'plant:p',
      createdAt: now,
      updatedAt: now);

  Future<_Actions> open(WidgetTester tester,
      {List<PlantAction> planned = const []}) async {
    final plants = PlantProvider(repository: _Plants(plant));
    final repository = _Actions(planned);
    await plants.loadPlants();
    await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: plants),
          ChangeNotifierProvider(
              create: (_) => ActionProvider(repository: repository)),
          ChangeNotifierProvider<SpaceProvider>(create: (_) => _Spaces()),
        ],
        child: MaterialApp(
            home: PlannedActionsScreen(draftStore: MemoryFormDraftStore()))));
    await tester.pumpAndSettle();
    return repository;
  }

  testWidgets(
      'consulter une suggestion ne crée rien, réaliser ouvre le bon formulaire',
      (tester) async {
    final repository = await open(tester);
    expect(repository.saved, isEmpty);
    expect(find.text('Vérifier le besoin d’eau'), findsNothing);
    await tester.tap(find.text('Réaliser'));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<AddActionScreen>(find.byType(AddActionScreen))
            .initialActionType,
        'observation');
    expect(repository.saved, isEmpty);
    await tester.tap(find.text('Enregistrer').first);
    await tester.pumpAndSettle();
    expect(repository.saved.single.actionType, 'observation');
    expect(repository.saved.single.isDone, isTrue);
    expect(find.text('Faire un point sur la plante'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'planifier préremplit demain et laisse la validation à l’utilisateur',
      (tester) async {
    final repository = await open(tester);
    await tester.tap(find.text('Planifier'));
    await tester.pumpAndSettle();
    final screen = tester.widget<AddActionScreen>(find.byType(AddActionScreen));
    expect(screen.initialDate!.isAfter(DateTime.now()), isTrue);
    expect(screen.initialActionType, 'observation');
    expect(repository.saved, isEmpty);
  });

  testWidgets('les actions planifiées restent lisibles en petite largeur',
      (tester) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await open(tester, planned: [
      PlantAction(
          id: 'plan',
          plantId: plant.id,
          actionType: 'observation',
          timestamp: now.subtract(const Duration(days: 3)),
          createdAt: now,
          status: 'planned')
    ]);
    await tester.tap(find.text('Planifiées'));
    await tester.pumpAndSettle();
    expect(find.text('Valider maintenant'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _Plants extends PlantRepository {
  final Plant plant;
  _Plants(this.plant);
  @override
  Future<List<Plant>> getAllPlants() async => [plant];
}

class _Spaces extends SpaceProvider {
  @override
  Future<void> refresh() async {}
}

class _Actions extends ActionRepository {
  final List<PlantAction> planned;
  final saved = <PlantAction>[];
  _Actions(this.planned);
  @override
  Future<List<PlantAction>> getPlannedActions() async => planned;
  @override
  Future<Map<String, ActionHomeSummary>> getHomeSummaries() async => {
        for (final action in saved)
          action.plantId: ActionHomeSummary(
              plantId: action.plantId,
              lastActivityAt: action.timestamp,
              lastObservationAt:
                  action.actionType == 'observation' ? action.timestamp : null),
      };
  @override
  Future<void> insertAction(PlantAction action) async {
    saved.add(action);
  }
}
