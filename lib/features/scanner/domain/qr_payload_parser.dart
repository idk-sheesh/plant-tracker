import 'dart:convert';

enum QrEntityType { plant, device, gateway }

class QrPayload {
  final QrEntityType entityType;
  final String entityId;
  final String? model;
  final String? pairingToken;
  final DateTime? pairingExpiresAt;
  final String? bleServiceUuid;
  final String? transport;
  final Map<String, String>? legacyProfile;

  const QrPayload({
    this.entityType = QrEntityType.plant,
    required this.entityId,
    this.model,
    this.pairingToken,
    this.pairingExpiresAt,
    this.bleServiceUuid,
    this.transport,
    this.legacyProfile,
  });

  String get plantId => entityId;
  String get deviceId => entityId;
  bool get isLegacyProfile => legacyProfile != null;
  bool get canProvision =>
      entityType != QrEntityType.plant && pairingToken != null;
}

class QrPayloadParser {
  QrPayloadParser._();

  static const maxPayloadLength = 4096;
  static const maxIdLength = 128;
  static final _idPattern = RegExp(r'^[A-Za-z0-9_-]+$');
  static final _tokenPattern = RegExp(r'^[A-Za-z0-9_-]{16,128}$');
  static final _uuidPattern = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
    r'[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  static QrPayload parse(String raw, {DateTime? now}) {
    final input = raw.trim();
    if (input.isEmpty) throw const FormatException('QR vide');
    if (input.length > maxPayloadLength) {
      throw const FormatException('QR trop volumineux');
    }

    for (final type in QrEntityType.values) {
      final prefix = '${type.name}:';
      if (input.startsWith(prefix)) {
        return QrPayload(
          entityType: type,
          entityId: _validateId(input.substring(prefix.length)),
        );
      }
    }

    final decoded = jsonDecode(input);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Objet QR attendu');
    }
    _rejectCredentials(decoded);
    if (decoded['type'] == null) return _parseLegacyPlant(decoded);
    if (decoded['v'] != 1) {
      throw const FormatException('Version QR appareil incompatible');
    }
    final entityType = switch (decoded['type']) {
      'device' => QrEntityType.device,
      'gateway' => QrEntityType.gateway,
      'plant' => QrEntityType.plant,
      _ => throw const FormatException('Type QR inconnu'),
    };
    final pairingToken = _optionalToken(decoded['pairingToken']);
    final expiresAt = _optionalExpiry(
      decoded['expiresAt'],
      now: now ?? DateTime.now(),
    );
    if ((pairingToken == null) != (expiresAt == null)) {
      throw const FormatException(
        'Jeton et expiration d’association doivent être fournis ensemble',
      );
    }
    final serviceUuid = _optionalText(
      decoded['serviceUuid'],
      maximumLength: 36,
    );
    if (serviceUuid != null && !_uuidPattern.hasMatch(serviceUuid)) {
      throw const FormatException('UUID BLE invalide');
    }
    final transport = _optionalText(decoded['transport'], maximumLength: 16);
    if (transport != null &&
        !const {'ble', 'http', 'lora'}.contains(transport)) {
      throw const FormatException('Transport appareil invalide');
    }
    return QrPayload(
      entityType: entityType,
      entityId: _validateId(decoded['id']),
      model: _optionalText(decoded['model'], maximumLength: 80),
      pairingToken: pairingToken,
      pairingExpiresAt: expiresAt,
      bleServiceUuid: serviceUuid?.toLowerCase(),
      transport: transport,
    );
  }

  static QrPayload _parseLegacyPlant(Map<String, dynamic> decoded) {
    return QrPayload(
      entityId: _validateId(decoded['id']),
      legacyProfile: {
        'name': _optionalText(decoded['n'], fallback: 'Plante')!,
        'variety': _optionalText(decoded['v']) ?? '',
        'culture': _optionalText(decoded['c'], fallback: '-')!,
        'pottingDate': _optionalText(decoded['d'], fallback: '-')!,
        'pot': _optionalText(decoded['p']) ?? '',
      },
    );
  }

  static void _rejectCredentials(Map<String, dynamic> decoded) {
    const forbidden = {
      'password',
      'wifiPassword',
      'wifi_password',
      'passphrase',
      'mqttPassword',
      'mqtt_password',
      'psk',
      'secret',
    };
    if (decoded.keys.any(forbidden.contains)) {
      throw const FormatException('Le QR ne doit contenir aucun identifiant');
    }
  }

  static String _validateId(Object? value) {
    if (value is! String) throw const FormatException('Identifiant absent');
    final id = value.trim();
    if (id.isEmpty || id.length > maxIdLength || !_idPattern.hasMatch(id)) {
      throw const FormatException('Identifiant invalide');
    }
    return id;
  }

  static String? _optionalToken(Object? value) {
    final token = _optionalText(value, maximumLength: 128);
    if (token != null && !_tokenPattern.hasMatch(token)) {
      throw const FormatException('Jeton d’association invalide');
    }
    return token;
  }

  static DateTime? _optionalExpiry(Object? value, {required DateTime now}) {
    if (value == null) return null;
    if (value is! String || value.length > 80) {
      throw const FormatException('Expiration d’association invalide');
    }
    final expiry = DateTime.tryParse(value)?.toUtc();
    if (expiry == null ||
        !expiry.isAfter(now.toUtc()) ||
        expiry.isAfter(now.toUtc().add(const Duration(hours: 24)))) {
      throw const FormatException('Jeton d’association expiré ou trop long');
    }
    return expiry;
  }

  static String? _optionalText(
    Object? value, {
    String? fallback,
    int maximumLength = 200,
  }) {
    if (value == null) return fallback;
    if (value is! String) throw const FormatException('Champ texte invalide');
    final text = value.trim();
    if (text.length > maximumLength) {
      throw const FormatException('Champ texte trop long');
    }
    return text.isEmpty ? fallback : text;
  }
}
