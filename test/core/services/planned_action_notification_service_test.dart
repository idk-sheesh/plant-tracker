import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garden_journal/core/services/planned_action_notification_service.dart';

void main() {
  test('un appui sur le corps de la notification ne valide pas l’action',
      () async {
    const response = NotificationResponse(
      notificationResponseType: NotificationResponseType.selectedNotification,
      payload: 'planned-action-1',
    );

    await PlannedActionNotificationService.handleNotificationResponse(response);
  });

  test('une action de notification inconnue ne modifie pas l’action', () async {
    const response = NotificationResponse(
      notificationResponseType:
          NotificationResponseType.selectedNotificationAction,
      actionId: 'unknown',
      payload: 'planned-action-1',
    );

    await PlannedActionNotificationService.handleNotificationResponse(response);
  });
}
