import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../config/app_config.dart';
import '../database/database_helper.dart';
import '../../features/observations/domain/entities/observation_assessment.dart';
import 'photo_storage_service.dart';

class GardenJournalBackupService {
  static const formatVersion = 1;
  static const _maximumBackupBytes = 250 * 1024 * 1024;
  static const _tableIntroducedInVersion = <String, int>{
    'sensor_device_capabilities': 11,
    'sensor_measurements': 11,
    'device_health_snapshots': 12,
    'calibration_records': 13,
    'alert_rules': 13,
    'alert_evaluation_states': 13,
    'alert_events': 13,
    'device_commands': 14,
    'node_schedules': 14,
    'gateway_configs': 15,
    'gateway_messages': 15,
    'gateway_nodes': 16,
    'lora_packets': 16,
    'ota_device_states': 17,
    'ota_updates': 17,
    'automation_rules': 18,
    'automation_executions': 18,
    'cycle_exports': 19,
    'camera_snapshots': 22,
    'zone_photos': 24,
    'observation_assessments': 25,
  };
  static const _tables = <String>[
    'groups',
    'plants',
    'observation_assessments',
    'actions',
    'action_photos',
    'cultivation_zones',
    'zone_photos',
    'sensor_devices',
    'camera_snapshots',
    'device_health_snapshots',
    'calibration_records',
    'alert_rules',
    'alert_evaluation_states',
    'alert_events',
    'device_commands',
    'node_schedules',
    'gateway_configs',
    'gateway_messages',
    'gateway_nodes',
    'lora_packets',
    'ota_device_states',
    'ota_updates',
    'automation_rules',
    'automation_executions',
    'cycle_exports',
    'sensor_device_capabilities',
    'sensor_readings',
    'sensor_measurements',
    'zone_placements',
    'devices',
  ];
  static const _insertOrder = <String>[
    'groups',
    'plants',
    'observation_assessments',
    'actions',
    'action_photos',
    'cultivation_zones',
    'zone_photos',
    'sensor_devices',
    'camera_snapshots',
    'device_health_snapshots',
    'calibration_records',
    'alert_rules',
    'alert_evaluation_states',
    'alert_events',
    'device_commands',
    'node_schedules',
    'gateway_configs',
    'gateway_messages',
    'gateway_nodes',
    'lora_packets',
    'ota_device_states',
    'ota_updates',
    'automation_rules',
    'automation_executions',
    'cycle_exports',
    'sensor_device_capabilities',
    'sensor_readings',
    'sensor_measurements',
    'zone_placements',
    'devices',
  ];
  static const _deleteOrder = <String>[
    'observation_assessments',
    'zone_photos',
    'action_photos',
    'actions',
    'zone_placements',
    'alert_events',
    'gateway_messages',
    'lora_packets',
    'ota_updates',
    'cycle_exports',
    'automation_executions',
    'automation_rules',
    'ota_device_states',
    'gateway_nodes',
    'alert_evaluation_states',
    'alert_rules',
    'calibration_records',
    'node_schedules',
    'device_commands',
    'gateway_configs',
    'camera_snapshots',
    'device_health_snapshots',
    'sensor_measurements',
    'sensor_readings',
    'sensor_device_capabilities',
    'sensor_devices',
    'devices',
    'plants',
    'groups',
    'cultivation_zones',
  ];

  final Database? _databaseOverride;
  final Directory? _documentsOverride;
  final String appVersion;
  final Uuid _uuid;
  final Future<void> Function()? beforeImportCommit;
  final Future<void> Function(Iterable<String>, Directory)?
      obsoletePhotoCleanup;

  GardenJournalBackupService({
    Database? database,
    Directory? documentsDirectory,
    this.appVersion = AppConfig.appVersion,
    Uuid? uuid,
    this.beforeImportCommit,
    this.obsoletePhotoCleanup,
  })  : _databaseOverride = database,
        _documentsOverride = documentsDirectory,
        _uuid = uuid ?? const Uuid();

  Future<Database> get _database async =>
      _databaseOverride ?? await DatabaseHelper.instance.database;

  Future<Directory> get _documents async =>
      _documentsOverride ?? await getApplicationDocumentsDirectory();

