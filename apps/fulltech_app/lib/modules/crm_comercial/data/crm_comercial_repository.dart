import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:typed_data';

import '../../../core/api/api_routes.dart';
import '../../../core/auth/auth_repository.dart';
import '../../../core/errors/api_exception.dart';
import '../models/crm_comercial_models.dart';

final crmComercialRepositoryProvider = Provider<CrmComercialRepository>((ref) {
  return CrmComercialRepository(ref.watch(dioProvider));
});

class CrmComercialRepository {
  CrmComercialRepository(this._dio);

  final Dio _dio;
  DateTime? _orthographyEndpointNotFoundUntil;

  String _extractErrorMessage(dynamic data, String fallback) {
    if (data is String && data.trim().isNotEmpty) return data.trim();
    if (data is Map) {
      final message = data['message'];
      if (message is String && message.trim().isNotEmpty) return message.trim();
      if (message is List && message.isNotEmpty) {
        final first = message.first;
        if (first is String && first.trim().isNotEmpty) return first.trim();
      }
      final error = data['error'];
      if (error is String && error.trim().isNotEmpty) return error.trim();
    }
    return fallback;
  }

  ApiException _mapError(DioException error, String fallback) {
    final message = _extractErrorMessage(error.response?.data, fallback);
    return ApiException.detailed(
      message: message,
      code: error.response?.statusCode,
      responseBody: error.response?.data?.toString(),
      uri: error.requestOptions.uri,
      method: error.requestOptions.method,
      technicalDetails: error.message,
    );
  }

  Future<CrmComercialCustomerListResponse> listCustomers({
    String? q,
    String? status,
    bool onlyMine = false,
    int page = 1,
    int pageSize = 30,
  }) async {
    final res = await _dio.get<Map<String, dynamic>>(
      ApiRoutes.crmCommercialCustomers,
      queryParameters: {
        if ((q ?? '').trim().isNotEmpty) 'q': q!.trim(),
        if ((status ?? '').trim().isNotEmpty) 'status': status,
        'onlyMine': onlyMine,
        'page': page,
        'pageSize': pageSize,
      },
    );
    return CrmComercialCustomerListResponse.fromJson(res.data ?? const {});
  }

  Future<CrmComercialCustomer> getCustomer(String id) async {
    final res = await _dio.get<Map<String, dynamic>>(
      ApiRoutes.crmCommercialCustomerById(id),
    );
    return CrmComercialCustomer.fromJson(res.data ?? const {});
  }

  Future<CrmComercialCustomer> updateCustomer(
    String id, {
    String? responsableUserId,
    String? nextAction,
    DateTime? nextActionAt,
  }) async {
    final res = await _dio.patch<Map<String, dynamic>>(
      ApiRoutes.crmCommercialCustomerById(id),
      data: {
        if (responsableUserId != null) 'responsableUserId': responsableUserId,
        if (nextAction != null) 'nextAction': nextAction,
        if (nextActionAt != null) 'nextActionAt': nextActionAt.toIso8601String(),
      },
    );
    return CrmComercialCustomer.fromJson(res.data ?? const {});
  }

  Future<CrmComercialCustomer> changeStatus(
    String id,
    String status, {
    String? note,
  }) async {
    final res = await _dio.patch<Map<String, dynamic>>(
      ApiRoutes.crmCommercialCustomerStatus(id),
      data: {
        'status': status,
        if ((note ?? '').trim().isNotEmpty) 'note': note!.trim(),
      },
    );
    return CrmComercialCustomer.fromJson(res.data ?? const {});
  }

  Future<CrmComercialNote> addNote(String id, String note) async {
    final res = await _dio.post<Map<String, dynamic>>(
      ApiRoutes.crmCommercialCustomerNotes(id),
      data: {'note': note.trim()},
    );
    return CrmComercialNote.fromJson(res.data ?? const {});
  }

