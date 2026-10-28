import 'package:sqflite/sqflite.dart';

import '../../../../core/database/database_helper.dart';
import '../../domain/entities/gateway.dart';

class GatewayRepository {
  final DatabaseHelper _databaseHelper;
  final Database? _database;

  GatewayRepository({DatabaseHelper? databaseHelper, Database? database})
      : _databaseHelper = databaseHelper ?? DatabaseHelper.instance,
        _database = database;

  Future<Database> get _db async {
    if (_database != null) return _database;
    return _databaseHelper.database;
  }

  Future<void> saveConfig(GatewayConfig config) async {
    final db = await _db;
    await db.transaction((txn) async {
      final existing = await txn.query(
        'gateway_configs',
        columns: const ['id'],
        where: 'device_id = ?',
        whereArgs: [config.deviceId],
        limit: 1,
      );
      if (existing.isEmpty) {
        await txn.insert(
          'gateway_configs',
          config.toMap(),
          conflictAlgorithm: ConflictAlgorithm.abort,
        );
        return;
      }
      if (existing.single['id'] != config.id) {
        throw StateError('Identité de configuration gateway incohérente');
      }
      await txn.update(
        'gateway_configs',
        config.toMap(),
        where: 'id = ?',
        whereArgs: [config.id],
      );
    });
  }

  Future<GatewayConfig?> getConfigForDevice(String deviceId) async {
    final db = await _db;
    final rows = await db.query(
      'gateway_configs',
      where: 'device_id = ?',
      whereArgs: [deviceId],
      limit: 1,
    );
    return rows.isEmpty ? null : GatewayConfig.fromMap(rows.single);
  }

  Future<List<GatewayConfig>> getConfigs() async {
    final db = await _db;
    final rows = await db.query('gateway_configs', orderBy: 'updated_at DESC');
    return rows.map(GatewayConfig.fromMap).toList();
  }

  Future<GatewayConfig?> getConfig(String id) async {
    final db = await _db;
    final rows = await db.query(
      'gateway_configs',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : GatewayConfig.fromMap(rows.single);
  }

  Future<GatewayMessageRecord?> getMessage(
    String gatewayId,
    String messageId,
  ) async {
    final db = await _db;
    final rows = await db.query(
      'gateway_messages',
      where: 'gateway_id = ? AND message_id = ?',
      whereArgs: [gatewayId, messageId],
      limit: 1,
    );
    return rows.isEmpty ? null : GatewayMessageRecord.fromMap(rows.single);
  }

  /// Retourne l'identifiant de la réservation à traiter, ou `null` quand le
  /// même message a déjà été accepté.
  ///
  /// Une réservation interrompue ou rejetée est réouverte afin qu'une erreur
  /// temporaire du traitement ne transforme pas la déduplication en perte.
  Future<String?> reserveMessage(GatewayMessageRecord record) async {
    final db = await _db;
    return db.transaction((txn) async {
      final rows = await txn.query(
        'gateway_messages',
        where: 'gateway_id = ? AND message_id = ?',
        whereArgs: [record.gatewayId, record.messageId],
        limit: 1,
      );
      if (rows.isNotEmpty) {
        final existing = GatewayMessageRecord.fromMap(rows.single);
        if (existing.payloadHash != record.payloadHash) {
          throw const FormatException('Collision d’identifiant gateway');
        }
        if (existing.status == 'accepted') return null;
        final changed = await txn.update(
          'gateway_messages',
          {
            'transport': record.transport,
            'topic': record.topic,
            'sent_at': record.toMap()['sent_at'],
            'received_at': record.toMap()['received_at'],
            'status': 'processing',
            'error_code': null,
            'payload_json': record.payloadJson,
          },
          where: 'id = ?',
          whereArgs: [existing.id],
        );
        if (changed != 1) {
          throw StateError('Réservation gateway non actualisée');
        }
        return existing.id;
      }
      await txn.insert('gateway_messages', record.toMap());
      return record.id;
    });
  }

  Future<void> storeRejectedMessage(GatewayMessageRecord record) async {
    final db = await _db;
    await db.transaction((txn) async {
      final rows = await txn.query(
        'gateway_messages',
        where: 'gateway_id = ? AND message_id = ?',
        whereArgs: [record.gatewayId, record.messageId],
        limit: 1,
      );
      if (rows.isNotEmpty) {
        final existing = GatewayMessageRecord.fromMap(rows.single);
        if (existing.payloadHash != record.payloadHash) {
          throw const FormatException('Collision d’identifiant gateway');
        }
        return;
      }
      await txn.insert('gateway_messages', record.toMap());
    });
  }

  Future<void> finishMessage(
    String id, {
    required String status,
    String? errorCode,
  }) async {
    final db = await _db;
    final changed = await db.update(
      'gateway_messages',
      {'status': status, 'error_code': errorCode},
      where: 'id = ?',
      whereArgs: [id],
    );
    if (changed != 1) throw StateError('Message gateway introuvable');
  }

  Future<void> updateCursor(String id, int cursor) async {
    final db = await _db;
    await db.update(
      'gateway_configs',
      {
        'last_http_cursor': cursor,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<GatewayMessageRecord>> getMessages(String gatewayId) async {
    final db = await _db;
    final rows = await db.query(
      'gateway_messages',
      where: 'gateway_id = ?',
      whereArgs: [gatewayId],
      orderBy: 'received_at DESC',
      limit: 200,
    );
    return rows.map(GatewayMessageRecord.fromMap).toList();
  }
}
