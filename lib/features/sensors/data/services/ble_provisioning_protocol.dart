import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart' as cryptography;

class BleProvisioningSession {
  final String deviceId;
  final String authNonce;
  final String _pairingToken;

  const BleProvisioningSession._({
    required this.deviceId,
    required this.authNonce,
    required String pairingToken,
  }) : _pairingToken = pairingToken;

  Map<String, Object?> get authenticationRequest => {
        'v': 2,
        'op': 'authenticate',
        'deviceId': deviceId,
        'nonce': authNonce,
      };
}

/// Protocole applicatif BLE v2.
///
/// Le jeton temporaire reste dans le QR et dans le nœud. Il n'est jamais
/// transmis par BLE : il authentifie un défi frais, puis dérive une clé dédiée
/// au chiffrement AES-GCM de la configuration sensible.
class BleProvisioningProtocol {
  static const version = 2;
  static const _authDomain = 'gardenjournal-ble-auth-v2';
  static const _configDomain = 'gardenjournal-ble-config-v2';
  static const _ackDomain = 'gardenjournal-ble-ack-v2';

  final Random _random;
  final cryptography.Cipher _cipher;

  BleProvisioningProtocol({Random? random, cryptography.Cipher? cipher})
      : _random = random ?? Random.secure(),
        _cipher = cipher ?? cryptography.AesGcm.with256bits();

  BleProvisioningSession start({
    required String deviceId,
    required String pairingToken,
  }) {
    return BleProvisioningSession._(
      deviceId: deviceId,
      authNonce: _base64(_randomBytes(32)),
      pairingToken: pairingToken,
    );
  }

  void verifyAuthentication(
    BleProvisioningSession session,
    Map<String, dynamic> response,
  ) {
    final proof = response['proof'];
    if (response['v'] != version ||
        response['op'] != 'authenticated' ||
        response['deviceId'] != session.deviceId ||
        response['nonce'] != session.authNonce ||
        proof is! String ||
        !RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(proof)) {
      throw const BleProtocolException(
        'Preuve d’identité BLE absente ou invalide',
      );
    }
    final expected = authenticationProof(
      pairingToken: session._pairingToken,
      deviceId: session.deviceId,
      nonce: session.authNonce,
    );
    if (!_constantTimeEquals(expected, proof.toLowerCase())) {
      throw const BleProtocolException('Périphérique BLE non authentifié');
    }
  }

  Future<Map<String, Object?>> encryptConfiguration(
    BleProvisioningSession session,
    Map<String, Object?> configuration,
  ) async {
    final nonce = _randomBytes(12);
    final aad = _configurationAad(session);
    final key = _derivedKey(session);
    final box = await _cipher.encrypt(
      utf8.encode(jsonEncode(configuration)),
      secretKey: cryptography.SecretKey(key),
      nonce: nonce,
      aad: aad,
    );
    return {
      'v': version,
      'op': 'provision',
      'deviceId': session.deviceId,
      'authNonce': session.authNonce,
      'nonce': _base64(box.nonce),
      'ciphertext': _base64(box.cipherText),
      'mac': _base64(box.mac.bytes),
    };
  }

  void verifyAcknowledgement(
    BleProvisioningSession session,
    Map<String, dynamic> response,
  ) {
    final baseUrl = _boundedOptionalText(response['baseUrl'], 2048);
    final firmwareVersion = _boundedOptionalText(
      response['firmwareVersion'],
      80,
    );
    final proof = response['proof'];
    if (response['v'] != version ||
        response['op'] != 'provisioned' ||
        response['deviceId'] != session.deviceId ||
        response['authNonce'] != session.authNonce ||
        response['ok'] != true ||
        proof is! String ||
        !RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(proof)) {
      throw const BleProtocolException('Accusé BLE invalide');
    }
    final expected = acknowledgementProof(
      pairingToken: session._pairingToken,
      deviceId: session.deviceId,
      authNonce: session.authNonce,
      baseUrl: baseUrl,
      firmwareVersion: firmwareVersion,
    );
    if (!_constantTimeEquals(expected, proof.toLowerCase())) {
      throw const BleProtocolException('Accusé BLE non authentifié');
    }
  }

  static String authenticationProof({
    required String pairingToken,
    required String deviceId,
    required String nonce,
  }) {
    return _hmac(
      pairingToken,
      '$_authDomain\n$deviceId\n$nonce',
    );
  }

  static String acknowledgementProof({
    required String pairingToken,
    required String deviceId,
    required String authNonce,
    String? baseUrl,
    String? firmwareVersion,
  }) {
    return _hmac(
      pairingToken,
      '$_ackDomain\n$deviceId\n$authNonce\n1\n${baseUrl ?? ''}\n'
      '${firmwareVersion ?? ''}',
    );
  }

  List<int> _derivedKey(BleProvisioningSession session) => Hmac(
        sha256,
        utf8.encode(session._pairingToken),
      )
          .convert(utf8.encode(
            '$_configDomain\n${session.deviceId}\n${session.authNonce}',
          ))
          .bytes;

  List<int> _configurationAad(BleProvisioningSession session) => utf8.encode(
        '$_configDomain\n${session.deviceId}\n${session.authNonce}',
      );

  List<int> _randomBytes(int length) =>
      List<int>.generate(length, (_) => _random.nextInt(256));

  static String _hmac(String key, String value) =>
      Hmac(sha256, utf8.encode(key)).convert(utf8.encode(value)).toString();

  static bool _constantTimeEquals(String expected, String actual) {
    if (expected.length != actual.length) return false;
    var difference = 0;
    for (var index = 0; index < expected.length; index++) {
      difference |= expected.codeUnitAt(index) ^ actual.codeUnitAt(index);
    }
    return difference == 0;
  }

  static String _base64(List<int> value) =>
      base64UrlEncode(value).replaceAll('=', '');

  static String? _boundedOptionalText(Object? value, int maximumLength) {
    if (value == null) return null;
    if (value is! String || value.length > maximumLength) {
      throw const BleProtocolException('Accusé BLE invalide');
    }
    return value;
  }
}

class BleProtocolException implements Exception {
  final String message;

  const BleProtocolException(this.message);

  @override
  String toString() => message;
}
