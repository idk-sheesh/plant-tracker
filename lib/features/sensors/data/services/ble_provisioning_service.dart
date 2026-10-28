import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../scanner/domain/qr_payload_parser.dart';
import 'ble_provisioning_protocol.dart';

class BleProvisioningRequest {
  final QrPayload identity;
  final String wifiSsid;
  final String wifiPassword;
  final String? gatewayUrl;

  const BleProvisioningRequest({
    required this.identity,
    required this.wifiSsid,
    required this.wifiPassword,
    this.gatewayUrl,
  });

  Map<String, Object?> toSensitiveConfiguration() => {
        'wifi': {'ssid': wifiSsid, 'password': wifiPassword},
        if (gatewayUrl != null) 'gatewayUrl': gatewayUrl,
      };
}

class BleProvisioningResult {
  final String deviceId;
  final String bleDeviceId;
  final bool secureConnections;
  final bool pairingTokenAccepted;
  final bool peerAuthenticated;
  final bool secretsEncrypted;
  final String? baseUrl;
  final String? firmwareVersion;

  const BleProvisioningResult({
    required this.deviceId,
    required this.bleDeviceId,
    required this.secureConnections,
    required this.pairingTokenAccepted,
    required this.peerAuthenticated,
    required this.secretsEncrypted,
    this.baseUrl,
    this.firmwareVersion,
  });
}

abstract class BleProvisioningAdapter {
  Future<BleProvisioningResult> provision(BleProvisioningRequest request);
}

class BleProvisioningService {
  final BleProvisioningAdapter _adapter;
  final DateTime Function() _clock;

  BleProvisioningService({
    BleProvisioningAdapter? adapter,
    DateTime Function()? clock,
  })  : _adapter = adapter ?? ReactiveBleProvisioningAdapter(),
        _clock = clock ?? DateTime.now;

  Future<BleProvisioningResult> provision(
    BleProvisioningRequest request,
  ) async {
    final identity = request.identity;
    if (identity.entityType == QrEntityType.plant || !identity.canProvision) {
      throw const BleProvisioningException(
        'QR appareil avec jeton temporaire requis',
      );
    }
    if (!identity.pairingExpiresAt!.isAfter(_clock().toUtc())) {
      throw const BleProvisioningException('Jeton d’association expiré');
    }
    final ssid = request.wifiSsid.trim();
    if (ssid.isEmpty || ssid.length > 32) {
      throw const BleProvisioningException('SSID Wi-Fi invalide');
    }
    if (request.wifiPassword.length < 8 || request.wifiPassword.length > 63) {
      throw const BleProvisioningException('Mot de passe Wi-Fi invalide');
    }
    if (request.gatewayUrl case final gatewayUrl?) {
      final uri = Uri.tryParse(gatewayUrl.trim());
      if (uri == null ||
          !{'http', 'https'}.contains(uri.scheme) ||
          uri.host.isEmpty ||
          uri.userInfo.isNotEmpty ||
          uri.hasFragment) {
        throw const BleProvisioningException('Adresse de passerelle invalide');
      }
    }

    final result = await _adapter.provision(request);
    if (result.deviceId != identity.deviceId) {
      throw const BleProvisioningException(
        'Identité BLE différente du QR scanné',
      );
    }
    if (!result.peerAuthenticated) {
      throw const BleProvisioningException(
        'Identité cryptographique du nœud BLE non vérifiée',
      );
    }
    if (!result.secretsEncrypted || !result.pairingTokenAccepted) {
      throw const BleProvisioningException(
        'Configuration BLE non protégée ou non confirmée',
      );
    }
    return result;
  }
}

class ReactiveBleProvisioningAdapter implements BleProvisioningAdapter {
  static const defaultServiceUuid = '7f510001-1b15-4f0d-9a63-8c2f6a000001';
  static const identityCharacteristicUuid =
      '7f510002-1b15-4f0d-9a63-8c2f6a000001';
  static const configCharacteristicUuid =
      '7f510003-1b15-4f0d-9a63-8c2f6a000001';
  static const responseCharacteristicUuid =
      '7f510004-1b15-4f0d-9a63-8c2f6a000001';

  final FlutterReactiveBle _ble;
  final BleProvisioningProtocol _protocol;

  ReactiveBleProvisioningAdapter({
    FlutterReactiveBle? ble,
    BleProvisioningProtocol? protocol,
  })  : _ble = ble ?? FlutterReactiveBle(),
        _protocol = protocol ?? BleProvisioningProtocol();

