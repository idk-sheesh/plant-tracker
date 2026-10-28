import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garden_journal/features/sensors/domain/entities/device_capability.dart';
import 'package:garden_journal/features/sensors/domain/entities/sensor_measurement.dart';
import 'package:garden_journal/features/sensors/domain/entities/sensor_reading.dart';
import 'package:garden_journal/features/sensors/presentation/providers/sensor_provider.dart';
import 'package:garden_journal/features/sensors/presentation/screens/sensor_comparison_screen.dart';

class _SensorsForComparison extends SensorProvider {
  final List<SensorReading> readings;
  final List<SensorMeasurement> values;

  _SensorsForComparison(this.readings, this.values);

  @override
  Future<List<SensorReading>> historyForZone(
          String zoneId, Duration period) async =>
      readings;

  @override
  Future<List<SensorMeasurement>> measurementsForZone(
          String zoneId, Duration period) async =>
      values;
}

void main() {
  testWidgets('comparaison vide, lecture avec gros texte et sélection vide',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final sensors = _SensorsForComparison([], []);
    addTearDown(sensors.dispose);
    await tester.pumpWidget(MaterialApp(
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.5)),
            child: child!),
        home: SensorComparisonScreen(
            zoneId: 'zone', zoneName: 'Serre', sensors: sensors)));
    await tester.pumpAndSettle();
    expect(find.text('Aucune mesure sur cette période.'), findsOneWidget);
    for (final label in ['Température (°C)', 'Humidité (%)', 'VPD (kPa)']) {
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
    }
    expect(find.text('Sélectionne au moins une courbe.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('comparaison mobile : période, axe daté et valeur réelle',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final start = DateTime(2026, 9, 20, 12);
    final end = start.add(const Duration(minutes: 10));
    final sensors = _SensorsForComparison(
      [
        SensorReading(
          temperature: 20,
          humidity: 50,
          vpd: 1.17,
          timestamp: start,
          mistOn: false,
        ),
        SensorReading(
          temperature: 22,
          humidity: 55,
          vpd: 1.19,
          timestamp: end,
          mistOn: false,
        ),
      ],
      [
        SensorMeasurement(
          deviceId: 'node-1',
          capabilityKey: 'light_adc_raw',
          valueType: SensorValueType.number,
          numericValue: 1234,
          unit: 'ADC',
          timestamp: end,
          createdAt: end,
        ),
      ],
    );
    addTearDown(sensors.dispose);
    await tester.pumpWidget(MaterialApp(
      home: SensorComparisonScreen(
        zoneId: 'zone-1',
        zoneName: 'Éclaircissage',
        sensors: sensors,
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('20/09 12:00 au 20/09 12:10'), findsOneWidget);
    expect(find.text('Lumière brute (ADC)'), findsOneWidget);
    final chart = tester.widget<LineChart>(find.byType(LineChart).first);
    expect(chart.data.titlesData.bottomTitles.sideTitles.showTitles, isTrue);
    expect(
        chart.data.lineBarsData.single.spots.map((point) => point.y), [20, 22]);
    expect(find.textContaining('indice normalisé'), findsNothing);
    await tester.tap(find.text('Lumière brute (ADC)').first);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
        find.textContaining('Dernier : 1234 ADC'), 300,
        scrollable: find.byType(Scrollable).first);
    expect(find.textContaining('Dernier : 1234 ADC'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
