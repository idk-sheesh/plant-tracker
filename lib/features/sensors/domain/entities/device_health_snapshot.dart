class DeviceHealthSnapshot {
  final String id;
  final String deviceId;
  final DateTime observedAt;
  final bool isOnline;
  final double? batteryPercent;
  final double? batteryVoltage;
  final int? rssi;
  final double? snr;
  final int? uptimeSeconds;
  final int? freeHeapBytes;
  final int missingReadings;
  final String? firmwareVersion;
  final String? lastError;
  final DateTime createdAt;

  const DeviceHealthSnapshot({
    required this.id,
    required this.deviceId,
    required this.observedAt,
    required this.isOnline,
    this.batteryPercent,
    this.batteryVoltage,
    this.rssi,
    this.snr,
    this.uptimeSeconds,
    this.freeHeapBytes,
    this.missingReadings = 0,
    this.firmwareVersion,
    this.lastError,
    required this.createdAt,
  });

  Map<String, Object?> toMap() => {
        'id': id,
        'device_id': deviceId,
        'observed_at': observedAt.toUtc().millisecondsSinceEpoch ~/ 1000,
        'is_online': isOnline ? 1 : 0,
        'battery_percent': batteryPercent,
        'battery_voltage': batteryVoltage,
        'rssi_dbm': rssi,
        'snr_db': snr,
        'uptime_seconds': uptimeSeconds,
        'free_heap_bytes': freeHeapBytes,
        'missing_readings': missingReadings,
        'firmware_version': firmwareVersion,
        'last_error': lastError,
        'created_at': createdAt.toUtc().toIso8601String(),
      };

  factory DeviceHealthSnapshot.fromMap(Map<String, dynamic> map) {
    DateTime fromSeconds(Object? value) => DateTime.fromMillisecondsSinceEpoch(
          (value as int) * 1000,
          isUtc: true,
        ).toLocal();
    return DeviceHealthSnapshot(
      id: map['id'] as String,
      deviceId: map['device_id'] as String,
      observedAt: fromSeconds(map['observed_at']),
      isOnline: map['is_online'] == 1,
      batteryPercent: (map['battery_percent'] as num?)?.toDouble(),
      batteryVoltage: (map['battery_voltage'] as num?)?.toDouble(),
      rssi: (map['rssi_dbm'] as num?)?.toInt(),
      snr: (map['snr_db'] as num?)?.toDouble(),
      uptimeSeconds: (map['uptime_seconds'] as num?)?.toInt(),
      freeHeapBytes: (map['free_heap_bytes'] as num?)?.toInt(),
      missingReadings: (map['missing_readings'] as num?)?.toInt() ?? 0,
      firmwareVersion: map['firmware_version'] as String?,
      lastError: map['last_error'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String).toLocal(),
    );
  }
}
