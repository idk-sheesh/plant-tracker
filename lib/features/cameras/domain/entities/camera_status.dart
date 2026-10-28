import 'camera_snapshot.dart';

class CameraStatus {
  final String cameraId;
  final String name;
  final String zoneId;
  final String status;
  final DateTime? lastSeenAt;
  final String? firmwareVersion;
  final int? rssi;
  final int? freeHeapBytes;
  final int? uptimeSeconds;
  final String? lastError;
  final CameraSnapshot? latestSnapshot;

  const CameraStatus({
    required this.cameraId,
    required this.name,
    required this.zoneId,
    required this.status,
    required this.lastSeenAt,
    required this.firmwareVersion,
    required this.rssi,
    required this.freeHeapBytes,
    required this.uptimeSeconds,
    required this.lastError,
    required this.latestSnapshot,
  });

  bool get isOnline => status == 'online';

  factory CameraStatus.fromJson(Map<String, dynamic> json) {
    final id = _identifier(json['id'], 'id');
    final zoneId = _identifier(json['zoneId'], 'zoneId');
    final name = json['name'];
    final status = json['status'];
    if (name is! String ||
        name.trim().isEmpty ||
        name.length > 120 ||
        !const {'online', 'offline'}.contains(status)) {
      throw const FormatException('État caméra invalide');
    }
    final lastSeenRaw = json['lastSeenAt'];
    final lastSeen = lastSeenRaw == null
        ? null
        : lastSeenRaw is String
            ? DateTime.tryParse(lastSeenRaw)?.toLocal()
            : null;
    if (lastSeenRaw != null && lastSeen == null) {
      throw const FormatException('Date de contact caméra invalide');
    }
    int? boundedInt(String key, int minimum, int maximum) {
      final value = json[key];
      if (value == null) return null;
      if (value is! int || value < minimum || value > maximum) {
        throw FormatException('Champ caméra $key invalide');
      }
      return value;
    }

    final firmware = json['firmwareVersion'];
    final error = json['lastError'];
    if (firmware != null && (firmware is! String || firmware.length > 80)) {
      throw const FormatException('Version firmware caméra invalide');
    }
    if (error != null && (error is! String || error.length > 240)) {
      throw const FormatException('Erreur caméra invalide');
    }
    final rawSnapshot = json['latestSnapshot'];
    if (rawSnapshot != null && rawSnapshot is! Map) {
      throw const FormatException('Dernière photo caméra invalide');
    }
    return CameraStatus(
      cameraId: id,
      name: name.trim(),
      zoneId: zoneId,
      status: status as String,
      lastSeenAt: lastSeen,
      firmwareVersion: firmware as String?,
      rssi: boundedInt('rssiDbm', -200, 20),
      freeHeapBytes: boundedInt('freeHeapBytes', 0, 1 << 31),
      uptimeSeconds: boundedInt('uptimeSeconds', 0, 1 << 31),
      lastError: error as String?,
      latestSnapshot: rawSnapshot == null
          ? null
          : CameraSnapshot.fromGatewayJson(
              Map<String, dynamic>.from(rawSnapshot),
              deviceId: id,
              zoneId: zoneId,
            ),
    );
  }

  static String _identifier(Object? value, String field) {
    if (value is! String ||
        !RegExp(r'^[a-zA-Z0-9][a-zA-Z0-9_.:-]{0,79}$').hasMatch(value)) {
      throw FormatException('Identifiant caméra $field invalide');
    }
    return value;
  }
}
