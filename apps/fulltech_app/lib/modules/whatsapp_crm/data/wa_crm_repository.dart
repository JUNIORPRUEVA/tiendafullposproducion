import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http_parser/http_parser.dart';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';

import '../../../core/auth/auth_repository.dart';
import 'wa_crm_local_cache.dart';
import '../application/wa_crm_controller.dart';
import '../models/wa_crm_conversation.dart';
import '../models/wa_crm_message.dart';

final waCrmRepositoryProvider = Provider<WaCrmRepository>((ref) {
  return WaCrmRepository(
    ref.watch(dioProvider),
    ref.watch(waCrmLocalCacheProvider),
  );
});

class WaCrmRepository {
  WaCrmRepository(this._dio, this._cache);

  final Dio _dio;
  final WaCrmLocalCache _cache;

  /// List users that have a WhatsApp instance
  Future<List<Map<String, dynamic>>> listUsers() async {
    final res = await _dio.get<List<dynamic>>('/whatsapp-inbox/users');
    final rows = (res.data ?? []).cast<Map<String, dynamic>>();
    await _cache.saveUserRows(rows);
    return rows;
  }

  Future<List<WaCrmUser>> cachedUsers() async {
    final rows = await _cache.getUserRows();
    return rows.map(WaCrmUser.fromJson).toList(growable: false);
  }

  /// List ALL instances (user + company) with webhook status — for CRM panel
  Future<List<Map<String, dynamic>>> listAllInstancesForCrm() async {
    final res = await _dio.get<List<dynamic>>('/whatsapp/admin/all-instances');
    final rows = (res.data ?? []).cast<Map<String, dynamic>>();
    await _cache.saveInstanceRows(rows);
    return rows;
  }

  Future<List<WaCrmInstanceEntry>> cachedInstances() async {
    final rows = await _cache.getInstanceRows();
    return rows.map(WaCrmInstanceEntry.fromJson).toList(growable: false);
  }

  /// Toggle webhook for a specific instance — returns the configured URL
  Future<String> setInstanceWebhook(
    String instanceName, {
    required bool enabled,
  }) async {
    try {
      final res = await _dio.patch<Map<String, dynamic>>(
        '/whatsapp/admin/instance-webhook',
        data: {'instanceName': instanceName, 'enabled': enabled},
      );
      return sanitizeWaText(res.data?['webhookUrl']) ?? '';
    } on DioException catch (e) {
      String msg = 'Error configurando webhook en Evolution API';
      final data = e.response?.data;
      if (data is Map) {
        final raw = data['message'];
        if (raw is List) {
          msg = raw.join(', ');
        } else if (raw != null) {
          msg = sanitizeWaText(raw.toString()) ?? msg;
        }
      } else if (data is String && data.isNotEmpty) {
        msg = sanitizeWaText(data) ?? msg;
      }
      throw Exception(msg);
    }
  }

  /// List conversations for a user
  Future<List<WaCrmConversation>> getConversations(
    String userId, {
    DateTime? updatedAfter,
  }) async {
    final res = await _dio.get<List<dynamic>>(
      '/whatsapp-inbox/conversations',
      queryParameters: {
        'userId': userId,
        if (updatedAfter != null)
          'updatedAfter': updatedAfter.toIso8601String(),
      },
      options: Options(extra: const {'skipLoader': true, 'silent': true}),
    );
    final conversations = (res.data ?? [])
        .cast<Map<String, dynamic>>()
        .map(WaCrmConversation.fromJson)
        .toList();
    await _cache.saveConversations(userId, conversations);
    return conversations;
  }

  Future<List<WaCrmConversation>> cachedConversations(String userId) {
    return _cache.getConversations(userId);
  }

  Future<DateTime?> lastConversationSync(String userId) {
    return _cache.getLastConversationSync(userId);
  }

  /// Load messages for a conversation
  Future<List<WaCrmMessage>> getMessages(
    String conversationId, {
    int limit = 50,
    DateTime? before,
    DateTime? after,
  }) async {
    final res = await _dio.get<List<dynamic>>(
      '/whatsapp-inbox/conversations/$conversationId/messages',
      queryParameters: {
        'limit': limit,
        if (before != null) 'before': before.toIso8601String(),
        if (after != null) 'after': after.toIso8601String(),
      },
      options: Options(extra: const {'skipLoader': true, 'silent': true}),
    );
    final messages = (res.data ?? [])
        .cast<Map<String, dynamic>>()
        .map(WaCrmMessage.fromJson)
        .toList();
    await _cache.saveMessages(conversationId, messages);
    return messages;
  }

