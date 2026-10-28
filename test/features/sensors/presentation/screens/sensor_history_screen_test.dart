import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garden_journal/features/sensors/domain/entities/sensor_reading.dart';
import 'package:garden_journal/features/sensors/presentation/screens/sensor_history_screen.dart';

void main() {
  testWidgets(
      'tableau mobile : lumière mesurée, état distinct, aucun débordement',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final reading = SensorReading.fromJson({
      'deviceId': 'culture-ldr-01',
      'timestamp': 1783947600,
      'temperature': 25,
      'humidity': 50,
      'lightRaw': 3498,
      'lightOn': true,
    });
    await tester.pumpWidget(MaterialApp(
      home: SensorHistoryScreen(
        readings: [reading],
        measurements: reading.measurements,
        devices: const [],
      ),
    ));
    expect(find.text('Tableau des mesures'), findsOneWidget);
    expect(find.textContaining('Jour détecté'), findsOneWidget);
    expect(find.textContaining('3498 ADC'), findsOneWidget);
    expect(find.textContaining('Inconnu'), findsOneWidget);
    expect(find.textContaining('Température'), findsOneWidget);
    expect(find.textContaining('Humidité'), findsOneWidget);
    expect(find.textContaining('VPD air'), findsOneWidget);
    expect(find.byType(SingleChildScrollView), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('les relevés suivants restent accessibles sur téléphone',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final readings = List.generate(
      21,
      (index) => SensorReading(
        deviceId: 'capteur-$index',
        temperature: 20,
        humidity: 50,
        vpd: 1,
        timestamp: DateTime(2026, 9, 20, 12, index),
        mistOn: false,
      ),
    );
    await tester.pumpWidget(MaterialApp(
      home: SensorHistoryScreen(
        readings: readings,
        measurements: const [],
        devices: const [],
      ),
    ));
    expect(find.text('Page 1 / 2').first, findsOneWidget);
    expect(find.textContaining('capteur-20'), findsOneWidget);
    await tester.tap(find.byTooltip('Page suivante').first);
    await tester.pumpAndSettle();
    expect(find.text('Page 2 / 2').first, findsOneWidget);
    expect(find.textContaining('capteur-0'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
