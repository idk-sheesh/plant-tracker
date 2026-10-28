const _unsetActionValue = Object();

double? _optionalDouble(Object? value) {
  if (value == null) return null;
  return (value as num).toDouble();
}

class PlantAction {
  final String id;
  final String plantId;
  final String actionType;
  final DateTime timestamp;
  final double? quantity;
  final String? quantityUnit;
  final double? ph;
  final bool phNA;
  final double? tds;
  final bool tdsNA;
  final String? productUsed;
  final String? pruningType;
  final String? notes;
  final DateTime createdAt;
  final String? parentPlantId;
  final String? cuttingNotes;
  final String? repotContainerType;
  final List<String> photoPaths;
  final bool isWateringCombined;
  final double? harvestWeightFresh;
  final double? harvestWeightStored;
  final double? harvestWeightWaste;
  final String status;
  final DateTime? completedAt;

  const PlantAction({
    required this.id,
    required this.plantId,
    required this.actionType,
    required this.timestamp,
    this.quantity,
    this.quantityUnit,
    this.ph,
    this.phNA = false,
    this.tds,
    this.tdsNA = false,
    this.productUsed,
    this.pruningType,
    this.notes,
    required this.createdAt,
    this.parentPlantId,
    this.cuttingNotes,
    this.repotContainerType,
    this.photoPaths = const [],
    this.isWateringCombined = false,
    this.harvestWeightFresh,
    this.harvestWeightStored,
    this.harvestWeightWaste,
    this.status = 'done',
    this.completedAt,
  });

  bool get isPlanned => status == 'planned';
  bool get isDone => status != 'planned';

  PlantAction copyWith({
    String? id,
    String? plantId,
    String? actionType,
    DateTime? timestamp,
    Object? quantity = _unsetActionValue,
    Object? quantityUnit = _unsetActionValue,
    Object? ph = _unsetActionValue,
    bool? phNA,
    Object? tds = _unsetActionValue,
    bool? tdsNA,
    Object? productUsed = _unsetActionValue,
    Object? pruningType = _unsetActionValue,
    Object? notes = _unsetActionValue,
    DateTime? createdAt,
    Object? parentPlantId = _unsetActionValue,
    Object? cuttingNotes = _unsetActionValue,
    Object? repotContainerType = _unsetActionValue,
    List<String>? photoPaths,
    bool? isWateringCombined,
    Object? harvestWeightFresh = _unsetActionValue,
    Object? harvestWeightStored = _unsetActionValue,
    Object? harvestWeightWaste = _unsetActionValue,
    String? status,
    Object? completedAt = _unsetActionValue,
  }) {
    return PlantAction(
      id: id ?? this.id,
      plantId: plantId ?? this.plantId,
      actionType: actionType ?? this.actionType,
      timestamp: timestamp ?? this.timestamp,
      quantity: identical(quantity, _unsetActionValue)
          ? this.quantity
          : _optionalDouble(quantity),
      quantityUnit: identical(quantityUnit, _unsetActionValue)
          ? this.quantityUnit
          : quantityUnit as String?,
      ph: identical(ph, _unsetActionValue) ? this.ph : _optionalDouble(ph),
      phNA: phNA ?? this.phNA,
      tds: identical(tds, _unsetActionValue) ? this.tds : _optionalDouble(tds),
      tdsNA: tdsNA ?? this.tdsNA,
      productUsed: identical(productUsed, _unsetActionValue)
          ? this.productUsed
          : productUsed as String?,
      pruningType: identical(pruningType, _unsetActionValue)
          ? this.pruningType
          : pruningType as String?,
      notes:
          identical(notes, _unsetActionValue) ? this.notes : notes as String?,
      createdAt: createdAt ?? this.createdAt,
      parentPlantId: identical(parentPlantId, _unsetActionValue)
          ? this.parentPlantId
          : parentPlantId as String?,
      cuttingNotes: identical(cuttingNotes, _unsetActionValue)
          ? this.cuttingNotes
          : cuttingNotes as String?,
      repotContainerType: identical(repotContainerType, _unsetActionValue)
          ? this.repotContainerType
          : repotContainerType as String?,
      photoPaths: photoPaths ?? this.photoPaths,
      isWateringCombined: isWateringCombined ?? this.isWateringCombined,
      harvestWeightFresh: identical(harvestWeightFresh, _unsetActionValue)
          ? this.harvestWeightFresh
          : _optionalDouble(harvestWeightFresh),
      harvestWeightStored: identical(harvestWeightStored, _unsetActionValue)
          ? this.harvestWeightStored
          : _optionalDouble(harvestWeightStored),
      harvestWeightWaste: identical(harvestWeightWaste, _unsetActionValue)
          ? this.harvestWeightWaste
          : _optionalDouble(harvestWeightWaste),
      status: status ?? this.status,
      completedAt: identical(completedAt, _unsetActionValue)
          ? this.completedAt
          : completedAt as DateTime?,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'plant_id': plantId,
        'action_type': actionType,
        'timestamp': timestamp.toIso8601String(),
        'quantity': quantity,
        'quantity_unit': quantityUnit,
        'ph': ph,
        'ph_na': phNA ? 1 : 0,
        'tds': tds,
        'tds_na': tdsNA ? 1 : 0,
        'product_used': productUsed,
        'pruning_type': pruningType,
        'notes': notes,
        'created_at': createdAt.toIso8601String(),
        'parent_plant_id': parentPlantId,
        'cutting_notes': cuttingNotes,
        'repot_container_type': repotContainerType,
        'is_watering_combined': isWateringCombined ? 1 : 0,
        'harvest_weight_fresh': harvestWeightFresh,
        'harvest_weight_stored': harvestWeightStored,
        'harvest_weight_waste': harvestWeightWaste,
        'status': status,
        'completed_at': completedAt?.toIso8601String(),
      };

  factory PlantAction.fromMap(Map<String, dynamic> map,
          {List<String>? photos}) =>
      PlantAction(
        id: map['id'] as String,
        plantId: map['plant_id'] as String,
        actionType: map['action_type'] as String,
        timestamp: DateTime.parse(map['timestamp'] as String),
        quantity: (map['quantity'] as num?)?.toDouble(),
        quantityUnit: map['quantity_unit'] as String?,
        ph: (map['ph'] as num?)?.toDouble(),
        phNA: (map['ph_na'] as int? ?? 0) == 1,
        tds: (map['tds'] as num?)?.toDouble(),
        tdsNA: (map['tds_na'] as int? ?? 0) == 1,
        productUsed: map['product_used'] as String?,
        pruningType: map['pruning_type'] as String?,
        notes: map['notes'] as String?,
        createdAt: DateTime.parse(map['created_at'] as String),
        parentPlantId: map['parent_plant_id'] as String?,
        cuttingNotes: map['cutting_notes'] as String?,
        repotContainerType: map['repot_container_type'] as String?,
        photoPaths: photos ?? [],
        isWateringCombined: (map['is_watering_combined'] as int? ?? 0) == 1,
        harvestWeightFresh: (map['harvest_weight_fresh'] as num?)?.toDouble(),
        harvestWeightStored: (map['harvest_weight_stored'] as num?)?.toDouble(),
        harvestWeightWaste: (map['harvest_weight_waste'] as num?)?.toDouble(),
        status: map['status'] as String? ?? 'done',
        completedAt: map['completed_at'] == null
            ? null
            : DateTime.parse(map['completed_at'] as String),
      );
}