  Future<BackupInspection> inspectBackup(File source) async {
    final validated = await _readAndValidateBackup(source);
    for (final rawFile in validated.files) {
      _decodePhoto(rawFile);
    }
    return BackupInspection(
      createdAt: validated.createdAt,
      appVersion: validated.appVersion,
      databaseVersion: validated.databaseVersion,
      tableCounts: {
        for (final entry in validated.tables.entries)
          entry.key: entry.value.length,
      },
      photoCount: validated.files.length,
      sourceBytes: await source.length(),
      warnings: validated.warnings,
    );
  }

  Future<BackupExportResult> exportBackup({File? destination}) async {
    final db = await _database;
    final documents = await _documents;
    final errors = <String>[];
    final tableData = <String, List<Map<String, Object?>>>{};
    await db.transaction((txn) async {
      for (final table in _tables) {
        tableData[table] = (await txn.query(table))
            .map((row) => Map<String, Object?>.from(row))
            .toList();
      }
    });

    final files = <Map<String, Object?>>[];
    final photoTokens = <String, String>{};
    final missingPaths = <String>{};
    final referencedPaths = <String>{
      ...tableData['plants']!
          .map((row) => row['photo_path'])
          .whereType<String>(),
      ...tableData['action_photos']!
          .map((row) => row['photo_path'])
          .whereType<String>(),
      ...tableData['camera_snapshots']!
          .map((row) => row['photo_path'])
          .whereType<String>(),
      ...tableData['zone_photos']!
          .map((row) => row['photo_path'])
          .whereType<String>(),
    };
    for (final photoPath in referencedPaths) {
      final file = File(photoPath);
      if (!await file.exists()) {
        missingPaths.add(photoPath);
        errors.add('Photo absente: ${path.basename(photoPath)}');
        continue;
      }
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) {
        missingPaths.add(photoPath);
        errors.add('Photo vide: ${path.basename(photoPath)}');
        continue;
      }
      final token =
          'backup://photo-${files.length}${_safeExtension(photoPath)}';
      photoTokens[photoPath] = token;
      files.add({
        'token': token,
        'length': bytes.length,
        'sha256': sha256.convert(bytes).toString(),
        'data': base64Encode(bytes),
      });
    }

    for (final plant in tableData['plants']!) {
      final photoPath = plant['photo_path'];
      if (photoPath is String) plant['photo_path'] = photoTokens[photoPath];
    }
    tableData['action_photos'] = tableData['action_photos']!
        .where((row) => !missingPaths.contains(row['photo_path']))
        .map((row) {
      final copy = Map<String, Object?>.from(row);
      copy['photo_path'] = photoTokens[row['photo_path']];
      return copy;
    }).toList();
    for (final snapshot in tableData['camera_snapshots']!) {
      final photoPath = snapshot['photo_path'];
      if (photoPath is String) {
        snapshot['photo_path'] = photoTokens[photoPath];
      }
    }
    tableData['zone_photos'] = tableData['zone_photos']!
        .where((row) => !missingPaths.contains(row['photo_path']))
        .map((row) => Map<String, Object?>.from(row)
          ..['photo_path'] = photoTokens[row['photo_path']])
        .toList();

    final createdAt = DateTime.now().toUtc();
    final payload = <String, Object?>{
      'manifest': {
        'formatVersion': formatVersion,
        'createdAt': createdAt.toIso8601String(),
        'appVersion': appVersion,
        'databaseVersion': DatabaseHelper.currentVersion,
        'tables': {
          for (final entry in tableData.entries) entry.key: entry.value.length,
        },
        'files': files
            .map((file) => {
                  'token': file['token'],
                  'length': file['length'],
                  'sha256': file['sha256'],
                })
            .toList(),
        'errors': errors,
      },
      'tables': tableData,
      'files': files,
    };
    final payloadBytes = utf8.encode(jsonEncode(payload));
    final envelope = jsonEncode({
      'checksum': sha256.convert(payloadBytes).toString(),
      'payload': base64Encode(payloadBytes),
    });
    if (utf8.encode(envelope).length > _maximumBackupBytes) {
      throw const BackupException('Sauvegarde trop volumineuse');
    }

