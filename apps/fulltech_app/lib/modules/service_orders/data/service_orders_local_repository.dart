import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

import '../../../core/storage/resilient_local_database.dart';
import '../../../core/models/user_model.dart';
import '../../clientes/cliente_model.dart';
import '../service_order_models.dart';

final serviceOrdersLocalRepositoryProvider =
    Provider<ServiceOrdersLocalRepository>((ref) {
      return ServiceOrdersLocalRepository();
    });

class ServiceOrdersLocalSnapshot {
  const ServiceOrdersLocalSnapshot({
    required this.orders,
    required this.clientsById,
    required this.usersById,
    this.lastSyncedAt,
  });

  final List<ServiceOrderModel> orders;
  final Map<String, ClienteModel> clientsById;
  final Map<String, UserModel> usersById;
  final DateTime? lastSyncedAt;
}

class ServiceOrdersLocalRepository {
  static const _dbName = 'operations_local.db';
  static const _dbVersion = 1;
  static const _ordersTable = 'operations_orders';
  static const _clientsTable = 'operations_clients';
  static const _usersTable = 'operations_users';
  static const _metaTable = 'operations_meta';
  static const _lastSyncedAtKey = 'last_synced_at';

  Database? _database;
  ServiceOrdersLocalSnapshot? _memorySnapshot;

