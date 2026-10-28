import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:garden_journal/features/groups/presentation/providers/group_provider.dart';
import 'package:garden_journal/features/plants/domain/entities/plant.dart';
import 'package:garden_journal/features/plants/presentation/screens/create_plant_screen.dart';
import 'package:garden_journal/features/plants/presentation/screens/edit_plant_screen.dart';

void main() {
  testWidgets('création masque le volume quand le contenant est plein sol',
      (tester) async {
    await tester.pumpWidget(_withGroups(const CreatePlantScreen()));

    final fullGround = find.text('Plein sol').last;
    await tester.ensureVisible(fullGround);
    await tester.pump();
    await tester.tap(fullGround);
    await tester.pump();
    await tester.drag(find.byType(ListView).first, const Offset(0, -400));
    await tester.pump();

    expect(find.text('Taille du pot'), findsNothing);
    expect(find.text('Plein sol : aucun volume de pot à renseigner.'),
        findsOneWidget);
  });

  testWidgets('édition ne réaffiche pas un ancien volume pour plein sol',
      (tester) async {
    final now = DateTime(2026, 7, 22);
    final plant = Plant(
      id: 'plant-1',
      name: 'FJ',
      pottingDate: now,
      cultureType: 'Terre vivante',
      potSize: '15L',
      qrCode: 'plant:plant-1',
      createdAt: now,
      updatedAt: now,
      containerType: 'plein_sol',
    );

    await tester.pumpWidget(_withGroups(EditPlantScreen(plant: plant)));
    await tester.drag(find.byType(ListView), const Offset(0, -1000));
    await tester.pump();

    expect(find.text('Taille du pot'), findsNothing);
    expect(
      find.text('Plein sol : aucun volume de pot à renseigner.'),
      findsOneWidget,
    );
  });
}

Widget _withGroups(Widget child) => ChangeNotifierProvider<GroupProvider>(
      create: (_) => GroupProvider(),
      child: MaterialApp(home: child),
    );
