import 'package:flutter_test/flutter_test.dart';
import 'package:garden_journal/core/database/database_helper.dart';
import 'package:garden_journal/features/observations/data/repositories/observation_repository.dart';
import 'package:garden_journal/features/observations/domain/entities/observation_assessment.dart';
import 'package:garden_journal/features/plants/domain/entities/plant.dart';
import '../../support/database_test_utils.dart';

void main() {
  final now = DateTime(2026, 10, 25);
  Plant plant(String id) => Plant(
      id: id,
      name: 'Plante $id',
      pottingDate: now,
      cultureType: 'Terre',
      qrCode: 'plant:$id',
      createdAt: now,
      updatedAt: now);

  test('v25 crée les observations et conserve le réglage de chaque plante',
      () async {
    final db = await openMemoryDatabase();
    addTearDown(db.close);
    await DatabaseHelper.instance.createSchemaForTesting(db);
    await db.insert(
        'plants',
        plant('p')
            .copyWith(
                location: 'outdoor',
                observationCode: 'P01',
                wateringReminder: true)
            .toMap());
    final repository = ObservationRepository(database: db);
    final assessment = ObservationAssessment(
        id: 'a',
        plantId: 'p',
        observedAt: now,
        stage: 'growth',
        createdAt: now,
        scores: {'vigor': 4},
        measurements: {'height': 32.5});
    await repository.save(assessment);
    expect((await repository.getAll()).single.measurements['height'], 32.5);
    final restored = Plant.fromMap((await db.query('plants')).single);
    expect(restored.observationCode, 'P01');
    expect(restored.hasWateringReminder, isTrue);
    expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    await db.delete('plants');
    expect(await repository.getAll(), isEmpty);
  });

  test(
      'upgrade v24 partiel répété conserve les fiches, réglages et observations',
      () async {
    final db = await openMemoryDatabase();
    addTearDown(db.close);
    await db.execute('''CREATE TABLE plants (
      id TEXT PRIMARY KEY, name TEXT NOT NULL, location TEXT,
      watering_reminder INTEGER)''');
    await db.insert('plants', {
      'id': 'p',
      'name': 'Ancienne',
      'location': 'outdoor',
      'watering_reminder': 1
    });
    await db.insert(
        'plants', {'id': 'rain', 'name': 'Pluie', 'location': 'outdoor'});
    await DatabaseHelper.instance.upgradeSchemaForTesting(db, 24);
    final repository = ObservationRepository(database: db);
    await repository.save(ObservationAssessment(
        id: 'a',
        plantId: 'p',
        observedAt: now,
        stage: 'growth',
        scores: {'vigor': 5},
        createdAt: now));
    await DatabaseHelper.instance.upgradeSchemaForTesting(db, 24);
    expect(
        (await db.query('plants', where: 'id = ?', whereArgs: ['p']))
            .single['watering_reminder'],
        1);
    expect(
        (await db.query('plants', where: 'id = ?', whereArgs: ['rain']))
            .single['watering_reminder'],
        isNull);
    expect((await repository.getAll()).single.scores['vigor'], 5);
    expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
  });

  test('les observations sont datées, indépendantes et validées avant écriture',
      () async {
    final db = await openMemoryDatabase();
    addTearDown(db.close);
    await DatabaseHelper.instance.createSchemaForTesting(db);
    await db.insert('plants', plant('p').toMap());
    final repository = ObservationRepository(database: db);
    for (var n = 1; n <= 2; n++) {
      await repository.save(ObservationAssessment(
          id: 'a$n',
          plantId: 'p',
          observedAt: now.add(Duration(days: n)),
          stage: 'growth',
          scores: {'vigor': n},
          createdAt: now));
    }
    expect((await repository.getAll()).map((a) => a.id), ['a2', 'a1']);
    await expectLater(
        repository.save(ObservationAssessment(
            id: 'bad',
            plantId: 'p',
            observedAt: now,
            stage: 'growth',
            scores: {'vigor': 0},
            createdAt: now)),
        throwsFormatException);
    expect(await db.query('observation_assessments'), hasLength(2));
    await repository.save(
        ObservationAssessment(
            id: 'a1',
            plantId: 'p',
            observedAt: now,
            stage: 'growth',
            scores: {'vigor': 5},
            createdAt: now),
        editing: true);
    expect(await db.query('observation_assessments'), hasLength(2));
  });
}