  Future<Database> get _db async {
    if (_database != null) return _database!;
    _database = await openResilientLocalDatabase(
      fileName: _dbName,
      version: _dbVersion,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE $_ordersTable (
            id TEXT PRIMARY KEY,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            payload TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE $_clientsTable (
            id TEXT PRIMARY KEY,
            payload TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE $_usersTable (
            id TEXT PRIMARY KEY,
            payload TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE $_metaTable (
            key TEXT PRIMARY KEY,
            value TEXT
          )
        ''');
      },
    );
    return _database!;
  }

  Future<ServiceOrdersLocalSnapshot> readSnapshot() async {
    final memorySnapshot = _memorySnapshot;
    if (memorySnapshot != null) {
      return memorySnapshot;
    }

    if (kIsWeb) {
      return const ServiceOrdersLocalSnapshot(
        orders: [],
        clientsById: {},
        usersById: {},
      );
    }

    final db = await _db;
    final orderRows = await db.query(_ordersTable, orderBy: 'created_at DESC');
    final clientRows = await db.query(_clientsTable);
    final userRows = await db.query(_usersTable);
    final metaRows = await db.query(
      _metaTable,
      where: 'key = ?',
      whereArgs: [_lastSyncedAtKey],
      limit: 1,
    );

    final snapshot = ServiceOrdersLocalSnapshot(
      orders: orderRows
          .map((row) => _decodeMap(row['payload']))
          .whereType<Map<String, dynamic>>()
          .map(ServiceOrderModel.fromJson)
          .toList(growable: false),
      clientsById: {
        for (final row in clientRows)
          if (((row['id'] ?? '').toString()).isNotEmpty)
            (row['id'] ?? '').toString(): ClienteModel.fromJson(
              _decodeMap(row['payload']) ?? const <String, dynamic>{},
            ),
      },
      usersById: {
        for (final row in userRows)
          if (((row['id'] ?? '').toString()).isNotEmpty)
            (row['id'] ?? '').toString(): UserModel.fromJson(
              _decodeMap(row['payload']) ?? const <String, dynamic>{},
            ),
      },
      lastSyncedAt: metaRows.isEmpty
          ? null
          : DateTime.tryParse((metaRows.first['value'] ?? '').toString()),
    );
    _memorySnapshot = snapshot;
    return snapshot;
  }

  Future<ServiceOrderModel?> readOrder(String id) async {
    if (kIsWeb) {
      final snapshot = await readSnapshot();
      for (final order in snapshot.orders) {
        if (order.id == id) return order;
      }
      return null;
    }

    final db = await _db;
    final rows = await db.query(
      _ordersTable,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final payload = _decodeMap(rows.first['payload']);
    if (payload == null) return null;
    return ServiceOrderModel.fromJson(payload);
  }

  Future<void> saveSnapshot({
    required List<ServiceOrderModel> orders,
    required Map<String, ClienteModel> clientsById,
    required Map<String, UserModel> usersById,
  }) async {
    _memorySnapshot = ServiceOrdersLocalSnapshot(
      orders: orders.toList(growable: false),
      clientsById: Map<String, ClienteModel>.from(clientsById),
      usersById: Map<String, UserModel>.from(usersById),
      lastSyncedAt: DateTime.now(),
    );

    if (kIsWeb) {
      return;
    }

    final db = await _db;
    await db.transaction((txn) async {
      await txn.delete(_ordersTable);
      for (final order in orders) {
        await txn.insert(_ordersTable, {
          'id': order.id,
          'created_at': order.createdAt.toIso8601String(),
          'updated_at': order.updatedAt.toIso8601String(),
          'payload': jsonEncode(order.toJson()),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }

      await txn.delete(_clientsTable);
      for (final entry in clientsById.entries) {
        await txn.insert(_clientsTable, {
          'id': entry.key,
          'payload': jsonEncode(entry.value.toJson()),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }

      await txn.delete(_usersTable);
      for (final entry in usersById.entries) {
        await txn.insert(_usersTable, {
          'id': entry.key,
          'payload': jsonEncode(entry.value.toJson()),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }

      await txn.insert(_metaTable, {
        'key': _lastSyncedAtKey,
        'value': DateTime.now().toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  Future<void> saveOrder({
    required ServiceOrderModel order,
    ClienteModel? client,
    Map<String, UserModel> usersById = const {},
  }) async {
    if (kIsWeb) {
      final snapshot = await readSnapshot();
      final nextOrders = [...snapshot.orders];
      final index = nextOrders.indexWhere((item) => item.id == order.id);
      if (index >= 0) {
        nextOrders[index] = order;
      } else {
        nextOrders.add(order);
      }
      final nextClients = Map<String, ClienteModel>.from(snapshot.clientsById);
      final effectiveClient = client ?? order.client;
      if (effectiveClient != null) {
        nextClients[effectiveClient.id] = effectiveClient;
      }
      final nextUsers = Map<String, UserModel>.from(snapshot.usersById)
        ..addAll(usersById);
      _memorySnapshot = ServiceOrdersLocalSnapshot(
        orders: nextOrders,
        clientsById: nextClients,
        usersById: nextUsers,
        lastSyncedAt: DateTime.now(),
      );
      return;
    }

    final db = await _db;
    await db.transaction((txn) async {
      await txn.insert(_ordersTable, {
        'id': order.id,
        'created_at': order.createdAt.toIso8601String(),
        'updated_at': order.updatedAt.toIso8601String(),
        'payload': jsonEncode(order.toJson()),
      }, conflictAlgorithm: ConflictAlgorithm.replace);

      final effectiveClient = client ?? order.client;
      if (effectiveClient != null) {
        await txn.insert(_clientsTable, {
          'id': effectiveClient.id,
          'payload': jsonEncode(effectiveClient.toJson()),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }

      for (final entry in usersById.entries) {
        await txn.insert(_usersTable, {
          'id': entry.key,
          'payload': jsonEncode(entry.value.toJson()),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  Future<void> deleteOrder(String id) async {
    if (kIsWeb) {
      final snapshot = await readSnapshot();
      _memorySnapshot = ServiceOrdersLocalSnapshot(
        orders: snapshot.orders.where((item) => item.id != id).toList(growable: false),
        clientsById: snapshot.clientsById,
        usersById: snapshot.usersById,
        lastSyncedAt: snapshot.lastSyncedAt,
      );
      return;
    }

    final db = await _db;
    await db.delete(_ordersTable, where: 'id = ?', whereArgs: [id]);
  }

  Future<Map<String, UserModel>> readUsersById() async {
    if (kIsWeb) {
      return Map<String, UserModel>.from((await readSnapshot()).usersById);
    }

    final db = await _db;
    final rows = await db.query(_usersTable);
    return {
      for (final row in rows)
        if (((row['id'] ?? '').toString()).isNotEmpty)
          (row['id'] ?? '').toString(): UserModel.fromJson(
            _decodeMap(row['payload']) ?? const <String, dynamic>{},
          ),
    };
  }

  Future<ClienteModel?> readClientById(String id) async {
    if (kIsWeb) {
      return (await readSnapshot()).clientsById[id];
    }

    final db = await _db;
    final rows = await db.query(
      _clientsTable,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final payload = _decodeMap(rows.first['payload']);
    if (payload == null) return null;
    return ClienteModel.fromJson(payload);
  }

  Map<String, dynamic>? _decodeMap(Object? raw) {
    final value = (raw ?? '').toString();
    if (value.trim().isEmpty) return null;
    final decoded = jsonDecode(value);
    if (decoded is Map) return decoded.cast<String, dynamic>();
    return null;
  }
}
