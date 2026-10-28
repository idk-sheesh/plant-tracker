class SensorDevice {
  final String id;
  final String uid;
  final String name;
  final String? zoneId;
  final String baseUrl;
  final String? firmwareVersion;
  final DateTime? lastSeenAt;
  final DateTime? lastSyncAt;
  final String? cloudDeviceId;
  final String? cloudCursor;
  final DateTime? cloudLastSyncAt;
  final String? cloudLastError;
  final DateTime? cloudLastErrorAt;
  final DateTime? cloudLastContactAt;
  final String status;
  final String deviceKind;
  final String transport;
  final String? model;
  final String? hardwareVersion;
  final String? bleDeviceId;
  final DateTime createdAt;
  final DateTime updatedAt;

  const SensorDevice({
    required this.id,
    required this.uid,
    required this.name,
    required this.zoneId,
    required this.baseUrl,
    this.firmwareVersion,
    this.lastSeenAt,
    this.lastSyncAt,
    this.cloudDeviceId,
    this.cloudCursor,
    this.cloudLastSyncAt,
    this.cloudLastError,
    this.cloudLastErrorAt,
    this.cloudLastContactAt,
    this.status = 'unknown',
    this.deviceKind = 'sensor',
    this.transport = 'http',
    this.model,
    this.hardwareVersion,
    this.bleDeviceId,
    required this.createdAt,
    required this.updatedAt,
  });

  String get ipAddress => Uri.tryParse(baseUrl)?.host ?? baseUrl;
  bool get isOnline => status == 'online';

  bool get hasCloudLink => cloudDeviceId != null && cloudDeviceId!.isNotEmpty;

  SensorDevice copyWith({
    String? id,
    String? uid,
    String? name,
    String? zoneId,
    String? baseUrl,
    String? firmwareVersion,
    DateTime? lastSeenAt,
    DateTime? lastSyncAt,
    String? cloudDeviceId,
    String? cloudCursor,
    DateTime? cloudLastSyncAt,
    String? cloudLastError,
    DateTime? cloudLastErrorAt,
    DateTime? cloudLastContactAt,
    String? status,
    String? deviceKind,
    String? transport,
    String? model,
    String? hardwareVersion,
    String? bleDeviceId,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return SensorDevice(
      id: id ?? this.id,
      uid: uid ?? this.uid,
      name: name ?? this.name,
      zoneId: zoneId ?? this.zoneId,
      baseUrl: baseUrl ?? this.baseUrl,
      firmwareVersion: firmwareVersion ?? this.firmwareVersion,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
      lastSyncAt: lastSyncAt ?? this.lastSyncAt,
      cloudDeviceId: cloudDeviceId ?? this.cloudDeviceId,
      cloudCursor: cloudCursor ?? this.cloudCursor,
      cloudLastSyncAt: cloudLastSyncAt ?? this.cloudLastSyncAt,
      cloudLastError: cloudLastError ?? this.cloudLastError,
      cloudLastErrorAt: cloudLastErrorAt ?? this.cloudLastErrorAt,
      cloudLastContactAt: cloudLastContactAt ?? this.cloudLastContactAt,
      status: status ?? this.status,
      deviceKind: deviceKind ?? this.deviceKind,
      transport: transport ?? this.transport,
      model: model ?? this.model,
      hardwareVersion: hardwareVersion ?? this.hardwareVersion,
      bleDeviceId: bleDeviceId ?? this.bleDeviceId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'uid': uid,
        'name': name,
        'zone_id': zoneId,
        'base_url': baseUrl,
        'firmware_version': firmwareVersion,
        'last_seen_at': _seconds(lastSeenAt),
        'last_sync_at': _seconds(lastSyncAt),
        'cloud_device_id': cloudDeviceId,
        'cloud_cursor': cloudCursor,
        'cloud_last_sync_at': _seconds(cloudLastSyncAt),
        'cloud_last_error': cloudLastError,
        'cloud_last_error_at': _seconds(cloudLastErrorAt),
        'cloud_last_contact_at': _seconds(cloudLastContactAt),
        'status': status,
        'device_kind': deviceKind,
        'transport': transport,
        'model': model,
        'hardware_version': hardwareVersion,
        'ble_device_id': bleDeviceId,
        'created_at': createdAt.toUtc().toIso8601String(),
        'updated_at': updatedAt.toUtc().toIso8601String(),
      };

  static int? _seconds(DateTime? value) =>
      value?.toUtc().millisecondsSinceEpoch == null
          ? null
          : value!.toUtc().millisecondsSinceEpoch ~/ 1000;

  static DateTime? _date(Object? seconds) => seconds == null
      ? null
      : DateTime.fromMillisecondsSinceEpoch(
          (seconds as int) * 1000,
          isUtc: true,
        ).toLocal();

  factory SensorDevice.fromMap(Map<String, dynamic> map) {
    final now = DateTime.now();
    return SensorDevice(
      id: map['id'] as String,
      uid: map['uid'] as String? ?? map['id'] as String,
      name: map['name'] as String,
      zoneId: map['zone_id'] as String?,
      baseUrl: map['base_url'] as String? ??
          'http://${map['ip_address'] as String? ?? '127.0.0.1'}',
      firmwareVersion: map['firmware_version'] as String?,
      lastSeenAt: _date(map['last_seen_at']),
      lastSyncAt: _date(map['last_sync_at']),
      cloudDeviceId: map['cloud_device_id'] as String?,
      cloudCursor: map['cloud_cursor'] as String?,
      cloudLastSyncAt: _date(map['cloud_last_sync_at']),
      cloudLastError: map['cloud_last_error'] as String?,
      cloudLastErrorAt: _date(map['cloud_last_error_at']),
      cloudLastContactAt: _date(map['cloud_last_contact_at']),
      status: map['status'] as String? ?? 'unknown',
      deviceKind: map['device_kind'] as String? ?? 'sensor',
      transport: map['transport'] as String? ?? 'http',
      model: map['model'] as String?,
      hardwareVersion: map['hardware_version'] as String?,
      bleDeviceId: map['ble_device_id'] as String?,
      createdAt: map['created_at'] == null
          ? now
          : DateTime.parse(map['created_at'] as String).toLocal(),
      updatedAt: map['updated_at'] == null
          ? now
          : DateTime.parse(map['updated_at'] as String).toLocal(),
    );
  }
}
