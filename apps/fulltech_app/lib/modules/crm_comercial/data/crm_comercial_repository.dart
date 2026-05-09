import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_routes.dart';
import '../../../core/auth/auth_repository.dart';
import '../models/crm_comercial_models.dart';

final crmComercialRepositoryProvider = Provider<CrmComercialRepository>((ref) {
  return CrmComercialRepository(ref.watch(dioProvider));
});

class CrmComercialRepository {
  CrmComercialRepository(this._dio);

  final Dio _dio;

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