import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garden_journal/core/widgets/photo_viewer_screen.dart';
import 'package:garden_journal/core/widgets/safe_file_image.dart';

void main() {
  testWidgets('affiche un fallback stable et accessible si le fichier manque',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 120,
          height: 80,
          child: SafeFileImage(
            path: 'Z:/private/missing.jpg',
            semanticLabel: 'Photo de test',
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.broken_image_outlined), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('Photo de test')), findsOneWidget);
    expect(tester.getSize(find.byType(SafeFileImage)), const Size(120, 80));
  });

  testWidgets('ouvre la photo en plein écran au toucher', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: SafeFileImage(
          path: 'Z:/private/missing.jpg',
          semanticLabel: 'Photo de test',
        ),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(SafeFileImage));
    await tester.pumpAndSettle();

    expect(find.byType(PhotoViewerScreen), findsOneWidget);
    expect(find.text('Photo de test'), findsOneWidget);
  });

  testWidgets('conserve la position initiale et le balayage de la galerie',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: PhotoViewerScreen(
        paths: ['Z:/private/one.jpg', 'Z:/private/two.jpg'],
        initialIndex: 1,
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('2 / 2'), findsOneWidget);
    expect(find.byIcon(Icons.broken_image_outlined), findsOneWidget);
  });
}
