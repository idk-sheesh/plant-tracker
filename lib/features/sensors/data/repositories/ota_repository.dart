import 'package:sqflite/sqflite.dart';

import '../../../../core/database/database_helper.dart';
import '../../domain/entities/ota_update.dart';

class OtaRepository {
  static const buildKeyId = String.fromEnvironment('OTA_KEY_ID');
  static const buildPublicKey =
      String.fromEnvironment('OTA_ED25519_PUBLIC_KEY');

  final DatabaseHelper _databaseHelper;
  final Database? _database;

  OtaRepository({DatabaseHelper? databaseHelper, Database? database})
      : _databaseHelper = databaseHelper ?? DatabaseHelper.instance,
        _database = database;

  Future<Database> get _db async {
    if (_database != null) return _database;
    return _databaseHelper.database;
  }

  Future<void> ensureBuildKey({DateTime? validFrom}) async {
    if (buildKeyId.isEmpty || buildPublicKey.isEmpty) return;
    await storeBuildKey(OtaTrustedKey(
      keyId: buildKeyId,
      publicKeyBase64: buildPublicKey,
      validFrom: validFrom ?? DateTime.utc(2026, 1, 1),
    ));
  }

  Future<void> storeBuildKey(OtaTrustedKey key) async {
    final db = await _db;
    final existing = await db.query(
      'ota_trusted_keys',
      where: 'key_id = ?',
      whereArgs: [key.keyId],
      limit: 1,
    );
    if (existing.isNotEmpty &&
        existing.single['public_key_base64'] != key.publicKeyBase64) {
      throw StateError('Une clé OTA existante ne peut pas être remplacée');
    }
    await db.insert(
      'ota_trusted_keys',
      key.toMap(),
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<OtaTrustedKey?> getKey(String keyId) async {
    final db = await _db;
    final rows = await db.query(
      'ota_trusted_keys',
      where: 'key_id = ?',
      whereArgs: [keyId],
      limit: 1,
    );
    return rows.isEmpty ? null : OtaTrustedKey.fromMap(rows.single);
  }

  Future<void> saveDeviceState(OtaDeviceState state) async {
    final db = await _db;
    await db.insert(
      'ota_device_states',
      state.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<OtaDeviceState?> getDeviceState(String deviceId) async {
    final db = await _db;
    final rows = await db.query(
      'ota_device_states',
      where: 'device_id = ?',
      whereArgs: [deviceId],
      limit: 1,
    );
    return rows.isEmpty ? null : OtaDeviceState.fromMap(rows.single);
  }

  Future<void> insertUpdate(OtaUpdateRecord update) async {
    final db = await _db;
    await db.insert(
      'ota_updates',
      update.toMap(),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  Future<void> updateStatus(
    String id, {
    required String status,
    DateTime? requestedAt,
    DateTime? nodeAckAt,
    String? errorCode,
    required DateTime updatedAt,
  }) async {
    final db = await _db;
    await db.update(
      'ota_updates',
      {
        'status': status,
        if (requestedAt != null)
          'requested_at': requestedAt.toUtc().millisecondsSinceEpoch ~/ 1000,
        if (nodeAckAt != null)
          'node_ack_at': nodeAckAt.toUtc().millisecondsSinceEpoch ~/ 1000,
        'error_code': errorCode,
        'updated_at': updatedAt.toUtc().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<OtaUpdateRecord?> getUpdate(String id) async {
    final db = await _db;
    final rows = await db.query(
      'ota_updates',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : OtaUpdateRecord.fromMap(rows.single);
  }

  Future<List<OtaUpdateRecord>> getUpdates(String deviceId) async {
    final db = await _db;
    final rows = await db.query(
      'ota_updates',
      where: 'device_id = ?',
      whereArgs: [deviceId],
      orderBy: 'created_at DESC',
    );
    return rows.map(OtaUpdateRecord.fromMap).toList();
  }
}
