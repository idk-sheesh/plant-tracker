import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../../domain/entities/plant_action.dart';
import '../../data/repositories/action_repository.dart';
import '../../../plants/domain/entities/plant.dart';
import '../../../plants/data/repositories/plant_repository.dart';
import '../../../../core/services/planned_action_notification_service.dart';
import '../../../../core/services/photo_storage_service.dart';

class ActionProvider extends ChangeNotifier {
  final ActionRepository _repo;
  final PlantRepository _plantRepo;
  final _uuid = const Uuid();
  final Map<String, List<PlantAction>> _byPlant = {};
  List<PlantAction> _plannedActions = [];
  Map<String, ActionHomeSummary> _homeSummaries = {};
  bool _isLoading = false;
  bool _isPlannedLoading = false;
  bool _isHomeSummaryLoading = false;
  bool _homeSummariesLoaded = false;
  String? _homeSummariesError;
  String? _error;
  String? _plannedError;

  ActionProvider({
    ActionRepository? repository,
    PlantRepository? plantRepository,
  })  : _repo = repository ?? ActionRepository(),
        _plantRepo = plantRepository ?? PlantRepository();

  bool get isLoading => _isLoading;
  bool get isPlannedLoading => _isPlannedLoading;
  bool get isHomeSummaryLoading => _isHomeSummaryLoading;
  bool get homeSummariesLoaded => _homeSummariesLoaded;
  String? get homeSummariesError => _homeSummariesError;
  String? get error => _error;
  String? get plannedError => _plannedError;
  List<PlantAction> get plannedActions => List.unmodifiable(_plannedActions);
  Map<String, ActionHomeSummary> get homeSummaries =>
      Map.unmodifiable(_homeSummaries);
  List<PlantAction> getActionsForPlant(String id) => _byPlant[id] ?? [];

  Future<void> loadPlannedActions() async {
    _isPlannedLoading = true;
    _plannedError = null;
    notifyListeners();
    try {
      _plannedActions = List<PlantAction>.of(
        await _repo.getPlannedActions(),
        growable: true,
      );
    } catch (error, stackTrace) {
      _plannedError = 'Impossible de charger les actions planifiées';
      _report(error, stackTrace, 'chargement des actions planifiées');
    } finally {
      _isPlannedLoading = false;
      notifyListeners();
    }
  }

  Future<Map<String, DateTime>> latestFloweringStartsForPlants(
    Iterable<String> plantIds,
  ) =>
      _repo.getLatestFloweringStarts(plantIds);

  Future<void> loadHomeSummaries() async {
    _isHomeSummaryLoading = true;
    notifyListeners();
    try {
      _homeSummaries = await _repo.getHomeSummaries();
      _homeSummariesLoaded = true;
      _homeSummariesError = null;
    } catch (e, st) {
      _homeSummariesError = 'Historique indisponible';
      _homeSummariesLoaded = true;
      FlutterError.reportError(FlutterErrorDetails(
        exception: e,
        stack: st,
        library: 'gardenjournal actions',
        context: ErrorDescription('loading action home summaries'),
      ));
    } finally {
      _isHomeSummaryLoading = false;
      notifyListeners();
    }
  }

  Future<void> _refreshHomeSummaries() async {
    try {
      _homeSummaries = await _repo.getHomeSummaries();
      _homeSummariesLoaded = true;
      _homeSummariesError = null;
    } catch (e, st) {
      _homeSummariesError = 'Historique non actualise';
      FlutterError.reportError(FlutterErrorDetails(
        exception: e,
        stack: st,
        library: 'gardenjournal actions',
        context: ErrorDescription('refreshing action home summaries'),
      ));
    }
  }

  int? daysSinceWaterForPlant(Plant plant) {
    if (!plant.hasWateringReminder) {
      return null;
    }
    final lastWater = _homeSummaries[plant.id]?.lastWaterAt;
    return lastWater == null
        ? null
        : DateTime.now().difference(lastWater).inDays;
  }

