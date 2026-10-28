import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garden_journal/core/database/database_helper.dart';
import 'package:garden_journal/core/services/gardenjournal_backup_service.dart';
import 'package:garden_journal/core/services/photo_storage_service.dart';
import 'package:garden_journal/features/actions/data/repositories/action_repository.dart';
import 'package:garden_journal/features/actions/domain/entities/plant_action.dart';
import 'package:garden_journal/features/observations/domain/entities/observation_assessment.dart';
import 'package:garden_journal/features/observations/data/repositories/observation_repository.dart';
import 'package:garden_journal/features/cameras/data/repositories/camera_data_repository.dart';
import 'package:garden_journal/features/cameras/domain/entities/camera_snapshot.dart';
import 'package:garden_journal/features/sensors/data/repositories/sensor_data_repository.dart';
import 'package:garden_journal/features/sensors/domain/entities/sensor_device.dart';
import 'package:garden_journal/features/sensors/domain/entities/sensor_reading.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../support/database_test_utils.dart';

void main() {
  sqfliteFfiInit();

  late Directory temp;
  late Directory documents;
  late Database db;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('gardenjournal-backup-test-');
    documents = Directory('${temp.path}${Platform.pathSeparator}documents');
    await documents.create(recursive: true);
    db = await openMemoryDatabase();
    await DatabaseHelper.instance.createSchemaForTesting(db);
  });

  tearDown(() async {
    await db.close();
    await temp.delete(recursive: true);
  });

  test('export vide produit une enveloppe intègre sans chemin privé', () async {
    final service = GardenJournalBackupService(
      database: db,
      documentsDirectory: documents,
    );

    final result = await service.exportBackup();

    expect(await result.file.exists(), isTrue);
    expect(result.warnings, isEmpty);
    final content = await result.file.readAsString();
    expect(content, isNot(contains(documents.path)));
    final envelope = jsonDecode(content) as Map<String, dynamic>;
    final payloadBytes = base64Decode(envelope['payload'] as String);
    expect(sha256.convert(payloadBytes).toString(), envelope['checksum']);
    final payload =
        jsonDecode(utf8.decode(payloadBytes)) as Map<String, dynamic>;
    final tables = payload['tables'] as Map<String, dynamic>;
    expect(tables, isNot(contains('ota_trusted_keys')));
  });

  test('inspection vérifie le contenu avant restauration', () async {
    await db.insert('plants', _plant('plant-preview', null));
    final service = GardenJournalBackupService(
      database: db,
      documentsDirectory: documents,
    );
    final exported = await service.exportBackup();

    final inspection = await service.inspectBackup(exported.file);

    expect(inspection.databaseVersion, DatabaseHelper.currentVersion);
    expect(inspection.tableCounts['plants'], 1);
    expect(inspection.tableCounts['actions'], 0);
    expect(inspection.photoCount, 0);
    expect(inspection.sourceBytes, greaterThan(0));
  });

  test('v25 sauvegarde et restaure les notes repère et le rappel individuel',
      () async {
    await db.insert('plants', {
      ..._plant('specimen', null),
      'observation_code': 'P03',
      'watering_reminder': 0
    });
    final repository = ObservationRepository(database: db);
    final now = DateTime(2026, 10, 25);
    await repository.save(ObservationAssessment(
        id: 'review',
        plantId: 'specimen',
        observedAt: now,
        stage: 'flowering',
        scores: {'fruit_quality': 4},
        notes: 'Observation réelle',
        createdAt: now));
    final service =
        GardenJournalBackupService(database: db, documentsDirectory: documents);
    final backup = await service.exportBackup();
    await db.delete('plants');
    await service.importBackup(backup.file);
    expect((await repository.getAll()).single.scores, {'fruit_quality': 4});
    expect((await db.query('plants')).single['observation_code'], 'P03');
    expect((await db.query('plants')).single['watering_reminder'], 0);
    expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
  });

  test('une sauvegarde v24 reçoit des repères vides et le réglage automatique',
      () async {
    await db
        .insert('plants', {..._plant('outdoor', null), 'location': 'outdoor'});
    final service =
        GardenJournalBackupService(database: db, documentsDirectory: documents);
    final backup = await service.exportBackup();
    await _rewritePayload(backup.file, (payload) {
      final manifest = payload['manifest'] as Map<String, dynamic>;
      manifest['databaseVersion'] = 24;
      (manifest['tables'] as Map<String, dynamic>)
          .remove('observation_assessments');
      final tables = payload['tables'] as Map<String, dynamic>;
      tables.remove('observation_assessments');
      for (final row in tables['plants'] as List) {
        (row as Map).remove('observation_code');
        row.remove('watering_reminder');
      }
    });
    final inspection = await service.inspectBackup(backup.file);
    expect(inspection.tableCounts['observation_assessments'], 0);
    await service.importBackup(backup.file);
    expect(await db.query('observation_assessments'), isEmpty);
    expect((await db.query('plants')).single['watering_reminder'], isNull);
  });

  test('inspection refuse des notes repère altérées avant tout import',
      () async {
    await db.insert('plants', _plant('p', null));
    final service =
        GardenJournalBackupService(database: db, documentsDirectory: documents);
    final backup = await service.exportBackup();
    await _rewritePayload(backup.file, (payload) {
      final tables = payload['tables'] as Map<String, dynamic>;
      final now = DateTime(2026, 10, 25);
      tables['observation_assessments'] = [
        ObservationAssessment(
                id: 'bad',
                plantId: 'p',
                observedAt: now,
                stage: 'growth',
                scores: {'vigor': 8},
                createdAt: now)
            .toMap()
      ];
      final manifest = payload['manifest'] as Map<String, dynamic>;
      (manifest['tables'] as Map<String, dynamic>)['observation_assessments'] =
          1;
    });
    await expectLater(
        service.inspectBackup(backup.file), throwsA(isA<BackupException>()));
    expect((await db.query('plants')).single['id'], 'p');
    expect(await db.query('observation_assessments'), isEmpty);
  });

  test('export et import restaurent plante, action et photo', () async {
    final photo = await _createManagedPhoto(documents, 'plant.jpg');
    await db.insert('plants', _plant('plant-source', photo.path));
    final actionRepository = ActionRepository(database: db);
    await actionRepository.insertAction(
      PlantAction(
        id: 'harvest-source',
        plantId: 'plant-source',
        actionType: 'recolte',
        timestamp: DateTime.utc(2026, 2, 1),
        createdAt: DateTime.utc(2026, 2, 1),
        completedAt: DateTime.utc(2026, 2, 1),
        harvestWeightFresh: 120,
        harvestWeightStored: 42,
        harvestWeightWaste: 8,
        photoPaths: [photo.path],
      ),
    );
    final sourceService = GardenJournalBackupService(
      database: db,
      documentsDirectory: documents,
    );
    final exported = await sourceService.exportBackup();

    final targetDb = await openMemoryDatabase();
    addTearDown(targetDb.close);
    await DatabaseHelper.instance.createSchemaForTesting(targetDb);
    await targetDb.insert('plants', _plant('old-plant', null));
    final targetDocuments =
        Directory('${temp.path}${Platform.pathSeparator}target-documents');
    await targetDocuments.create(recursive: true);
    final targetService = GardenJournalBackupService(
      database: targetDb,
      documentsDirectory: targetDocuments,
    );

    final imported = await targetService.importBackup(exported.file);

    expect(await imported.safetyBackup.exists(), isTrue);
    final plants = await targetDb.query('plants');
    final actions = await targetDb.query('actions');
    final photos = await targetDb.query('action_photos');
    expect(plants.single['id'], 'plant-source');
    expect(plants.single['is_harvested'], 1);
    expect(actions.single['harvest_weight_fresh'], 120.0);
    expect(photos, hasLength(1));
    expect(await File(photos.single['photo_path'] as String).exists(), isTrue);
    expect(await targetDb.rawQuery('PRAGMA foreign_key_check'), isEmpty);
  });

  test('export et import restaurent une photo caméra conservée', () async {
    final photo = await _createManagedPhoto(documents, 'camera.jpg');
    final originalBytes = await photo.readAsBytes();
    final now = DateTime.utc(2026, 9, 9, 12);
    await db.insert('cultivation_zones', {
      'id': 'zone-camera',
      'name': 'Serre caméra',
      'type': 'main',
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
    });
    final cameraRepository = CameraDataRepository(database: db);
    await cameraRepository.upsertCamera(SensorDevice(
      id: 'cam-01',
      uid: 'cam-01',
      name: 'Caméra privée',
      zoneId: 'zone-camera',
      baseUrl: 'https://hub.example.ts.net:8443',
      status: 'online',
      deviceKind: 'camera',
      transport: 'https',
      createdAt: now,
      updatedAt: now,
    ));
    expect(
      await cameraRepository.saveSnapshot(CameraSnapshot(
        id: 'camera-saved',
        deviceId: 'cam-01',
        zoneId: 'zone-camera',
        capturedAt: now,
        sha256: sha256.convert(originalBytes).toString(),
        sizeBytes: originalBytes.length,
        createdAt: now,
        photoPath: photo.path,
      )),
      isTrue,
    );
    final exported = await GardenJournalBackupService(
      database: db,
      documentsDirectory: documents,
    ).exportBackup();
    final inspection = await GardenJournalBackupService(
      database: db,
      documentsDirectory: documents,
    ).inspectBackup(exported.file);
    expect(inspection.photoCount, 1);

    final targetDb = await openMemoryDatabase();
    addTearDown(targetDb.close);
    await DatabaseHelper.instance.createSchemaForTesting(targetDb);
    final targetDocuments =
        Directory('${temp.path}${Platform.pathSeparator}camera-target');
    await targetDocuments.create(recursive: true);
    await GardenJournalBackupService(
      database: targetDb,
      documentsDirectory: targetDocuments,
    ).importBackup(exported.file);

    final restored = (await targetDb.query('camera_snapshots')).single;
    final restoredPath = restored['photo_path'] as String;
    expect(await File(restoredPath).readAsBytes(), originalBytes);
    expect(restoredPath, isNot(contains(documents.path)));
  });

  test('sauvegarde restaure photo, note et date d’espace sans caméra',
      () async {
    final photo = await _createManagedPhoto(documents, 'space.jpg');
    final bytes = await photo.readAsBytes();
    await db.insert('zone_photos', {
      'id': 'space-photo',
      'zone_id': 'zone-main',
      'photo_path': photo.path,
      'captured_at': 1791288000,
      'caption': 'Vue avant taille',
      'created_at': '2026-10-06T12:00:00Z',
    });
    final service =
        GardenJournalBackupService(database: db, documentsDirectory: documents);
    final exported = await service.exportBackup();
    expect((await service.inspectBackup(exported.file)).photoCount, 1);
    expect(await exported.file.readAsString(), isNot(contains(photo.path)));
    final targetDb = await openMemoryDatabase();
    addTearDown(targetDb.close);
    await DatabaseHelper.instance.createSchemaForTesting(targetDb);
    await GardenJournalBackupService(
            database: targetDb,
            documentsDirectory:
                Directory('${temp.path}${Platform.pathSeparator}space-target'))
        .importBackup(exported.file);
    final restored = (await targetDb.query('zone_photos')).single;
    expect(restored['caption'], 'Vue avant taille');
    expect(restored['captured_at'], 1791288000);
    expect(await File(restored['photo_path'] as String).readAsBytes(), bytes);
    expect(await targetDb.query('sensor_devices'), isEmpty);
    expect(await targetDb.rawQuery('PRAGMA foreign_key_check'), isEmpty);
  });

  test('sauvegarde v23 sans photos d’espace reste importable', () async {
    await db.insert('plants', _plant('plant-v23', null));
    final service =
        GardenJournalBackupService(database: db, documentsDirectory: documents);
    final exported = await service.exportBackup();
    await _rewritePayload(exported.file, (payload) {
      final manifest = payload['manifest'] as Map<String, dynamic>;
      manifest['databaseVersion'] = 23;
      (manifest['tables'] as Map<String, dynamic>).remove('zone_photos');
      (payload['tables'] as Map<String, dynamic>).remove('zone_photos');
    });
    await service.importBackup(exported.file);
    expect((await db.query('plants')).single['id'], 'plant-v23');
    expect(await db.query('zone_photos'), isEmpty);
  });

  test('export et import conservent capacités et mesures génériques', () async {
    final now = DateTime.utc(2026, 7, 19, 10);
    final device = SensorDevice(
      id: 'reservoir-01',
      uid: 'reservoir-01',
      name: 'Réservoir',
      zoneId: 'zone-main',
      baseUrl: 'http://192.168.1.44',
      createdAt: now,
      updatedAt: now,
    );
    final repository = SensorDataRepository(database: db);
    await repository.upsertDevice(device);
    await repository.insertReadings(device, [
      SensorReading.fromJson({
        'deviceId': device.uid,
        'timestamp': now.millisecondsSinceEpoch ~/ 1000,
        'temperature': 22.0,
        'humidity': 60.0,
        'capabilities': {
          'water_ph': {'type': 'number', 'unit': 'pH'},
        },
        'measurements': {'water_ph': 6.3},
      }, now: now.add(const Duration(minutes: 1))),
    ]);
    final exported = await GardenJournalBackupService(
      database: db,
      documentsDirectory: documents,
    ).exportBackup();

    final targetDb = await openMemoryDatabase();
    addTearDown(targetDb.close);
    await DatabaseHelper.instance.createSchemaForTesting(targetDb);
    final targetService = GardenJournalBackupService(
      database: targetDb,
      documentsDirectory: Directory(
        '${temp.path}${Platform.pathSeparator}generic-target',
      ),
    );

    await targetService.importBackup(exported.file);

    expect(await targetDb.query('sensor_device_capabilities'), hasLength(1));
    expect(await targetDb.query('sensor_measurements'), hasLength(1));
    expect(
      (await targetDb.query('sensor_measurements')).single['numeric_value'],
      6.3,
    );
    expect(await targetDb.rawQuery('PRAGMA foreign_key_check'), isEmpty);
  });

  test('import accepte une sauvegarde v10 sans les tables génériques',
      () async {
    await db.insert('plants', _plant('plant-v10', null));
    final service = GardenJournalBackupService(
      database: db,
      documentsDirectory: documents,
    );
    final exported = await service.exportBackup();
    await _rewritePayload(exported.file, (payload) {
      final manifest = payload['manifest'] as Map<String, dynamic>;
      manifest['databaseVersion'] = 10;
      final counts = manifest['tables'] as Map<String, dynamic>;
      final tables = payload['tables'] as Map<String, dynamic>;
      for (final table in const [
        'sensor_device_capabilities',
        'sensor_measurements',
        'device_health_snapshots',
        'camera_snapshots',
      ]) {
        counts.remove(table);
        tables.remove(table);
      }
    });

    final inspection = await service.inspectBackup(exported.file);
    final imported = await service.importBackup(exported.file);

    expect(inspection.tableCounts['sensor_device_capabilities'], 0);
    expect(inspection.tableCounts['sensor_measurements'], 0);
    expect(inspection.tableCounts['device_health_snapshots'], 0);
    expect(inspection.tableCounts['camera_snapshots'], 0);
    expect(imported.restoredTables['sensor_device_capabilities'], 0);
    expect((await db.query('plants')).single['id'], 'plant-v10');
  });

  test('import refuse une sauvegarde corrompue', () async {
    final service = GardenJournalBackupService(
      database: db,
      documentsDirectory: documents,
    );
    final exported = await service.exportBackup();
    await exported.file.writeAsString('{"checksum":"bad","payload":"bad"}');

    await expectLater(
      service.importBackup(exported.file),
      throwsA(isA<BackupException>()),
    );
  });

  test('import refuse une version de format incompatible', () async {
    final service = GardenJournalBackupService(
      database: db,
      documentsDirectory: documents,
    );
    final exported = await service.exportBackup();
    final envelope =
        jsonDecode(await exported.file.readAsString()) as Map<String, dynamic>;
    final payload = jsonDecode(
      utf8.decode(base64Decode(envelope['payload'] as String)),
    ) as Map<String, dynamic>;
    (payload['manifest'] as Map<String, dynamic>)['formatVersion'] = 999;
    final payloadBytes = utf8.encode(jsonEncode(payload));
    await exported.file.writeAsString(jsonEncode({
      'checksum': sha256.convert(payloadBytes).toString(),
      'payload': base64Encode(payloadBytes),
    }));

    await expectLater(
      service.importBackup(exported.file),
      throwsA(isA<BackupException>()),
    );
  });

  test('import refuse une version de base future sans modifier les données',
      () async {
    await db.insert('plants', _plant('existing-plant', null));
    final service = GardenJournalBackupService(
      database: db,
      documentsDirectory: documents,
    );
    final exported = await service.exportBackup();
    await _rewritePayload(exported.file, (payload) {
      final manifest = payload['manifest'] as Map<String, dynamic>;
      manifest['databaseVersion'] = DatabaseHelper.currentVersion + 1;
    });

    await expectLater(
      service.importBackup(exported.file),
      throwsA(isA<BackupException>()),
    );

    expect((await db.query('plants')).single['id'], 'existing-plant');
  });

  test('import refuse un comptage de manifeste incohérent', () async {
    await db.insert('plants', _plant('existing-plant', null));
    final service = GardenJournalBackupService(
      database: db,
      documentsDirectory: documents,
    );
    final exported = await service.exportBackup();
    await _rewritePayload(exported.file, (payload) {
      final manifest = payload['manifest'] as Map<String, dynamic>;
      final counts = manifest['tables'] as Map<String, dynamic>;
      counts['plants'] = 99;
    });

    await expectLater(
      service.importBackup(exported.file),
      throwsA(isA<BackupException>()),
    );

    expect((await db.query('plants')).single['id'], 'existing-plant');
  });

  test('inspection refuse les entrées photo dupliquées', () async {
    final photo = await _createManagedPhoto(documents, 'duplicate.jpg');
    await db.insert('plants', _plant('plant-photo', photo.path));
    final service = GardenJournalBackupService(
      database: db,
      documentsDirectory: documents,
    );
    final exported = await service.exportBackup();
    await _rewritePayload(exported.file, (payload) {
      final files = payload['files'] as List<dynamic>;
      files.add(Map<String, dynamic>.from(files.single as Map));
      final manifest = payload['manifest'] as Map<String, dynamic>;
      final manifestFiles = manifest['files'] as List<dynamic>;
      manifestFiles.add(
        Map<String, dynamic>.from(manifestFiles.single as Map),
      );
    });

    await expectLater(
      service.inspectBackup(exported.file),
      throwsA(isA<BackupException>()),
    );
  });

  test('échec injecté restaure la base courante et nettoie les photos',
      () async {
    final sourcePhoto = await _createManagedPhoto(documents, 'rollback.jpg');
    await db.insert('plants', _plant('source-plant', sourcePhoto.path));
    final exported = await GardenJournalBackupService(
      database: db,
      documentsDirectory: documents,
    ).exportBackup();

    final targetDb = await openMemoryDatabase();
    addTearDown(targetDb.close);
    await DatabaseHelper.instance.createSchemaForTesting(targetDb);
    await targetDb.insert('plants', _plant('existing-plant', null));
    final targetDocuments =
        Directory('${temp.path}${Platform.pathSeparator}rollback-documents');
    await targetDocuments.create(recursive: true);
    final service = GardenJournalBackupService(
      database: targetDb,
      documentsDirectory: targetDocuments,
      beforeImportCommit: () => throw StateError('injected failure'),
    );

    await expectLater(service.importBackup(exported.file), throwsStateError);

    expect((await targetDb.query('plants')).single['id'], 'existing-plant');
    expect(await targetDb.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    final restoredDirectory = Directory(
      '${targetDocuments.path}${Platform.pathSeparator}gardenjournal_photos'
      '${Platform.pathSeparator}restored',
    );
    final restoredFiles = await restoredDirectory.exists()
        ? await restoredDirectory
            .list()
            .where((entity) => entity is File)
            .toList()
        : const <FileSystemEntity>[];
    expect(restoredFiles, isEmpty);
  });

  test('échec de nettoyage après commit conserve les photos restaurées',
      () async {
    final sourcePhoto = await _createManagedPhoto(documents, 'source.jpg');
    await db.insert('plants', _plant('source-plant', sourcePhoto.path));
    final exported = await GardenJournalBackupService(
      database: db,
      documentsDirectory: documents,
    ).exportBackup();

    final targetDb = await openMemoryDatabase();
    addTearDown(targetDb.close);
    await DatabaseHelper.instance.createSchemaForTesting(targetDb);
    final targetDocuments =
        Directory('${temp.path}${Platform.pathSeparator}cleanup-documents');
    await targetDocuments.create(recursive: true);
    final oldPhoto = await _createManagedPhoto(targetDocuments, 'old.jpg');
    await targetDb.insert('plants', _plant('old-plant', oldPhoto.path));
    final service = GardenJournalBackupService(
      database: targetDb,
      documentsDirectory: targetDocuments,
      obsoletePhotoCleanup: (_, __) =>
          throw const PhotoCleanupException(['old.jpg']),
    );

    final imported = await service.importBackup(exported.file);

    final restoredPlant = (await targetDb.query('plants')).single;
    final restoredPath = restoredPlant['photo_path'] as String;
    expect(restoredPlant['id'], 'source-plant');
    expect(await File(restoredPath).exists(), isTrue);
    expect(imported.warnings, isNotEmpty);
  });
}

