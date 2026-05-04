import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http_parser/http_parser.dart';
import 'dart:typed_data';

import '../../../core/auth/auth_repository.dart';
import '../models/wa_crm_conversation.dart';
import '../models/wa_crm_message.dart';

final waCrmRepositoryProvider = Provider<WaCrmRepository>((ref) {
  return WaCrmRepository(ref.watch(dioProvider));
});

class WaCrmRepository {
  WaCrmRepository(this._dio);

  final Dio _dio;

  /// List users that have a WhatsApp instance
  Future<List<Map<String, dynamic>>> listUsers() async {
    final res = await _dio.get<List<dynamic>>('/whatsapp-inbox/users');
    return (res.data ?? []).cast<Map<String, dynamic>>();
  }

  /// List ALL instances (user + company) with webhook status — for CRM panel
  Future<List<Map<String, dynamic>>> listAllInstancesForCrm() async {
    final res = await _dio.get<List<dynamic>>('/whatsapp/admin/all-instances');
    return (res.data ?? []).cast<Map<String, dynamic>>();
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
  Future<List<WaCrmConversation>> getConversations(String userId) async {
    final res = await _dio.get<List<dynamic>>(
      '/whatsapp-inbox/conversations',
      queryParameters: {'userId': userId},
      options: Options(extra: const {'skipLoader': true, 'silent': true}),
    );
    return (res.data ?? [])
        .cast<Map<String, dynamic>>()
        .map(WaCrmConversation.fromJson)
        .toList();
  }

  /// Load messages for a conversation
  Future<List<WaCrmMessage>> getMessages(
    String conversationId, {
    int limit = 50,
    DateTime? before,
  }) async {
    final res = await _dio.get<List<dynamic>>(
      '/whatsapp-inbox/conversations/$conversationId/messages',
      queryParameters: {
        'limit': limit,
        if (before != null) 'before': before.toIso8601String(),
      },
      options: Options(extra: const {'skipLoader': true, 'silent': true}),
    );
    return (res.data ?? [])
        .cast<Map<String, dynamic>>()
        .map(WaCrmMessage.fromJson)
        .toList();
  }

  Future<Uint8List> downloadMediaBytes(String mediaUrl) async {
    final res = await _dio.get<dynamic>(
      mediaUrl,
      options: Options(
        responseType: ResponseType.bytes,
        extra: const {'skipLoader': true, 'silent': true},
      ),
    );
    final data = res.data;
    if (data is Uint8List) return data;
    if (data is List<int>) return Uint8List.fromList(data);
    if (data is ByteBuffer) return data.asUint8List();
    return Uint8List(0);
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
