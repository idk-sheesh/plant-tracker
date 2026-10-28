import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garden_journal/features/plants/domain/entities/plant.dart';
import 'package:garden_journal/features/plants/presentation/widgets/qr_code_dialog.dart';

void main() {
  testWidgets('dialogue QR scrollable sur petit écran et grand texte',
      (tester) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final now = DateTime.utc(2026, 1, 1);
    final plant = Plant(
      id: 'plant-qr',
      name: 'Plante au nom volontairement très long',
      pottingDate: now,
      cultureType: 'Terre vivante',
      qrCode: 'plant:plant-qr',
      createdAt: now,
      updatedAt: now,
    );

    await tester.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(1.8)),
        child: Builder(builder: (context) {
          return Scaffold(
            body: FilledButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => QrCodeDialog(plant: plant),
              ),
              child: const Text('Ouvrir'),
            ),
          );
        }),
      ),
    ));
    await tester.tap(find.text('Ouvrir'));
    await tester.pumpAndSettle();

    expect(find.byType(SingleChildScrollView), findsWidgets);
    expect(find.text('Code QR Plante'), findsOneWidget);
    expect(find.text('Exporter STL impression 3D'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
