import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'core/theme/app_theme.dart';
import 'features/plants/presentation/providers/plant_provider.dart';
import 'features/actions/presentation/providers/action_provider.dart';
import 'features/groups/presentation/providers/group_provider.dart';
import 'features/sensors/presentation/providers/sensor_provider.dart';
import 'features/sensors/presentation/providers/cloud_provider.dart';
import 'features/spaces/presentation/providers/space_provider.dart';
import 'features/cameras/presentation/providers/camera_provider.dart';
import 'app_shell.dart';
import 'core/services/planned_action_notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await PlannedActionNotificationService.init();
  } catch (error, stackTrace) {
    FlutterError.reportError(FlutterErrorDetails(
      exception: error,
      stack: stackTrace,
      library: 'gardenjournal notifications',
      context: ErrorDescription('initialisation des notifications'),
    ));
  }
  SystemChrome.setPreferredOrientations(
      [DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light));
  runApp(const GardenJournalApp());
}

class GardenJournalApp extends StatelessWidget {
  const GardenJournalApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => GroupProvider()..loadGroups()),
        ChangeNotifierProvider(create: (_) => PlantProvider()..loadPlants()),
        ChangeNotifierProvider(create: (_) => ActionProvider()),
        ChangeNotifierProvider(create: (_) => SpaceProvider()..initialize()),
        ChangeNotifierProvider(create: (_) => SensorProvider()),
        ChangeNotifierProvider(create: (_) => CloudProvider()),
        ChangeNotifierProvider(create: (_) => CameraProvider()..initialize()),
      ],
      child: MaterialApp(
        title: 'GardenJournal',
        theme: AppTheme.lightTheme,
        debugShowCheckedModeBanner: false,
        home: const AppShell(),
      ),
    );
  }
}
