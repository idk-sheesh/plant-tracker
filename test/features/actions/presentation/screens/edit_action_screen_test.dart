import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garden_journal/features/actions/domain/entities/plant_action.dart';
import 'package:garden_journal/features/actions/presentation/screens/edit_action_screen.dart';

void main() {
  testWidgets('permet de changer le type et adapte les champs', (tester) async {
    final timestamp = DateTime(2026, 7, 17, 10);
    final action = PlantAction(
      id: 'action-1',
      plantId: 'plant-1',
      actionType: 'observation',
      timestamp: timestamp,
      createdAt: timestamp,
      notes: 'Observation initiale',
    );

    await tester
        .pumpWidget(MaterialApp(home: EditActionScreen(action: action)));

    final typeSelector = find.byKey(const ValueKey('edit-action-type'));
    expect(typeSelector, findsOneWidget);

    await tester.tap(typeSelector);
    await tester.pumpAndSettle();

    expect(find.text('Recolte'), findsOneWidget);
    await tester.tap(find.text('Taille / tuteurage').last);
    await tester.pumpAndSettle();

    expect(find.text('Type de taille'), findsOneWidget);
    expect(find.text('Modifier — Taille / tuteurage'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
