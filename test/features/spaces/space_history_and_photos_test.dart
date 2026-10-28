import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:garden_journal/core/database/database_helper.dart';
import 'package:garden_journal/features/sensors/data/repositories/sensor_data_repository.dart';
import 'package:garden_journal/features/sensors/domain/entities/sensor_device.dart';
import 'package:garden_journal/features/sensors/domain/entities/sensor_reading.dart';
import 'package:garden_journal/features/spaces/data/repositories/zone_photo_repository.dart';
import 'package:garden_journal/features/spaces/data/repositories/zone_placement_repository.dart';
import 'package:garden_journal/features/spaces/presentation/providers/space_provider.dart';

import '../../support/database_test_utils.dart';

void main() {
  test('détacher une plante conserve sa période et les relevés de son espace',
      () async {
    final db = await openMemoryDatabase();
    addTearDown(db.close);
    await DatabaseHelper.instance.createSchemaForTesting(db);
    final start = DateTime.utc(2026, 10, 1);
    await db.insert('plants', {
      'id': 'plant',
      'name': 'FJ',
      'potting_date': start.toIso8601String(),
      'culture_type': 'terre',
      'qr_code': 'plant:plant',
      'created_at': start.toIso8601String(),
      'updated_at': start.toIso8601String()
    });
    final placements = ZonePlacementRepository(database: db);
    final data = SensorDataRepository(database: db);
    final spaces = SpaceProvider(
        placementRepository: placements, sensorDataRepository: data);
    addTearDown(spaces.dispose);
    final placement = await placements.movePlant(
        plantId: 'plant',
        plantName: 'FJ',
        zoneId: 'zone-main',
        enteredAt: start);
    final device = SensorDevice(
        id: 'node',
        uid: 'node',
        name: 'Serre',
        zoneId: 'zone-main',
        baseUrl: 'http://192.168.1.10',
        createdAt: start,
        updatedAt: start);
    await data.upsertDevice(device);
    final end = start.add(const Duration(days: 2));
    await data.insertReadings(device, [
      for (final date in [
        start.subtract(const Duration(hours: 1)),
        start,
        end,
        end.add(const Duration(hours: 1))
      ])
        SensorReading(
            deviceId: device.id,
            zoneId: 'zone-main',
            temperature: 24,
            humidity: 60,
            vpd: 1.2,
            timestamp: date,
            mistOn: false),
    ]);
    await placements.closePlacement(placement, exitedAt: end);
    final history = await spaces.historyForPlant('plant');
    expect(history.single.exitedAt, end.toLocal());
    expect(await placements.getActive(), isEmpty);
    final readings = await spaces.climateReadingsBetween(
        'zone-main', history.single.enteredAt,
        end: history.single.exitedAt);
    expect(readings.map((item) => item.timestamp.toUtc()), [start]);
    expect(await db.query('sensor_readings'), hasLength(4));
  });

  test('photo copiée dans le stockage privé, triée et rollback si zone absente',
      () async {
    final db = await openMemoryDatabase();
    addTearDown(db.close);
    await DatabaseHelper.instance.createSchemaForTesting(db);
    final fixtures = Directory('.dart_tool/test-fixtures');
    await fixtures.create(recursive: true);
    final temp = await fixtures.createTemp('space-photos-');
    addTearDown(() => temp.delete(recursive: true));
    final source = File('${temp.path}/gallery.jpg');
    await source.writeAsBytes([1, 2, 3]);
    final root = Directory('${temp.path}/managed');
    final spaces = SpaceProvider(
        photoRepository: ZonePhotoRepository(database: db), photoRoot: root);
    addTearDown(spaces.dispose);
    final photo = await spaces.addZonePhoto(
        zoneId: 'zone-main',
        sourcePath: source.path,
        capturedAt: DateTime.utc(2026, 10, 1),
        caption: '  Vue de la serre  ');
    expect(photo.caption, 'Vue de la serre');
    expect(await File(photo.photoPath).readAsBytes(), [1, 2, 3]);
    await source.delete();
    expect(await File(photo.photoPath).exists(), isTrue);
    await spaces.addZonePhoto(
        zoneId: 'zone-main',
        sourcePath: photo.photoPath,
        capturedAt: DateTime.utc(2026, 10, 2));
    expect((await spaces.photosForZone('zone-main')).first.capturedAt.toUtc(),
        DateTime.utc(2026, 10, 2));
    final filesBefore =
        await root.list(recursive: true).where((item) => item is File).length;
    final another = File('${temp.path}/another.jpg');
    await another.writeAsBytes([4, 5, 6]);
    await expectLater(
        spaces.addZonePhoto(zoneId: 'missing-zone', sourcePath: another.path),
        throwsA(anything));
    expect(
        await root.list(recursive: true).where((item) => item is File).length,
        filesBefore);
    expect(await another.exists(), isTrue);
  });
}