  @override
  Future<BleProvisioningResult> provision(
    BleProvisioningRequest request,
  ) async {
    await _requestPermissions();
    if (_ble.status != BleStatus.ready) {
      try {
        await _ble.statusStream
            .firstWhere((status) => status == BleStatus.ready)
            .timeout(const Duration(seconds: 10));
      } on TimeoutException {
        throw const BleProvisioningException('Bluetooth indisponible');
      }
    }

    final service = Uuid.parse(
      request.identity.bleServiceUuid ?? defaultServiceUuid,
    );
    late final DiscoveredDevice discovered;
    try {
      discovered = await _ble
          .scanForDevices(
            withServices: [service],
            scanMode: ScanMode.lowLatency,
          )
          .firstWhere(
            (device) =>
                device.name.contains(request.identity.deviceId) ||
                device.name.contains(request.identity.model ?? '\u0000'),
          )
          .timeout(const Duration(seconds: 12));
    } on TimeoutException {
      throw const BleProvisioningException(
        'Nœud BLE correspondant au QR introuvable',
      );
    }

    StreamSubscription<ConnectionStateUpdate>? connection;
    try {
      final connected = Completer<void>();
      connection = _ble
          .connectToAdvertisingDevice(
        id: discovered.id,
        withServices: [service],
        prescanDuration: const Duration(seconds: 3),
        servicesWithCharacteristicsToDiscover: {
          service: [
            Uuid.parse(identityCharacteristicUuid),
            Uuid.parse(configCharacteristicUuid),
            Uuid.parse(responseCharacteristicUuid),
          ],
        },
        connectionTimeout: const Duration(seconds: 8),
      )
          .listen(
        (update) {
          if (update.connectionState == DeviceConnectionState.connected &&
              !connected.isCompleted) {
            connected.complete();
          }
          if (update.connectionState == DeviceConnectionState.disconnected &&
              !connected.isCompleted) {
            connected.completeError(
              const BleProvisioningException('Connexion BLE interrompue'),
            );
          }
        },
        onError: (Object error, StackTrace stackTrace) {
          if (!connected.isCompleted) {
            connected.completeError(
              const BleProvisioningException('Connexion BLE impossible'),
              stackTrace,
            );
          }
        },
      );
      await connected.future.timeout(const Duration(seconds: 12));
      await _ble.requestMtu(deviceId: discovered.id, mtu: 247);

      QualifiedCharacteristic characteristic(String uuid) =>
          QualifiedCharacteristic(
            serviceId: service,
            characteristicId: Uuid.parse(uuid),
            deviceId: discovered.id,
          );
      final identityBytes = await _ble.readCharacteristic(
        characteristic(identityCharacteristicUuid),
      );
      final identity = _decodeObject(identityBytes, 'identité BLE');
      final deviceId = identity['deviceId'];
      final secureConnections = identity['secureConnections'];
      final protocolVersion = identity['protocolVersion'] ?? identity['v'];
      if (deviceId is! String || secureConnections is! bool) {
        throw const BleProvisioningException('Identité BLE invalide');
      }
      if (deviceId != request.identity.deviceId) {
        throw const BleProvisioningException(
          'Identité BLE différente du QR scanné',
        );
      }
      if (protocolVersion != BleProvisioningProtocol.version) {
        throw const BleProvisioningException(
          'Firmware BLE incompatible : protocole sécurisé v2 requis',
        );
      }

      final session = _protocol.start(
        deviceId: deviceId,
        pairingToken: request.identity.pairingToken!,
      );
      final authPayload =
          utf8.encode(jsonEncode(session.authenticationRequest));
      await _ble.writeCharacteristicWithResponse(
        characteristic(configCharacteristicUuid),
        value: authPayload,
      );
      final authResponse = _decodeObject(
        await _ble.readCharacteristic(
          characteristic(responseCharacteristicUuid),
        ),
        'preuve d’identité BLE',
      );
      try {
        _protocol.verifyAuthentication(session, authResponse);
      } on BleProtocolException catch (error) {
        throw BleProvisioningException(error.message);
      }

      final encrypted = await _protocol.encryptConfiguration(
        session,
        request.toSensitiveConfiguration(),
      );
      final payload = utf8.encode(jsonEncode(encrypted));
      if (payload.length > 4096) {
        throw const BleProvisioningException(
          'Configuration BLE trop volumineuse',
        );
      }
      await _ble.writeCharacteristicWithResponse(
        characteristic(configCharacteristicUuid),
        value: payload,
      );
      final responseBytes = await _ble.readCharacteristic(
        characteristic(responseCharacteristicUuid),
      );
      final response = _decodeObject(responseBytes, 'réponse BLE');
      try {
        _protocol.verifyAcknowledgement(session, response);
      } on BleProtocolException catch (error) {
        throw BleProvisioningException(error.message);
      }
      return BleProvisioningResult(
        deviceId: deviceId,
        bleDeviceId: discovered.id,
        secureConnections: secureConnections,
        pairingTokenAccepted: true,
        peerAuthenticated: true,
        secretsEncrypted: true,
        baseUrl: response['baseUrl'] as String?,
        firmwareVersion: response['firmwareVersion'] as String?,
      );
    } on BleProvisioningException {
      rethrow;
    } on TimeoutException {
      throw const BleProvisioningException('Opération BLE expirée');
    } catch (_) {
      throw const BleProvisioningException('Provisioning BLE impossible');
    } finally {
      await connection?.cancel();
    }
  }

  Future<void> _requestPermissions() async {
    if (kIsWeb) return;
    if (defaultTargetPlatform == TargetPlatform.android) {
      final statuses = await [
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
      ].request();
      if (statuses.values.any((status) => !status.isGranted)) {
        throw const BleProvisioningException(
          'Autorisations Bluetooth refusées',
        );
      }
    } else if (defaultTargetPlatform == TargetPlatform.iOS) {
      if (!(await Permission.bluetooth.request()).isGranted) {
        throw const BleProvisioningException(
          'Autorisation Bluetooth refusée',
        );
      }
    }
  }

  Map<String, dynamic> _decodeObject(List<int> bytes, String label) {
    try {
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException();
      }
      return decoded;
    } catch (_) {
      throw BleProvisioningException('$label invalide');
    }
  }
}

class BleProvisioningException implements Exception {
  final String message;

  const BleProvisioningException(this.message);

  @override
  String toString() => message;
}
