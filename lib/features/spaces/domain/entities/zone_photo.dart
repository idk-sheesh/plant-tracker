class ZonePhoto {
  final String id;
  final String zoneId;
  final String photoPath;
  final DateTime capturedAt;
  final String? caption;
  final DateTime createdAt;

  const ZonePhoto(
      {required this.id,
      required this.zoneId,
      required this.photoPath,
      required this.capturedAt,
      this.caption,
      required this.createdAt});

  Map<String, Object?> toMap() => {
        'id': id,
        'zone_id': zoneId,
        'photo_path': photoPath,
        'captured_at': capturedAt.toUtc().millisecondsSinceEpoch ~/ 1000,
        'caption': caption,
        'created_at': createdAt.toUtc().toIso8601String(),
      };

  factory ZonePhoto.fromMap(Map<String, Object?> map) => ZonePhoto(
        id: map['id'] as String,
        zoneId: map['zone_id'] as String,
        photoPath: map['photo_path'] as String,
        capturedAt: DateTime.fromMillisecondsSinceEpoch(
                (map['captured_at'] as int) * 1000,
                isUtc: true)
            .toLocal(),
        caption: map['caption'] as String?,
        createdAt: DateTime.parse(map['created_at'] as String).toLocal(),
      );
}
