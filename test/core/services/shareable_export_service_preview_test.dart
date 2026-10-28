import 'dart:io';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:garden_journal/core/services/shareable_export_service.dart';
import 'package:garden_journal/features/actions/domain/entities/plant_action.dart';
import 'package:garden_journal/features/plants/domain/entities/plant.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('produit un PDF multipage structurellement valide', () async {
    final plant = Plant(
      id: 'preview-plant',
      name: 'Tomate cerise A',
      variety: 'Tomate cerise',
      pottingDate: DateTime(2026, 5, 14),
      cultureType: 'Terre vivante',
      potSize: '30L',
      qrCode: 'gardenjournal://plant/preview-plant',
      createdAt: DateTime(2026, 5, 14),
      updatedAt: DateTime(2026, 7, 7),
      location: 'indoor',
      containerType: 'pot_tissu',
      origin: 'seed',
      notes: 'Mise en eau le 14\nObservation des nœuds 🌿 — mise en pot le 16',
    );
    final actions = <PlantAction>[
      _action('1', 'nutriments', DateTime(2026, 7, 6),
          quantity: 2,
          unit: 'L',
          ph: 6.2,
          tds: 344,
          product: 'Compost végétal',
          notes: 'Mode: Solution nutritive'),
      _action('2', 'traitement', DateTime(2026, 7, 2),
          quantity: 500,
          unit: 'mL',
          ph: 6.6,
          tds: 390,
          product: 'Savon horticole',
          notes: 'Cible: Acariens\nApplication: Foliaire'),
      _action('10', 'observation', DateTime(2026, 7, 1),
          notes: 'Entre-nœuds plus courts — apex propre 🌱'),
      _action('3', 'arrosage', DateTime(2026, 6, 29),
          quantity: 2, unit: 'L', ph: 6.0, tds: 232),
      _action('4', 'nutriments', DateTime(2026, 6, 25),
          quantity: 2.2,
          unit: 'L',
          ph: 6.49,
          tds: 291,
          product: 'Engrais pour tomates'),
      _action('5', 'nutriments', DateTime(2026, 6, 21),
          quantity: 75, unit: 'g', phNA: true, tdsNA: true, product: 'Basalte'),
      _action('6', 'nutriments', DateTime(2026, 6, 20),
          quantity: 75,
          unit: 'g',
          phNA: true,
          tdsNA: true,
          product: "Amendement calcaire"),
      _action('7', 'floraison', DateTime(2026, 6, 16)),
      _action('8', 'rempotage', DateTime(2026, 6, 2),
          quantity: 30, unit: 'L', product: 'Terreau potager'),
      _action('9', 'arrosage', DateTime(2026, 5, 20),
          quantity: 0.1, unit: 'L', ph: 6.8, tds: 205),
      _action('11', 'recolte', DateTime(2026, 7, 7),
          fresh: 120.5,
          stored: 42.5,
          waste: 8,
          notes: 'Récolte complète humide, conservée et écartée.'),
    ];

    final bytes =
        await ShareableExportService.buildPlantHistoryPdf(plant, actions);
    final dir = Directory('tmp/pdf_review');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    File('${dir.path}/new_export_preview.pdf').writeAsBytesSync(bytes);
    final structure = latin1.decode(bytes, allowInvalid: true);
    expect(structure, startsWith('%PDF-'));
    expect(structure.trimRight(), endsWith('%%EOF'));
    expect(RegExp(r'/Type\s*/Page\b').allMatches(structure).length,
        greaterThanOrEqualTo(2));
    expect(bytes.length, greaterThan(10000));
  });

  test('ignore une image absente sans casser le document', () async {
    final now = DateTime.utc(2026, 1, 1);
    final plant = Plant(
      id: 'missing-photo',
      name: 'Sans photo',
      pottingDate: now,
      cultureType: 'Terre',
      photoPath: 'Z:/private/does-not-exist.jpg',
      qrCode: 'plant:missing-photo',
      createdAt: now,
      updatedAt: now,
    );
    final bytes = await ShareableExportService.buildPlantHistoryPdf(
      plant,
      [_action('missing', 'observation', now, notes: 'Photo manquante')],
    );
    final structure = latin1.decode(bytes, allowInvalid: true);
    expect(structure, startsWith('%PDF-'));
    expect(structure, contains('%%EOF'));
  });

  test('ignore les photos corrompues ou trop volumineuses', () async {
    final directory = await Directory.systemTemp.createTemp('pdf-invalid-');
    addTearDown(() => directory.delete(recursive: true));
    final corrupt = File('${directory.path}/corrupt.jpg');
    await corrupt.writeAsString('not-an-image');
    final large = File('${directory.path}/large.jpg');
    await large.writeAsBytes(List.filled(12 * 1024 * 1024 + 1, 0));
    final now = DateTime.utc(2026, 1, 1);
    final base = Plant(
      id: 'invalid-photo',
      name: 'Photo invalide',
      pottingDate: now,
      cultureType: 'Terre',
      qrCode: 'plant:invalid-photo',
      createdAt: now,
      updatedAt: now,
    );

    for (final path in [corrupt.path, large.path]) {
      final bytes = await ShareableExportService.buildPlantHistoryPdf(
        base.copyWith(photoPath: path),
        const [],
      );
      expect(latin1.decode(bytes, allowInvalid: true), startsWith('%PDF-'));
    }
  });

  test('normalise les noms de fichiers et fournit un fallback', () {
    expect(ShareableExportService.normalizeFileName('  Planté #1 / été  '),
        'Plant_1_t');
    expect(ShareableExportService.normalizeFileName('🌿'), 'plante');
  });
}

PlantAction _action(
  String id,
  String type,
  DateTime date, {
  double? quantity,
  String? unit,
  double? ph,
  bool phNA = false,
  double? tds,
  bool tdsNA = false,
  String? product,
  String? notes,
  double? fresh,
  double? stored,
  double? waste,
}) {
  return PlantAction(
    id: id,
    plantId: 'preview-plant',
    actionType: type,
    timestamp: date,
    quantity: quantity,
    quantityUnit: unit,
    ph: ph,
    phNA: phNA,
    tds: tds,
    tdsNA: tdsNA,
    productUsed: product,
    notes: notes,
    harvestWeightFresh: fresh,
    harvestWeightStored: stored,
    harvestWeightWaste: waste,
    createdAt: date,
  );
}
