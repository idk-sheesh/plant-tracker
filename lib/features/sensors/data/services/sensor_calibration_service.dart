import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';

import '../../domain/entities/calibration_record.dart';
import '../../domain/entities/sensor_device.dart';
import '../repositories/calibration_repository.dart';
import '../repositories/sensor_repository.dart';

class SensorCalibrationService {
  final SensorRepository _remote;
  final CalibrationRepository _local;
  final Uuid _uuid;
  final DateTime Function() _clock;

  SensorCalibrationService({
    SensorRepository? remote,
    CalibrationRepository? local,
    Uuid uuid = const Uuid(),
    DateTime Function()? clock,
  })  : _remote = remote ?? SensorRepository(),
        _local = local ?? CalibrationRepository(),
        _uuid = uuid,
        _clock = clock ?? DateTime.now;

  Future<CalibrationRecord> calibrate({
    required SensorDevice device,
    required String capabilityKey,
    required String calibrationType,
    required Map<String, double> referenceValues,
    required Map<String, double> coefficients,
    double? temperatureC,
    String? operatorName,
    String? solutionLot,
    DateTime? expiresAt,
    String? notes,
  }) async {
    final calibratedAt = _clock();
    _validate(
      capabilityKey: capabilityKey,
      calibrationType: calibrationType,
      referenceValues: referenceValues,
      coefficients: coefficients,
      temperatureC: temperatureC,
      expiresAt: expiresAt,
      now: calibratedAt,
    );
    if (!_remote.configureBaseUrl(device.baseUrl)) {
      throw const FormatException('Adresse HTTP locale du nœud invalide');
    }

    final calibration = <String, Object?>{
      'version': 1,
      'capabilityKey': capabilityKey.trim(),
      'type': calibrationType,
      'referenceValues': _sortedNumbers(referenceValues),
      'coefficients': _sortedNumbers(coefficients),
      if (temperatureC != null) 'temperatureC': temperatureC,
      if (_text(operatorName) case final value?) 'operator': value,
      if (_text(solutionLot) case final value?) 'solutionLot': value,
      if (expiresAt != null) 'expiresAt': expiresAt.toUtc().toIso8601String(),
    };
    final canonical = jsonEncode(calibration);
    final accepted = await _remote.updateConfig({'calibration': calibration});
    if (!accepted) throw StateError('Calibration refusée par le nœud');

    final acknowledgedAt = _clock();
    final record = CalibrationRecord(
      id: _uuid.v4(),
      deviceId: device.id,
      capabilityKey: capabilityKey.trim(),
      calibrationType: calibrationType,
      calibratedAt: calibratedAt,
      referenceValues: Map.unmodifiable(_sortedNumbers(referenceValues)),
      coefficients: Map.unmodifiable(_sortedNumbers(coefficients)),
      temperatureC: temperatureC,
      operatorName: _text(operatorName),
      solutionLot: _text(solutionLot),
      expiresAt: expiresAt,
      nodeAckAt:
          acknowledgedAt.isBefore(calibratedAt) ? calibratedAt : acknowledgedAt,
      nodeConfigHash: sha256.convert(utf8.encode(canonical)).toString(),
      notes: _text(notes, maximum: 2000),
      createdAt: acknowledgedAt,
    );
    await _local.insert(record);
    return record;
  }

  void _validate({
    required String capabilityKey,
    required String calibrationType,
    required Map<String, double> referenceValues,
    required Map<String, double> coefficients,
    required double? temperatureC,
    required DateTime? expiresAt,
    required DateTime now,
  }) {
    if (capabilityKey.trim().isEmpty || capabilityKey.length > 80) {
      throw const FormatException('Capacité invalide');
    }
    const expectedPoints = {
      'single_point': 1,
      'two_point': 2,
      'three_point': 3,
    };
    final points = expectedPoints[calibrationType];
    if (points == null)
      throw const FormatException('Type de calibration invalide');
    if (referenceValues.length != points) {
      throw FormatException('$points valeur(s) de référence requise(s)');
    }
    if (coefficients.isEmpty || coefficients.length > 12) {
      throw const FormatException('Coefficients de calibration invalides');
    }
    for (final entry in [...referenceValues.entries, ...coefficients.entries]) {
      if (entry.key.trim().isEmpty ||
          entry.key.length > 40 ||
          !entry.value.isFinite) {
        throw const FormatException('Valeur de calibration invalide');
      }
    }
    if (temperatureC != null &&
        (!temperatureC.isFinite || temperatureC < -20 || temperatureC > 80)) {
      throw const FormatException('Température de calibration invalide');
    }
    if (expiresAt != null && !expiresAt.isAfter(now)) {
      throw const FormatException('Expiration de calibration invalide');
    }
  }

  static Map<String, double> _sortedNumbers(Map<String, double> source) {
    final keys = source.keys.toList()..sort();
    return {for (final key in keys) key: source[key]!};
  }

  static String? _text(String? value, {int maximum = 120}) {
    final normalized = value?.trim();
    if (normalized == null || normalized.isEmpty) return null;
    if (normalized.length > maximum) {
      throw FormatException('Texte limité à $maximum caractères');
    }
    return normalized;
  }
}