  Future<CrmComercialActivity> addActivity(
    String id, {
    required String type,
    required String description,
    String? assignedToUserId,
    DateTime? dueAt,
  }) async {
    final res = await _dio.post<Map<String, dynamic>>(
      ApiRoutes.crmCommercialCustomerActivities(id),
      data: {
        'type': type.trim(),
        'description': description.trim(),
        if ((assignedToUserId ?? '').trim().isNotEmpty)
          'assignedToUserId': assignedToUserId,
        if (dueAt != null) 'dueAt': dueAt.toIso8601String(),
      },
    );
    return CrmComercialActivity.fromJson(res.data ?? const {});
  }

  Future<List<CrmComercialUserRef>> listUsers() async {
    final res = await _dio.get<List<dynamic>>(ApiRoutes.users);
    final rows = (res.data ?? const [])
        .whereType<Map>()
        .map((entry) =>
            CrmComercialUserRef.fromJson(entry.cast<String, dynamic>()))
        .toList(growable: false);
    return rows;
  }

  Future<CrmComercialSettings> getSettings() async {
    final res = await _dio.get<Map<String, dynamic>>(
      ApiRoutes.crmCommercialSettings,
    );
    return CrmComercialSettings.fromJson(res.data ?? const {});
  }

  Future<CrmComercialSettings> updateSettings({
    bool? enabled,
    String? selectedWhatsappInstanceId,
    String? selectedWhatsappInstanceName,
  }) async {
    final payload = <String, dynamic>{
      if (enabled != null) 'enabled': enabled,
      if (selectedWhatsappInstanceId != null)
        'selectedWhatsappInstanceId': selectedWhatsappInstanceId,
      if (selectedWhatsappInstanceName != null)
        'selectedWhatsappInstanceName': selectedWhatsappInstanceName,
    };
    final res = await _dio.patch<Map<String, dynamic>>(
      ApiRoutes.crmCommercialSettings,
      data: payload,
    );
    final data = res.data ?? const {};
    final nested = data['settings'];
    if (nested is Map<String, dynamic>) {
      return CrmComercialSettings.fromJson(nested);
    }
    return CrmComercialSettings.fromJson(data);
  }

  Future<List<CrmComercialWhatsappInstance>> listAvailableWhatsappInstances() async {
    final res = await _dio.get<List<dynamic>>(
      ApiRoutes.crmCommercialAvailableWhatsappInstances,
    );
    return (res.data ?? const [])
        .whereType<Map>()
        .map(
          (entry) =>
              CrmComercialWhatsappInstance.fromJson(entry.cast<String, dynamic>()),
        )
        .toList(growable: false);
  }

  Future<CrmComercialInboxConversationListResponse> listConversations({
    int limit = 100,
  }) async {
    final res = await _dio.get<Map<String, dynamic>>(
      ApiRoutes.crmCommercialConversations,
      queryParameters: {'limit': limit},
    );
    return CrmComercialInboxConversationListResponse.fromJson(
      res.data ?? const {},
    );
  }

  Future<CrmComercialInboxMessageListResponse> getConversationMessages(
    String conversationId, {
    int limit = 200,
  }) async {
    final res = await _dio.get<Map<String, dynamic>>(
      ApiRoutes.crmCommercialConversationMessages(conversationId),
      queryParameters: {'limit': limit},
    );
    return CrmComercialInboxMessageListResponse.fromJson(res.data ?? const {});
  }

  /// Downloads media bytes using the authenticated backend proxy.
  /// For WhatsappMessage media, the endpoint is /whatsapp-inbox/media/:messageId.
  /// The [mediaUrl] may be a full internal path like /whatsapp-inbox/media/UUID
  /// or a relative path — it is forwarded as-is through the Dio client (which
  /// already carries the JWT auth header).
  Future<Uint8List> downloadMediaBytes(String mediaUrl) async {
    try {
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
    } catch (_) {
      return Uint8List(0);
    }
  }

