import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garden_journal/features/actions/presentation/widgets/harvest_weight_fields.dart';

void main() {
  testWidgets('reste utilisable en petite largeur avec texte agrandi',
      (tester) async {
    final fresh = TextEditingController();
    final stored = TextEditingController();
    final waste = TextEditingController();
    addTearDown(fresh.dispose);
    addTearDown(stored.dispose);
    addTearDown(waste.dispose);

    await tester.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(
          size: Size(320, 640),
          textScaler: TextScaler.linear(2),
        ),
        child: Scaffold(
          body: SingleChildScrollView(
            child: HarvestWeightFields(
              wetController: fresh,
              dryController: stored,
              wasteController: waste,
              decorationBuilder: (label, icon) => InputDecoration(
                labelText: label,
                prefixIcon: Icon(icon),
              ),
              helperText: 'Valeurs optionnelles',
            ),
          ),
        ),
      ),
    ));

    expect(find.byType(TextFormField), findsNWidgets(3));
    expect(find.text('Valeurs optionnelles'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