  DateTime lastActivityForPlant(Plant plant) {
    final latestAction = _homeSummaries[plant.id]?.lastActivityAt;
    if (latestAction == null) return plant.updatedAt;
    return latestAction.isAfter(plant.updatedAt)
        ? latestAction
        : plant.updatedAt;
  }

  Future<void> loadActionsForPlant(String id) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final actions = await _repo.getActionsForPlant(id);
      _byPlant[id] = await _migrateLegacyPhotos(actions);
    } catch (error, stackTrace) {
      _error = 'Impossible de charger l’historique';
      _report(error, stackTrace, 'chargement des actions');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> reloadAfterRestore({bool reconcileNotifications = true}) async {
    _byPlant.clear();
    _plannedActions = [];
    _plannedError = null;
    _error = null;
    _homeSummaries = {};
    _homeSummariesLoaded = false;
    await Future.wait([loadHomeSummaries(), loadPlannedActions()]);

    var success = _homeSummariesError == null && _plannedError == null;
    if (!reconcileNotifications) return success;
    try {
      await PlannedActionNotificationService.reconcileFromDatabase();
    } catch (error, stackTrace) {
      success = false;
      _error = 'Données restaurées, mais rappels non replanifiés';
      _report(error, stackTrace, 'replanification après restauration');
      notifyListeners();
    }
    return success;
  }

  Future<PlantAction> addAction({
    required String plantId,
    required String actionType,
    DateTime? timestamp,
    double? quantity,
    String? quantityUnit,
    double? ph,
    bool phNA = false,
    double? tds,
    bool tdsNA = false,
    String? productUsed,
    String? pruningType,
    String? notes,
    String? parentPlantId,
    String? cuttingNotes,
    String? repotContainerType,
    List<String> photoPaths = const [],
    bool isWateringCombined = false,
    double? harvestWeightFresh,
    double? harvestWeightStored,
    double? harvestWeightWaste,
    String? status,
    DateTime? completedAt,
  }) async {
    final now = DateTime.now();
    final actionTime = timestamp ?? now;
    final actionStatus =
        status ?? (actionTime.isAfter(now) ? 'planned' : 'done');
    final action = PlantAction(
      id: _uuid.v4(),
      plantId: plantId,
      actionType: actionType,
      timestamp: actionTime,
      quantity: quantity,
      quantityUnit: quantityUnit,
      ph: ph,
      phNA: phNA,
      tds: tds,
      tdsNA: tdsNA,
      productUsed: productUsed,
      pruningType: pruningType,
      notes: notes,
      createdAt: now,
      parentPlantId: parentPlantId,
      cuttingNotes: cuttingNotes,
      repotContainerType: repotContainerType,
      photoPaths: photoPaths,
      isWateringCombined: isWateringCombined,
      harvestWeightFresh: harvestWeightFresh,
      harvestWeightStored: harvestWeightStored,
      harvestWeightWaste: harvestWeightWaste,
      status: actionStatus,
      completedAt: completedAt ?? (actionStatus == 'done' ? now : null),
    );
    await _repo.insertAction(action);
    _byPlant[plantId] ??= [];
    _byPlant[plantId]!.add(action);
    _byPlant[plantId]!.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    if (action.isPlanned) {
      _upsertPlanned(action);
      try {
        final p = await _plantRepo.getPlantById(plantId);
        await PlannedActionNotificationService.schedule(action, p);
      } catch (error, stackTrace) {
        _error = 'Action enregistrée, mais rappel non planifié';
        _report(error, stackTrace, 'planification d’un rappel');
      }
    }
    await _refreshHomeSummaries();
    notifyListeners();
    return action;
  }

  Future<void> addPhotoToAction(
      String plantId, String actionId, String path) async {
    try {
      await _repo.addPhotoToAction(actionId, plantId, path);
    } catch (error, stackTrace) {
      _report(error, stackTrace, 'association d’une photo à une action');
      try {
        if (await PhotoStorageService.isManagedPath(path)) {
          await PhotoStorageService.deleteManagedFile(path);
        }
      } catch (cleanupError, cleanupStackTrace) {
        _report(
          cleanupError,
          cleanupStackTrace,
          'nettoyage après échec d’association photo',
        );
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
    final list = _byPlant[plantId];
    if (list != null) {
      final i = list.indexWhere((a) => a.id == actionId);
      if (i != -1)
        list[i] = list[i].copyWith(photoPaths: [...list[i].photoPaths, path]);
    }
    notifyListeners();
  }

  Future<void> updateAction(PlantAction action) async {
    final removedPhotos = await _repo.updateAction(action);
    final list = _byPlant[action.plantId];
    if (list != null) {
      final i = list.indexWhere((a) => a.id == action.id);
      if (i != -1) list[i] = action;
      list.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    }
    if (action.isPlanned) {
      _upsertPlanned(action);
    } else {
      _plannedActions.removeWhere((item) => item.id == action.id);
    }
    await _refreshHomeSummaries();
    notifyListeners();
    try {
      await PhotoStorageService.deleteManagedFiles(removedPhotos);
    } on PhotoCleanupException catch (error, stackTrace) {
      _error = 'Action modifiée, mais nettoyage photo incomplet';
      _report(error, stackTrace, 'nettoyage après modification d’une action');
      notifyListeners();
    }
  }

  Future<PlantAction> repeatAction(PlantAction source) {
    return addAction(
      plantId: source.plantId,
      actionType: source.actionType,
      timestamp: DateTime.now(),
      quantity: source.quantity,
      quantityUnit: source.quantityUnit,
      ph: source.ph,
      phNA: source.phNA,
      tds: source.tds,
      tdsNA: source.tdsNA,
      productUsed: source.productUsed,
      pruningType: source.pruningType,
      notes: source.notes,
      parentPlantId: source.parentPlantId,
      cuttingNotes: source.cuttingNotes,
      repotContainerType: source.repotContainerType,
      isWateringCombined: source.isWateringCombined,
      harvestWeightFresh: source.harvestWeightFresh,
      harvestWeightStored: source.harvestWeightStored,
      harvestWeightWaste: source.harvestWeightWaste,
      status: 'done',
      completedAt: DateTime.now(),
    );
  }

  Future<List<PlantAction>> copyActionToPlants(
    PlantAction source,
    List<String> plantIds,
  ) async {
    final copied = <PlantAction>[];
    for (final plantId in plantIds) {
      if (plantId == source.plantId) continue;
      copied.add(await addAction(
        plantId: plantId,
        actionType: source.actionType,
        timestamp: DateTime.now(),
        quantity: source.quantity,
        quantityUnit: source.quantityUnit,
        ph: source.ph,
        phNA: source.phNA,
        tds: source.tds,
        tdsNA: source.tdsNA,
        productUsed: source.productUsed,
        pruningType: source.pruningType,
        notes: source.notes,
        parentPlantId: source.parentPlantId,
        cuttingNotes: source.cuttingNotes,
        repotContainerType: source.repotContainerType,
        isWateringCombined: source.isWateringCombined,
        harvestWeightFresh: source.harvestWeightFresh,
        harvestWeightStored: source.harvestWeightStored,
        harvestWeightWaste: source.harvestWeightWaste,
        status: 'done',
        completedAt: DateTime.now(),
      ));
    }
    return copied;
  }

  Future<void> completePlannedAction(PlantAction source) async {
    final stored = await _repo.getActionById(source.id);
    if (stored == null) throw StateError('Action planifiée introuvable');
    final now = DateTime.now();
    final done = stored.copyWith(
      timestamp: now,
      status: 'done',
      completedAt: now,
    );
    await _repo.updateAction(done);
    final list = _byPlant[done.plantId];
    if (list != null) {
      final i = list.indexWhere((a) => a.id == done.id);
      if (i != -1) list[i] = done;
      list.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    }
    _plannedActions.removeWhere((action) => action.id == done.id);
    await _refreshHomeSummaries();
    _error = null;
    try {
      await PlannedActionNotificationService.cancel(done.id);
    } catch (error, stackTrace) {
      _error = 'Action validée, mais rappel non annulé';
      _report(error, stackTrace, 'annulation d’un rappel validé');
    }
    notifyListeners();
  }

  Future<void> postponePlannedAction(
    PlantAction source,
    Duration duration,
  ) async {
    final stored = await _repo.getActionById(source.id);
    if (stored == null) throw StateError('Action planifiée introuvable');
    final postponed = stored.copyWith(
      timestamp: stored.timestamp.add(duration).isBefore(DateTime.now())
          ? DateTime.now().add(duration)
          : stored.timestamp.add(duration),
      status: 'planned',
    );
    await _repo.updateAction(postponed);
    final list = _byPlant[postponed.plantId];
    if (list != null) {
      final i = list.indexWhere((a) => a.id == postponed.id);
      if (i != -1) list[i] = postponed;
      list.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    }
    _upsertPlanned(postponed);
    await _refreshHomeSummaries();
    _error = null;
    try {
      final plant = await _plantRepo.getPlantById(postponed.plantId);
      await PlannedActionNotificationService.schedule(postponed, plant);
    } catch (error, stackTrace) {
      _error = 'Action reportée, mais rappel non replanifié';
      _report(error, stackTrace, 'replanification d’un rappel');
    }
    notifyListeners();
  }

  Future<void> deleteAction(String plantId, String actionId) async {
    final deleted = await _repo.deleteAction(actionId);
    if (deleted == null) throw StateError('Action introuvable');
    _byPlant[plantId]?.removeWhere((a) => a.id == actionId);
    _plannedActions.removeWhere((action) => action.id == actionId);
    await _refreshHomeSummaries();
    _error = null;
    notifyListeners();
    try {
      await PhotoStorageService.deleteManagedFiles(deleted.photoPaths);
    } on PhotoCleanupException catch (error, stackTrace) {
      _error = 'Action supprimée, mais nettoyage photo incomplet';
      _report(error, stackTrace, 'nettoyage après suppression d’une action');
    }
    try {
      await PlannedActionNotificationService.cancel(actionId);
    } catch (error, stackTrace) {
      _error = 'Action supprimée, mais rappel non annulé';
      _report(error, stackTrace, 'annulation d’un rappel');
    }
    notifyListeners();
  }

  Future<List<PlantAction>> _migrateLegacyPhotos(
    List<PlantAction> actions,
  ) async {
    final migratedActions = <PlantAction>[];
    for (final action in actions) {
      final migratedPaths = <String>[];
      for (final oldPath in action.photoPaths) {
        try {
          if (await PhotoStorageService.isManagedPath(oldPath)) {
            migratedPaths.add(oldPath);
            continue;
          }
          final newPath = await PhotoStorageService.migrateLegacyImage(
            oldPath,
            bucket: 'actions',
          );
          await _repo.replacePhotoPath(action.id, oldPath, newPath);
          await PhotoStorageService.finalizeLegacyMigration(oldPath);
          migratedPaths.add(newPath);
        } catch (error, stackTrace) {
          migratedPaths.add(oldPath);
          _error = 'Certaines anciennes photos n’ont pas pu être migrées';
          _report(error, stackTrace, 'migration d’une photo héritée');
        }
      }
      migratedActions.add(action.copyWith(photoPaths: migratedPaths));
    }
    return migratedActions;
  }

  void _upsertPlanned(PlantAction action) {
    _plannedActions.removeWhere((item) => item.id == action.id);
    _plannedActions.add(action);
    _plannedActions.sort((a, b) => a.timestamp.compareTo(b.timestamp));
  }

  void _report(Object error, StackTrace stackTrace, String operation) {
    FlutterError.reportError(FlutterErrorDetails(
      exception: error,
      stack: stackTrace,
      library: 'gardenjournal actions',
      context: ErrorDescription(operation),
    ));
  }
}
