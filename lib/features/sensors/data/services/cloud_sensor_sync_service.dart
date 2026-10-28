import '../../domain/entities/sensor_device.dart';
import '../../domain/entities/sensor_reading.dart';
import '../repositories/cloud_sensor_repository.dart';
import '../repositories/sensor_data_repository.dart';

class CloudSensorSyncService {
  final CloudSensorRepository _remote;
  final SensorDataRepository _data;

  const CloudSensorSyncService({
    required CloudSensorRepository remote,
    required SensorDataRepository data,
  })  : _remote = remote,
        _data = data;

  Future<CloudSyncResult> synchronize(SensorDevice device) async {
    final cloudDeviceId = device.cloudDeviceId ?? device.uid;
    try {
      final since = await _data.getLastMeasuredAtSeconds(device.id);
      var cursor = device.cloudCursor;
      DateTime? lastContactAt;
      var received = 0;
      var inserted = 0;
      // The API serves at most 500 events per page. Bound one foreground sync
      // while continuing from the persisted cursor on the next refresh.
      for (var pageIndex = 0; pageIndex < 8; pageIndex++) {
        final page = await _remote.fetchReadings(
          cloudDeviceId,
          since: since,
          cursor: cursor,
        );
        if (page.readings.isNotEmpty &&
            (page.nextCursor == null || page.nextCursor == cursor)) {
          throw const FormatException('Curseur cloud non progressif');
        }
        final normalized = page.readings
            .map(
              (reading) => reading.copyWith(
                deviceId: device.id,
                zoneId: device.zoneId,
              ),
            )
            .toList(growable: false);
        received += normalized.length;
        inserted += await _data.insertReadings(
          device,
          normalized,
          markLocalOnline: false,
        );
        cursor = page.nextCursor ?? cursor;
        lastContactAt =
            page.lastContactAt ?? _latestTimestamp(normalized) ?? lastContactAt;
        await _data.recordCloudSyncSuccess(
          device.id,
          cloudDeviceId: cloudDeviceId,
          cursor: cursor,
          lastContactAt: lastContactAt,
        );
        if (page.readings.length < 500) break;
      }
      return CloudSyncResult(
        deviceId: device.id,
        received: received,
        inserted: inserted,
        nextCursor: cursor,
        lastContactAt: lastContactAt,
      );
    } catch (error) {
      await _data.recordCloudSyncFailure(device.id, '$error');
      rethrow;
    }
  }

  static DateTime? _latestTimestamp(Iterable<SensorReading> readings) {
    DateTime? latest;
    for (final reading in readings) {
      if (latest == null || reading.timestamp.isAfter(latest)) {
        latest = reading.timestamp;
      }
    }
    return latest;
  }
}

class CloudSyncResult {
  final String deviceId;
  final int received;
  final int inserted;
  final String? nextCursor;
  final DateTime? lastContactAt;

  const CloudSyncResult({
    required this.deviceId,
    required this.received,
    required this.inserted,
    required this.nextCursor,
    required this.lastContactAt,
  });
}
