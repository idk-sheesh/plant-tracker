import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/services/photo_storage_service.dart';
import '../../data/repositories/plant_repository.dart';
import '../../domain/entities/plant.dart';

class PlantProvider extends ChangeNotifier {
  final PlantRepository _repository;
  final Uuid _uuid;

  PlantProvider({PlantRepository? repository, Uuid? uuid})
      : _repository = repository ?? PlantRepository(),
        _uuid = uuid ?? const Uuid();

  List<Plant> _plants = [];
  bool _isLoading = false;
  bool _hasLoaded = false;
  String? _error;
  String? _filterGroupId;

  List<Plant> get plants {
    final filtered = _filterGroupId != null
        ? _plants
            .where((plant) => plant.groupId == _filterGroupId && !plant.isDead)
            .toList()
        : List<Plant>.from(_plants);
    filtered.sort((a, b) {
      if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
      if (a.isHarvested != b.isHarvested) return a.isHarvested ? 1 : -1;
      return b.updatedAt.compareTo(a.updatedAt);
    });
    return filtered;
  }

  List<Plant> get allPlants => List.unmodifiable(_plants);
  bool get isLoading => _isLoading;
  bool get hasLoaded => _hasLoaded;
  String? get error => _error;
  String? get filterGroupId => _filterGroupId;

  void setGroupFilter(String? id) {
    _filterGroupId = id;
    notifyListeners();
  }

  Future<void> loadPlants() async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      _plants = await _migrateLegacyPhotos(await _repository.getAllPlants());
      _hasLoaded = true;
    } catch (error, stackTrace) {
      _error = 'Impossible de charger les plantes';
      _report(error, stackTrace, 'chargement des plantes');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<Plant?> getPlantById(String id) async {
    for (final plant in _plants) {
      if (plant.id == id) return plant;
    }
    return _repository.getPlantById(id);
  }

  Future<Plant?> getPlantByQrCode(String qr) =>
      _repository.getPlantByQrCode(qr);

  Future<Plant> createPlant({
    required String name,
    String? variety,
    required DateTime pottingDate,
    required String cultureType,
    String? potSize,
    String? photoPath,
    String? notes,
    String? groupId,
    String location = 'indoor',
    String containerType = 'pot',
    String origin = 'unknown',
    bool? wateringReminder,
    String? observationCode,
  }) async {
    final now = DateTime.now();
    final id = _uuid.v4();
    final plant = Plant(
      id: id,
      name: name,
      variety: variety,
      pottingDate: pottingDate,
      cultureType: cultureType,
      potSize: potSize,
      photoPath: photoPath,
      notes: notes,
      groupId: groupId,
      qrCode: 'plant:$id',
      createdAt: now,
      updatedAt: now,
      location: location,
      containerType: containerType,
      origin: origin,
      wateringReminder: wateringReminder,
      observationCode: observationCode,
    );
    try {
      await _repository.insertPlant(plant);
      _plants.insert(0, plant);
      _error = null;
      notifyListeners();
      return plant;
    } catch (error, stackTrace) {
      _error = 'Création de la plante impossible';
      _report(error, stackTrace, 'création d’une plante');
      notifyListeners();
      rethrow;
    }
  }

  Future<void> updatePlant(Plant plant) async {
    final updated = plant.copyWith(updatedAt: DateTime.now());
    late List<String> removedPhotos;
    try {
      removedPhotos = await _repository.updatePlant(updated);
      final index = _plants.indexWhere((item) => item.id == plant.id);
      if (index != -1) _plants[index] = updated;
      _error = null;
      notifyListeners();
    } catch (error, stackTrace) {
      _error = 'Modification de la plante impossible';
      _report(error, stackTrace, 'modification d’une plante');
      notifyListeners();
      rethrow;
    }
    try {
      await PhotoStorageService.deleteManagedFiles(removedPhotos);
    } on PhotoCleanupException catch (error, stackTrace) {
      _error = 'Plante modifiée, mais nettoyage photo incomplet';
      _report(error, stackTrace, 'nettoyage après modification d’une plante');
      notifyListeners();
    }
  }

  Future<void> deletePlant(String id) async {
    late PlantDeletionResult result;
    try {
      final deletion = await _repository.deletePlant(id);
      if (deletion == null) throw StateError('Plante introuvable');
      result = deletion;
      _plants.removeWhere((plant) => plant.id == id);
      _error = null;
      notifyListeners();
    } catch (error, stackTrace) {
      _error = 'Suppression de la plante impossible';
      _report(error, stackTrace, 'suppression d’une plante');
      notifyListeners();
      rethrow;
    }
    try {
      await PhotoStorageService.deleteManagedFiles(result.photoPaths);
    } on PhotoCleanupException catch (error, stackTrace) {
      _error = 'Plante supprimée, mais nettoyage photo incomplet';
      _report(error, stackTrace, 'nettoyage après suppression d’une plante');
      notifyListeners();
    }
  }

  Future<Plant> duplicatePlant(Plant original) async {
    final now = DateTime.now();
    final id = _uuid.v4();
    final cutting = Plant(
      id: id,
      name: '${original.name} (cutting)',
      variety: original.variety,
      pottingDate: now,
      cultureType: original.cultureType,
      potSize: original.potSize,
      photoPath: original.photoPath,
      notes: original.notes,
      groupId: original.groupId,
      qrCode: 'plant:$id',
      createdAt: now,
      updatedAt: now,
      location: original.location,
      containerType: original.containerType,
      origin: original.origin,
      wateringReminder: original.wateringReminder,
      observationCode: original.observationCode,
    );
    await _repository.insertPlant(cutting);
    _plants.insert(0, cutting);
    notifyListeners();
    return cutting;
  }

  Future<void> togglePin(String id) async {
    final index = _plants.indexWhere((plant) => plant.id == id);
    if (index == -1) return;
    final updated = _plants[index].copyWith(
      isPinned: !_plants[index].isPinned,
      updatedAt: DateTime.now(),
    );
    await _repository.updatePlant(updated);
    _plants[index] = updated;
    notifyListeners();
  }

  Future<List<Plant>> _migrateLegacyPhotos(List<Plant> plants) async {
    final migrated = <Plant>[];
    for (final plant in plants) {
      final oldPath = plant.photoPath;
      if (oldPath == null || oldPath.trim().isEmpty) {
        migrated.add(plant);
        continue;
      }
      try {
        if (await PhotoStorageService.isManagedPath(oldPath)) {
          migrated.add(plant);
          continue;
        }
        final newPath = await PhotoStorageService.migrateLegacyImage(
          oldPath,
          bucket: 'plants',
        );
        await _repository.replacePhotoPath(plant.id, oldPath, newPath);
        await PhotoStorageService.finalizeLegacyMigration(oldPath);
        migrated.add(plant.copyWith(photoPath: newPath));
      } catch (error, stackTrace) {
        _error = 'Certaines anciennes photos n’ont pas pu être migrées';
        _report(error, stackTrace, 'migration d’une photo de plante');
        migrated.add(plant);
      }
    }
    return migrated;
  }

  void _report(Object error, StackTrace stackTrace, String operation) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'gardenjournal plants',
        context: ErrorDescription(operation),
      ),
    );
  }
}
