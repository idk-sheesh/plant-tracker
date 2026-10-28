import 'package:flutter/foundation.dart';
import '../../data/repositories/observation_repository.dart';
import '../../domain/entities/observation_assessment.dart';

class ObservationProvider extends ChangeNotifier {
  final ObservationRepository _repository;
  ObservationProvider({ObservationRepository? repository})
      : _repository = repository ?? ObservationRepository();

  List<ObservationAssessment> _assessments = [];
  List<ObservationAssessment> get assessments =>
      List.unmodifiable(_assessments);
  bool isLoading = false;
  String? error;

  Future<void> load() async {
    isLoading = true;
    error = null;
    notifyListeners();
    try {
      _assessments = await _repository.getAll();
    } catch (e, st) {
      error = 'Impossible de charger les observations de plantes.';
      FlutterError.reportError(FlutterErrorDetails(
          exception: e, stack: st, library: 'gardenjournal observations'));
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  ObservationAssessment? latest(String plantId, String stage) {
    for (final assessment in _assessments) {
      if (assessment.plantId == plantId && assessment.stage == stage)
        return assessment;
    }
    return null;
  }

  Future<void> save(ObservationAssessment assessment,
      {bool editing = false}) async {
    await _repository.save(assessment, editing: editing);
    _assessments.removeWhere((a) => a.id == assessment.id);
    _assessments.add(assessment);
    _assessments.sort((a, b) {
      final byDate = b.observedAt.compareTo(a.observedAt);
      return byDate != 0 ? byDate : b.createdAt.compareTo(a.createdAt);
    });
    error = null;
    notifyListeners();
  }
}
