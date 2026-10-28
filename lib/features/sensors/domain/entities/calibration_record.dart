import 'dart:convert';

class CalibrationRecord {
  final String id;
  final String deviceId;
  final String capabilityKey;
  final String calibrationType;
  final DateTime calibratedAt;
  final Map<String, double> referenceValues;
  final Map<String, double> coefficients;
  final double? temperatureC;
  final String? operatorName;
  final String? solutionLot;
  final DateTime? expiresAt;
  final DateTime nodeAckAt;
  final String nodeConfigHash;
  final String? notes;
  final DateTime createdAt;

  const CalibrationRecord({
    required this.id,
    required this.deviceId,
    required this.capabilityKey,
    required this.calibrationType,
    required this.calibratedAt,
    required this.referenceValues,
    required this.coefficients,
    this.temperatureC,
    this.operatorName,
    this.solutionLot,
    this.expiresAt,
    required this.nodeAckAt,
    required this.nodeConfigHash,
    this.notes,
    required this.createdAt,
  });

  bool get isExpired =>
      expiresAt != null && !expiresAt!.isAfter(DateTime.now());

  Map<String, Object?> toMap() => {
        'id': id,
        'device_id': deviceId,
        'capability_key': capabilityKey,
        'calibration_type': calibrationType,
        'calibrated_at': calibratedAt.toUtc().millisecondsSinceEpoch ~/ 1000,
        'reference_values_json': jsonEncode(referenceValues),
        'coefficients_json': jsonEncode(coefficients),
        'temperature_c': temperatureC,
        'operator_name': operatorName,
        'solution_lot': solutionLot,
        'expires_at': expiresAt?.toUtc().millisecondsSinceEpoch == null
            ? null
            : expiresAt!.toUtc().millisecondsSinceEpoch ~/ 1000,
        'node_ack_at': nodeAckAt.toUtc().millisecondsSinceEpoch ~/ 1000,
        'node_config_hash': nodeConfigHash,
        'notes': notes,
        'created_at': createdAt.toUtc().toIso8601String(),
      };

  factory CalibrationRecord.fromMap(Map<String, dynamic> map) {
    DateTime fromSeconds(Object? value) => DateTime.fromMillisecondsSinceEpoch(
          (value as int) * 1000,
          isUtc: true,
        ).toLocal();
    Map<String, double> decodeNumbers(Object? raw) {
      final decoded = jsonDecode(raw as String) as Map<String, dynamic>;
      return decoded.map(
        (key, value) => MapEntry(key, (value as num).toDouble()),
      );
    }

    return CalibrationRecord(
      id: map['id'] as String,
      deviceId: map['device_id'] as String,
      capabilityKey: map['capability_key'] as String,
      calibrationType: map['calibration_type'] as String,
      calibratedAt: fromSeconds(map['calibrated_at']),
      referenceValues: decodeNumbers(map['reference_values_json']),
      coefficients: decodeNumbers(map['coefficients_json']),
      temperatureC: (map['temperature_c'] as num?)?.toDouble(),
      operatorName: map['operator_name'] as String?,
      solutionLot: map['solution_lot'] as String?,
      expiresAt:
          map['expires_at'] == null ? null : fromSeconds(map['expires_at']),
      nodeAckAt: fromSeconds(map['node_ack_at']),
      nodeConfigHash: map['node_config_hash'] as String,
      notes: map['notes'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String).toLocal(),
    );
  }
}
