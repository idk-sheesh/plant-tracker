import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garden_journal/features/plants/presentation/screens/cutting_protocol_screen.dart';

void main() {
  testWidgets('affiche le jour courant et la regle du lot de 12 boutures',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CuttingProtocolScreen(
          startDate: DateTime(2026, 8, 1),
          referenceDate: DateTime(2026, 8, 12),
          cuttingCount: 12,
        ),
      ),
    );

    expect(find.text('Jour 11 — Test sans dôme'), findsOneWidget);
    expect(
        find.textContaining('Bouturage démarré le 01/08/2026'), findsOneWidget);
    expect(
      find.textContaining('remets le dôme dès 3 boutures flétris'),
      findsOneWidget,
    );

    await tester.scrollUntilVisible(
      find.textContaining('Retirer le dôme pendant 10 minutes'),
      200,
      scrollable: find.byType(Scrollable),
    );
    expect(
      find.textContaining('Retirer le dôme pendant 10 minutes'),
      findsOneWidget,
    );
    expect(
        find.text('Pour ce lot : seuil atteint à 3 boutures.'), findsOneWidget);
  });

  testWidgets('le bouton ouvre le calendrier Jardin', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GardenCuttingProtocolButton(
            startDate: DateTime(2026, 8, 1),
            cuttingCountProvider: () => 12,
          ),
        ),
      ),
    );

    await tester
        .tap(find.byKey(const ValueKey('open-garden-cutting-protocol')));
    await tester.pumpAndSettle();

    expect(find.text('Protocole Jardin'), findsOneWidget);
    expect(find.textContaining('12 boutures'), findsWidgets);
  });
}
