import 'package:flutter_test/flutter_test.dart';
import 'package:garden_journal/core/database/database_helper.dart';
import 'package:garden_journal/features/cameras/data/repositories/camera_data_repository.dart';
import 'package:garden_journal/features/cameras/domain/entities/camera_snapshot.dart';
import 'package:garden_journal/features/sensors/domain/entities/sensor_device.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../../support/database_test_utils.dart';

void main() {
  sqfliteFfiInit();

  test('persiste une caméra de zone et les métadonnées du dernier cliché',
      () async {
    final db = await openMemoryDatabase();
    addTearDown(db.close);
    await DatabaseHelper.instance.createSchemaForTesting(db);
    final repository = CameraDataRepository(database: db);
    final now = DateTime(2026, 8, 20, 12);
    final camera = SensorDevice(
      id: 'cam-01',
      uid: 'cam-01',
      name: 'Caméra principale',
      zoneId: 'zone-main',
      baseUrl: 'https://192.168.0.21:8443',
      status: 'online',
      deviceKind: 'camera',
      transport: 'https',
      createdAt: now,
      updatedAt: now,
    );
    await repository.upsertCamera(camera);
    expect(
      await repository.saveSnapshot(
        CameraSnapshot(
          id: 'snap_1',
          deviceId: camera.id,
          zoneId: camera.zoneId,
          capturedAt: now,
          sha256: List.filled(64, 'b').join(),
          sizeBytes: 2048,
          createdAt: now,
          photoPath: '/private/camera.jpg',
        ),
      ),
      isTrue,
    );

    final cameras = await repository.getCameras();
    final latest = await repository.getLatestSnapshot(camera.id);
    expect(cameras.single.deviceKind, 'camera');
    expect(cameras.single.zoneId, 'zone-main');
    expect(latest?.id, 'snap_1');
    expect(latest?.sha256, List.filled(64, 'b').join());
    expect((await repository.getSavedSnapshots()).single.photoPath,
        '/private/camera.jpg');
    expect(await repository.deleteSnapshot('snap_1'), isTrue);
    expect(await repository.getSavedSnapshots(), isEmpty);
  });
}
