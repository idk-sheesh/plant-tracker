import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:garden_journal/core/database/database_helper.dart';
import 'package:garden_journal/core/services/photo_storage_service.dart';
import 'package:garden_journal/core/services/shareable_export_service.dart';
import 'package:garden_journal/features/actions/data/repositories/action_repository.dart';
import 'package:garden_journal/features/actions/domain/entities/plant_action.dart';
import 'package:garden_journal/features/actions/presentation/providers/action_provider.dart';
import 'package:garden_journal/features/groups/data/models/plant_group.dart';
import 'package:garden_journal/features/groups/data/repositories/group_repository.dart';
import 'package:garden_journal/features/plants/data/repositories/plant_repository.dart';
import 'package:garden_journal/features/plants/domain/entities/plant.dart';
import 'package:garden_journal/features/plants/presentation/providers/plant_provider.dart';
import 'package:garden_journal/features/plants/presentation/widgets/action_timeline.dart';
import 'package:provider/provider.dart';
import 'package:sqflite/sqflite.dart' as mobile_sqlite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../test/support/database_test_utils.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  if (!Platform.isAndroid && !Platform.isIOS) sqfliteFfiInit();

  testWidgets('groupe, plante, action, récolte, relance, PDF puis cascades',
      (tester) async {
    final temp = await Directory.systemTemp.createTemp('gardenjournal-e2e-');
    addTearDown(() async {
      if (await temp.exists()) await temp.delete(recursive: true);
    });
    final managedRoot = Directory('${temp.path}/photos');
    String? migratedActionPhoto;
    addTearDown(() async {
      final path = migratedActionPhoto;
      if (path != null && await File(path).exists()) {
        await PhotoStorageService.deleteManagedFile(path);
      }
    });
    final sourcePlant = await _writePng('${temp.path}/plant.png');
    final sourceAction = await _writePng('${temp.path}/action.png');
    final plantPhoto = await PhotoStorageService.persistImage(
      sourcePlant.path,
      bucket: 'plants',
      rootDirectory: managedRoot,
    );
    final actionPhoto = await PhotoStorageService.persistImage(
      sourceAction.path,
      bucket: 'actions',
      rootDirectory: managedRoot,
    );

    final databasePath = '${temp.path}/critical.sqlite';
    var db = await _openDatabase(
      databasePath,
    );
    addTearDown(() async {
      if (db.isOpen) await db.close();
    });
    await db.execute('PRAGMA foreign_keys = ON');
    await DatabaseHelper.instance.createSchemaForTesting(db);
    var plants = PlantRepository(database: db);
    var actions = ActionRepository(database: db);
    var groups = GroupRepository(database: db);
    final now = DateTime.utc(2026, 7, 15, 10);
    await groups.insertGroup(PlantGroup(
      id: 'critical-group',
      name: 'Groupe critique',
      color: Colors.green,
      createdAt: now,
    ));
    final plant = Plant(
      id: 'critical-plant',
      name: 'Workflow critique',
      pottingDate: now,
      cultureType: 'Terre',
      photoPath: plantPhoto,
      groupId: 'critical-group',
      qrCode: 'plant:critical-plant',
      createdAt: now,
      updatedAt: now,
    );
    await plants.insertPlant(plant);
    await actions.insertAction(PlantAction(
      id: 'critical-action',
      plantId: plant.id,
      actionType: 'observation',
      timestamp: now,
      notes: 'Scénario critique',
      photoPaths: [actionPhoto],
      createdAt: now,
      completedAt: now,
    ));
    final observation = await actions.getActionById('critical-action');
    await actions.updateAction(
      observation!.copyWith(notes: 'Scénario critique modifié'),
    );
    await actions.insertAction(PlantAction(
      id: 'critical-harvest',
      plantId: plant.id,
      actionType: 'recolte',
      timestamp: now.add(const Duration(hours: 1)),
      harvestWeightFresh: 120.5,
      harvestWeightStored: 42.5,
      harvestWeightWaste: 8,
      createdAt: now,
      completedAt: now,
    ));
    expect((await plants.getPlantById(plant.id))?.isHarvested, isTrue);

    final actionProvider = ActionProvider(
      repository: actions,
      plantRepository: plants,
    );
    await actionProvider.loadActionsForPlant(plant.id);
    final currentActionPhoto =
        (await actions.getActionById('critical-action'))!.photoPaths.single;
    migratedActionPhoto = currentActionPhoto;
    expect(currentActionPhoto, isNot(actionPhoto));
    expect(await File(currentActionPhoto).exists(), isTrue);
    expect(await File(actionPhoto).exists(), isFalse);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: actionProvider),
        ChangeNotifierProvider(
          create: (_) => PlantProvider(repository: plants),
        ),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: ActionTimeline(plantId: plant.id)),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Observation'), findsOneWidget);
    expect(find.text('Scénario critique modifié'), findsOneWidget);
    expect(find.text('Récolté 120.5 g'), findsOneWidget);

    final loadedActions = await actions.getActionsForPlant(plant.id);
    final pdf = await ShareableExportService.buildPlantHistoryPdf(
      plant,
      loadedActions,
    );
    expect(latin1.decode(pdf, allowInvalid: true), startsWith('%PDF-'));

    await tester.pumpWidget(const SizedBox.shrink());
    await db.close();
    db = await _openDatabase(
      databasePath,
    );
    await db.execute('PRAGMA foreign_keys = ON');
    plants = PlantRepository(database: db);
    actions = ActionRepository(database: db);
    groups = GroupRepository(database: db);
    expect(await groups.getAllGroups(), hasLength(1));
    expect((await plants.getPlantById(plant.id))?.isHarvested, isTrue);
    expect((await actions.getActionById('critical-action'))?.notes,
        'Scénario critique modifié');

    await actions.deleteAction('critical-harvest');
    expect((await plants.getPlantById(plant.id))?.isHarvested, isFalse);

    final deletion = await plants.deletePlant(plant.id);
    expect(
      deletion?.photoPaths.toSet(),
      {plantPhoto, currentActionPhoto},
    );
    await PhotoStorageService.deleteManagedFile(
      plantPhoto,
      rootDirectory: managedRoot,
    );
    await PhotoStorageService.deleteManagedFile(currentActionPhoto);
    expect(await db.query('plants'), isEmpty);
    expect(await db.query('actions'), isEmpty);
    expect(await db.query('action_photos'), isEmpty);
    expect(await File(plantPhoto).exists(), isFalse);
    expect(await File(currentActionPhoto).exists(), isFalse);
    expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
  });

  test('migration intégrée d’une fixture v4 vers v10', () async {
    final directory =
        await Directory.systemTemp.createTemp('gardenjournal-migration-e2e-');
    addTearDown(() => directory.delete(recursive: true));
    final db = await _openDatabase('${directory.path}/legacy-v4.sqlite');
    addTearDown(db.close);
    await createLegacySchema(db, 4);

    await db.execute('BEGIN IMMEDIATE');
    try {
      await DatabaseHelper.instance.upgradeSchemaForTesting(db, 4);
      await db.execute('COMMIT');
    } catch (error, stackTrace) {
      await db.execute('ROLLBACK');
      Error.throwWithStackTrace(error, stackTrace);
    }

    expect(await db.query('groups'), hasLength(2));
    expect(await db.query('plants'), hasLength(1));
    expect(await db.query('actions'), hasLength(1));
    expect(await db.query('action_photos'), hasLength(1));
    expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
  });
}

Future<Database> _openDatabase(String path) async {
  final options = OpenDatabaseOptions(singleInstance: false);
  final db = Platform.isAndroid || Platform.isIOS
      ? await mobile_sqlite.openDatabase(path, singleInstance: false)
      : await databaseFactoryFfi.openDatabase(path, options: options);
  await db.execute('PRAGMA foreign_keys = ON');
  return db;
}

Future<File> _writePng(String path) async {
  const transparentPng =
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=';
  return File(path).writeAsBytes(base64Decode(transparentPng));
}
