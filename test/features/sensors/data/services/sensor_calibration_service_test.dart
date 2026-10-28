import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:garden_journal/core/database/database_helper.dart';
import 'package:garden_journal/features/sensors/data/repositories/calibration_repository.dart';
import 'package:garden_journal/features/sensors/data/repositories/sensor_repository.dart';
import 'package:garden_journal/features/sensors/data/services/sensor_calibration_service.dart';
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
      id: 'node-cal',
      uid: 'node-cal',
      name: 'Nœud calibration',
      zoneId: 'zone-main',
      baseUrl: 'http://192.168.1.42',
      createdAt: now,
      updatedAt: now,
    );
    await db.insert('sensor_devices', device.toMap());
    return (db, device);
  }

  test('archive seulement une calibration acquittée par le nœud', () async {
    final (db, device) = await setup();
    addTearDown(db.close);
    late Map<String, dynamic> body;
    final remote = SensorRepository(client: MockClient((request) async {
      body = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response('{}', 204);
    }));
    final local = CalibrationRepository(database: db);
    final service = SensorCalibrationService(
      remote: remote,
      local: local,
      clock: () => now,
    );

    final record = await service.calibrate(
      device: device,
      capabilityKey: 'ph',
      calibrationType: 'two_point',
      referenceValues: const {'point2': 7, 'point1': 4.01},
      coefficients: const {'offset': 0.1, 'slope': 0.99},
      operatorName: 'Beta',
    );

    expect(body['calibration'], isA<Map>());
    expect(record.nodeConfigHash, hasLength(64));
    expect(await local.getForDevice(device.id), hasLength(1));
  });

  test('n’écrit rien si le nœud refuse la calibration', () async {
    final (db, device) = await setup();
    addTearDown(db.close);
    final local = CalibrationRepository(database: db);
    final service = SensorCalibrationService(
      remote: SensorRepository(
        client: MockClient((_) async => http.Response('{}', 500)),
      ),
      local: local,
      clock: () => now,
    );

    await expectLater(
      service.calibrate(
        device: device,
        capabilityKey: 'ec',
        calibrationType: 'single_point',
        referenceValues: const {'point1': 1.41},
        coefficients: const {'slope': 1},
      ),
      throwsException,
    );
    expect(await local.getForDevice(device.id), isEmpty);
  });
}
