import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:garden_journal/features/sensors/data/services/ble_provisioning_protocol.dart';

void main() {
  const token = 'abcdefghijklmnop';

  test('authentifie une réponse liée au défi frais de l’application', () {
    final protocol = BleProvisioningProtocol(random: Random(7));
    final session = protocol.start(deviceId: 'node-01', pairingToken: token);
    final proof = BleProvisioningProtocol.authenticationProof(
      pairingToken: token,
      deviceId: session.deviceId,
      nonce: session.authNonce,
    );

    protocol.verifyAuthentication(session, {
      'v': 2,
      'op': 'authenticated',
      'deviceId': 'node-01',
      'nonce': session.authNonce,
      'proof': proof,
    });
  });

  test('refuse un périphérique imposteur avant de préparer les secrets', () {
    final protocol = BleProvisioningProtocol(random: Random(8));
    final session = protocol.start(deviceId: 'node-01', pairingToken: token);

    expect(
      () => protocol.verifyAuthentication(session, {
        'v': 2,
        'op': 'authenticated',
        'deviceId': 'node-01',
        'nonce': session.authNonce,
        'proof': List.filled(64, '0').join(),
      }),
      throwsA(isA<BleProtocolException>()),
    );
  });

  test('ne place aucun secret en clair dans l’enveloppe de provisioning',
      () async {
    final protocol = BleProvisioningProtocol(random: Random(9));
    final session = protocol.start(deviceId: 'node-01', pairingToken: token);

    final envelope = await protocol.encryptConfiguration(session, {
      'wifi': {'ssid': 'GrowNet', 'password': 'correct-horse'},
      'gatewayUrl': 'http://192.168.1.10',
    });
    final encoded = jsonEncode(envelope);

    expect(encoded, isNot(contains('GrowNet')));
    expect(encoded, isNot(contains('correct-horse')));
    expect(encoded, isNot(contains(token)));
    expect(envelope['op'], 'provision');
    expect(envelope['ciphertext'], isNotEmpty);
    expect(envelope['mac'], isNotEmpty);
  });

  test('vérifie cryptographiquement l’accusé final', () {
    final protocol = BleProvisioningProtocol(random: Random(10));
    final session = protocol.start(deviceId: 'node-01', pairingToken: token);
    final proof = BleProvisioningProtocol.acknowledgementProof(
      pairingToken: token,
      deviceId: 'node-01',
      authNonce: session.authNonce,
      baseUrl: 'http://192.168.1.42',
      firmwareVersion: '2.0.0',
    );

    protocol.verifyAcknowledgement(session, {
      'v': 2,
      'op': 'provisioned',
      'deviceId': 'node-01',
      'authNonce': session.authNonce,
      'ok': true,
      'baseUrl': 'http://192.168.1.42',
      'firmwareVersion': '2.0.0',
      'proof': proof,
    });
  });
}
