import 'package:flutter_test/flutter_test.dart';
import 'package:garden_journal/features/plants/domain/entities/cutting_protocol.dart';

void main() {
  group('GardenCuttingProtocol', () {
    test('calcule le jour par date civile', () {
      final start = DateTime(2026, 8, 1, 23, 30);
      final nextMorning = DateTime(2026, 8, 2, 7);

      expect(GardenCuttingProtocol.dayNumber(start, nextMorning), 1);
    });

    test('selectionne les etapes J0, J11 et J14+', () {
      expect(GardenCuttingProtocol.stepForDay(0)?.dayLabel, 'J0–J2');
      expect(GardenCuttingProtocol.stepForDay(11)?.title, 'Test sans dôme');
      expect(GardenCuttingProtocol.stepForDay(25)?.dayLabel, 'J14+');
      expect(GardenCuttingProtocol.stepForDay(-1), isNull);
    });

    test('convertit plus de 20 pour cent de 12 boutures en seuil de 3', () {
      expect(GardenCuttingProtocol.wiltedCuttingThreshold(12), 3);
      expect(GardenCuttingProtocol.wiltedCuttingThreshold(5), 2);
      expect(GardenCuttingProtocol.wiltedCuttingThreshold(null), isNull);
    });
  });
}
