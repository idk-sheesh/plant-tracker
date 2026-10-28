import 'dart:convert';

class LoRaFrame {
  final String nodeId;
  final String sessionId;
  final int frameCounter;
  final DateTime sentAt;
  final int rssi;
  final double snr;
  final Map<String, Object> measurements;
  final Map<String, dynamic> canonicalPayload;

  const LoRaFrame({
    required this.nodeId,
    required this.sessionId,
    required this.frameCounter,
    required this.sentAt,
    required this.rssi,
    required this.snr,
    required this.measurements,
    required this.canonicalPayload,
  });

  factory LoRaFrame.parse(Object? raw, {DateTime? now}) {
    if (raw is! Map) throw const FormatException('Trame LoRa invalide');
    final json = Map<String, dynamic>.from(raw);
    if (json['type'] != 'lora_reading' || json['protocolVersion'] != 1) {
      throw const FormatException('Protocole LoRa incompatible');
    }
    if (json['authenticated'] != true) {
      throw const FormatException('Trame LoRa non authentifiée par la gateway');
    }
    final nodeId = _identifier(json['nodeId'], 'nodeId');
    final sessionId = _identifier(json['sessionId'], 'sessionId');
    final counter = json['frameCounter'];
    if (counter is! int || counter < 0 || counter > 0x7fffffff) {
      throw const FormatException('Compteur LoRa invalide');
    }
    final sentAt = DateTime.tryParse(json['sentAt'] as String? ?? '')?.toUtc();
    final reference = (now ?? DateTime.now()).toUtc();
    if (sentAt == null ||
        sentAt.isAfter(reference.add(const Duration(minutes: 5))) ||
        sentAt.isBefore(reference.subtract(const Duration(days: 366)))) {
      throw const FormatException('Date LoRa invalide');
    }
    final rssi = json['rssi'];
    final snr = json['snr'];
    if (rssi is! int || rssi < -200 || rssi > 0) {
      throw const FormatException('RSSI LoRa invalide');
    }
    if (snr is! num || !snr.toDouble().isFinite || snr < -50 || snr > 50) {
      throw const FormatException('SNR LoRa invalide');
    }
    final rawMeasurements = json['measurements'];
    if (rawMeasurements is! Map ||
        rawMeasurements.isEmpty ||
        rawMeasurements.length > 100) {
      throw const FormatException('Mesures LoRa invalides');
    }
    final measurements = <String, Object>{};
    for (final entry in rawMeasurements.entries) {
      final key = _identifier(entry.key, 'clé mesure');
      final value = entry.value;
      if (value is num && value.toDouble().isFinite ||
          value is bool ||
          value is String && value.length <= 500) {
        measurements[key] = value as Object;
      } else {
        throw FormatException('Valeur LoRa invalide pour $key');
      }
    }
    return LoRaFrame(
      nodeId: nodeId,
      sessionId: sessionId,
      frameCounter: counter,
      sentAt: sentAt.toLocal(),
      rssi: rssi,
      snr: snr.toDouble(),
      measurements: Map.unmodifiable(measurements),
      canonicalPayload: Map.unmodifiable(json),
    );
  }

  String encode() => jsonEncode(canonicalPayload);
}

String _identifier(Object? value, String field) {
  if (value is! String ||
      !RegExp(r'^[A-Za-z0-9][A-Za-z0-9_.:-]{0,127}$').hasMatch(value)) {
    throw FormatException('$field LoRa invalide');
  }
  return value;
}
