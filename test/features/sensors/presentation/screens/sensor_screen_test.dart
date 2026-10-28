import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garden_journal/features/sensors/presentation/providers/cloud_provider.dart';
import 'package:garden_journal/features/sensors/presentation/providers/sensor_provider.dart';
import 'package:garden_journal/features/sensors/presentation/screens/sensor_screen.dart';
import 'package:garden_journal/features/spaces/presentation/providers/space_provider.dart';
import 'package:provider/provider.dart';

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  testWidgets('la barre Espaces expose directement la synchronisation',
      (tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SpaceProvider>(
            create: (_) => _EmptySpaceProvider(),
          ),
          ChangeNotifierProvider<SensorProvider>(
            create: (_) => _IdleSensorProvider(),
          ),
          ChangeNotifierProvider<CloudProvider>(
            create: (_) => CloudProvider(),
          ),
        ],
        child: const MaterialApp(home: SensorScreen()),
      ),
    );
    await tester.pump();

    expect(find.widgetWithText(TextButton, 'Synchro'), findsOneWidget);
    expect(find.text('Synchroniser mes données'), findsNothing);

    await tester.tap(find.text('Synchro'));
    await tester.pumpAndSettle();

    expect(find.text('Synchronisation'), findsOneWidget);
    expect(find.text('Mon compte'), findsOneWidget);
  });

  testWidgets('reprise automatique chaque minute et pause en arrière-plan',
      (tester) async {
    final cloud = _AutoCloud();
    final sensors = _IdleSensorProvider();
    await tester.pumpWidget(MultiProvider(providers: [
      ChangeNotifierProvider<SpaceProvider>(
          create: (_) => _EmptySpaceProvider()),
      ChangeNotifierProvider<SensorProvider>.value(value: sensors),
      ChangeNotifierProvider<CloudProvider>.value(value: cloud),
    ], child: const MaterialApp(home: SensorScreen())));
    await tester.pumpAndSettle();
    expect(cloud.syncs, 1);
    await tester.pump(const Duration(minutes: 1));
    await tester.pumpAndSettle();
    expect(cloud.syncs, 2);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(minutes: 2));
    expect(cloud.syncs, 2);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(cloud.syncs, 3);
    await tester.pumpWidget(const SizedBox.shrink());
    cloud.dispose();
    sensors.dispose();
  });
}

class _AutoCloud extends CloudProvider {
  int syncs = 0;
  @override
  bool get isConfigured => true;
  @override
  Future<Set<String>> synchronizeMyData() async {
    syncs++;
    return {};
  }
}

class _EmptySpaceProvider extends SpaceProvider {
  @override
  Future<void> initialize() async {}

  @override
  Future<void> refresh() async {}
}

class _IdleSensorProvider extends SensorProvider {
  @override
  Future<void> initialize() async {}

  @override
  Future<void> syncAllDevices({Set<String> skipDeviceIds = const {}}) async {}
}
