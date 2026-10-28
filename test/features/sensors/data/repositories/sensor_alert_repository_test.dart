import 'package:flutter_test/flutter_test.dart';
import 'package:garden_journal/core/database/database_helper.dart';
import 'package:garden_journal/features/sensors/data/repositories/sensor_alert_repository.dart';
import 'package:garden_journal/features/sensors/domain/entities/sensor_alert.dart';
import 'package:garden_journal/features/sensors/domain/entities/sensor_device.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../../support/database_test_utils.dart';

void main() {
  sqfliteFfiInit();
  final origin = DateTime.utc(2026, 7, 19, 12);

  Future<Database> setup() async {
    final db = await openMemoryDatabase();
    await DatabaseHelper.instance.createSchemaForTesting(db);
    await db.insert(
      'sensor_devices',
      SensorDevice(
        id: 'node-alert',
        uid: 'node-alert',
        name: 'Nœud alertes',
        zoneId: 'zone-main',
        baseUrl: 'http://192.168.1.42',
        createdAt: origin,
        updatedAt: origin,
      ).toMap(),
    );
    return db;
  }

  SensorAlertRule rule({int duration = 60}) => SensorAlertRule(
        id: 'hot',
        name: 'Température haute',
        deviceId: 'node-alert',
        metricKey: 'temperature_c',
        comparison: 'gt',
        thresholdMax: 30,
        durationSeconds: duration,
        hysteresis: 2,
        cooldownSeconds: 900,
        severity: 'critical',
        createdAt: origin,
        updatedAt: origin,
      );

  test('durée et état de violation survivent à une nouvelle instance',
      () async {
    final db = await setup();
    addTearDown(db.close);
    final firstRepository = SensorAlertRepository(database: db);
    await firstRepository.saveRule(rule());

    final pending = await firstRepository.evaluate(
      rule(),
      value: 31,
      observedAt: origin,
    );
    expect(pending.openedEvent, isNull);

    final restartedRepository = SensorAlertRepository(database: db);
    final opened = await restartedRepository.evaluate(
      rule(),
      value: 31,
      observedAt: origin.add(const Duration(seconds: 61)),
    );
    expect(opened.openedEvent, isNotNull);
    expect(opened.shouldNotify, isTrue);
    expect(await restartedRepository.getEvents(activeOnly: true), hasLength(1));
  });

  test('hystérésis évite le battement puis résout et conserve l’historique',
      () async {
    final db = await setup();
    addTearDown(db.close);
    final repository = SensorAlertRepository(database: db);
    final immediate = rule(duration: 0);
    await repository.saveRule(immediate);
    await repository.evaluate(immediate, value: 31, observedAt: origin);

    await repository.evaluate(
      immediate,
      value: 29,
      observedAt: origin.add(const Duration(seconds: 10)),
    );
    expect(await repository.getEvents(activeOnly: true), hasLength(1));

    final resolved = await repository.evaluate(
      immediate,
      value: 28,
      observedAt: origin.add(const Duration(seconds: 20)),
    );
    expect(resolved.resolvedEvent, isNotNull);
    expect(await repository.getEvents(activeOnly: true), isEmpty);
    expect((await repository.getEvents()).single.resolvedAt, isNotNull);
  });

  test('acquittement et suppression de règle ne suppriment pas l’événement',
      () async {
    final db = await setup();
    addTearDown(db.close);
    final repository = SensorAlertRepository(database: db);
    final immediate = rule(duration: 0);
    await repository.saveRule(immediate);
    final event = (await repository.evaluate(
      immediate,
      value: 35,
      observedAt: origin,
    ))
        .openedEvent!;
    await repository.acknowledge(
        event.id, origin.add(const Duration(seconds: 1)));
    await repository.deleteRule(immediate.id);

    final saved = (await repository.getEvents()).single;
    expect(saved.isAcknowledged, isTrue);
    expect(saved.ruleId, immediate.id);
  });
}
