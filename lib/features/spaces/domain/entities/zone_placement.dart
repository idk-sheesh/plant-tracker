class ZonePlacement {
  final String id;
  final String zoneId;
  final String? plantId;
  final String? groupId;
  final String entityName;
  final DateTime enteredAt;
  final DateTime? exitedAt;
  final String? note;
  final DateTime createdAt;
  final DateTime updatedAt;

  const ZonePlacement({
    required this.id,
    required this.zoneId,
    this.plantId,
    this.groupId,
    required this.entityName,
    required this.enteredAt,
    this.exitedAt,
    this.note,
    required this.createdAt,
    required this.updatedAt,
  }) : assert(plantId == null || groupId == null);

  bool get isActive => exitedAt == null;
  bool get isPlant => plantId != null;
  String get entityTypeLabel => isPlant ? 'Plante' : 'Groupe';

  ZonePlacement copyWith({DateTime? exitedAt, DateTime? updatedAt}) {
    return ZonePlacement(
      id: id,
      zoneId: zoneId,
      plantId: plantId,
      groupId: groupId,
      entityName: entityName,
      enteredAt: enteredAt,
      exitedAt: exitedAt ?? this.exitedAt,
      note: note,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'zone_id': zoneId,
        'plant_id': plantId,
        'group_id': groupId,
        'entity_name': entityName,
        'entered_at': enteredAt.toUtc().millisecondsSinceEpoch ~/ 1000,
        'exited_at': exitedAt?.toUtc().millisecondsSinceEpoch == null
            ? null
            : exitedAt!.toUtc().millisecondsSinceEpoch ~/ 1000,
        'note': note,
        'created_at': createdAt.toUtc().toIso8601String(),
        'updated_at': updatedAt.toUtc().toIso8601String(),
      };

  factory ZonePlacement.fromMap(Map<String, dynamic> map) {
    DateTime fromSeconds(Object? value) => DateTime.fromMillisecondsSinceEpoch(
          (value as int) * 1000,
          isUtc: true,
        ).toLocal();
    return ZonePlacement(
      id: map['id'] as String,
      zoneId: map['zone_id'] as String,
      plantId: map['plant_id'] as String?,
      groupId: map['group_id'] as String?,
      entityName: map['entity_name'] as String,
      enteredAt: fromSeconds(map['entered_at']),
      exitedAt: map['exited_at'] == null ? null : fromSeconds(map['exited_at']),
      note: map['note'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String).toLocal(),
      updatedAt: DateTime.parse(map['updated_at'] as String).toLocal(),
    );
  }
}
