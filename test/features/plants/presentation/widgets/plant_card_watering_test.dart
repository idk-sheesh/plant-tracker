import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:garden_journal/features/actions/data/repositories/action_repository.dart';
import 'package:garden_journal/features/actions/domain/entities/plant_action.dart';
import 'package:garden_journal/features/actions/presentation/providers/action_provider.dart';
import 'package:garden_journal/features/groups/presentation/providers/group_provider.dart';
import 'package:garden_journal/features/plants/domain/entities/plant.dart';
import 'package:garden_journal/features/plants/presentation/widgets/plant_card.dart';

void main() {
  testWidgets(
      'l’arrosage rapide conserve volume, pH et TDS saisis avec virgules',
      (tester) async {
    final now = DateTime.now();
    final repository = _Actions();
    await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => GroupProvider()),
          ChangeNotifierProvider(
              create: (_) => ActionProvider(repository: repository)),
        ],
        child: MaterialApp(
            home: Scaffold(
                body: PlantCard(
                    plant: Plant(
          id: 'p',
          name: 'Plante',
          pottingDate: now,
          cultureType: 'Terre',
          qrCode: 'plant:p',
          createdAt: now,
          updatedAt: now,
        ))))));
    await tester.tap(find.byTooltip('Arrosage rapide'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Volume (L)'), '1,5');
    await tester.enterText(find.widgetWithText(TextField, 'pH'), '6,4');
    await tester.enterText(
        find.widgetWithText(TextField, 'TDS (ppm)'), '750,5');
    await tester.tap(find.text('Enregistrer'));
    await tester.pumpAndSettle();
    expect(repository.saved.single.quantity, 1.5);
    expect(repository.saved.single.ph, 6.4);
    expect(repository.saved.single.tds, 750.5);
    expect(tester.takeException(), isNull);
  });
}

class _Actions extends ActionRepository {
  final saved = <PlantAction>[];
  @override
  Future<void> insertAction(PlantAction action) async {
    saved.add(action);
  }

  @override
  Future<Map<String, ActionHomeSummary>> getHomeSummaries() async => {};
}
