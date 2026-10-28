class CameraSnapshot {
  final String id;
  final String deviceId;
  final String? zoneId;
  final DateTime capturedAt;
  final String sha256;
  final int sizeBytes;
  final DateTime createdAt;
  final String? photoPath;

  const CameraSnapshot({
    required this.id,
    required this.deviceId,
    required this.zoneId,
    required this.capturedAt,
    required this.sha256,
    required this.sizeBytes,
    required this.createdAt,
    this.photoPath,
  });

  factory CameraSnapshot.fromGatewayJson(
    Map<String, dynamic> json, {
    required String deviceId,
    required String? zoneId,
  }) {
    final id = json['id'];
    final capturedAtRaw = json['capturedAt'];
    final hash = json['sha256'];
    final size = json['sizeBytes'];
    final capturedAt = capturedAtRaw is String
        ? DateTime.tryParse(capturedAtRaw)?.toLocal()
        : null;
    if (id is! String ||
        !RegExp(r'^[a-zA-Z0-9][a-zA-Z0-9_.:-]{0,127}$').hasMatch(id) ||
        capturedAt == null ||
        hash is! String ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(hash) ||
        size is! int ||
        size <= 0 ||
        size > 16 * 1024 * 1024) {
      throw const FormatException('Métadonnées de photo caméra invalides');
    }
    return CameraSnapshot(
      id: id,
      deviceId: deviceId,
      zoneId: zoneId,
      capturedAt: capturedAt,
      sha256: hash,
      sizeBytes: size,
      createdAt: DateTime.now(),
      photoPath: null,
    );
  }

  CameraSnapshot copyWith({
    String? photoPath,
    DateTime? createdAt,
  }) =>
      CameraSnapshot(
        id: id,
        deviceId: deviceId,
        zoneId: zoneId,
        capturedAt: capturedAt,
        sha256: sha256,
        sizeBytes: sizeBytes,
        createdAt: createdAt ?? this.createdAt,
        photoPath: photoPath ?? this.photoPath,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'device_id': deviceId,
        'zone_id': zoneId,
        'captured_at': capturedAt.toUtc().millisecondsSinceEpoch ~/ 1000,
        'sha256': sha256,
        'size_bytes': sizeBytes,
        'created_at': createdAt.toUtc().toIso8601String(),
        'photo_path': photoPath,
      };

  factory CameraSnapshot.fromMap(Map<String, dynamic> map) => CameraSnapshot(
        id: map['id'] as String,
        deviceId: map['device_id'] as String,
        zoneId: map['zone_id'] as String?,
        capturedAt: DateTime.fromMillisecondsSinceEpoch(
          (map['captured_at'] as int) * 1000,
          isUtc: true,
        ).toLocal(),
        sha256: map['sha256'] as String,
        sizeBytes: map['size_bytes'] as int,
        createdAt: DateTime.parse(map['created_at'] as String).toLocal(),
        photoPath: map['photo_path'] as String?,
      );
}
