import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
  Future<String> setInstanceWebhook(String instanceName, {required bool enabled}) async {
    try {
      final res = await _dio.patch<Map<String, dynamic>>(
        '/whatsapp/admin/instance-webhook',
        data: {'instanceName': instanceName, 'enabled': enabled},
      );
      return (res.data?['webhookUrl'] as String?) ?? '';
    } on DioException catch (e) {
      String msg = 'Error configurando webhook en Evolution API';
      final data = e.response?.data;
      if (data is Map) {
        final raw = data['message'];
        if (raw is List) {
          msg = raw.join(', ');
        } else if (raw != null) {
          msg = raw.toString();
        }
      } else if (data is String && data.isNotEmpty) {
        msg = data;
      }
      throw Exception(msg);
    }
  }

  /// List conversations for a user
  Future<List<WaCrmConversation>> getConversations(String userId) async {
    final res = await _dio.get<List<dynamic>>(
      '/whatsapp-inbox/conversations',
      queryParameters: {'userId': userId},
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
    );
    return (res.data ?? [])
        .cast<Map<String, dynamic>>()
        .map(WaCrmMessage.fromJson)
        .toList();
  }

  /// Mark conversation as read
  Future<void> markRead(String conversationId) async {
    await _dio.post<void>('/whatsapp-inbox/conversations/$conversationId/read');
  }

  /// Reply to a conversation
  Future<void> reply(String conversationId, String text) async {
    await _dio.post<void>(
      '/whatsapp-inbox/conversations/$conversationId/reply',
      data: {'text': text},
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
    );
    return res.data ?? const {};
  }
}
