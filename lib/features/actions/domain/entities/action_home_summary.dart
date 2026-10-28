class ActionHomeSummary {
  final String plantId;
  final DateTime? lastWaterAt;
  final DateTime? lastActivityAt;
  final DateTime? lastObservationAt;
  final DateTime? lastFloweringAt;

  const ActionHomeSummary(
      {required this.plantId,
      this.lastWaterAt,
      this.lastActivityAt,
      this.lastObservationAt,
      this.lastFloweringAt});

  factory ActionHomeSummary.fromMap(Map<String, dynamic> map) =>
      ActionHomeSummary(
        plantId: map['plant_id'] as String,
        lastWaterAt: _parseDate(map['last_water_at']),
        lastActivityAt: _parseDate(map['last_activity_at']),
        lastObservationAt: _parseDate(map['last_observation_at']),
        lastFloweringAt: _parseDate(map['last_flowering_at']),
      );

  static DateTime? _parseDate(Object? value) =>
      value == null ? null : DateTime.tryParse(value as String);
}
