import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../database/database_helper.dart';

class ReproducibleCycleExportService {
  static const schema = 'gardenjournal.cycle_export';
  static const schemaVersion = 1;
  static const maxRecords = 250000;

  final Database? _databaseOverride;
  final Uuid _uuid;
  final DateTime Function() _clock;

  ReproducibleCycleExportService({
    Database? database,
    Uuid uuid = const Uuid(),
    DateTime Function()? clock,
  })  : _databaseOverride = database,
        _uuid = uuid,
        _clock = clock ?? DateTime.now;

  Future<Database> get _database async =>
      _databaseOverride ?? await DatabaseHelper.instance.database;

  Future<CycleExportResult> buildExport({
    required String plantId,
    required DateTime periodStart,
    required DateTime periodEnd,
    bool recordAudit = true,
  }) async {
    final start = _secondsDate(periodStart);
    final end = _secondsDate(periodEnd);
    if (!end.isAfter(start)) {
      throw const CycleExportException(
        'La fin du cycle doit être postérieure au début',
      );
    }
    final db = await _database;
    final plantRows = await db.query(
      'plants',
      where: 'id = ?',
      whereArgs: [plantId],
      limit: 1,
    );
    if (plantRows.isEmpty) {
      throw const CycleExportException('Plante introuvable');
    }
    final plant = plantRows.single;
    final startSeconds = start.millisecondsSinceEpoch ~/ 1000;
    final endSeconds = end.millisecondsSinceEpoch ~/ 1000;

    final placementRows = await db.query(
      'zone_placements',
      where: plant['group_id'] == null
          ? 'plant_id = ?'
          : 'plant_id = ? OR group_id = ?',
      whereArgs:
          plant['group_id'] == null ? [plantId] : [plantId, plant['group_id']],
    );
    final intervals = placementRows
        .where((row) =>
            (row['entered_at'] as int) < endSeconds &&
            ((row['exited_at'] as int?) == null ||
                (row['exited_at'] as int) > startSeconds))
        .map(
          (row) => _CycleInterval(
            placementId: row['id'] as String,
            zoneId: row['zone_id'] as String,
            source: row['plant_id'] == plantId ? 'plant' : 'current_group',
            enteredAt: row['entered_at'] as int,
            exitedAt: row['exited_at'] as int?,
          ),
        )
        .toList()
      ..sort(_compareIntervals);

    final zoneIds = intervals.map((item) => item.zoneId).toSet();
    final zones = zoneIds.isEmpty
        ? <Map<String, Object?>>[]
        : (await db.query(
            'cultivation_zones',
            where: _inClause('id', zoneIds.length),
            whereArgs: zoneIds.toList()..sort(),
          ))
            .map(_zoneSnapshot)
            .toList()
      ..sort((a, b) => (a['id'] as String).compareTo(b['id'] as String));

    final actionPhotoCounts = <String, int>{};
    final actions = <Map<String, Object?>>[];
    for (final row in await db
        .query('actions', where: 'plant_id = ?', whereArgs: [plantId])) {
      final timestamp = DateTime.parse(row['timestamp'] as String).toUtc();
      if (timestamp.isBefore(start) || !timestamp.isBefore(end)) continue;
      actions.add(_actionSnapshot(row));
    }
    actions.sort(_compareTimed('timestamp'));
    if (actions.isNotEmpty) {
      final ids = actions.map((item) => item['id'] as String).toList();
      final photoRows = await db.rawQuery(
        'SELECT action_id, COUNT(*) AS total FROM action_photos '
        'WHERE ${_inClause('action_id', ids.length)} GROUP BY action_id',
        ids,
      );
      for (final row in photoRows) {
        actionPhotoCounts[row['action_id'] as String] = row['total'] as int;
      }
      for (final action in actions) {
        action['photoCount'] = actionPhotoCounts[action['id']] ?? 0;
      }
    }

    final measurements = <Map<String, Object?>>[];
    final measurementDeviceIds = <String>{};
    final relevantDeviceIds = <String>{};
    if (intervals.isNotEmpty) {
      final climateRows = await db.query(
        'sensor_readings',
        where: 'measured_at >= ? AND measured_at < ?',
        whereArgs: [startSeconds, endSeconds],
      );
      for (final row in climateRows) {
        final zoneId = row['zone_id'] as String?;
        final measuredAt = row['measured_at'] as int;
        if (!_matchesInstant(intervals, zoneId, measuredAt)) continue;
        measurementDeviceIds.add(row['device_id'] as String);
        relevantDeviceIds.add(row['device_id'] as String);
        measurements.add(_climateSnapshot(row));
      }
      final genericRows = await db.query(
        'sensor_measurements',
        where: 'measured_at >= ? AND measured_at < ?',
        whereArgs: [startSeconds, endSeconds],
      );
      for (final row in genericRows) {
        final zoneId = row['zone_id'] as String?;
        final measuredAt = row['measured_at'] as int;
        if (!_matchesInstant(intervals, zoneId, measuredAt)) continue;
        measurementDeviceIds.add(row['device_id'] as String);
        relevantDeviceIds.add(row['device_id'] as String);
        measurements.add(_genericMeasurementSnapshot(row));
      }
    }
    measurements.sort(_compareTimed('measuredAt'));

    final currentDeviceZones = <String, String>{};
    if (zoneIds.isNotEmpty) {
      final currentDevices = await db.query(
        'sensor_devices',
        columns: const ['id', 'zone_id'],
        where: _inClause('zone_id', zoneIds.length),
        whereArgs: zoneIds.toList()..sort(),
      );
      for (final row in currentDevices) {
        final id = row['id'] as String;
        relevantDeviceIds.add(id);
        currentDeviceZones[id] = row['zone_id'] as String;
      }
    }

    final alerts = <Map<String, Object?>>[];
    for (final row in await db.query(
      'alert_events',
      where: 'started_at < ? AND (resolved_at IS NULL OR resolved_at >= ?)',
      whereArgs: [endSeconds, startSeconds],
    )) {
      final zoneId = row['zone_id'] as String?;
      final deviceId = row['device_id'] as String?;
      final overlapsZone = _matchesPeriod(
        intervals,
        zoneId,
        row['started_at'] as int,
        row['resolved_at'] as int? ?? endSeconds,
      );
      final relevant = zoneId != null
          ? overlapsZone
          : deviceId != null && relevantDeviceIds.contains(deviceId);
      if (!relevant) {
        continue;
      }
      alerts.add(_alertSnapshot(row));
    }
    alerts.sort(_compareTimed('startedAt'));

    final commands = <Map<String, Object?>>[];
    final automatedCommands = <Map<String, Object?>>[];
    if (relevantDeviceIds.isNotEmpty) {
      final deviceIds = relevantDeviceIds.toList()..sort();
      for (final row in await db.query(
        'device_commands',
        where: '${_inClause('device_id', deviceIds.length)} '
            'AND requested_at >= ? AND requested_at < ?',
        whereArgs: [...deviceIds, startSeconds, endSeconds],
      )) {
        final zoneId = row['zone_id'] as String?;
        final requestedAt = row['requested_at'] as int;
        final association = zoneId != null
            ? (_matchesInstant(intervals, zoneId, requestedAt)
                ? 'zone_snapshot'
                : null)
            : measurementDeviceIds.contains(row['device_id'])
                ? 'measurement_history'
                : _matchesInstant(
                    intervals,
                    currentDeviceZones[row['device_id']],
                    requestedAt,
                  )
                    ? 'current_device_zone'
                    : null;
        if (association != null) {
          commands.add(_commandSnapshot(row, association));
        }
      }
      for (final row in await db.query(
        'automation_executions',
        where: '${_inClause('device_id', deviceIds.length)} '
            'AND executed_at >= ? AND executed_at < ?',
        whereArgs: [...deviceIds, startSeconds, endSeconds],
      )) {
        final executedAt = row['executed_at'] as int;
        final association = measurementDeviceIds.contains(row['device_id'])
            ? 'measurement_history'
            : _matchesInstant(
                intervals,
                currentDeviceZones[row['device_id']],
                executedAt,
              )
                ? 'current_device_zone'
                : null;
        if (association != null) {
          automatedCommands.add(_automationExecutionSnapshot(row, association));
        }
      }
    }
    commands.sort(_compareTimed('requestedAt'));
    automatedCommands.sort(_compareTimed('executedAt'));

    final calibrations = <Map<String, Object?>>[];
    final devices = <Map<String, Object?>>[];
    if (relevantDeviceIds.isNotEmpty) {
      final deviceIds = relevantDeviceIds.toList()..sort();
      for (final row in await db.query(
        'sensor_devices',
        where: _inClause('id', deviceIds.length),
        whereArgs: deviceIds,
      )) {
        devices.add(_deviceSnapshot(row));
      }
      for (final row in await db.query(
        'calibration_records',
        where: '${_inClause('device_id', deviceIds.length)} '
            'AND calibrated_at < ? AND (expires_at IS NULL OR expires_at >= ?)',
        whereArgs: [...deviceIds, endSeconds, startSeconds],
      )) {
        calibrations.add(_calibrationSnapshot(row));
      }
    }
    devices.sort((a, b) => (a['id'] as String).compareTo(b['id'] as String));
    calibrations.sort(_compareTimed('calibratedAt'));

    final counts = <String, int>{
      'actions': actions.length,
      'measurements': measurements.length,
      'alerts': alerts.length,
      'commands': commands.length,
      'automatedCommands': automatedCommands.length,
      'calibrations': calibrations.length,
    };
    final total = counts.values.fold<int>(0, (sum, value) => sum + value);
    if (total > maxRecords) {
      throw const CycleExportException(
        'Cycle trop volumineux : réduisez la période',
      );
    }

    final chronology = <Map<String, Object?>>[
      for (final item in actions)
        _chronologyItem('action', item['id'], item['timestamp']),
      for (final item in measurements)
        _chronologyItem('measurement', item['id'], item['measuredAt']),
      for (final item in alerts)
        _chronologyItem('alert', item['id'], item['startedAt']),
      for (final item in commands)
        _chronologyItem('command', item['id'], item['requestedAt']),
      for (final item in automatedCommands)
        _chronologyItem(
          'automated_command',
          item['id'],
          item['executedAt'],
        ),
    ]..sort((a, b) {
        final byTime = (a['at'] as String).compareTo(b['at'] as String);
        if (byTime != 0) return byTime;
        final byType = (a['type'] as String).compareTo(b['type'] as String);
        if (byType != 0) return byType;
        return (a['id'] as String).compareTo(b['id'] as String);
      });

    final content = <String, Object?>{
      'plant': _plantSnapshot(plant),
      'period': {
        'startInclusive': start.toIso8601String(),
        'endExclusive': end.toIso8601String(),
      },
      'selection': {
        'zonePlacementMode': 'direct_or_current_group_membership',
        'commandDeviceMode': 'measurement_history_or_current_device_zone',
        'placements': intervals.map((item) => item.toJson()).toList(),
        'zones': zones,
        'devices': devices,
      },
      'counts': counts,
      'actions': actions,
      'measurements': measurements,
      'alerts': alerts,
      'commands': commands,
      'automatedCommands': automatedCommands,
      'calibrations': calibrations,
      'chronology': chronology,
    };
    final contentHash =
        sha256.convert(utf8.encode(_canonicalJson(content))).toString();
    final id = _uuid.v4();
    final generatedAt = _clock().toUtc();
    final envelope = <String, Object?>{
      'schema': schema,
      'schemaVersion': schemaVersion,
      'exportId': id,
      'generatedAt': generatedAt.toIso8601String(),
      'contentSha256': contentHash,
      'content': content,
    };
    final bytes = Uint8List.fromList(
      utf8.encode(const JsonEncoder.withIndent('  ').convert(envelope)),
    );
    if (recordAudit) {
      await db.insert('cycle_exports', {
        'id': id,
        'plant_id': plantId,
        'period_start': startSeconds,
        'period_end': endSeconds,
        'schema_version': schemaVersion,
        'content_sha256': contentHash,
        'counts_json': _canonicalJson(counts),
        'created_at': generatedAt.toIso8601String(),
      });
    }
    return CycleExportResult(
      exportId: id,
      plantName: plant['name'] as String,
      contentSha256: contentHash,
      counts: counts,
      bytes: bytes,
    );
  }

