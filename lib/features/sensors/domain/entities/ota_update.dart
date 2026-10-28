import 'dart:convert';

class OtaManifest {
  final String manifestId;
  final String deviceModel;
  final String version;
  final int buildNumber;
  final Uri firmwareUri;
  final int sizeBytes;
  final String firmwareSha256;
  final String keyId;
  final DateTime issuedAt;
  final DateTime expiresAt;
  final String? minimumBootloader;
  final String signatureBase64;
  final Map<String, dynamic> canonicalFields;
  final Map<String, dynamic> completeJson;

  const OtaManifest({
    required this.manifestId,
    required this.deviceModel,
    required this.version,
    required this.buildNumber,
    required this.firmwareUri,
    required this.sizeBytes,
    required this.firmwareSha256,
    required this.keyId,
    required this.issuedAt,
    required this.expiresAt,
    this.minimumBootloader,
    required this.signatureBase64,
    required this.canonicalFields,
    required this.completeJson,
  });

  factory OtaManifest.parse(Object? raw, {DateTime? now}) {
    if (raw is! Map) throw const FormatException('Manifest OTA invalide');
    final json = Map<String, dynamic>.from(raw);
    if (json['schemaVersion'] != 1 || json.keys.length > 20) {
      throw const FormatException('Version de manifest OTA incompatible');
    }
    final manifestId = _identifier(json['manifestId'], 'manifestId');
    final deviceModel = _text(json['deviceModel'], 'deviceModel', 80);
    final version = _text(json['version'], 'version', 40);
    if (!RegExp(r'^[0-9]+\.[0-9]+\.[0-9]+(?:[-+][A-Za-z0-9.-]+)?$')
        .hasMatch(version)) {
      throw const FormatException('Version firmware invalide');
    }
    final build = json['buildNumber'];
    final size = json['sizeBytes'];
    if (build is! int || build < 1 || build > 0x7fffffff) {
      throw const FormatException('Build OTA invalide');
    }
    if (size is! int || size < 1 || size > 32 * 1024 * 1024) {
      throw const FormatException('Taille firmware invalide');
    }
    final uri = Uri.tryParse(_text(json['firmwareUrl'], 'firmwareUrl', 2048));
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment) {
      throw const FormatException('URL firmware HTTPS invalide');
    }
    final firmwareSha = _text(json['sha256'], 'sha256', 64).toLowerCase();
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(firmwareSha)) {
      throw const FormatException('SHA-256 firmware invalide');
    }
    final issuedAt = _date(json['issuedAt'], 'issuedAt');
    final expiresAt = _date(json['expiresAt'], 'expiresAt');
    final reference = (now ?? DateTime.now()).toUtc();
    if (issuedAt.isAfter(reference.add(const Duration(minutes: 5))) ||
        expiresAt.isBefore(reference) ||
        !expiresAt.isAfter(issuedAt) ||
        expiresAt.difference(issuedAt) > const Duration(days: 30)) {
      throw const FormatException('Fenêtre de validité OTA invalide');
    }
    final keyId = _identifier(json['keyId'], 'keyId');
    final signature = _text(json['signature'], 'signature', 256);
    final bootloader = json['minimumBootloader'] == null
        ? null
        : _text(json['minimumBootloader'], 'minimumBootloader', 40);
    final canonical = Map<String, dynamic>.from(json)..remove('signature');
    return OtaManifest(
      manifestId: manifestId,
      deviceModel: deviceModel,
      version: version,
      buildNumber: build,
      firmwareUri: uri,
      sizeBytes: size,
      firmwareSha256: firmwareSha,
      keyId: keyId,
      issuedAt: issuedAt.toLocal(),
      expiresAt: expiresAt.toLocal(),
      minimumBootloader: bootloader,
      signatureBase64: signature,
      canonicalFields: Map.unmodifiable(canonical),
      completeJson: Map.unmodifiable(json),
    );
  }

  List<int> signedBytes() => utf8.encode(canonicalJson(canonicalFields));
}

class OtaTrustedKey {
  final String keyId;
  final String publicKeyBase64;
  final DateTime validFrom;
  final DateTime? revokedAt;

  const OtaTrustedKey({
    required this.keyId,
    required this.publicKeyBase64,
    required this.validFrom,
    this.revokedAt,
  });

  bool isValidAt(DateTime value) =>
      !value.isBefore(validFrom) &&
      (revokedAt == null || value.isBefore(revokedAt!));

  Map<String, Object?> toMap() => {
        'key_id': keyId,
        'algorithm': 'ed25519',
        'public_key_base64': publicKeyBase64,
        'valid_from': validFrom.toUtc().millisecondsSinceEpoch ~/ 1000,
        'revoked_at': revokedAt?.toUtc().millisecondsSinceEpoch == null
            ? null
            : revokedAt!.toUtc().millisecondsSinceEpoch ~/ 1000,
        'source': 'app_build',
        'created_at': DateTime.now().toUtc().toIso8601String(),
      };

  factory OtaTrustedKey.fromMap(Map<String, dynamic> map) => OtaTrustedKey(
        keyId: map['key_id'] as String,
        publicKeyBase64: map['public_key_base64'] as String,
        validFrom: _secondsDate(map['valid_from'])!,
        revokedAt: _secondsDate(map['revoked_at']),
      );
}

class OtaDeviceState {
  final String deviceId;
  final String? currentVersion;
  final int currentBuild;
  final int highestAcceptedBuild;
  final int lastKnownGoodBuild;
  final String? hardwareModel;
  final String? bootloaderVersion;
  final bool rollbackSupported;
  final DateTime? lastUpdateAt;
  final DateTime updatedAt;

