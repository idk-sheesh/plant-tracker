import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../features/actions/data/repositories/action_repository.dart';
import '../../features/actions/domain/entities/plant_action.dart';
import '../../features/plants/data/repositories/plant_repository.dart';
import '../../features/plants/domain/entities/plant.dart';
import '../utils/app_utils.dart';
import 'device_time_zone_service.dart';

@pragma('vm:entry-point')
void plannedActionNotificationTapBackground(NotificationResponse response) {
  PlannedActionNotificationService.handleNotificationResponse(response);
}

class PlannedActionNotificationService {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static final ActionRepository _actionRepo = ActionRepository();
  static final PlantRepository _plantRepo = PlantRepository();
  static TimeZoneResolver timeZoneResolver = const PlatformTimeZoneResolver();
  static bool _ready = false;

  static Future<void> init() async {
    if (_ready) return;
    await DeviceTimeZoneService.refreshLocalLocation(timeZoneResolver);

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: android);
    await _plugin.initialize(
      settings: settings,
      onDidReceiveNotificationResponse: handleNotificationResponse,
      onDidReceiveBackgroundNotificationResponse:
          plannedActionNotificationTapBackground,
    );

    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.requestNotificationsPermission();
    _ready = true;
  }

  static Future<void> schedule(PlantAction action, Plant? plant) async {
    if (!action.isPlanned) return;
    await init();
    await DeviceTimeZoneService.refreshLocalLocation(timeZoneResolver);
    final scheduled = action.timestamp.isBefore(DateTime.now())
        ? DateTime.now().add(const Duration(minutes: 1))
        : action.timestamp;

    await _plugin.zonedSchedule(
      id: _notificationId(action.id),
      title: '${AppUtils.actionLabel(action.actionType)} prevu',
      body: plant == null
          ? AppUtils.formatDateTime(action.timestamp)
          : '${plant.name} - ${AppUtils.formatDateTime(action.timestamp)}',
      scheduledDate: tz.TZDateTime.from(scheduled, tz.local),
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'planned_actions',
          'Actions planifiees',
          channelDescription: 'Rappels des actions GardenJournal planifiees',
          importance: Importance.high,
          priority: Priority.high,
          actions: [
            AndroidNotificationAction('done', 'Valider'),
            AndroidNotificationAction('snooze_1h', 'Reporter 1h'),
          ],
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      payload: action.id,
    );
  }

  static Future<void> cancel(String actionId) async {
    await init();
    await _plugin.cancel(id: _notificationId(actionId));
  }

  static Future<void> reconcileFromDatabase() async {
    final actions = await _actionRepo.getPlannedActions();
    final plants = <String, Plant?>{};
    for (final action in actions) {
      plants[action.plantId] ??= await _plantRepo.getPlantById(action.plantId);
    }

    await init();
    await _plugin.cancelAll();
    var failed = 0;
    for (final action in actions) {
      try {
        await schedule(action, plants[action.plantId]);
      } catch (_) {
        failed++;
      }
    }
    if (failed > 0) {
      throw StateError('$failed rappel(s) n’ont pas pu être replanifiés');
    }
  }

  static Future<void> handleNotificationResponse(
    NotificationResponse response,
  ) async {
    final actionId = response.payload;
    if (actionId == null || actionId.isEmpty) return;
    if (response.actionId != 'done' && response.actionId != 'snooze_1h') {
      return;
    }
    final action = await _actionRepo.getActionById(actionId);
    if (action == null || !action.isPlanned) return;

    if (response.actionId == 'snooze_1h') {
      final postponed = action.copyWith(
        timestamp: DateTime.now().add(const Duration(hours: 1)),
        status: 'planned',
      );
      await _actionRepo.updateAction(postponed);
      final plant = await _plantRepo.getPlantById(postponed.plantId);
      await schedule(postponed, plant);
      return;
    }
    // Seul le bouton explicite « Valider » atteint ce chemin. Un appui sur le
    // corps de la notification ne modifie jamais l'action.
    final now = DateTime.now();
    final done = action.copyWith(
      timestamp: now,
      status: 'done',
      completedAt: now,
    );
    await _actionRepo.updateAction(done);
    await cancel(action.id);
  }

  static int _notificationId(String id) {
    var hash = 0;
    for (final unit in id.codeUnits) {
      hash = (hash * 31 + unit) & 0x7fffffff;
    }
    return hash == 0 ? 1 : hash;
  }
}
