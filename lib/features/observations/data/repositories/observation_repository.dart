import 'package:sqflite/sqflite.dart';
import '../../../../core/database/database_helper.dart';
import '../../domain/entities/observation_assessment.dart';

class ObservationRepository {
  final Database? _databaseOverride;
  ObservationRepository({Database? database}) : _databaseOverride = database;
  Future<Database> get _database async =>
      _databaseOverride ?? await DatabaseHelper.instance.database;

  Future<List<ObservationAssessment>> getAll() async {
    final db = await _database;
    final rows = await db.query('observation_assessments',
        orderBy: 'observed_at DESC, created_at DESC, id ASC');
    final assessments = rows.map(ObservationAssessment.fromMap).toList();
    assessments.sort((a, b) {
      final byDate = b.observedAt.compareTo(a.observedAt);
      return byDate != 0 ? byDate : b.createdAt.compareTo(a.createdAt);
    });
    return assessments;
  }

  Future<void> save(ObservationAssessment assessment,
      {bool editing = false}) async {
    assessment.validate();
    final db = await _database;
    if (editing) {
      final count = await db.update(
          'observation_assessments', assessment.toMap(),
          where: 'id = ? AND plant_id = ?',
          whereArgs: [assessment.id, assessment.plantId]);
      if (count != 1) throw StateError('Observation introuvable.');
    } else {
      await db.insert('observation_assessments', assessment.toMap(),
          conflictAlgorithm: ConflictAlgorithm.abort);
    }
  }
}