Future<void> _rewritePayload(
  File file,
  void Function(Map<String, dynamic> payload) update,
) async {
  final envelope =
      jsonDecode(await file.readAsString()) as Map<String, dynamic>;
  final payload = jsonDecode(
    utf8.decode(base64Decode(envelope['payload'] as String)),
  ) as Map<String, dynamic>;
  update(payload);
  final payloadBytes = utf8.encode(jsonEncode(payload));
  await file.writeAsString(jsonEncode({
    'checksum': sha256.convert(payloadBytes).toString(),
    'payload': base64Encode(payloadBytes),
  }));
}

Future<File> _createManagedPhoto(Directory documents, String name) async {
  final file = File(
    '${documents.path}${Platform.pathSeparator}gardenjournal_photos'
    '${Platform.pathSeparator}plants${Platform.pathSeparator}$name',
  );
  await file.parent.create(recursive: true);
  await file.writeAsBytes(List<int>.generate(256, (index) => index % 255));
  return file;
}

Map<String, Object?> _plant(String id, String? photoPath) => {
      'id': id,
      'name': 'Plante $id',
      'potting_date': '2026-01-01T00:00:00Z',
      'culture_type': 'indoor',
      'photo_path': photoPath,
      'qr_code': 'plant:$id',
      'created_at': '2026-01-01T00:00:00Z',
      'updated_at': '2026-01-01T00:00:00Z',
    };