  Future<File> shareExport(CycleExportResult result) async {
    final directory = await getTemporaryDirectory();
    final safeName = _safeFileName(result.plantName);
    final file = File(
        '${directory.path}/gardenjournal_cycle_${safeName}_${result.exportId}.json');
    await file.writeAsBytes(result.bytes, flush: true);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'application/json')],
        subject: 'Cycle GardenJournal - ${result.plantName}',
        text: 'Export vérifiable SHA-256 ${result.contentSha256}',
      ),
    );
    return file;
  }

  static CycleExportInspection inspect(Uint8List bytes) {
    if (bytes.isEmpty || bytes.length > 100 * 1024 * 1024) {
      throw const CycleExportException('Taille d’export invalide');
    }
    final raw = jsonDecode(utf8.decode(bytes));
    if (raw is! Map<String, dynamic> ||
        raw['schema'] != schema ||
        raw['schemaVersion'] != schemaVersion ||
        raw['content'] is! Map<String, dynamic> ||
        raw['contentSha256'] is! String) {
      throw const CycleExportException('Format d’export incompatible');
    }
    final content = raw['content'] as Map<String, dynamic>;
    final actual =
        sha256.convert(utf8.encode(_canonicalJson(content))).toString();
    if (actual != raw['contentSha256']) {
      throw const CycleExportException('Empreinte de cycle invalide');
    }
    final rawCounts = content['counts'];
    if (rawCounts is! Map<String, dynamic>) {
      throw const CycleExportException('Comptages absents');
    }
    const sections = {
      'actions': 'actions',
      'measurements': 'measurements',
      'alerts': 'alerts',
      'commands': 'commands',
      'automatedCommands': 'automatedCommands',
      'calibrations': 'calibrations',
    };
    final counts = <String, int>{};
    for (final entry in sections.entries) {
      final values = content[entry.value];
      final expected = rawCounts[entry.key];
      if (values is! List || expected is! int || expected != values.length) {
        throw CycleExportException('Comptage invalide : ${entry.key}');
      }
      counts[entry.key] = expected;
    }
    return CycleExportInspection(
      exportId: raw['exportId'] as String,
      contentSha256: actual,
      counts: counts,
    );
  }

  static DateTime _secondsDate(DateTime value) =>
      DateTime.fromMillisecondsSinceEpoch(
        value.toUtc().millisecondsSinceEpoch ~/ 1000 * 1000,
        isUtc: true,
      );

  static String _inClause(String column, int count) =>
      '$column IN (${List.filled(count, '?').join(',')})';

  static int _compareIntervals(_CycleInterval a, _CycleInterval b) {
    final byTime = a.enteredAt.compareTo(b.enteredAt);
    return byTime != 0 ? byTime : a.placementId.compareTo(b.placementId);
  }

  static int Function(Map<String, Object?>, Map<String, Object?>) _compareTimed(
    String field,
  ) =>
      (a, b) {
        final byTime = (a[field] as String).compareTo(b[field] as String);
        if (byTime != 0) return byTime;
        return (a['id'] as String).compareTo(b['id'] as String);
      };

  static bool _matchesInstant(
    List<_CycleInterval> intervals,
    String? zoneId,
    int at,
  ) =>
      zoneId != null &&
      intervals.any((item) =>
          item.zoneId == zoneId &&
          item.enteredAt <= at &&
          (item.exitedAt == null || at < item.exitedAt!));

  static bool _matchesPeriod(
    List<_CycleInterval> intervals,
    String? zoneId,
    int start,
    int end,
  ) =>
      zoneId != null &&
      intervals.any((item) =>
          item.zoneId == zoneId &&
          item.enteredAt < end &&
          (item.exitedAt == null || item.exitedAt! > start));

  static Map<String, Object?> _plantSnapshot(Map<String, Object?> row) => {
        'id': row['id'],
        'name': row['name'],
        'variety': row['variety'],
        'pottingDate': _isoDate(row['potting_date']),
        'cultureType': row['culture_type'],
        'potSize': row['pot_size'],
        'groupId': row['group_id'],
        'location': row['location'],
        'containerType': row['container_type'],
        'origin': row['origin'],
        'isHarvested': row['is_harvested'] == 1,
      };

  static Map<String, Object?> _zoneSnapshot(Map<String, Object?> row) => {
        'id': row['id'],
        'name': row['name'],
        'type': row['type'],
        'targetProfile': jsonDecode(row['target_profile'] as String),
      };

  static Map<String, Object?> _deviceSnapshot(Map<String, Object?> row) => {
        'id': row['id'],
        'uid': row['uid'],
        'name': row['name'],
        'zoneId': row['zone_id'],
        'deviceKind': row['device_kind'],
        'transport': row['transport'],
        'model': row['model'],
        'hardwareVersion': row['hardware_version'],
        'firmwareVersion': row['firmware_version'],
      };

  static Map<String, Object?> _actionSnapshot(Map<String, Object?> row) => {
        'id': row['id'],
        'type': row['action_type'],
        'timestamp': _isoDate(row['timestamp']),
        'quantity': row['quantity'],
        'quantityUnit': row['quantity_unit'],
        'ph': row['ph'],
        'phNotApplicable': row['ph_na'] == 1,
        'tds': row['tds'],
        'tdsNotApplicable': row['tds_na'] == 1,
        'productUsed': row['product_used'],
        'pruningType': row['pruning_type'],
        'notes': row['notes'],
        'parentPlantId': row['parent_plant_id'],
        'cuttingNotes': row['cutting_notes'],
        'repotContainerType': row['repot_container_type'],
        'isWateringCombined': row['is_watering_combined'] == 1,
        'harvestWeightFresh': row['harvest_weight_fresh'],
        'harvestWeightStored': row['harvest_weight_stored'],
        'harvestWeightWaste': row['harvest_weight_waste'],
        'status': row['status'],
        'completedAt': _optionalIsoDate(row['completed_at']),
      };

  static Map<String, Object?> _climateSnapshot(Map<String, Object?> row) => {
        'id': row['id'],
        'source': 'climate',
        'deviceId': row['device_id'],
        'zoneId': row['zone_id'],
        'measuredAt': _secondsIso(row['measured_at']),
        'values': {
          'temperature_c': {'value': row['temperature_c'], 'unit': '°C'},
          'humidity_percent': {'value': row['humidity_percent'], 'unit': '%'},
          'vpd_kpa': {'value': row['vpd_kpa'], 'unit': 'kPa'},
          if (row['dew_point_c'] != null)
            'dew_point_c': {'value': row['dew_point_c'], 'unit': '°C'},
          'mist_on': {'value': row['mist_on'] == 1},
          if (row['fan_percent'] != null)
            'fan_percent': {'value': row['fan_percent'], 'unit': '%'},
          if (row['light_on'] != null)
            'light_on': {'value': row['light_on'] == 1},
          if (row['water_low'] != null)
            'water_low': {'value': row['water_low'] == 1},
          if (row['rssi'] != null)
            'rssi_dbm': {'value': row['rssi'], 'unit': 'dBm'},
        },
      };

  static Map<String, Object?> _genericMeasurementSnapshot(
    Map<String, Object?> row,
  ) =>
      {
        'id': row['id'],
        'source': 'generic',
        'deviceId': row['device_id'],
        'zoneId': row['zone_id'],
        'measuredAt': _secondsIso(row['measured_at']),
        'metric': row['capability_key'],
        'valueType': row['value_type'],
        'value': row['numeric_value'] ??
            row['text_value'] ??
            (row['boolean_value'] == null ? null : row['boolean_value'] == 1),
        'unit': row['unit'],
        'quality': row['quality'],
      };

  static Map<String, Object?> _alertSnapshot(Map<String, Object?> row) => {
        'id': row['id'],
        'ruleId': row['rule_id'],
        'deviceId': row['device_id'],
        'zoneId': row['zone_id'],
        'metric': row['metric_key'],
        'severity': row['severity'],
        'message': row['message'],
        'observedValue': row['observed_value'],
        'startedAt': _secondsIso(row['started_at']),
        'lastObservedAt': _secondsIso(row['last_observed_at']),
        'resolvedAt': _optionalSecondsIso(row['resolved_at']),
        'acknowledgedAt': _optionalSecondsIso(row['acknowledged_at']),
        'notificationSentAt': _optionalSecondsIso(row['notification_sent_at']),
      };

  static Map<String, Object?> _commandSnapshot(
    Map<String, Object?> row,
    String zoneAssociation,
  ) =>
      {
        'id': row['id'],
        'deviceId': row['device_id'],
        'zoneId': row['zone_id'],
        'zoneAssociation': zoneAssociation,
        'type': row['command_type'],
        'params': jsonDecode(row['params_json'] as String),
        'idempotencyKey': row['idempotency_key'],
        'safetyClass': row['safety_class'],
        'requestedAt': _secondsIso(row['requested_at']),
        'expiresAt': _secondsIso(row['expires_at']),
        'status': row['status'],
        'nodeAckAt': _optionalSecondsIso(row['node_ack_at']),
        'errorCode': row['error_code'],
      };

  static Map<String, Object?> _automationExecutionSnapshot(
    Map<String, Object?> row,
    String zoneAssociation,
  ) =>
      {
        'id': row['id'],
        'ruleId': row['rule_id'],
        'deviceId': row['device_id'],
        'zoneAssociation': zoneAssociation,
        'executedAt': _secondsIso(row['executed_at']),
        'commandId': row['command_id'],
        'observedValues': jsonDecode(row['observed_values_json'] as String),
        'status': row['status'],
        'errorCode': row['error_code'],
      };

  static Map<String, Object?> _calibrationSnapshot(Map<String, Object?> row) =>
      {
        'id': row['id'],
        'deviceId': row['device_id'],
        'metric': row['capability_key'],
        'type': row['calibration_type'],
        'calibratedAt': _secondsIso(row['calibrated_at']),
        'referenceValues': jsonDecode(row['reference_values_json'] as String),
        'coefficients': jsonDecode(row['coefficients_json'] as String),
        'temperatureC': row['temperature_c'],
        'expiresAt': _optionalSecondsIso(row['expires_at']),
        'nodeAckAt': _secondsIso(row['node_ack_at']),
        'nodeConfigHash': row['node_config_hash'],
      };

  static Map<String, Object?> _chronologyItem(
    String type,
    Object? id,
    Object? at,
  ) =>
      {'type': type, 'id': id, 'at': at};

  static String _isoDate(Object? value) =>
      DateTime.parse(value as String).toUtc().toIso8601String();

  static String? _optionalIsoDate(Object? value) =>
      value == null ? null : _isoDate(value);

  static String _secondsIso(Object? value) =>
      DateTime.fromMillisecondsSinceEpoch(
        (value as int) * 1000,
        isUtc: true,
      ).toIso8601String();

  static String? _optionalSecondsIso(Object? value) =>
      value == null ? null : _secondsIso(value);

  static String _safeFileName(String value) {
    final safe = value
        .trim()
        .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    return safe.isEmpty ? 'plante' : safe;
  }

  static String _canonicalJson(Object? value) {
    Object? normalize(Object? input) {
      if (input is Map) {
        final keys = input.keys.map((key) => key.toString()).toList()..sort();
        return {for (final key in keys) key: normalize(input[key])};
      }
      if (input is List) return input.map(normalize).toList();
      return input;
    }

    return jsonEncode(normalize(value));
  }
}

class CycleExportResult {
  final String exportId;
  final String plantName;
  final String contentSha256;
  final Map<String, int> counts;
  final Uint8List bytes;

  const CycleExportResult({
    required this.exportId,
    required this.plantName,
    required this.contentSha256,
    required this.counts,
    required this.bytes,
  });
}

class CycleExportInspection {
  final String exportId;
  final String contentSha256;
  final Map<String, int> counts;

  const CycleExportInspection({
    required this.exportId,
    required this.contentSha256,
    required this.counts,
  });
}

class CycleExportException implements Exception {
  final String message;

  const CycleExportException(this.message);

  @override
  String toString() => message;
}

class _CycleInterval {
  final String placementId;
  final String zoneId;
  final String source;
  final int enteredAt;
  final int? exitedAt;

  const _CycleInterval({
    required this.placementId,
    required this.zoneId,
    required this.source,
    required this.enteredAt,
    required this.exitedAt,
  });

  Map<String, Object?> toJson() => {
        'placementId': placementId,
        'zoneId': zoneId,
        'source': source,
        'enteredAt': ReproducibleCycleExportService._secondsIso(enteredAt),
        'exitedAt':
            ReproducibleCycleExportService._optionalSecondsIso(exitedAt),
      };
}
