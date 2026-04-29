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
}
