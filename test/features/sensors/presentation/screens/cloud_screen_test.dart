import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:provider/provider.dart';
import 'package:garden_journal/features/sensors/data/services/cloud_credential_store.dart';
import 'package:garden_journal/features/sensors/presentation/providers/cloud_provider.dart';
import 'package:garden_journal/features/sensors/presentation/providers/sensor_provider.dart';
import 'package:garden_journal/features/sensors/presentation/screens/cloud_screen.dart';

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  testWidgets('affiche la connexion cloud et le protocole de sécurité',
      (tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => CloudProvider(),
        child: const MaterialApp(home: CloudScreen()),
      ),
    );

    expect(find.text('Le cloud complète le stockage local'), findsOneWidget);
    expect(find.text('Mon compte'), findsOneWidget);
    expect(find.text('Se connecter'), findsOneWidget);
    expect(find.text('Connexion avec un token'), findsOneWidget);

    await tester.tap(find.byTooltip('Sécurité des données'));
    await tester.pumpAndSettle();

    expect(find.text('Avant une mise à jour de l’application'), findsOneWidget);
    expect(find.text('Avant de reflasher l’ESP32'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Les 5 jours déjà enregistrés'),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('Les 5 jours déjà enregistrés'), findsOneWidget);
  });

  testWidgets('préremplit le compte mémorisé depuis le coffre sécurisé',
      (tester) async {
    await SecureCloudCredentialStore().write(const CloudCredentials(
      baseUrl: 'https://gateway.example.test',
      username: 'projet',
      password: 'test-password-123',
    ));
    expect((await SecureCloudCredentialStore().read())?.username, 'projet');
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => CloudProvider(),
        child: const MaterialApp(home: CloudScreen()),
      ),
    );
    await tester.pumpAndSettle();
    final fields =
        tester.widgetList<TextField>(find.byType(TextField)).toList();
    expect(fields[0].controller?.text, 'https://gateway.example.test');
    expect(fields[1].controller?.text, 'projet');
    expect(fields[2].controller?.text, 'test-password-123');
    expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isTrue);
  });

  testWidgets('un bouton publie le journal puis récupère les mesures',
      (tester) async {
    final cloud = _ConnectedCloudProvider();
    final sensors = _RefreshingSensorProvider();
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<CloudProvider>.value(value: cloud),
          ChangeNotifierProvider<SensorProvider>.value(value: sensors),
        ],
        child: const MaterialApp(home: CloudScreen()),
      ),
    );

    await tester.tap(find.text('Synchroniser mes données'));
    await tester.pumpAndSettle();
    expect(cloud.steps, ['publication', 'mesures']);
    expect(sensors.refreshed, isTrue);
  });
}

class _ConnectedCloudProvider extends CloudProvider {
  final steps = <String>[];

  @override
  bool get isConfigured => true;

  @override
  Future<Set<String>> synchronizeMyData() async {
    steps.addAll(['publication', 'mesures']);
    return {};
  }
}

class _RefreshingSensorProvider extends SensorProvider {
  bool refreshed = false;

  @override
  Future<void> refreshFromLocalCache() async {
    refreshed = true;
  }
}
