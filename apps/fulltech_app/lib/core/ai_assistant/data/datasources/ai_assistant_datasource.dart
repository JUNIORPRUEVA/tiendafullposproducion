import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../auth/auth_repository.dart';
import '../../../api/api_routes.dart';
import '../../../errors/api_exception.dart';
import '../../domain/models/ai_chat_context.dart';

final aiAssistantDataSourceProvider = Provider<AiAssistantDataSource>((ref) {
  return AiAssistantDataSource(ref.watch(dioProvider));
});

class AiAssistantDataSource {
  AiAssistantDataSource(this._dio);

  final Dio _dio;

  Future<Map<String, dynamic>> chat({
    required AiChatContext context,
    required String message,
    required List<Map<String, dynamic>> history,
  }) async {
    return _post(
      ApiRoutes.aiChat,
      data: {
        'context': context.toMap(),
        'message': message.trim(),
        if (history.isNotEmpty) 'history': history,
      },
    );
  }

  Future<Map<String, dynamic>> _post(
    String path, {
    required Map<String, dynamic> data,
  }) async {
    try {
      final response = await _dio.post(
        path,
        data: data,
        options: Options(extra: const {'skipLoader': true}),
      );
      if (response.data is Map<String, dynamic>) {
        return response.data as Map<String, dynamic>;
      }
      if (response.data is Map) {
        return (response.data as Map).cast<String, dynamic>();
      }
      throw ApiException('Respuesta inválida del asistente IA.');
    } on DioException catch (error) {
      final message = _extractMessage(
        error.response?.data,
        'No se pudo consultar el asistente IA.',
      );
      throw ApiException(message, error.response?.statusCode);
    }
  }

  String _extractMessage(dynamic data, String fallback) {
    if (data is String && data.trim().isNotEmpty) return data;
    if (data is Map) {
      final message = data['message'];
      if (message is String && message.trim().isNotEmpty) return message;
      if (message is List) {
        final normalized = message
            .whereType<String>()
            .map((item) => item.trim())
            .where((item) => item.isNotEmpty)
            .join(' | ');
        if (normalized.isNotEmpty) return normalized;
      }
      final errorMessage = data['error'];
      if (errorMessage is String && errorMessage.trim().isNotEmpty) {
        return errorMessage;
      }
    }
    return fallback;
  }
}
