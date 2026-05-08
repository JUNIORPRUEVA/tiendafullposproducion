import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

import '../../../core/storage/resilient_local_database.dart';
import '../models/wa_crm_conversation.dart';
import '../models/wa_crm_message.dart';

final waCrmLocalCacheProvider = Provider<WaCrmLocalCache>((ref) {
  return WaCrmLocalCache();
});

class WaCrmLocalCache {
  static const _dbName = 'wa_crm_cache.db';
  static const _dbVersion = 1;

  Future<Database>? _dbFuture;

  Future<Database> get _db {
    return _dbFuture ??= openResilientLocalDatabase(
      fileName: _dbName,
      version: _dbVersion,
      onCreate: _create,
    );
  }

  Future<void> _create(Database db, int version) async {
    await db.execute('''
      CREATE TABLE wa_crm_users (
        id TEXT PRIMARY KEY,
        sort_order INTEGER NOT NULL DEFAULT 0,
        json TEXT NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE wa_crm_instances (
        id TEXT PRIMARY KEY,
        json TEXT NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE wa_crm_conversations (
        id TEXT PRIMARY KEY,
        user_id TEXT NOT NULL,
        instance_id TEXT NOT NULL,
        merge_key TEXT NOT NULL,
        last_message_at INTEGER NOT NULL DEFAULT 0,
        json TEXT NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE wa_crm_messages (
        id TEXT PRIMARY KEY,
        conversation_id TEXT NOT NULL,
        sent_at INTEGER NOT NULL DEFAULT 0,
        media_storage_key TEXT,
        media_status TEXT,
        json TEXT NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE wa_crm_meta (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_wa_crm_conversations_user_activity ON wa_crm_conversations(user_id, last_message_at DESC)',
    );
    await db.execute(
      'CREATE INDEX idx_wa_crm_messages_conversation_sent ON wa_crm_messages(conversation_id, sent_at ASC)',
    );
  }

  Future<List<Map<String, dynamic>>> getUserRows() async {
    final db = await _db;
    final rows = await db.query('wa_crm_users', orderBy: 'sort_order ASC');
    return rows
        .map((row) => _decode(row['json']))
        .where((row) {
          final nestedUser = row['user'];
          return (row['id'] ?? (nestedUser is Map ? nestedUser['id'] : null)) !=
              null;
        })
        .toList(growable: false);
  }

  Future<void> saveUserRows(List<Map<String, dynamic>> users) async {
    final db = await _db;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.transaction((tx) async {
      for (var i = 0; i < users.length; i++) {
        final user = users[i];
        final userId = _stringValue(
          user['id'] ?? (user['user'] as Map?)?['id'],
        );
        if (userId == null || userId.isEmpty) continue;
        await tx.insert('wa_crm_users', {
          'id': userId,
          'sort_order': i,
          'json': jsonEncode(user),
          'updated_at': now,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await _setMetaTx(
        tx,
        'users:lastSyncAt',
        DateTime.now().toIso8601String(),
      );
    });
  }

  Future<List<Map<String, dynamic>>> getInstanceRows() async {
    final db = await _db;
    final rows = await db.query('wa_crm_instances', orderBy: 'updated_at DESC');
    return rows
        .map((row) => _decode(row['json']))
        .where((row) => _stringValue(row['id'])?.isNotEmpty == true)
        .toList(growable: false);
  }

  Future<void> saveInstanceRows(List<Map<String, dynamic>> instances) async {
    final db = await _db;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.transaction((tx) async {
      for (final item in instances) {
        final id = _stringValue(item['id']);
        if (id == null || id.isEmpty) continue;
        await tx.insert('wa_crm_instances', {
          'id': id,
          'json': jsonEncode(item),
          'updated_at': now,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await _setMetaTx(
        tx,
        'instances:lastSyncAt',
        DateTime.now().toIso8601String(),
      );
    });
  }

  Future<List<WaCrmConversation>> getConversations(String userId) async {
    final db = await _db;
    final rows = await db.query(
      'wa_crm_conversations',
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'last_message_at DESC, updated_at DESC',
      limit: 120,
    );
    return rows
        .map((row) => WaCrmConversation.fromJson(_decode(row['json'])))
        .where((conv) => conv.id.isNotEmpty)
        .toList(growable: false);
  }

  Future<void> saveConversations(
    String userId,
    List<WaCrmConversation> conversations,
  ) async {
    final db = await _db;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.transaction((tx) async {
      for (final conv in conversations) {
        await _upsertConversationTx(tx, userId, conv, now);
      }
      final cursor = _latestConversationCursor(conversations);
      if (cursor != null) {
        await _setMetaTx(
          tx,
          'conversations:$userId:lastSyncAt',
          cursor.toIso8601String(),
        );
      }
    });
  }

  Future<void> upsertConversation(
    String userId,
    WaCrmConversation conversation,
  ) async {
    final db = await _db;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.transaction((tx) async {
      await _upsertConversationTx(tx, userId, conversation, now);
    });
  }

  Future<List<WaCrmMessage>> getMessages(
    String conversationId, {
    int limit = 80,
  }) async {
    final db = await _db;
    final rows = await db.query(
      'wa_crm_messages',
      where: 'conversation_id = ?',
      whereArgs: [conversationId],
      orderBy: 'sent_at DESC',
      limit: limit,
    );
    return rows.reversed
        .map((row) => WaCrmMessage.fromJson(_decode(row['json'])))
        .where((msg) => msg.id.isNotEmpty)
        .toList(growable: false);
  }

  Future<void> saveMessages(
    String conversationId,
    List<WaCrmMessage> messages,
  ) async {
    final db = await _db;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.transaction((tx) async {
      for (final msg in messages) {
        await _upsertMessageTx(tx, conversationId, msg, now);
      }
      final cursor = _latestMessageCursor(messages);
      if (cursor != null) {
        await _setMetaTx(
          tx,
          'messages:$conversationId:lastSyncAt',
          cursor.toIso8601String(),
        );
      }
    });
  }

  Future<void> upsertMessage(
    String conversationId,
    WaCrmMessage message,
  ) async {
    final db = await _db;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.transaction((tx) async {
      await _upsertMessageTx(tx, conversationId, message, now);
    });
  }

  Future<DateTime?> getLastConversationSync(String userId) {
    return _getDateMeta('conversations:$userId:lastSyncAt');
  }

  Future<DateTime?> getLastMessageSync(String conversationId) {
    return _getDateMeta('messages:$conversationId:lastSyncAt');
  }

  Future<DateTime?> _getDateMeta(String key) async {
    final value = await getMeta(key);
    if (value == null || value.trim().isEmpty) return null;
    return DateTime.tryParse(value);
  }

  Future<String?> getMeta(String key) async {
    final db = await _db;
    final rows = await db.query(
      'wa_crm_meta',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['value'] as String?;
  }

  Future<void> setMeta(String key, String value) async {
    final db = await _db;
    await _setMetaTx(db, key, value);
  }

  Future<void> _upsertConversationTx(
    DatabaseExecutor tx,
    String userId,
    WaCrmConversation conv,
    int now,
  ) async {
    if (conv.id.isEmpty) return;
    await tx.insert('wa_crm_conversations', {
      'id': conv.id,
      'user_id': userId,
      'instance_id': conv.instanceId,
      'merge_key': conv.mergeKey,
      'last_message_at': conv.activityAt.millisecondsSinceEpoch,
      'json': jsonEncode(_conversationToJson(conv)),
      'updated_at': now,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> _upsertMessageTx(
    DatabaseExecutor tx,
    String conversationId,
    WaCrmMessage msg,
    int now,
  ) async {
    if (msg.id.isEmpty) return;
    await tx.insert('wa_crm_messages', {
      'id': msg.id,
      'conversation_id': conversationId,
      'sent_at': msg.sentAt.millisecondsSinceEpoch,
      'media_storage_key': msg.mediaStorageKey,
      'media_status': msg.mediaStatus,
      'json': jsonEncode(_messageToJson(msg)),
      'updated_at': now,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> _setMetaTx(DatabaseExecutor tx, String key, String value) async {
    await tx.insert('wa_crm_meta', {
      'key': key,
      'value': value,
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Map<String, dynamic> _decode(Object? raw) {
    if (raw is! String || raw.trim().isEmpty) return <String, dynamic>{};
    final decoded = jsonDecode(raw);
    return decoded is Map
        ? decoded.cast<String, dynamic>()
        : <String, dynamic>{};
  }

  DateTime? _latestConversationCursor(List<WaCrmConversation> conversations) {
    DateTime? cursor;
    for (final conv in conversations) {
      final value = conv.activityAt;
      if (cursor == null || value.isAfter(cursor)) cursor = value;
    }
    return cursor;
  }

  DateTime? _latestMessageCursor(List<WaCrmMessage> messages) {
    DateTime? cursor;
    for (final msg in messages) {
      if (cursor == null || msg.sentAt.isAfter(cursor)) cursor = msg.sentAt;
    }
    return cursor;
  }

  String? _stringValue(dynamic value) {
    if (value == null) return null;
    final text = '$value'.trim();
    return text.isEmpty ? null : text;
  }

  Map<String, dynamic> _conversationToJson(WaCrmConversation conv) => {
    'id': conv.id,
    'instanceId': conv.instanceId,
    'remoteJid': conv.remoteJid,
    'remotePhone': conv.remotePhone,
    'remoteName': conv.remoteName,
    'remoteAvatarUrl': conv.remoteAvatarUrl,
    'lastMessageAt': conv.lastMessageAt?.toIso8601String(),
    'unreadCount': conv.unreadCount,
    'messageCount': conv.messageCount,
    if (conv.lastMessage != null)
      'messages': [_messageToJson(conv.lastMessage!)],
  };

  Map<String, dynamic> _messageToJson(WaCrmMessage msg) => {
    'id': msg.id,
    'conversationId': msg.conversationId,
    'direction': msg.isOutgoing ? 'OUTGOING' : 'INCOMING',
    'messageType': _messageTypeToJson(msg.messageType),
    'sentAt': msg.sentAt.toIso8601String(),
    'evolutionId': msg.evolutionId,
    'body': msg.body,
    'mediaUrl': msg.mediaUrl,
    'mediaMimeType': msg.mediaMimeType,
    'mediaStorageKey': msg.mediaStorageKey,
    'mediaFileSize': msg.mediaFileSize,
    'mediaStatus': msg.mediaStatus,
    'mediaError': msg.mediaError,
    'caption': msg.caption,
    'senderName': msg.senderName,
  };

  String _messageTypeToJson(WaMessageType type) {
    switch (type) {
      case WaMessageType.image:
        return 'IMAGE';
      case WaMessageType.audio:
        return 'AUDIO';
      case WaMessageType.video:
        return 'VIDEO';
      case WaMessageType.document:
        return 'DOCUMENT';
      case WaMessageType.sticker:
        return 'STICKER';
      case WaMessageType.other:
        return 'OTHER';
      case WaMessageType.text:
        return 'TEXT';
    }
  }
}
