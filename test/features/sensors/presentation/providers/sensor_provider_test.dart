import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:garden_journal/features/sensors/data/repositories/sensor_repository.dart';
import 'package:garden_journal/features/sensors/domain/entities/sensor_reading.dart';
import 'package:garden_journal/features/sensors/presentation/providers/sensor_provider.dart';

void main() {
  group('SensorProvider.configure', () {
    test('returns false and keeps sensors unconfigured when host is invalid',
        () {
      final provider = SensorProvider();

      final configured = provider.configure('192.168.1.42/api');

      expect(configured, isFalse);
      expect(provider.isConfigured, isFalse);
      expect(provider.error, 'Adresse ESP32 invalide');
    });

    test('returns true for a valid private ESP32 host', () {
      final provider = SensorProvider();

      final configured = provider.configure('192.168.1.42');

      expect(configured, isTrue);
      expect(provider.isConfigured, isTrue);
      expect(provider.error, isNull);
    });
  });

  group('SensorProvider.setStage', () {
    test('attend le réseau et confirme le succès', () async {
      final provider = SensorProvider(
        remoteRepository: SensorRepository(
          client: MockClient((request) async => http.Response('{}', 204)),
        ),
      );
      addTearDown(provider.dispose);
      provider.configure('192.168.1.42');

      final updated = await provider.setStage(GrowStage.flower);

      expect(updated, isTrue);
      expect(provider.stage, GrowStage.flower);
      expect(provider.isSettingStage, isFalse);
      expect(provider.stageError, isNull);
    });

    test('restaure le stade local et expose l’échec', () async {
      final provider = SensorProvider(
        remoteRepository: SensorRepository(
          client: MockClient((request) async => http.Response('{}', 500)),
        ),
      );
      addTearDown(provider.dispose);
      provider.configure('192.168.1.42');

      final updated = await provider.setStage(GrowStage.flower);

      expect(updated, isFalse);
      expect(provider.stage, GrowStage.veg);
      expect(provider.isSettingStage, isFalse);
      expect(provider.stageError, isNotNull);
    });
  });
}
