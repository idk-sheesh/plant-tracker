import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Color;
import 'package:uuid/uuid.dart';

import '../../data/models/plant_group.dart';
import '../../data/repositories/group_repository.dart';

class GroupProvider extends ChangeNotifier {
  final GroupRepository _repository;
  final Uuid _uuid;

  GroupProvider({GroupRepository? repository, Uuid? uuid})
      : _repository = repository ?? GroupRepository(),
        _uuid = uuid ?? const Uuid();

  List<PlantGroup> _groups = [];
  bool _isLoading = false;
  bool _hasLoaded = false;
  String? _error;

  bool get isLoading => _isLoading;
  bool get hasLoaded => _hasLoaded;
  String? get error => _error;
  List<PlantGroup> get groups => List.unmodifiable(_groups);

  PlantGroup? getGroupById(String? id) {
    if (id == null) return null;
    for (final group in _groups) {
      if (group.id == id) return group;
    }
    return null;
  }

  Future<void> loadGroups() async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      _groups = await _repository.getAllGroups();
      _hasLoaded = true;
    } catch (error, stackTrace) {
      _error = 'Impossible de charger les groupes';
      _report(error, stackTrace, 'chargement des groupes');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<PlantGroup> createGroup({
    required String name,
    String? description,
    required Color color,
    String? parentGroupId,
  }) async {
    final group = PlantGroup(
      id: _uuid.v4(),
      name: name,
      description: description,
      color: color,
      createdAt: DateTime.now(),
      parentGroupId: parentGroupId,
    );
    try {
      await _repository.insertGroup(group);
      _groups.insert(0, group);
      _error = null;
      notifyListeners();
      return group;
    } catch (error, stackTrace) {
      _error = 'Création du groupe impossible';
      _report(error, stackTrace, 'création d’un groupe');
      notifyListeners();
      rethrow;
    }
  }

  Future<void> updateGroup(PlantGroup group) async {
    try {
      await _repository.updateGroup(group);
      final index = _groups.indexWhere((item) => item.id == group.id);
      if (index != -1) _groups[index] = group;
      _error = null;
      notifyListeners();
    } catch (error, stackTrace) {
      _error = 'Modification du groupe impossible';
      _report(error, stackTrace, 'modification d’un groupe');
      notifyListeners();
      rethrow;
    }
  }

  Future<void> deleteGroup(String id) async {
    try {
      await _repository.deleteGroup(id);
      _groups = await _repository.getAllGroups();
      _error = null;
      notifyListeners();
    } catch (error, stackTrace) {
      _error = 'Suppression du groupe impossible';
      _report(error, stackTrace, 'suppression d’un groupe');
      notifyListeners();
      rethrow;
    }
  }

  void _report(Object error, StackTrace stackTrace, String operation) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'gardenjournal groups',
        context: ErrorDescription(operation),
      ),
    );
  }
}
