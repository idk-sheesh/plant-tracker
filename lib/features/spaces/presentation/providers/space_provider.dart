import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../../../../core/services/photo_storage_service.dart';

import '../../../groups/data/models/plant_group.dart';
import '../../../plants/domain/entities/plant.dart';
import '../../../sensors/data/repositories/sensor_data_repository.dart';
import '../../../sensors/domain/entities/sensor_reading.dart';
import '../../data/repositories/cultivation_zone_repository.dart';
import '../../data/repositories/zone_placement_repository.dart';
import '../../data/repositories/zone_photo_repository.dart';
import '../../domain/entities/climate_summary.dart';
import '../../domain/entities/cultivation_zone.dart';
import '../../domain/entities/zone_placement.dart';
import '../../domain/entities/zone_photo.dart';

class SpaceProvider extends ChangeNotifier {
  final CultivationZoneRepository _zoneRepository;
  final ZonePlacementRepository _placementRepository;
  final SensorDataRepository _sensorDataRepository;
  final Uuid _uuid;
  final ZonePhotoRepository _photoRepository;
  final Directory? _photoRoot;

  SpaceProvider({
    CultivationZoneRepository? zoneRepository,
    ZonePlacementRepository? placementRepository,
    SensorDataRepository? sensorDataRepository,
    ZonePhotoRepository? photoRepository,
    Directory? photoRoot,
    Uuid uuid = const Uuid(),
  })  : _zoneRepository = zoneRepository ?? CultivationZoneRepository(),
        _placementRepository = placementRepository ?? ZonePlacementRepository(),
        _sensorDataRepository = sensorDataRepository ?? SensorDataRepository(),
        _photoRepository = photoRepository ?? ZonePhotoRepository(),
        _photoRoot = photoRoot,
        _uuid = uuid;

  List<CultivationZone> _zones = [];
  List<ZonePlacement> _activePlacements = [];
  bool _isLoading = false;
  String? _error;
  Future<void>? _initialization;

  List<CultivationZone> get zones => List.unmodifiable(_zones);
  List<ZonePlacement> get activePlacements =>
      List.unmodifiable(_activePlacements);
  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<void> initialize() => _initialization ??= refresh();

