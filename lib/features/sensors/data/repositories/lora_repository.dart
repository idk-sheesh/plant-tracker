import 'dart:convert';

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/database/database_helper.dart';
import '../../domain/entities/lora_packet.dart';

class GatewayNodeLink {
  final String gatewayId;
  final String nodeDeviceId;
  final String loraAddress;
  final String? lastSessionId;
  final int lastFrameCounter;
  final String status;

  const GatewayNodeLink({
    required this.gatewayId,
    required this.nodeDeviceId,
    required this.loraAddress,
    this.lastSessionId,
    this.lastFrameCounter = -1,
    this.status = 'active',
  });

  factory GatewayNodeLink.fromMap(Map<String, dynamic> map) => GatewayNodeLink(
        gatewayId: map['gateway_id'] as String,
        nodeDeviceId: map['node_device_id'] as String,
        loraAddress: map['lora_address'] as String,
        lastSessionId: map['last_session_id'] as String?,
        lastFrameCounter: map['last_frame_counter'] as int? ?? -1,
        status: map['status'] as String,
      );
}

enum LoRaReservationStatus { reserved, duplicate, replay, unknownNode }

class LoRaReservation {
  final LoRaReservationStatus status;
  final String packetId;
  final GatewayNodeLink? link;

  const LoRaReservation(this.status, this.packetId, this.link);
}

class LoRaRepository {
  final DatabaseHelper _databaseHelper;
  final Database? _database;
  final Uuid _uuid;

  LoRaRepository({
    DatabaseHelper? databaseHelper,
    Database? database,
    Uuid uuid = const Uuid(),
  })  : _databaseHelper = databaseHelper ?? DatabaseHelper.instance,
        _database = database,
        _uuid = uuid;

  Future<Database> get _db async {
    if (_database != null) return _database;
    return _databaseHelper.database;
  }

