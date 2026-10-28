import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:garden_journal/features/observations/data/repositories/observation_repository.dart';
import 'package:garden_journal/features/observations/domain/entities/observation_assessment.dart';
import 'package:garden_journal/features/observations/presentation/screens/observation_screen.dart';
import 'package:garden_journal/features/observations/presentation/screens/observation_assessment_screen.dart';
import 'package:garden_journal/features/plants/data/repositories/plant_repository.dart';
import 'package:garden_journal/features/plants/domain/entities/plant.dart';
import 'package:garden_journal/features/plants/presentation/providers/plant_provider.dart';
import '../../support/memory_form_draft_store.dart';

void main() {
  final now = DateTime(2026, 10, 20);
  Plant plant(String id, String code) => Plant(
      id: id,
      name: 'Plante $id',
      variety: 'Même variété',
      observationCode: code,
      pottingDate: now,
      cultureType: 'Terre',
      qrCode: 'plant:$id',
      createdAt: now,
      updatedAt: now);

  testWidgets(
      'comparaison mobile : même variété, dernier relevé par stade, valeurs vides',
      (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final plants = PlantProvider(
        repository: _Plants([
      plant('1', 'P01'),
      plant('2', 'P02').copyWith(variety: ' même variété '),
      plant('other', 'P03').copyWith(variety: 'Autre'),
    ]));
    await plants.loadPlants();
    final repository = _Assessments([
      ObservationAssessment(
          id: 'old',
          plantId: '1',
          stage: 'growth',
          observedAt: now.subtract(const Duration(days: 1)),
          scores: {'vigor': 1},
          createdAt: now),
      ObservationAssessment(
          id: 'latest',
          plantId: '1',
          stage: 'growth',
          observedAt: now,
          scores: {'vigor': 4},
          createdAt: now),
      ObservationAssessment(
          id: 'flowering',
          plantId: '1',
          stage: 'flowering',
          observedAt: now,
          scores: {'fruit_quality': 5},
          createdAt: now),
    ]);
    await tester.pumpWidget(ChangeNotifierProvider.value(
        value: plants,
        child: MaterialApp(
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: const TextScaler.linear(1.3)),
                child: child!),
            home: ObservationScreen(
                repository: repository, initialPlantId: '1'))));
    await tester.pumpAndSettle();
    expect(find.text('Noter les 2 plantes à la suite'), findsOneWidget);
    await tester.scrollUntilVisible(find.byType(DataTable), 200,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('4 / 5'), findsOneWidget);
    expect(find.text('5 / 5'), findsNothing);
    expect(find.text('Non noté'), findsOneWidget);
    expect(tester.takeException(), isNull);

    final stage = find.byType(DropdownButtonFormField<String>).last;
    await tester.ensureVisible(stage);
    await tester.tap(stage);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.byType(DataTable), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Floraison').last);
    await tester.pumpAndSettle();
    expect(find.text('5 / 5'), findsOneWidget);
    expect(find.text('4 / 5'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'la saisie en série enregistre une observation indépendante par plante',
      (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final plants = PlantProvider(
        repository: _Plants([plant('1', 'P01'), plant('2', 'P02')]));
    await plants.loadPlants();
    final repository = _Assessments([]);
    await tester.pumpWidget(ChangeNotifierProvider.value(
        value: plants,
        child: MaterialApp(
            home: ObservationScreen(
                repository: repository, draftStore: MemoryFormDraftStore()))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Noter les 2 plantes à la suite'));
    await tester.pumpAndSettle();
    for (final id in ['1', '2']) {
      expect(find.byType(ObservationAssessmentScreen), findsOneWidget);
      final notes =
          find.widgetWithText(TextField, 'Notes et conditions d’observation');
      await tester.scrollUntilVisible(notes, 500,
          scrollable: find.byType(Scrollable).first);
      await tester.enterText(notes, 'Observation de $id');
      final save = find.text('Enregistrer l’observation');
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();
    }
    expect(repository.values.map((a) => a.plantId).toSet(), {'1', '2'});
    expect(repository.values.map((a) => a.id).toSet(), hasLength(2));
    expect(repository.values.every((a) => a.scores.isEmpty), isTrue);
    expect(find.byType(ObservationAssessmentScreen), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

class _Plants extends PlantRepository {
  final List<Plant> values;
  _Plants(this.values);
  @override
  Future<List<Plant>> getAllPlants() async => values;
}

class _Assessments extends ObservationRepository {
  final List<ObservationAssessment> values;
  _Assessments(this.values);
  @override
  Future<List<ObservationAssessment>> getAll() async =>
      List.of(values)..sort((a, b) => b.observedAt.compareTo(a.observedAt));
  @override
  Future<void> save(ObservationAssessment assessment,
      {bool editing = false}) async {
    assessment.validate();
    values.removeWhere((a) => a.id == assessment.id);
    values.add(assessment);
  }
}
