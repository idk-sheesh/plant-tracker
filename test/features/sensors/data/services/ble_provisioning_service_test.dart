import 'package:flutter_test/flutter_test.dart';
import 'package:garden_journal/features/scanner/domain/qr_payload_parser.dart';
import 'package:garden_journal/features/sensors/data/services/ble_provisioning_service.dart';

void main() {
  final now = DateTime.utc(2026, 7, 19, 12);

  QrPayload identity() => QrPayloadParser.parse(
        '{"v":1,"type":"device","id":"node-01",'
        '"pairingToken":"abcdefghijklmnop",'
        '"expiresAt":"2026-07-19T12:15:00Z"}',
        now: now,
      );

  BleProvisioningRequest request() => BleProvisioningRequest(
        identity: identity(),
        wifiSsid: 'GrowNet',
        wifiPassword: 'correct-horse',
        gatewayUrl: 'http://192.168.1.10',
      );

  test('accepte uniquement identité, sécurité et jeton confirmés', () async {
    final service = BleProvisioningService(
      adapter: _FakeAdapter(
        const BleProvisioningResult(
          deviceId: 'node-01',
          bleDeviceId: 'ble-1',
          secureConnections: true,
          pairingTokenAccepted: true,
          peerAuthenticated: true,
          secretsEncrypted: true,
          baseUrl: 'http://192.168.1.42',
        ),
      ),
      clock: () => now,
    );

    final result = await service.provision(request());

    expect(result.baseUrl, 'http://192.168.1.42');
  });

  test('refuse un nœud différent, non authentifié ou sans protection',
      () async {
    for (final result in const [
      BleProvisioningResult(
        deviceId: 'node-02',
        bleDeviceId: 'ble-1',
        secureConnections: true,
        pairingTokenAccepted: true,
        peerAuthenticated: true,
        secretsEncrypted: true,
      ),
      BleProvisioningResult(
        deviceId: 'node-01',
        bleDeviceId: 'ble-1',
        secureConnections: true,
        pairingTokenAccepted: false,
        peerAuthenticated: true,
        secretsEncrypted: true,
      ),
      BleProvisioningResult(
        deviceId: 'node-01',
        bleDeviceId: 'ble-1',
        secureConnections: true,
        pairingTokenAccepted: true,
        peerAuthenticated: false,
        secretsEncrypted: true,
      ),
      BleProvisioningResult(
        deviceId: 'node-01',
        bleDeviceId: 'ble-1',
        secureConnections: true,
        pairingTokenAccepted: true,
        peerAuthenticated: true,
        secretsEncrypted: false,
      ),
    ]) {
      final service = BleProvisioningService(
        adapter: _FakeAdapter(result),
        clock: () => now,
      );
      await expectLater(
        service.provision(request()),
        throwsA(isA<BleProvisioningException>()),
      );
    }
  });

  test('valide Wi-Fi et passerelle avant toute opération BLE', () async {
    final adapter = _FakeAdapter(
      const BleProvisioningResult(
        deviceId: 'node-01',
        bleDeviceId: 'ble-1',
        secureConnections: true,
        pairingTokenAccepted: true,
        peerAuthenticated: true,
        secretsEncrypted: true,
      ),
    );
    final service = BleProvisioningService(
      adapter: adapter,
      clock: () => now,
    );

    await expectLater(
      service.provision(BleProvisioningRequest(
        identity: identity(),
        wifiSsid: '',
        wifiPassword: 'short',
      )),
      throwsA(isA<BleProvisioningException>()),
    );
    expect(adapter.calls, 0);
  });
}

class _FakeAdapter implements BleProvisioningAdapter {
  final BleProvisioningResult result;
  int calls = 0;

  _FakeAdapter(this.result);

  @override
  Future<BleProvisioningResult> provision(
    BleProvisioningRequest request,
  ) async {
    calls++;
    return result;
  }
}