  const OtaDeviceState({
    required this.deviceId,
    this.currentVersion,
    required this.currentBuild,
    required this.highestAcceptedBuild,
    required this.lastKnownGoodBuild,
    this.hardwareModel,
    this.bootloaderVersion,
    required this.rollbackSupported,
    this.lastUpdateAt,
    required this.updatedAt,
  });

  Map<String, Object?> toMap() => {
        'device_id': deviceId,
        'current_version': currentVersion,
        'current_build': currentBuild,
        'highest_accepted_build': highestAcceptedBuild,
        'last_known_good_build': lastKnownGoodBuild,
        'hardware_model': hardwareModel,
        'bootloader_version': bootloaderVersion,
        'rollback_supported': rollbackSupported ? 1 : 0,
        'last_update_at': lastUpdateAt == null
            ? null
            : lastUpdateAt!.toUtc().millisecondsSinceEpoch ~/ 1000,
        'updated_at': updatedAt.toUtc().toIso8601String(),
      };

  factory OtaDeviceState.fromMap(Map<String, dynamic> map) => OtaDeviceState(
        deviceId: map['device_id'] as String,
        currentVersion: map['current_version'] as String?,
        currentBuild: map['current_build'] as int? ?? 0,
        highestAcceptedBuild: map['highest_accepted_build'] as int? ?? 0,
        lastKnownGoodBuild: map['last_known_good_build'] as int? ?? 0,
        hardwareModel: map['hardware_model'] as String?,
        bootloaderVersion: map['bootloader_version'] as String?,
        rollbackSupported: map['rollback_supported'] == 1,
        lastUpdateAt: _secondsDate(map['last_update_at']),
        updatedAt: DateTime.parse(map['updated_at'] as String).toLocal(),
      );
}

class OtaUpdateRecord {
  final String id;
  final String deviceId;
  final String manifestId;
  final String version;
  final int buildNumber;
  final String firmwareUrl;
  final int sizeBytes;
  final String firmwareSha256;
  final String signatureBase64;
  final String keyId;
  final String status;
  final DateTime? verifiedAt;
  final DateTime? requestedAt;
  final DateTime? nodeAckAt;
  final String? errorCode;
  final String manifestJson;
  final DateTime createdAt;
  final DateTime updatedAt;

  const OtaUpdateRecord({
    required this.id,
    required this.deviceId,
    required this.manifestId,
    required this.version,
    required this.buildNumber,
    required this.firmwareUrl,
    required this.sizeBytes,
    required this.firmwareSha256,
    required this.signatureBase64,
    required this.keyId,
    required this.status,
    this.verifiedAt,
    this.requestedAt,
    this.nodeAckAt,
    this.errorCode,
    required this.manifestJson,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, Object?> toMap() => {
        'id': id,
        'device_id': deviceId,
        'manifest_id': manifestId,
        'version': version,
        'build_number': buildNumber,
        'firmware_url': firmwareUrl,
        'size_bytes': sizeBytes,
        'firmware_sha256': firmwareSha256,
        'signature_base64': signatureBase64,
        'key_id': keyId,
        'status': status,
        'verified_at': _optionalSeconds(verifiedAt),
        'requested_at': _optionalSeconds(requestedAt),
        'node_ack_at': _optionalSeconds(nodeAckAt),
        'error_code': errorCode,
        'manifest_json': manifestJson,
        'created_at': createdAt.toUtc().toIso8601String(),
        'updated_at': updatedAt.toUtc().toIso8601String(),
      };

  factory OtaUpdateRecord.fromMap(Map<String, dynamic> map) => OtaUpdateRecord(
        id: map['id'] as String,
        deviceId: map['device_id'] as String,
        manifestId: map['manifest_id'] as String,
        version: map['version'] as String,
        buildNumber: map['build_number'] as int,
        firmwareUrl: map['firmware_url'] as String,
        sizeBytes: map['size_bytes'] as int,
        firmwareSha256: map['firmware_sha256'] as String,
        signatureBase64: map['signature_base64'] as String,
        keyId: map['key_id'] as String,
        status: map['status'] as String,
        verifiedAt: _secondsDate(map['verified_at']),
        requestedAt: _secondsDate(map['requested_at']),
        nodeAckAt: _secondsDate(map['node_ack_at']),
        errorCode: map['error_code'] as String?,
        manifestJson: map['manifest_json'] as String,
        createdAt: DateTime.parse(map['created_at'] as String).toLocal(),
        updatedAt: DateTime.parse(map['updated_at'] as String).toLocal(),
      );
}

String canonicalJson(Object? value) {
  Object? normalize(Object? input) {
    if (input is Map) {
      final keys = input.keys.map((key) => key.toString()).toList()..sort();
      return {for (final key in keys) key: normalize(input[key])};
    }
    if (input is List) return input.map(normalize).toList();
    return input;
  }

  return jsonEncode(normalize(value));
}

String _identifier(Object? value, String field) {
  final text = _text(value, field, 128);
  if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9_.:-]{0,127}$').hasMatch(text)) {
    throw FormatException('$field invalide');
  }
  return text;
}

String _text(Object? value, String field, int max) {
  if (value is! String || value.trim().isEmpty || value.length > max) {
    throw FormatException('$field invalide');
  }
  return value.trim();
}

DateTime _date(Object? value, String field) {
  if (value is! String) throw FormatException('$field invalide');
  final date = DateTime.tryParse(value)?.toUtc();
  if (date == null) throw FormatException('$field invalide');
  return date;
}

int? _optionalSeconds(DateTime? value) =>
    value?.toUtc().millisecondsSinceEpoch == null
        ? null
        : value!.toUtc().millisecondsSinceEpoch ~/ 1000;

DateTime? _secondsDate(Object? value) => value == null
    ? null
    : DateTime.fromMillisecondsSinceEpoch(
        (value as int) * 1000,
        isUtc: true,
      ).toLocal();