    final output = destination ??
        File(path.join(
          documents.path,
          'backups',
          _backupFileName(createdAt),
        ));
    await output.parent.create(recursive: true);
    final temporary = File('${output.path}.partial-${_uuid.v4()}');
    await temporary.writeAsString(envelope, flush: true);
    if (!await _verifyEnvelope(temporary)) {
      await temporary.delete();
      throw const BackupException('Vérification de la sauvegarde échouée');
    }
    if (await output.exists()) await output.delete();
    await temporary.rename(output.path);
    return BackupExportResult(file: output, warnings: errors);
  }

  Future<BackupImportResult> importBackup(File source) async {
    final validated = await _readAndValidateBackup(source);
    final rawFiles = validated.files;
    final tables = {
      for (final entry in validated.tables.entries)
        entry.key:
            entry.value.map((row) => Map<String, Object?>.from(row)).toList(),
    };

    final documents = await _documents;
    final photoRoot =
        Directory(path.join(documents.path, 'gardenjournal_photos'));
    final safetyBackup = File(path.join(
      documents.path,
      'backups',
      'pre_import_${_backupFileName(DateTime.now().toUtc())}',
    ));
    final safetyExport = await exportBackup(destination: safetyBackup);

    final tokenPaths = <String, String>{};
    final createdPhotos = <String>[];
    final importWarnings = <String>[...safetyExport.warnings];
    var databaseCommitted = false;
    final staging =
        await Directory.systemTemp.createTemp('gardenjournal-import-');
    try {
      for (final rawFile in rawFiles) {
        final token = rawFile['token'] as String;
        final bytes = _decodePhoto(rawFile);
        final staged = File(path.join(
          staging.path,
          '${_uuid.v4()}${_safeExtension(token)}',
        ));
        await staged.writeAsBytes(bytes, flush: true);
        final stored = await PhotoStorageService.persistImage(
          staged.path,
          bucket: 'restored',
          rootDirectory: photoRoot,
        );
        tokenPaths[token] = stored;
        createdPhotos.add(stored);
      }

      for (final plant in tables['plants']!) {
        final token = plant['photo_path'];
        if (token != null) {
          plant['photo_path'] = _requiredPhotoPath(token, tokenPaths);
        }
      }
      for (final photo in tables['action_photos']!) {
        photo['photo_path'] = _requiredPhotoPath(
          photo['photo_path'],
          tokenPaths,
        );
      }
      for (final snapshot in tables['camera_snapshots']!) {
        final token = snapshot['photo_path'];
        if (token != null) {
          snapshot['photo_path'] = _requiredPhotoPath(token, tokenPaths);
        }
      }
      for (final photo in tables['zone_photos']!) {
        photo['photo_path'] =
            _requiredPhotoPath(photo['photo_path'], tokenPaths);
      }

      final db = await _database;
      final oldPhotoPaths = await _allPhotoPaths(db);
      await db.transaction((txn) async {
        for (final table in _deleteOrder) {
          await txn.delete(table);
        }
        for (final table in _insertOrder) {
          for (final row in tables[table]!) {
            await txn.insert(
              table,
              row,
              conflictAlgorithm: ConflictAlgorithm.abort,
            );
          }
          final count = Sqflite.firstIntValue(
                await txn.rawQuery('SELECT COUNT(*) FROM $table'),
              ) ??
              0;
          if (count != tables[table]!.length) {
            throw BackupException('Restauration incomplète de $table');
          }
        }
        if (beforeImportCommit != null) await beforeImportCommit!();
        final foreignKeys = await txn.rawQuery('PRAGMA foreign_key_check');
        if (foreignKeys.isNotEmpty) {
          throw const BackupException('Relations restaurées invalides');
        }
      });
      databaseCommitted = true;

      final currentPaths = tokenPaths.values.toSet();
      final obsolete =
          oldPhotoPaths.where((item) => !currentPaths.contains(item));
      try {
        if (obsoletePhotoCleanup != null) {
          await obsoletePhotoCleanup!(obsolete, photoRoot);
        } else {
          await PhotoStorageService.deleteManagedFiles(
            obsolete,
            rootDirectory: photoRoot,
          );
        }
      } on PhotoCleanupException catch (error, stackTrace) {
        importWarnings.add(error.toString());
        developer.log(
          'Nettoyage incomplet après restauration validée',
          name: 'gardenjournal.backup',
          error: error,
          stackTrace: stackTrace,
        );
      }
      return BackupImportResult(
        safetyBackup: safetyBackup,
        warnings: importWarnings,
        restoredTables: {
          for (final entry in tables.entries) entry.key: entry.value.length,
        },
      );
    } catch (error, stackTrace) {
      if (!databaseCommitted) {
        try {
          await PhotoStorageService.deleteManagedFiles(
            createdPhotos,
            rootDirectory: photoRoot,
          );
        } catch (cleanupError, cleanupStackTrace) {
          developer.log(
            'Nettoyage incomplet après échec de restauration',
            name: 'gardenjournal.backup',
            error: cleanupError,
            stackTrace: cleanupStackTrace,
          );
        }
      }
      Error.throwWithStackTrace(error, stackTrace);
    } finally {
      if (await staging.exists()) await staging.delete(recursive: true);
    }
  }

  Future<_ValidatedBackup> _readAndValidateBackup(File source) async {
    if (!await source.exists()) {
      throw const BackupException('Fichier de sauvegarde introuvable');
    }
    final length = await source.length();
    if (length <= 0 || length > _maximumBackupBytes) {
      throw const BackupException('Taille de sauvegarde invalide');
    }

    final decoded = await _decodeAndVerify(source);
    final manifest = decoded['manifest'];
    if (manifest is! Map<String, dynamic>) {
      throw const BackupException('Manifeste absent');
    }
    if (manifest['formatVersion'] != formatVersion) {
      throw BackupException(
        'Version de sauvegarde incompatible: ${manifest['formatVersion']}',
      );
    }
    final databaseVersion = manifest['databaseVersion'];
    if (databaseVersion is! int ||
        databaseVersion < 1 ||
        databaseVersion > DatabaseHelper.currentVersion) {
      throw BackupException(
        'Version de base incompatible: $databaseVersion',
      );
    }
    final createdAtRaw = manifest['createdAt'];
    final createdAt = createdAtRaw is String
        ? DateTime.tryParse(createdAtRaw)?.toUtc()
        : null;
    final appVersion = manifest['appVersion'];
    if (createdAt == null ||
        appVersion is! String ||
        appVersion.trim().isEmpty) {
      throw const BackupException('Métadonnées de sauvegarde invalides');
    }

    final rawTables = decoded['tables'];
    final rawFiles = decoded['files'];
    final manifestTables = manifest['tables'];
    final manifestFiles = manifest['files'];
    final rawWarnings = manifest['errors'] ?? const <dynamic>[];
    if (rawTables is! Map<String, dynamic> ||
        rawFiles is! List<dynamic> ||
        manifestTables is! Map<String, dynamic> ||
        manifestFiles is! List<dynamic> ||
        rawWarnings is! List<dynamic> ||
        rawWarnings.any((item) => item is! String)) {
      throw const BackupException('Contenu de sauvegarde incomplet');
    }

    final warnings = rawWarnings.cast<String>().toList();
    final tables = <String, List<Map<String, Object?>>>{};
    for (final table in _tables) {
      final rawRows = rawTables[table];
      final introducedIn = _tableIntroducedInVersion[table];
      if (rawRows == null &&
          introducedIn != null &&
          databaseVersion < introducedIn) {
        tables[table] = [];
        continue;
      }
      if (rawRows is! List<dynamic>) {
        throw BackupException('Table absente de la sauvegarde: $table');
      }
      final rows = <Map<String, Object?>>[];
      for (final rawRow in rawRows) {
        if (rawRow is! Map<String, dynamic>) {
          throw BackupException('Ligne invalide dans $table');
        }
        rows.add(Map<String, Object?>.from(rawRow));
      }
      if (manifestTables[table] is! int ||
          manifestTables[table] != rows.length) {
        throw BackupException('Comptage invalide pour $table');
      }
      tables[table] = rows;
    }

    for (final row in tables['observation_assessments']!) {
      try {
        ObservationAssessment.fromMap(row).validate();
      } catch (_) {
        throw const BackupException(
            'Observation de plante invalide dans la sauvegarde');
      }
    }

    final files = <Map<String, dynamic>>[];
    final fileTokens = <String>{};
    for (final rawFile in rawFiles) {
      if (rawFile is! Map<String, dynamic>) {
        throw const BackupException('Entrée photo invalide');
      }
      final token = rawFile['token'];
      final data = rawFile['data'];
      final expectedLength = rawFile['length'];
      final expectedHash = rawFile['sha256'];
      if (token is! String ||
          !_isBackupPhotoToken(token) ||
          data is! String ||
          expectedLength is! int ||
          expectedLength <= 0 ||
          expectedHash is! String ||
          !RegExp(r'^[a-f0-9]{64}$').hasMatch(expectedHash)) {
        throw const BackupException('Métadonnées photo invalides');
      }
      if (!fileTokens.add(token)) {
        throw BackupException('Photo dupliquée dans la sauvegarde: $token');
      }
      files.add(rawFile);
    }

    if (manifestFiles.length != files.length) {
      throw const BackupException('Manifeste photo incohérent');
    }
    final manifestFileTokens = <String>{};
    for (final rawManifestFile in manifestFiles) {
      if (rawManifestFile is! Map<String, dynamic>) {
        throw const BackupException('Manifeste photo invalide');
      }
      final token = rawManifestFile['token'];
      if (token is! String || !manifestFileTokens.add(token)) {
        throw const BackupException('Manifeste photo dupliqué');
      }
      final rawFileIndex = files.indexWhere((item) => item['token'] == token);
      if (rawFileIndex < 0 ||
          rawManifestFile['length'] != files[rawFileIndex]['length'] ||
          rawManifestFile['sha256'] != files[rawFileIndex]['sha256']) {
        throw BackupException('Manifeste photo incohérent: $token');
      }
    }

    final referencedTokens = <String>{};
    for (final plant in tables['plants']!) {
      final token = plant['photo_path'];
      if (token == null) continue;
      if (token is! String || !_isBackupPhotoToken(token)) {
        throw BackupException('Référence photo de plante invalide: $token');
      }
      referencedTokens.add(token);
    }
    for (final photo in tables['action_photos']!) {
      final token = photo['photo_path'];
      if (token is! String || !_isBackupPhotoToken(token)) {
        throw BackupException('Référence photo d’action invalide: $token');
      }
      referencedTokens.add(token);
    }
    for (final snapshot in tables['camera_snapshots']!) {
      final token = snapshot['photo_path'];
      if (token == null) continue;
      if (token is! String || !_isBackupPhotoToken(token)) {
        throw BackupException('Référence photo de caméra invalide: $token');
      }
      referencedTokens.add(token);
    }
    for (final photo in tables['zone_photos']!) {
      final token = photo['photo_path'];
      if (token is! String || !_isBackupPhotoToken(token)) {
        throw BackupException('Référence photo d’espace invalide: $token');
      }
      referencedTokens.add(token);
    }
    final missingTokens = referencedTokens.difference(fileTokens);
    if (missingTokens.isNotEmpty) {
      throw BackupException(
        'Photo référencée absente: ${missingTokens.first}',
      );
    }
    final unusedTokens = fileTokens.difference(referencedTokens);
    if (unusedTokens.isNotEmpty) {
      throw BackupException(
        'Photo non référencée dans la sauvegarde: ${unusedTokens.first}',
      );
    }

    return _ValidatedBackup(
      createdAt: createdAt,
      appVersion: appVersion,
      databaseVersion: databaseVersion,
      warnings: warnings,
      tables: tables,
      files: files,
    );
  }

  List<int> _decodePhoto(Map<String, dynamic> rawFile) {
    final token = rawFile['token'] as String;
    try {
      final bytes = base64Decode(rawFile['data'] as String);
      if (bytes.length != rawFile['length'] ||
          sha256.convert(bytes).toString() != rawFile['sha256']) {
        throw BackupException('Photo corrompue: $token');
      }
      return bytes;
    } on BackupException {
      rethrow;
    } on FormatException {
      throw BackupException('Photo corrompue: $token');
    }
  }

  bool _isBackupPhotoToken(String token) =>
      RegExp(r'^backup://photo-[a-zA-Z0-9_-]+(?:\.[a-z0-9]{1,8})?$')
          .hasMatch(token);

  Future<Map<String, dynamic>> _decodeAndVerify(File source) async {
    try {
      final envelope = jsonDecode(await source.readAsString());
      if (envelope is! Map<String, dynamic> ||
          envelope['checksum'] is! String ||
          envelope['payload'] is! String) {
        throw const BackupException('Enveloppe de sauvegarde invalide');
      }
      final payloadBytes = base64Decode(envelope['payload'] as String);
      if (sha256.convert(payloadBytes).toString() != envelope['checksum']) {
        throw const BackupException('Checksum de sauvegarde invalide');
      }
      final payload = jsonDecode(utf8.decode(payloadBytes));
      if (payload is! Map<String, dynamic>) {
        throw const BackupException('Payload de sauvegarde invalide');
      }
      return payload;
    } on BackupException {
      rethrow;
    } on FormatException catch (error) {
      throw BackupException('Sauvegarde corrompue: ${error.message}');
    }
  }

  Future<bool> _verifyEnvelope(File file) async {
    try {
      await inspectBackup(file);
      return true;
    } on BackupException {
      return false;
    }
  }

  Future<Set<String>> _allPhotoPaths(DatabaseExecutor db) async {
    final rows = await db.rawQuery('''
      SELECT photo_path FROM plants WHERE photo_path IS NOT NULL
      UNION SELECT photo_path FROM action_photos
      UNION SELECT photo_path FROM camera_snapshots WHERE photo_path IS NOT NULL
      UNION SELECT photo_path FROM zone_photos
    ''');
    return rows.map((row) => row['photo_path'] as String).toSet();
  }

  String _requiredPhotoPath(
    Object? token,
    Map<String, String> tokenPaths,
  ) {
    if (token is! String || tokenPaths[token] == null) {
      throw BackupException('Référence photo inconnue: $token');
    }
    return tokenPaths[token]!;
  }

  static String _backupFileName(DateTime date) {
    String two(int value) => value.toString().padLeft(2, '0');
    String three(int value) => value.toString().padLeft(3, '0');
    return 'gardenjournal_backup_${date.year}${two(date.month)}${two(date.day)}_'
        '${two(date.hour)}${two(date.minute)}${two(date.second)}'
        '${three(date.millisecond)}${three(date.microsecond)}'
        '.gardenjournal-backup.json';
  }

  static String _safeExtension(String value) {
    final extension = path.extension(value).toLowerCase();
    return RegExp(r'^\.[a-z0-9]{1,8}$').hasMatch(extension)
        ? extension
        : '.jpg';
  }
}