  Future<Map<String, dynamic>> startConversationMessage({
    required String phone,
    required String text,
  }) async {
    final res = await _dio.post<Map<String, dynamic>>(
      ApiRoutes.crmCommercialStartConversationMessage,
      data: {
        'phone': phone.trim(),
        'text': text.trim(),
      },
    );
    return res.data ?? const <String, dynamic>{};
  }

  Future<Map<String, dynamic>> replyConversation({
    required String conversationId,
    required String text,
  }) async {
    final payload = <String, dynamic>{'text': text.trim()};
    final url = ApiRoutes.crmCommercialConversationReply(conversationId);

    try {
      if (kDebugMode) {
        debugPrint('[CRM][replyConversation] POST $url body=$payload');
      }
      final res = await _dio.post<Map<String, dynamic>>(url, data: payload);
      if (kDebugMode) {
        debugPrint('[CRM][replyConversation] OK status=${res.statusCode} response=${res.data}');
      }
      return res.data ?? const <String, dynamic>{};
    } on DioException catch (error) {
      if (kDebugMode) {
        debugPrint(
          '[CRM][replyConversation] ERROR url=${error.requestOptions.uri} '
          'status=${error.response?.statusCode} '
          'body=${error.requestOptions.data} '
          'response=${error.response?.data}',
        );
      }
      throw _mapError(error, 'No se pudo enviar el mensaje.');
    }
  }

