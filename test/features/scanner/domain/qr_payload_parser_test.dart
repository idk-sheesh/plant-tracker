import 'package:flutter_test/flutter_test.dart';
import 'package:garden_journal/features/scanner/domain/qr_payload_parser.dart';

void main() {
  group('QrPayloadParser', () {
    test('lit le format court GardenJournal', () {
      final result = QrPayloadParser.parse('plant:abc_123-DEF');
      expect(result.plantId, 'abc_123-DEF');
      expect(result.entityType, QrEntityType.plant);
      expect(result.isLegacyProfile, isFalse);
    });

    test('lit les formats courts appareil et passerelle', () {
      expect(
        QrPayloadParser.parse('device:node-01').entityType,
        QrEntityType.device,
      );
      expect(
        QrPayloadParser.parse('gateway:gw-01').entityType,
        QrEntityType.gateway,
      );
    });

    test('valide un QR appareil versionné et son jeton temporaire', () {
      final now = DateTime.utc(2026, 7, 19, 12);
      final result = QrPayloadParser.parse(
        '{"v":1,"type":"device","id":"node-01",'
        '"model":"GT-LORA","pairingToken":"abcdefghijklmnop",'
        '"expiresAt":"2026-07-19T12:15:00Z",'
        '"serviceUuid":"7f510001-1b15-4f0d-9a63-8c2f6a000001"}',
        now: now,
      );

      expect(result.deviceId, 'node-01');
      expect(result.model, 'GT-LORA');
      expect(result.canProvision, isTrue);
    });

    test('accepte un transport LoRa explicite sans secret radio', () {
      final result = QrPayloadParser.parse(
        '{"v":1,"type":"device","id":"node-lora-01",'
        '"transport":"lora","pairingToken":"abcdefghijklmnop",'
        '"expiresAt":"2026-07-19T12:15:00Z"}',
        now: DateTime.utc(2026, 7, 19, 12),
      );

      expect(result.transport, 'lora');
    });

    test('refuse secrets, jetons expirés et versions inconnues', () {
      final now = DateTime.utc(2026, 7, 19, 12);
      expect(
        () => QrPayloadParser.parse(
          '{"v":1,"type":"device","id":"node-01",'
          '"password":"secret"}',
          now: now,
        ),
        throwsFormatException,
      );
      expect(
        () => QrPayloadParser.parse(
          '{"v":1,"type":"device","id":"node-01",'
          '"pairingToken":"abcdefghijklmnop",'
          '"expiresAt":"2026-07-19T11:59:00Z"}',
          now: now,
        ),
        throwsFormatException,
      );
      expect(
        () => QrPayloadParser.parse(
          '{"v":2,"type":"device","id":"node-01"}',
        ),
        throwsFormatException,
      );
    });

    test('lit un ancien profil JSON sans faire confiance aux types', () {
      final result = QrPayloadParser.parse(
        '{"id":"plant-1","n":"Basilic","v":"Genovese","c":"Terre"}',
      );
      expect(result.plantId, 'plant-1');
      expect(result.legacyProfile?['name'], 'Basilic');
      expect(result.legacyProfile?['culture'], 'Terre');
    });

    test('rejette format, identifiant et payload inconnus', () {
      expect(() => QrPayloadParser.parse('https://example.test'),
          throwsFormatException);
      expect(() => QrPayloadParser.parse('plant:'), throwsFormatException);
      expect(() => QrPayloadParser.parse('plant:id avec espace'),
          throwsFormatException);
      expect(() => QrPayloadParser.parse('{"id":42}'), throwsFormatException);
    });

    test('borne la taille du QR et des champs hérités', () {
      expect(
        () => QrPayloadParser.parse(
          'plant:${'a' * (QrPayloadParser.maxPayloadLength + 1)}',
        ),
        throwsFormatException,
      );
      expect(
        () => QrPayloadParser.parse(
          '{"id":"ok","n":"${'a' * 201}"}',
        ),
        throwsFormatException,
      );
    });
  });
}