  Future<void> refresh() async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      await _placementRepository.closePlacementsForEndedPlants();
      _zones = await _zoneRepository.getAll();
      _activePlacements = await _placementRepository.getActive();
    } catch (error, stackTrace) {
      _error = 'Impossible de charger les espaces';
      FlutterError.reportError(FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'gardenjournal spaces',
        context: ErrorDescription('chargement des espaces de culture'),
      ));
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  CultivationZone? getZone(String? id) {
    if (id == null) return null;
    for (final zone in _zones) {
      if (zone.id == id) return zone;
    }
    return null;
  }

  List<ZonePlacement> occupants(String zoneId) => _activePlacements
      .where((placement) => placement.zoneId == zoneId)
      .toList();

  ZonePlacement? directPlacementForPlant(String plantId) {
    for (final placement in _activePlacements) {
      if (placement.plantId == plantId) return placement;
    }
    return null;
  }

  ZonePlacement? placementForPlant(Plant plant) {
    final direct = directPlacementForPlant(plant.id);
    if (direct != null) return direct;
    if (plant.groupId == null) return null;
    return placementForGroup(plant.groupId!);
  }

  ZonePlacement? placementForGroup(String groupId) {
    for (final placement in _activePlacements) {
      if (placement.groupId == groupId) return placement;
    }
    return null;
  }

  Future<CultivationZone> createZone({
    required String name,
    required CultivationZoneType type,
    double? widthCm,
    double? depthCm,
    double? heightCm,
    String? description,
    required ClimateTargetProfile targetProfile,
  }) async {
    final now = DateTime.now();
    final zone = CultivationZone(
      id: _uuid.v4(),
      name: name.trim(),
      type: type,
      widthCm: widthCm,
      depthCm: depthCm,
      heightCm: heightCm,
      description: description,
      targetProfile: targetProfile,
      createdAt: now,
      updatedAt: now,
    );
    await _zoneRepository.insert(zone);
    _zones.add(zone);
    _zones.sort((a, b) => a.name.compareTo(b.name));
    notifyListeners();
    return zone;
  }

  Future<void> updateZone(CultivationZone zone) async {
    final updated = zone.copyWith(updatedAt: DateTime.now());
    await _zoneRepository.update(updated);
    final index = _zones.indexWhere((item) => item.id == zone.id);
    if (index >= 0) _zones[index] = updated;
    notifyListeners();
  }

  Future<void> movePlant(
    Plant plant,
    CultivationZone zone, {
    String? note,
  }) async {
    await _placementRepository.movePlant(
      plantId: plant.id,
      plantName: plant.name,
      zoneId: zone.id,
      note: note,
    );
    _activePlacements = await _placementRepository.getActive();
    notifyListeners();
  }

  Future<void> moveGroup(
    PlantGroup group,
    CultivationZone zone, {
    String? note,
  }) async {
    await _placementRepository.moveGroup(
      groupId: group.id,
      groupName: group.name,
      zoneId: zone.id,
      note: note,
    );
    _activePlacements = await _placementRepository.getActive();
    notifyListeners();
  }

  Future<void> closePlacement(ZonePlacement placement) async {
    await _placementRepository.closePlacement(placement);
    _activePlacements = await _placementRepository.getActive();
    notifyListeners();
  }

  Future<List<ZonePlacement>> historyForZone(String zoneId) =>
      _placementRepository.getForZone(zoneId);

  Future<List<ZonePhoto>> photosForZone(String zoneId) =>
      _photoRepository.getForZone(zoneId);

  Future<ZonePhoto> addZonePhoto({
    required String zoneId,
    required String sourcePath,
    DateTime? capturedAt,
    String? caption,
  }) async {
    final stored = await PhotoStorageService.persistImage(sourcePath,
        bucket: 'spaces', rootDirectory: _photoRoot);
    final now = DateTime.now();
    final photo = ZonePhoto(
        id: _uuid.v4(),
        zoneId: zoneId,
        photoPath: stored,
        capturedAt: capturedAt ?? now,
        caption: caption?.trim().isEmpty == true ? null : caption?.trim(),
        createdAt: now);
    try {
      await _photoRepository.insert(photo);
    } catch (_) {
      if (File(sourcePath).absolute.path != stored) {
        await PhotoStorageService.deleteManagedFile(stored,
            rootDirectory: _photoRoot);
      }
      rethrow;
    }
    notifyListeners();
    return photo;
  }

  Future<List<ZonePlacement>> historyForPlant(
    String plantId, {
    String? groupId,
  }) async {
    final placements = await _placementRepository.getForPlant(plantId);
    if (groupId != null) {
      placements.addAll(await _placementRepository.getForGroup(groupId));
    }
    placements.sort((a, b) => b.enteredAt.compareTo(a.enteredAt));
    return placements;
  }

  Future<ClimateSummary> climateSummary(
    CultivationZone zone,
    Duration period,
  ) async {
    final end = DateTime.now();
    final start = end.subtract(period);
    final readings = await _sensorDataRepository.getReadingsForZoneSince(
      zone.id,
      start,
    );
    return ClimateSummary.calculate(
      readings: readings,
      profile: zone.targetProfile,
      periodStart: start,
      periodEnd: end,
    );
  }

  Future<ClimateSummary> climateSummaryBetween(
    CultivationZone zone,
    DateTime start,
    DateTime end,
  ) async {
    final data = await climateDataBetween(zone, start, end);
    return data.summary;
  }

  Future<({List<SensorReading> readings, ClimateSummary summary})>
      climateDataBetween(
    CultivationZone zone,
    DateTime start,
    DateTime end,
  ) async {
    final readings = (await _sensorDataRepository.getReadingsForZoneSince(
      zone.id,
      start,
    ))
        .where((reading) => !reading.timestamp.isAfter(end))
        .toList(growable: false);
    return (
      readings: readings,
      summary: ClimateSummary.calculate(
        readings: readings,
        profile: zone.targetProfile,
        periodStart: start,
        periodEnd: end,
      ),
    );
  }

  Future<List<SensorReading>> climateReadingsBetween(
    String zoneId,
    DateTime start, {
    DateTime? end,
  }) async {
    final readings =
        await _sensorDataRepository.getReadingsForZoneSince(zoneId, start);
    return end == null
        ? readings
        : readings
            .where((reading) => reading.timestamp.isBefore(end))
            .toList(growable: false);
  }
}
