import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:garden_journal/core/database/database_helper.dart';
import 'package:garden_journal/features/sensors/data/repositories/automation_repository.dart';
import 'package:garden_journal/features/sensors/data/repositories/sensor_repository.dart';
import 'package:garden_journal/features/sensors/data/services/automation_rule_service.dart';
import 'package:garden_journal/features/sensors/domain/entities/sensor_device.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../../support/database_test_utils.dart';

void main() {
  sqfliteFfiInit();
  final now = DateTime.utc(2026, 7, 19, 12);

  Future<(Database, SensorDevice)> setup() async {
    final db = await openMemoryDatabase();
    await DatabaseHelper.instance.createSchemaForTesting(db);
    final device = SensorDevice(
      id: 'node-rules',
      uid: 'node-rules',
      name: 'Nœud règles',
      zoneId: 'zone-main',
      baseUrl: 'http://192.168.1.42',
      createdAt: now,
      updatedAt: now,
    );
    await db.insert('sensor_devices', device.toMap());
    return (db, device);
  }

  test('normalise un arbre AND/OR imbriqué borné', () {
    final result = AutomationRuleService.validateCondition({
      'op': 'and',
      'conditions': [
        {
          'metric': 'temperature_c',
          'comparison': 'gt',
          'value': 28,
          'hysteresis': 0.5,
        },
        {
          'op': 'or',
          'conditions': [
            {
              'metric': 'humidity_percent',
              'comparison': 'lt',
              'value': 45,
            },
            {
              'metric': 'vpd_kpa',
              'comparison': 'between',
              'min': 1.0,
              'max': 1.5,
            },
          ],
        },
      ],
    });

    expect(result['op'], 'and');
    expect((result['conditions'] as List), hasLength(2));
  });

  test('refuse profondeur et nombre de nœuds excessifs', () {
    Map<String, Object?> leaf() => {
          'metric': 'temperature_c',
          'comparison': 'gt',
          'value': 28,
        };
    Map<String, Object?> nested(int levels) => levels == 0
        ? leaf()
        : {
            'op': 'and',
            'conditions': [nested(levels - 1), leaf()],
          };

    expect(
      () => AutomationRuleService.validateCondition(nested(5)),
      throwsA(isA<AutomationRuleException>()),
    );
    expect(
      () => AutomationRuleService.validateCondition({
        'op': 'and',
        'conditions': [
          for (var index = 0; index < 10; index++)
            {
              'op': 'and',
              'conditions': [leaf(), leaf()],
            },
        ],
      }),
      throwsA(isA<AutomationRuleException>()),
    );
  });

  test('refuse irrigation avant tout appel réseau', () async {
    final (db, device) = await setup();
    addTearDown(db.close);
    var calls = 0;
    final service = AutomationRuleService(
      repository: AutomationRepository(database: db),
      remote: SensorRepository(client: MockClient((_) async {
        calls++;
        return http.Response('{}', 200);
      })),
      clock: () => now,
    );

    await expectLater(
      service.synchronize(
        device: device,
        name: 'Arrosage interdit',
        condition: const {
          'metric': 'humidity_percent',
          'comparison': 'lt',
          'value': 40,
        },
        actionType: 'irrigation.pulse',
        actionParams: const {'durationSeconds': 10, 'maxVolumeMl': 500},
        durationSeconds: 60,
        cooldownSeconds: 900,
        maxRunsPerDay: 5,
      ),
      throwsA(isA<AutomationRuleException>()),
    );
    expect(calls, 0);
    expect(await db.query('automation_rules'), isEmpty);
  });

  test('active seulement après ACK exact du hash et de la révision', () async {
    final (db, device) = await setup();
    addTearDown(db.close);
    late Map<String, dynamic> requestBody;
    final repository = AutomationRepository(database: db);
    final service = AutomationRuleService(
      repository: repository,
      remote: SensorRepository(client: MockClient((request) async {
        requestBody = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({
            'ruleId': requestBody['ruleId'],
            'revision': requestBody['revision'],
            'ruleHash': requestBody['ruleHash'],
            'status': 'accepted',
          }),
          200,
        );
      })),
      clock: () => now,
    );

    final rule = await service.synchronize(
      device: device,
      name: 'Brume climat',
      condition: const {
        'op': 'and',
        'conditions': [
          {
            'metric': 'temperature_c',
            'comparison': 'gt',
            'value': 28,
          },
          {
            'metric': 'humidity_percent',
            'comparison': 'lt',
            'value': 45,
          },
        ],
      },
      actionType: 'mist.set',
      actionParams: const {'state': true},
      durationSeconds: 300,
      cooldownSeconds: 900,
      maxRunsPerDay: 10,
    );

    expect(requestBody['ruleHash'], hasLength(64));
    expect(rule.status, 'active');
    expect(rule.nodeAckHash, rule.ruleHash);
    expect(rule.revision, 1);
    expect((await repository.getRules(device.id)).single.status, 'active');
  });

  test('un ACK incohérent laisse une règle en échec', () async {
    final (db, device) = await setup();
    addTearDown(db.close);
    final repository = AutomationRepository(database: db);
    final service = AutomationRuleService(
      repository: repository,
      remote: SensorRepository(
          client: MockClient((_) async => http.Response(
                jsonEncode({
                  'ruleId': 'different',
                  'revision': 1,
                  'ruleHash': '0' * 64,
                  'status': 'accepted',
                }),
                200,
              ))),
      clock: () => now,
    );

    await expectLater(
      service.synchronize(
        device: device,
        name: 'ACK invalide',
        condition: const {
          'metric': 'temperature_c',
          'comparison': 'gt',
          'value': 28,
        },
        actionType: 'fan.set',
        actionParams: const {'percent': 50},
        durationSeconds: 60,
        cooldownSeconds: 900,
        maxRunsPerDay: 5,
      ),
      throwsA(isA<AutomationRuleException>()),
    );
    expect((await repository.getRules(device.id)).single.status, 'failed');
  });
}
