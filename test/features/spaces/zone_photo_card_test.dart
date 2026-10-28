import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:garden_journal/features/spaces/domain/entities/zone_photo.dart';
import 'package:garden_journal/features/spaces/presentation/providers/space_provider.dart';
import 'package:garden_journal/features/spaces/presentation/widgets/zone_photo_card.dart';
import 'package:provider/provider.dart';

class _Photos extends SpaceProvider {
  final photos = <ZonePhoto>[];
  bool fail = false;
  @override
  Future<List<ZonePhoto>> photosForZone(String zoneId) async {
    if (fail) throw StateError('load');
    return photos;
  }

  @override
  Future<ZonePhoto> addZonePhoto(
      {required String zoneId,
      required String sourcePath,
      DateTime? capturedAt,
      String? caption}) async {
    final photo = ZonePhoto(
        id: 'photo',
        zoneId: zoneId,
        photoPath: sourcePath,
        capturedAt: capturedAt!,
        caption: caption,
        createdAt: DateTime.now());
    photos.add(photo);
    return photo;
  }
}

void main() {
  testWidgets('photo mobile : vide, annulation, note et confirmation',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final spaces = _Photos();
    addTearDown(spaces.dispose);
    await tester.pumpWidget(ChangeNotifierProvider<SpaceProvider>.value(
        value: spaces,
        child: MaterialApp(
            home: Scaffold(
                body: SingleChildScrollView(
                    child: ZonePhotoCard(
                        zoneId: 'zone',
                        pickImage: (_) async => XFile('missing.jpg')))))));
    await tester.pumpAndSettle();
    expect(find.text('Aucune photo ajoutée pour le moment.'), findsOneWidget);
    await tester.tap(find.text('Ajouter une photo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choisir dans la galerie'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Essai annulé');
    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();
    expect(spaces.photos, isEmpty);
    await tester.tap(find.text('Ajouter une photo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Prendre une photo'));
    await tester.pumpAndSettle();
    const note =
        'Vue complète de la serre et évolution des plantes après déplacement.';
    await tester.enterText(find.byType(TextField), note);
    await tester.tap(find.text('Enregistrer'));
    await tester.pumpAndSettle();
    expect(spaces.photos.single.caption, note);
    expect(find.text(note), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('erreur photo permet de réessayer', (tester) async {
    final spaces = _Photos()..fail = true;
    addTearDown(spaces.dispose);
    await tester.pumpWidget(ChangeNotifierProvider<SpaceProvider>.value(
        value: spaces,
        child: const MaterialApp(
            home: Scaffold(body: ZonePhotoCard(zoneId: 'zone')))));
    await tester.pumpAndSettle();
    expect(find.text('Impossible de charger les photos.'), findsOneWidget);
    spaces.fail = false;
    await tester.tap(find.text('Réessayer'));
    await tester.pumpAndSettle();
    expect(find.text('Aucune photo ajoutée pour le moment.'), findsOneWidget);
  });
}