class BackupExportResult {
  final File file;
  final List<String> warnings;

  const BackupExportResult({required this.file, required this.warnings});
}

class BackupInspection {
  final DateTime createdAt;
  final String appVersion;
  final int databaseVersion;
  final Map<String, int> tableCounts;
  final int photoCount;
  final int sourceBytes;
  final List<String> warnings;

  const BackupInspection({
    required this.createdAt,
    required this.appVersion,
    required this.databaseVersion,
    required this.tableCounts,
    required this.photoCount,
    required this.sourceBytes,
    required this.warnings,
  });
}

class BackupImportResult {
  final File safetyBackup;
  final List<String> warnings;
  final Map<String, int> restoredTables;

  const BackupImportResult({
    required this.safetyBackup,
    required this.warnings,
    required this.restoredTables,
  });
}

class _ValidatedBackup {
  final DateTime createdAt;
  final String appVersion;
  final int databaseVersion;
  final List<String> warnings;
  final Map<String, List<Map<String, Object?>>> tables;
  final List<Map<String, dynamic>> files;

  const _ValidatedBackup({
    required this.createdAt,
    required this.appVersion,
    required this.databaseVersion,
    required this.warnings,
    required this.tables,
    required this.files,
  });
}

class BackupException implements Exception {
  final String message;

  const BackupException(this.message);

  @override
  String toString() => message;
}