  Future<void> linkNode({
    required String gatewayId,
    required String nodeDeviceId,
    required String loraAddress,
  }) async {
    final db = await _db;
    final now = DateTime.now();
    await db.insert(
      'gateway_nodes',
      {
        'gateway_id': gatewayId,
        'node_device_id': nodeDeviceId,
        'lora_address': loraAddress,
        'protocol_version': 1,
        'last_frame_counter': -1,
        'joined_at': now.toUtc().millisecondsSinceEpoch ~/ 1000,
        'status': 'active',
        'created_at': now.toUtc().toIso8601String(),
        'updated_at': now.toUtc().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  Future<List<GatewayNodeLink>> getLinks(String gatewayId) async {
    final db = await _db;
    final rows = await db.query(
      'gateway_nodes',
      where: 'gateway_id = ?',
      whereArgs: [gatewayId],
      orderBy: 'lora_address ASC',
    );
    return rows.map(GatewayNodeLink.fromMap).toList();
  }

  Future<GatewayNodeLink?> getLinkForNode(String nodeDeviceId) async {
    final db = await _db;
    final rows = await db.query(
      'gateway_nodes',
      where: 'node_device_id = ? AND status = ?',
      whereArgs: [nodeDeviceId, 'active'],
      limit: 1,
    );
    return rows.isEmpty ? null : GatewayNodeLink.fromMap(rows.single);
  }

  Future<LoRaReservation> reserveFrame({
    required String gatewayId,
    required LoRaFrame frame,
    required String payloadHash,
    required DateTime receivedAt,
  }) async {
    final db = await _db;
    return db.transaction((txn) async {
      final linkRows = await txn.query(
        'gateway_nodes',
        where: 'gateway_id = ? AND lora_address = ? AND status = ?',
        whereArgs: [gatewayId, frame.nodeId, 'active'],
        limit: 1,
      );
      final link =
          linkRows.isEmpty ? null : GatewayNodeLink.fromMap(linkRows.single);
      final existingRows = await txn.query(
        'lora_packets',
        where: 'gateway_id = ? AND node_uid = ? AND session_id = ? '
            'AND frame_counter = ? AND status IN (?, ?)',
        whereArgs: [
          gatewayId,
          frame.nodeId,
          frame.sessionId,
          frame.frameCounter,
          'processing',
          'accepted',
        ],
        limit: 1,
      );
      if (existingRows.isNotEmpty &&
          existingRows.single['payload_hash'] == payloadHash) {
        return LoRaReservation(
          LoRaReservationStatus.duplicate,
          existingRows.single['id'] as String,
          link,
        );
      }
      final packetId = _uuid.v4();
      if (link == null) {
        await _insertPacket(
          txn,
          id: packetId,
          gatewayId: gatewayId,
          frame: frame,
          payloadHash: payloadHash,
          receivedAt: receivedAt,
          status: 'unknown_node',
          errorCode: 'node_not_linked',
        );
        return LoRaReservation(
            LoRaReservationStatus.unknownNode, packetId, null);
      }
      final counterIsReplay = link.lastSessionId == frame.sessionId &&
          frame.frameCounter <= link.lastFrameCounter;
      if (existingRows.isNotEmpty || counterIsReplay) {
        await _insertPacket(
          txn,
          id: packetId,
          gatewayId: gatewayId,
          nodeDeviceId: link.nodeDeviceId,
          frame: frame,
          payloadHash: payloadHash,
          receivedAt: receivedAt,
          status: 'replay',
          errorCode: 'frame_counter_replay',
        );
        return LoRaReservation(LoRaReservationStatus.replay, packetId, link);
      }
      await _insertPacket(
        txn,
        id: packetId,
        gatewayId: gatewayId,
        nodeDeviceId: link.nodeDeviceId,
        frame: frame,
        payloadHash: payloadHash,
        receivedAt: receivedAt,
        status: 'processing',
      );
      return LoRaReservation(LoRaReservationStatus.reserved, packetId, link);
    });
  }

  Future<void> acceptFrame(
    LoRaReservation reservation,
    LoRaFrame frame,
    DateTime receivedAt,
  ) async {
    final link = reservation.link!;
    final db = await _db;
    await db.transaction((txn) async {
      await txn.update(
        'lora_packets',
        {'status': 'accepted'},
        where: 'id = ? AND status = ?',
        whereArgs: [reservation.packetId, 'processing'],
      );
      await txn.update(
        'gateway_nodes',
        {
          'last_session_id': frame.sessionId,
          'last_frame_counter': frame.frameCounter,
          'last_seen_at': receivedAt.toUtc().millisecondsSinceEpoch ~/ 1000,
          'updated_at': receivedAt.toUtc().toIso8601String(),
        },
        where: 'gateway_id = ? AND node_device_id = ?',
        whereArgs: [link.gatewayId, link.nodeDeviceId],
      );
    });
  }

  Future<void> rejectFrame(String packetId, Object error) async {
    final db = await _db;
    await db.update(
      'lora_packets',
      {
        'status': 'rejected',
        'error_code': error.runtimeType.toString(),
      },
      where: 'id = ? AND status = ?',
      whereArgs: [packetId, 'processing'],
    );
  }

  Future<void> _insertPacket(
    DatabaseExecutor db, {
    required String id,
    required String gatewayId,
    String? nodeDeviceId,
    required LoRaFrame frame,
    required String payloadHash,
    required DateTime receivedAt,
    required String status,
    String? errorCode,
  }) {
    return db.insert('lora_packets', {
      'id': id,
      'gateway_id': gatewayId,
      'node_device_id': nodeDeviceId,
      'node_uid': frame.nodeId,
      'session_id': frame.sessionId,
      'frame_counter': frame.frameCounter,
      'sent_at': frame.sentAt.toUtc().millisecondsSinceEpoch ~/ 1000,
      'received_at': receivedAt.toUtc().millisecondsSinceEpoch ~/ 1000,
      'rssi': frame.rssi,
      'snr': frame.snr,
      'payload_hash': payloadHash,
      'status': status,
      'error_code': errorCode,
      'raw_json': jsonEncode(frame.canonicalPayload),
      'created_at': receivedAt.toUtc().toIso8601String(),
    });
  }
}