  Future<List<WaCrmMessage>> cachedMessages(
    String conversationId, {
    int limit = 80,
  }) {
    return _cache.getMessages(conversationId, limit: limit);
  }

  Future<DateTime?> lastMessageSync(String conversationId) {
    return _cache.getLastMessageSync(conversationId);
  }

  Future<void> cacheRealtimeMessage({
    required String userId,
    required WaCrmConversation conversation,
    required WaCrmMessage message,
  }) async {
    await _cache.upsertConversation(userId, conversation);
    await _cache.upsertMessage(conversation.id, message);
  }

  Future<void> cacheConversation(
    String userId,
    WaCrmConversation conversation,
  ) {
    return _cache.upsertConversation(userId, conversation);
  }

  Future<Uint8List> downloadMediaBytes(String mediaUrl) async {
    final cached = await _readCachedMedia(mediaUrl);
    if (cached != null && cached.isNotEmpty) return cached;

    final res = await _dio.get<dynamic>(
      mediaUrl,
      options: Options(
        responseType: ResponseType.bytes,
        extra: const {'skipLoader': true, 'silent': true},
      ),
    );
    final data = res.data;
    final bytes = data is Uint8List
        ? data
        : data is List<int>
        ? Uint8List.fromList(data)
        : data is ByteBuffer
        ? data.asUint8List()
        : Uint8List(0);
    if (bytes.isNotEmpty) {
      await _writeCachedMedia(mediaUrl, bytes);
    }
    return bytes;
  }

  Future<Uint8List?> _readCachedMedia(String mediaUrl) async {
    try {
      final file = await _mediaCacheFile(mediaUrl);
      if (!await file.exists()) return null;
      final stat = await file.stat();
      if (stat.size <= 0) return null;
      return await file.readAsBytes();
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeCachedMedia(String mediaUrl, Uint8List bytes) async {
    try {
      final file = await _mediaCacheFile(mediaUrl);
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes, flush: false);
    } catch (_) {}
  }

  Future<File> _mediaCacheFile(String mediaUrl) async {
    final dir = await getApplicationCacheDirectory();
    final key = base64Url.encode(utf8.encode(mediaUrl)).replaceAll('=', '');
    return File(
      '${dir.path}${Platform.pathSeparator}wa_media$Platform.pathSeparator$key.bin',
    );
  }

  /// Mark conversation as read
  Future<void> markRead(String conversationId) async {
    await _dio.post<void>(
      '/whatsapp-inbox/conversations/$conversationId/read',
      options: Options(extra: const {'skipLoader': true, 'silent': true}),
    );
  }

  Future<void> unlockCompose(String password) async {
    await _dio.post<void>(
      '/whatsapp-inbox/compose/unlock',
      data: {'password': password},
      options: Options(extra: const {'skipLoader': true}),
    );
  }

  /// Reply to a conversation
  Future<void> reply(String conversationId, String text) async {
    await _dio.post<void>(
      '/whatsapp-inbox/conversations/$conversationId/reply',
      data: {'text': text},
    );
  }

  Future<void> replyMedia({
    required String conversationId,
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
    String? caption,
  }) async {
    await _dio.post<void>(
      '/whatsapp-inbox/conversations/$conversationId/media',
      data: FormData.fromMap({
        'file': MultipartFile.fromBytes(
          bytes,
          filename: fileName,
          contentType: MediaType.parse(mimeType),
        ),
        if (caption?.trim().isNotEmpty == true) 'caption': caption!.trim(),
      }),
    );
  }

  /// Generate daily AI summary for one user's WhatsApp activity.
  Future<Map<String, dynamic>> summarizeDailyActivity({
    required String userId,
    required DateTime date,
  }) async {
    final day =
        '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    final res = await _dio.post<Map<String, dynamic>>(
      '/whatsapp-inbox/daily-summary',
      data: {'userId': userId, 'date': day},
      options: Options(
        receiveTimeout: const Duration(seconds: 45),
        sendTimeout: const Duration(seconds: 15),
        extra: const {'skipLoader': true},
      ),
    );
    return res.data ?? const {};
  }
}
