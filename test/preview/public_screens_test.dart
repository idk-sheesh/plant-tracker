import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garden_journal/core/theme/app_theme.dart';
import 'package:garden_journal/features/actions/data/repositories/action_repository.dart';
import 'package:garden_journal/features/actions/domain/entities/plant_action.dart';
import 'package:garden_journal/features/actions/presentation/providers/action_provider.dart';
import 'package:garden_journal/features/actions/presentation/screens/planned_actions_screen.dart';
import 'package:garden_journal/features/groups/presentation/providers/group_provider.dart';
import 'package:garden_journal/features/observations/data/repositories/observation_repository.dart';
import 'package:garden_journal/features/observations/domain/entities/observation_assessment.dart';
import 'package:garden_journal/features/observations/presentation/screens/observation_screen.dart';
import 'package:garden_journal/features/plants/data/repositories/plant_repository.dart';
import 'package:garden_journal/features/plants/domain/entities/plant.dart';
import 'package:garden_journal/features/plants/presentation/providers/plant_provider.dart';
import 'package:garden_journal/features/plants/presentation/screens/home_screen.dart';
import 'package:garden_journal/features/settings/presentation/screens/settings_screen.dart';
import 'package:provider/provider.dart';

import '../support/memory_form_draft_store.dart';

/// Real application widgets, rendered with fictional in-memory records only.
/// To regenerate images: flutter test test/preview/public_screens_test.dart
/// --dart-define=GENERATE_PREVIEWS=true
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final font = FontLoader('Roboto')
      ..addFont(rootBundle.load('assets/fonts/Roboto-Regular.ttf'))
      ..addFont(rootBundle.load('assets/fonts/Roboto-Bold.ttf'));
    await font.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  });

  for (final screen in ['home', 'tasks', 'observations', 'settings']) {
    testWidgets('public $screen fits a mobile screen', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final previousShadows = debugDisableShadows;
      debugDisableShadows = false;
      addTearDown(() => debugDisableShadows = previousShadows);

      final fixtures = _Fixtures();
      final plants = PlantProvider(repository: _Plants(fixtures.plants));
      final actions = ActionProvider(repository: _Actions(fixtures.now));
      final groups = GroupProvider();
      await plants.loadPlants();
      final key = GlobalKey();
      final page = switch (screen) {
        'home' => const HomeScreen(),
        'tasks' => PlannedActionsScreen(draftStore: MemoryFormDraftStore()),
        'observations' => ObservationScreen(
            repository: _Observations(fixtures.now),
            initialPlantId: 'tomato-a',
            draftStore: MemoryFormDraftStore()),
        _ => const SettingsScreen(),
      };

      await tester.pumpWidget(MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: plants),
            ChangeNotifierProvider.value(value: actions),
            ChangeNotifierProvider.value(value: groups),
          ],
          child: RepaintBoundary(
              key: key,
              child: MaterialApp(
                  debugShowCheckedModeBanner: false,
                  theme: AppTheme.lightTheme.copyWith(
                      textTheme: AppTheme.lightTheme.textTheme
                          .apply(fontFamily: 'Roboto'),
                      primaryTextTheme: AppTheme.lightTheme.primaryTextTheme
                          .apply(fontFamily: 'Roboto'),
                      appBarTheme: AppTheme.lightTheme.appBarTheme.copyWith(
                          titleTextStyle: AppTheme
                              .lightTheme.appBarTheme.titleTextStyle
                              ?.copyWith(fontFamily: 'Roboto'))),
                  home: page))));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      if (const bool.fromEnvironment('GENERATE_PREVIEWS')) {
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final picture = await boundary.toImage(pixelRatio: 2);
          final data = await picture.toByteData(format: ui.ImageByteFormat.png);
          final file = File('docs/preview/$screen.png');
          await file.parent.create(recursive: true);
          await file.writeAsBytes(data!.buffer.asUint8List());
          picture.dispose();
        });
      }
      await tester.pumpWidget(const SizedBox.shrink());
      plants.dispose();
      actions.dispose();
      groups.dispose();
      debugDisableShadows = previousShadows;
    });
  }
}

class _Fixtures {
  final now = DateTime.now();
  late final plants = [
    _plant('tomato-a', 'Tomate cerise A', 'Tomate cerise', 'TC01', 30),
    _plant('tomato-b', 'Tomate cerise B', 'Tomate cerise', 'TC02', 25),
    _plant('orchid', 'Orchidée blanche', 'Phalaenopsis', 'O01', 60),
  ];

  Plant _plant(String id, String name, String variety, String code, int age) =>
      Plant(
          id: id,
          name: name,
          variety: variety,
          observationCode: code,
          pottingDate: now.subtract(Duration(days: age)),
          cultureType: id == 'orchid'
              ? 'Écorces pour orchidées'
              : 'Terreau pour tomates',
          potSize: id == 'orchid' ? '2L' : '10L',
          location: id == 'orchid' ? 'indoor' : 'outdoor',
          origin: 'seed',
          wateringReminder: true,
          qrCode: 'plant:$id',
          createdAt: now.subtract(Duration(days: age)),
          updatedAt: now);
}

class _Plants extends PlantRepository {
  final List<Plant> values;
  _Plants(this.values);
  @override
  Future<List<Plant>> getAllPlants() async => values;
}

class _Actions extends ActionRepository {
  final DateTime now;
  _Actions(this.now);
  @override
  Future<Map<String, ActionHomeSummary>> getHomeSummaries() async => {
        for (final entry in {'tomato-a': 4, 'tomato-b': 1, 'orchid': 6}.entries)
          entry.key: ActionHomeSummary(
              plantId: entry.key,
              lastWaterAt: now.subtract(Duration(days: entry.value)),
              lastActivityAt: now.subtract(Duration(days: entry.value)),
              lastObservationAt: now.subtract(const Duration(days: 2))),
      };
  @override
  Future<List<PlantAction>> getPlannedActions() async => [
        PlantAction(
            id: 'watering-plan',
            plantId: 'orchid',
            actionType: 'arrosage',
            timestamp: now.add(const Duration(days: 1)),
            status: 'planned',
            notes: 'Vérifier le substrat avant d’arroser.',
            createdAt: now),
      ];
}

class _Observations extends ObservationRepository {
  final DateTime now;
  _Observations(this.now);
  @override
  Future<List<ObservationAssessment>> getAll() async => [
        for (final id in ['tomato-a', 'tomato-b'])
          ObservationAssessment(
              id: 'observation-$id',
              plantId: id,
              stage: 'growth',
              observedAt: now,
              scores: {'vigor': id == 'tomato-a' ? 4 : 5, 'rooting': 4},
              notes: 'Feuillage sain, croissance régulière.',
              createdAt: now),
      ];
}