  Future<String?> suggestOrthography({
    required String text,
    String? previousText,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;
    final now = DateTime.now();
    final notFoundUntil = _orthographyEndpointNotFoundUntil;
    if (notFoundUntil != null && now.isBefore(notFoundUntil)) {
      return null;
    }
    try {
      final payload = <String, dynamic>{
        'text': text,
        if ((previousText ?? '').trim().isNotEmpty) 'previousText': previousText,
      };
      final res = await _dio.post<Map<String, dynamic>>(
        ApiRoutes.crmCommercialOrthographySuggestion,
        data: payload,
        options: Options(extra: const {'skipLoader': true, 'silent': true}),
      );
      final data = res.data ?? const <String, dynamic>{};
      final changed = data['changed'] == true;
      if (!changed) return null;
      final suggestion = data['suggestion']?.toString().trim() ?? '';
      _orthographyEndpointNotFoundUntil = null;
      if (suggestion.isEmpty || suggestion == trimmed) return null;
      return suggestion;
    } on DioException catch (error) {
      if (error.response?.statusCode == 404) {
        _orthographyEndpointNotFoundUntil = DateTime.now().add(
          const Duration(seconds: 45),
        );
      }
      return null;
    }
  }

  Future<CrmComercialAiReplySuggestion?> suggestReply({
    required String conversationId,
    required String lastCustomerMessage,
    required List<CrmComercialInboxMessage> recentMessages,
    String? crmStatus,
    Map<String, dynamic>? customerInfo,
    Map<String, dynamic>? availableBusinessData,
  }) async {
    final text = lastCustomerMessage.trim();
    if (conversationId.trim().isEmpty || text.isEmpty) return null;
    try {
      final payload = <String, dynamic>{
        'conversationId': conversationId,
        'lastCustomerMessage': text,
        'recentMessages': recentMessages
            .map(
              (msg) => {
                'direction': msg.direction,
                'text': (msg.body ?? msg.caption ?? '').trim(),
              },
            )
            .where((entry) => (entry['text'] ?? '').toString().trim().isNotEmpty)
            .toList(growable: false),
        if ((crmStatus ?? '').trim().isNotEmpty) 'crmStatus': crmStatus,
        if (customerInfo != null) 'customerInfo': customerInfo,
        if (availableBusinessData != null) 'availableBusinessData': availableBusinessData,
      };
      final res = await _dio.post<Map<String, dynamic>>(
        ApiRoutes.crmCommercialAiSuggestReply,
        data: payload,
        options: Options(extra: const {'skipLoader': true, 'silent': true}),
      );
      final data = res.data ?? const <String, dynamic>{};
      final suggestedReply = (data['suggestedReply'] ?? '').toString().trim();
      if (suggestedReply.isEmpty) return null;
      return CrmComercialAiReplySuggestion.fromJson(data);
    } on DioException {
      return null;
    }
  }

  Future<Map<String, dynamic>> replyConversationMedia({
    required String conversationId,
    required String mediaType, // 'image', 'video', 'audio', 'document'
    required String mimeType,
    required String fileName,
    required String base64Data,
    String? caption,
  }) async {
    final res = await _dio.post<Map<String, dynamic>>(
      ApiRoutes.crmCommercialConversationReplyMedia(conversationId),
      data: {
        'mediaType': mediaType,
        'mimeType': mimeType,
        'fileName': fileName,
        'base64Data': base64Data,
        if ((caption ?? '').trim().isNotEmpty) 'caption': caption!.trim(),
      },
    );
    return res.data ?? const <String, dynamic>{};
  }

  Future<Map<String, dynamic>> startConversationMediaMessage({
    required String phone,
    required String mediaType, // 'image', 'video', 'audio', 'document'
    required String mimeType,
    required String fileName,
    required String base64Data,
    String? caption,
  }) async {
    final res = await _dio.post<Map<String, dynamic>>(
      ApiRoutes.crmCommercialStartConversationMedia,
      data: {
        'phone': phone.trim(),
        'mediaType': mediaType,
        'mimeType': mimeType,
        'fileName': fileName,
        'base64Data': base64Data,
        if ((caption ?? '').trim().isNotEmpty) 'caption': caption!.trim(),
      },
    );
    return res.data ?? const <String, dynamic>{};
  }

  // Phase 2: Follow-up Tasks

  Future<List<CrmComercialFollowupTask>> listFollowupTasks({
    String? customerId,
    bool overdueOnly = false,
  }) async {
    final res = await _dio.get<List<dynamic>>(
      ApiRoutes.crmCommercialFollowupTasks,
      queryParameters: {
        if ((customerId ?? '').isNotEmpty) 'customerId': customerId,
        if (overdueOnly) 'overdueOnly': 'true',
      },
    );
    return (res.data ?? const [])
        .whereType<Map>()
        .map((e) =>
            CrmComercialFollowupTask.fromJson(e.cast<String, dynamic>()))
        .toList(growable: false);
  }

  Future<CrmComercialFollowupTask> createFollowupTask(
    String customerId, {
    required String title,
    String? description,
    DateTime? dueDate,
    String priority = 'NORMAL',
    String? assignedUserId,
  }) async {
    final res = await _dio.post<Map<String, dynamic>>(
      ApiRoutes.crmCommercialCustomerFollowupTasks(customerId),
      data: {
        'title': title.trim(),
        if ((description ?? '').trim().isNotEmpty)
          'description': description!.trim(),
        if (dueDate != null) 'dueDate': dueDate.toIso8601String(),
        'priority': priority,
        if ((assignedUserId ?? '').isNotEmpty) 'assignedUserId': assignedUserId,
      },
    );
    return CrmComercialFollowupTask.fromJson(res.data ?? const {});
  }

  Future<CrmComercialFollowupTask> completeFollowupTask(String taskId) async {
    final res = await _dio.patch<Map<String, dynamic>>(
      ApiRoutes.crmCommercialFollowupTaskComplete(taskId),
    );
    return CrmComercialFollowupTask.fromJson(res.data ?? const {});
  }

  Future<CrmComercialFollowupTask> cancelFollowupTask(String taskId) async {
    final res = await _dio.patch<Map<String, dynamic>>(
      ApiRoutes.crmCommercialFollowupTaskCancel(taskId),
    );
    return CrmComercialFollowupTask.fromJson(res.data ?? const {});
  }
}