import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../domain/entities/device_health_snapshot.dart';
import '../../domain/entities/gateway.dart';
import '../../domain/entities/lora_packet.dart';
import '../../domain/entities/sensor_measurement.dart';
import '../../domain/entities/sensor_reading.dart';
import '../repositories/lora_repository.dart';
import '../repositories/sensor_data_repository.dart';
import 'sensor_alert_service.dart';

class LoRaIngestResult {
  final int accepted;
  final int duplicates;
  final int replays;
  final int unknownNodes;
  final int rejected;

  const LoRaIngestResult({
    required this.accepted,
    required this.duplicates,
    required this.replays,
    required this.unknownNodes,
    required this.rejected,
  });
}

class LoRaGatewayIngestService {
  final LoRaRepository loraRepository;
  final SensorDataRepository sensorRepository;
  final SensorAlertService? alertService;
  final DateTime Function() _clock;

  LoRaGatewayIngestService({
    LoRaRepository? loraRepository,
    SensorDataRepository? sensorRepository,
    SensorAlertService? alertService,
    DateTime Function()? clock,
  })  : loraRepository = loraRepository ?? LoRaRepository(),
        sensorRepository = sensorRepository ?? SensorDataRepository(),
        alertService = alertService ??
            (sensorRepository == null ? SensorAlertService() : null),
        _clock = clock ?? DateTime.now;

  Future<LoRaIngestResult> handleEnvelope(
    GatewayConfig gateway,
    GatewayEnvelope envelope,
  ) async {
    var accepted = 0;
    var duplicates = 0;
    var replays = 0;
    var unknownNodes = 0;
    var rejected = 0;
    for (final raw in envelope.records) {
      if (raw['type'] != 'lora_reading') continue;
      try {
        final frame = LoRaFrame.parse(raw, now: _clock());
        final payload = frame.encode();
        final reservation = await loraRepository.reserveFrame(
          gatewayId: gateway.id,
          frame: frame,
          payloadHash: sha256.convert(utf8.encode(payload)).toString(),
          receivedAt: _clock(),
        );
        switch (reservation.status) {
          case LoRaReservationStatus.duplicate:
            duplicates++;
            continue;
          case LoRaReservationStatus.replay:
            replays++;
            continue;
          case LoRaReservationStatus.unknownNode:
            unknownNodes++;
            continue;
          case LoRaReservationStatus.reserved:
            break;
        }
        try {
          await _persistFrame(reservation, frame);
          await loraRepository.acceptFrame(reservation, frame, _clock());
          accepted++;
        } catch (error) {
          await loraRepository.rejectFrame(reservation.packetId, error);
          rejected++;
        }
      } catch (_) {
        rejected++;
      }
    }
    return LoRaIngestResult(
      accepted: accepted,
      duplicates: duplicates,
      replays: replays,
      unknownNodes: unknownNodes,
      rejected: rejected,
    );
  }

  Future<void> _persistFrame(
    LoRaReservation reservation,
    LoRaFrame frame,
  ) async {
    final device = await sensorRepository.getDeviceById(
      reservation.link!.nodeDeviceId,
    );
    if (device == null) throw StateError('Nœud LoRa lié introuvable');
    final measurements = <SensorMeasurement>[];
    for (final entry in frame.measurements.entries) {
      measurements.add(SensorMeasurement.fromValue(
        deviceId: device.id,
        zoneId: device.zoneId,
        key: entry.key,
        value: entry.value,
        unit: _unitFor(entry.key),
        quality: 'gateway_authenticated',
        timestamp: frame.sentAt,
        createdAt: _clock(),
      ));
    }
    measurements.addAll([
      SensorMeasurement.fromValue(
        deviceId: device.id,
        zoneId: device.zoneId,
        key: 'lora_rssi_dbm',
        value: frame.rssi,
        unit: 'dBm',
        quality: 'gateway_authenticated',
        timestamp: frame.sentAt,
        createdAt: _clock(),
      ),
      SensorMeasurement.fromValue(
        deviceId: device.id,
        zoneId: device.zoneId,
        key: 'lora_snr_db',
        value: frame.snr,
        unit: 'dB',
        quality: 'gateway_authenticated',
        timestamp: frame.sentAt,
        createdAt: _clock(),
      ),
    ]);
    final temperature = _numeric(frame, const ['air_temp_c', 'temperature_c']);
    final humidity = _numeric(
      frame,
      const ['air_humidity_pct', 'humidity_percent'],
    );
    if (temperature != null && humidity != null) {
      final reading = SensorReading(
        deviceId: device.id,
        zoneId: device.zoneId,
        temperature: temperature,
        humidity: humidity,
        vpd: SensorReading.calculateVpd(temperature, humidity),
        dewPoint: SensorReading.calculateDewPoint(temperature, humidity),
        timestamp: frame.sentAt,
        mistOn: false,
        rssi: frame.rssi,
        measurements: measurements,
        createdAt: _clock(),
      );
      await sensorRepository.insertReadings(device, [reading]);
      await alertService?.evaluateReading(device, reading);
    } else {
      await sensorRepository.insertMeasurements(device, measurements);
    }
    await sensorRepository.recordHealthSnapshot(DeviceHealthSnapshot(
      id: '${device.id}-${_clock().toUtc().millisecondsSinceEpoch ~/ 1000}',
      deviceId: device.id,
      observedAt: _clock(),
      isOnline: true,
      batteryVoltage: _numeric(frame, const ['battery_v']),
      rssi: frame.rssi,
      snr: frame.snr,
      missingReadings: 0,
      firmwareVersion: device.firmwareVersion,
      createdAt: _clock(),
    ));
  }

  static double? _numeric(LoRaFrame frame, List<String> keys) {
    for (final key in keys) {
      final value = frame.measurements[key];
      if (value is num) return value.toDouble();
    }
    return null;
  }

  static String? _unitFor(String key) => switch (key) {
        'air_temp_c' || 'temperature_c' || 'water_temp_c' => '°C',
        'air_humidity_pct' || 'humidity_percent' || 'soil_moisture_pct' => '%',
        'water_ph' => 'pH',
        'water_tds_ppm' => 'ppm',
        'water_ec_ms_cm' => 'mS/cm',
        'light_lux' => 'lux',
        'light_ppfd' => 'µmol/m²/s',
        'battery_v' => 'V',
        _ => null,
      };
}
