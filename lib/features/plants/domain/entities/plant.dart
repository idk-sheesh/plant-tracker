class Plant {
  final String id;
  final String name;
  final String? variety;
  final DateTime pottingDate;
  final String cultureType;
  final String? potSize;
  final String? photoPath;
  final String? notes;
  final String? groupId;
  final String qrCode;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String location;
  final String containerType;
  final String origin; // 'seed' | 'cutting' | 'unknown'
  final bool isPinned;
  final bool isHarvested;
  final bool isDead;

  /// Null follows the location default; an explicit choice survives moves.
  final bool? wateringReminder;
  final String? observationCode;

  const Plant({
    required this.id,
    required this.name,
    this.variety,
    required this.pottingDate,
    required this.cultureType,
    this.potSize,
    this.photoPath,
    this.notes,
    this.groupId,
    required this.qrCode,
    required this.createdAt,
    required this.updatedAt,
    this.location = 'indoor',
    this.containerType = 'pot',
    this.origin = 'unknown',
    this.isPinned = false,
    this.isHarvested = false,
    this.isDead = false,
    this.wateringReminder,
    this.observationCode,
  });

  Plant copyWith({
    String? id,
    String? name,
    Object? variety = _unsetPlantValue,
    DateTime? pottingDate,
    String? cultureType,
    Object? potSize = _unsetPlantValue,
    Object? photoPath = _unsetPlantValue,
    Object? notes = _unsetPlantValue,
    Object? groupId = _unsetPlantValue,
    String? qrCode,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? location,
    String? containerType,
    String? origin,
    bool? isPinned,
    bool? isHarvested,
    bool? isDead,
    Object? wateringReminder = _unsetPlantValue,
    Object? observationCode = _unsetPlantValue,
  }) {
    return Plant(
      id: id ?? this.id,
      name: name ?? this.name,
      variety: identical(variety, _unsetPlantValue)
          ? this.variety
          : variety as String?,
      pottingDate: pottingDate ?? this.pottingDate,
      cultureType: cultureType ?? this.cultureType,
      potSize: identical(potSize, _unsetPlantValue)
          ? this.potSize
          : potSize as String?,
      photoPath: identical(photoPath, _unsetPlantValue)
          ? this.photoPath
          : photoPath as String?,
      notes: identical(notes, _unsetPlantValue) ? this.notes : notes as String?,
      groupId: identical(groupId, _unsetPlantValue)
          ? this.groupId
          : groupId as String?,
      qrCode: qrCode ?? this.qrCode,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      location: location ?? this.location,
      containerType: containerType ?? this.containerType,
      origin: origin ?? this.origin,
      isPinned: isPinned ?? this.isPinned,
      isHarvested: isHarvested ?? this.isHarvested,
      isDead: isDead ?? this.isDead,
      wateringReminder: identical(wateringReminder, _unsetPlantValue)
          ? this.wateringReminder
          : wateringReminder as bool?,
      observationCode: identical(observationCode, _unsetPlantValue)
          ? this.observationCode
          : observationCode as String?,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'variety': variety,
        'potting_date': pottingDate.toIso8601String(),
        'culture_type': cultureType,
        'pot_size': potSize,
        'photo_path': photoPath,
        'notes': notes,
        'group_id': groupId,
        'qr_code': qrCode,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
        'location': location,
        'container_type': containerType,
        'origin': origin,
        'is_pinned': isPinned ? 1 : 0,
        'is_harvested': isHarvested ? 1 : 0,
        'is_dead': isDead ? 1 : 0,
        'watering_reminder':
            wateringReminder == null ? null : (wateringReminder! ? 1 : 0),
        'observation_code': observationCode,
      };

  factory Plant.fromMap(Map<String, dynamic> map) => Plant(
        id: map['id'] as String,
        name: map['name'] as String,
        variety: map['variety'] as String?,
        pottingDate: DateTime.parse(map['potting_date'] as String),
        cultureType: map['culture_type'] as String,
        potSize: map['pot_size'] as String?,
        photoPath: map['photo_path'] as String?,
        notes: map['notes'] as String?,
        groupId: map['group_id'] as String?,
        qrCode: map['qr_code'] as String,
        createdAt: DateTime.parse(map['created_at'] as String),
        updatedAt: DateTime.parse(map['updated_at'] as String),
        location: map['location'] as String? ?? 'indoor',
        containerType: map['container_type'] as String? ?? 'pot',
        origin: map['origin'] as String? ?? 'unknown',
        isPinned: (map['is_pinned'] as int? ?? 0) == 1,
        isHarvested: (map['is_harvested'] as int? ?? 0) == 1,
        isDead: (map['is_dead'] as int? ?? 0) == 1,
        wateringReminder: map['watering_reminder'] == null
            ? null
            : map['watering_reminder'] == 1,
        observationCode: map['observation_code'] as String?,
      );

  int get daysSincePotting => DateTime.now().difference(pottingDate).inDays;

  bool get hasWateringReminder =>
      !isHarvested &&
      !isDead &&
      (wateringReminder ??
          (location != 'outdoor' && containerType != 'plein_sol'));

  String get observationLabel => observationCode?.trim().isNotEmpty == true
      ? '$name · ${observationCode!.trim()}'
      : name;

  String get locationLabel => location == 'outdoor' ? 'Exterieur' : 'Interieur';
  String get locationEmoji => location == 'outdoor' ? 'Ext.' : 'Int.';

  String get containerLabel {
    switch (containerType) {
      case 'pot_tissu':
        return 'Pot tissu';
      case 'plein_sol':
        return 'Plein sol';
      default:
        return 'Pot';
    }
  }

  String get containerEmoji {
    switch (containerType) {
      case 'pot_tissu':
        return 'Tissu';
      case 'plein_sol':
        return 'Sol';
      default:
        return 'Pot';
    }
  }

  String get originLabel {
    switch (origin) {
      case 'seed':
        return 'Graine';
      case 'cutting':
        return 'Bouture';
      default:
        return 'Origine ?';
    }
  }

  String get originEmoji {
    switch (origin) {
      case 'seed':
        return 'Seed';
      case 'cutting':
        return 'Bouture';
      default:
        return '?';
    }
  }
}

const _unsetPlantValue = Object();
