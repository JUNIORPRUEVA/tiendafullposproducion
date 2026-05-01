import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/wa_crm_repository.dart';
import '../models/wa_crm_conversation.dart';
import '../models/wa_crm_message.dart';

// ─── CRM Instance Entry (for webhook management panel) ────────────────────

class WaCrmInstanceEntry {
  const WaCrmInstanceEntry({
    required this.id,
    required this.instanceName,
    required this.status,
    required this.webhookEnabled,
    required this.isCompany,
    required this.userName,
    this.userId,
    this.userRole,
    this.phoneNumber,
  });

  final String id;
  final String instanceName;
  final String status;
  final bool webhookEnabled;
  final bool isCompany;
  final String userName;
  final String? userId;
  final String? userRole;
  final String? phoneNumber;

  factory WaCrmInstanceEntry.fromJson(Map<String, dynamic> json) {
    return WaCrmInstanceEntry(
      id: json['id'] as String? ?? '',
      instanceName: json['instanceName'] as String? ?? '',
      status: json['status'] as String? ?? 'pending',
      webhookEnabled: json['webhookEnabled'] as bool? ?? false,
      isCompany: json['isCompany'] as bool? ?? false,
      userName: json['userName'] as String? ?? 'Sin nombre',
      userId: json['userId'] as String?,
      userRole: json['userRole'] as String?,
      phoneNumber: json['phoneNumber'] as String?,
    );
  }

  WaCrmInstanceEntry copyWithWebhook(bool enabled) => WaCrmInstanceEntry(
        id: id,
        instanceName: instanceName,
        status: status,
        webhookEnabled: enabled,
        isCompany: isCompany,
        userName: userName,
        userId: userId,
        userRole: userRole,
        phoneNumber: phoneNumber,
      );
}

// ─── User selector ────────────────────────────────────────────────────────

class WaCrmDailyAiSummary {
  const WaCrmDailyAiSummary({
    required this.source,
    required this.summary,
    required this.stats,
  });

  final String source;
  final String summary;
  final Map<String, dynamic> stats;

  factory WaCrmDailyAiSummary.fromJson(Map<String, dynamic> json) {
    return WaCrmDailyAiSummary(
      source: json['source'] as String? ?? 'rules-only',
      summary: json['summary'] as String? ?? '',
      stats: (json['stats'] as Map?)?.cast<String, dynamic>() ?? const {},
    );
  }
}

class WaCrmUser {
  const WaCrmUser({
    required this.id,
    required this.name,
    required this.role,
    this.instanceId,
    this.instanceStatus,
    this.phone,
  });

  final String id;
  final String name;
  final String role;
  final String? instanceId;
  final String? instanceStatus;
  final String? phone;

  factory WaCrmUser.fromJson(Map<String, dynamic> json) {
    final user = json['user'] as Map<String, dynamic>?;
    return WaCrmUser(
      id: user?['id'] as String? ?? json['id'] as String? ?? '',
      name: user?['nombreCompleto'] as String? ?? 'Sin nombre',
      role: user?['role'] as String? ?? '',
      instanceId: json['id'] as String?,
      instanceStatus: json['status'] as String?,
      phone: json['phoneNumber'] as String? ?? json['phone_number'] as String?,
    );
  }
}

// ─── State ────────────────────────────────────────────────────────────────

class WaCrmState {
  const WaCrmState({
    this.users = const [],
    this.loadingUsers = false,
    this.selectedUser,
    this.conversations = const [],
    this.loadingConversations = false,
    this.selectedConversation,
    this.messages = const [],
    this.loadingMessages = false,
    this.sending = false,
    this.error,
    this.allInstances = const [],
    this.loadingInstances = false,
    this.aiSummary,
    this.loadingAiSummary = false,
    this.aiSummaryError,
    this.aiSummaryDate,
  });

  final List<WaCrmUser> users;
  final bool loadingUsers;
  final WaCrmUser? selectedUser;
  final List<WaCrmConversation> conversations;
  final bool loadingConversations;
  final WaCrmConversation? selectedConversation;
  final List<WaCrmMessage> messages;
  final bool loadingMessages;
  final bool sending;
  final String? error;
  final List<WaCrmInstanceEntry> allInstances;
  final bool loadingInstances;
  final WaCrmDailyAiSummary? aiSummary;
  final bool loadingAiSummary;
  final String? aiSummaryError;
  final DateTime? aiSummaryDate;

  WaCrmState copyWith({
    List<WaCrmUser>? users,
    bool? loadingUsers,
    WaCrmUser? Function()? selectedUser,
    List<WaCrmConversation>? conversations,
    bool? loadingConversations,
    WaCrmConversation? Function()? selectedConversation,
    List<WaCrmMessage>? messages,
    bool? loadingMessages,
    bool? sending,
    String? Function()? error,
    List<WaCrmInstanceEntry>? allInstances,
    bool? loadingInstances,
    WaCrmDailyAiSummary? Function()? aiSummary,
    bool? loadingAiSummary,
    String? Function()? aiSummaryError,
    DateTime? Function()? aiSummaryDate,
  }) {
    return WaCrmState(
      users: users ?? this.users,
      loadingUsers: loadingUsers ?? this.loadingUsers,
      selectedUser:
          selectedUser != null ? selectedUser() : this.selectedUser,
      conversations: conversations ?? this.conversations,
      loadingConversations: loadingConversations ?? this.loadingConversations,
      selectedConversation: selectedConversation != null
          ? selectedConversation()
          : this.selectedConversation,
      messages: messages ?? this.messages,
      loadingMessages: loadingMessages ?? this.loadingMessages,
      sending: sending ?? this.sending,
      error: error != null ? error() : this.error,
      allInstances: allInstances ?? this.allInstances,
      loadingInstances: loadingInstances ?? this.loadingInstances,
      aiSummary: aiSummary != null ? aiSummary() : this.aiSummary,
      loadingAiSummary: loadingAiSummary ?? this.loadingAiSummary,
      aiSummaryError:
          aiSummaryError != null ? aiSummaryError() : this.aiSummaryError,
      aiSummaryDate:
          aiSummaryDate != null ? aiSummaryDate() : this.aiSummaryDate,
    );
  }
}

// ─── Controller ──────────────────────────────────────────────────────────

final waCrmControllerProvider =
    StateNotifierProvider<WaCrmController, WaCrmState>((ref) {
  return WaCrmController(ref.watch(waCrmRepositoryProvider));
});

class WaCrmController extends StateNotifier<WaCrmState> {
  WaCrmController(this._repo) : super(const WaCrmState());

  final WaCrmRepository _repo;
  bool _autoSyncedWebhookEvents = false;

  // ─── Clear selection (mobile back) ──────────────────────────────────

  void clearSelection() {
    state = state.copyWith(
      selectedConversation: () => null,
      messages: [],
    );
  }

  // ─── Load all instances with webhook status ──────────────────────────

  Future<void> loadAllInstances() async {
    state = state.copyWith(loadingInstances: true);
    try {
      final raw = await _repo.listAllInstancesForCrm();
      final instances = raw.map(WaCrmInstanceEntry.fromJson).toList();
      state = state.copyWith(allInstances: instances, loadingInstances: false);
      if (!_autoSyncedWebhookEvents) {
        _autoSyncedWebhookEvents = true;
        unawaited(_resyncEnabledWebhookEvents(instances));
      }
    } catch (e, st) {
      debugPrint('[WaCrm] loadAllInstances error: $e\n$st');
      state = state.copyWith(loadingInstances: false);
    }
  }

  Future<void> _resyncEnabledWebhookEvents(
    List<WaCrmInstanceEntry> instances,
  ) async {
    for (final instance in instances.where((item) => item.webhookEnabled)) {
      try {
        await _repo.setInstanceWebhook(instance.instanceName, enabled: true);
      } catch (e) {
        debugPrint(
          '[WaCrm] auto webhook event sync failed for ${instance.instanceName}: $e',
        );
      }
    }
  }

  // ─── Set webhook for a specific instance ────────────────────────────

  Future<String> setInstanceWebhook(
    String instanceName, {
    required bool enabled,
  }) async {
    // Optimistic update
    final updated = state.allInstances.map((inst) {
      return inst.instanceName == instanceName
          ? inst.copyWithWebhook(enabled)
          : inst;
    }).toList();
    state = state.copyWith(allInstances: updated);

    try {
      final webhookUrl = await _repo.setInstanceWebhook(instanceName, enabled: enabled);
      return webhookUrl;
    } catch (e, st) {
      debugPrint('[WaCrm] setInstanceWebhook error: $e\n$st');
      // Revert on error
      final reverted = state.allInstances.map((inst) {
        return inst.instanceName == instanceName
            ? inst.copyWithWebhook(!enabled)
            : inst;
      }).toList();
      state = state.copyWith(allInstances: reverted);
      rethrow;
    }
  }

  // ─── Load users ─────────────────────────────────────────────────────

  Future<void> loadUsers() async {
    state = state.copyWith(loadingUsers: true, error: () => null);
    try {
      final raw = await _repo.listUsers();
      final users = raw.map(WaCrmUser.fromJson).toList();
      state = state.copyWith(
        users: users,
        loadingUsers: false,
      );
      // Auto-select first user
      if (users.isNotEmpty && state.selectedUser == null) {
        await selectUser(users.first);
      }
    } catch (e, st) {
      debugPrint('[WaCrm] loadUsers error: $e\n$st');
      state = state.copyWith(
        loadingUsers: false,
        error: () => 'Error cargando usuarios: $e',
      );
    }
    // Also refresh the instance+webhook list
    unawaited(loadAllInstances());
  }

  // ─── Select user (loads conversations) ───────────────────────────────

  Future<void> selectUser(WaCrmUser user) async {
    state = state.copyWith(
      selectedUser: () => user,
      conversations: [],
      selectedConversation: () => null,
      messages: [],
      aiSummary: () => null,
      aiSummaryError: () => null,
    );
    await loadConversations(user.id);
  }

  Future<void> generateDailyAiSummary({DateTime? date}) async {
    final user = state.selectedUser;
    if (user == null) {
      state = state.copyWith(
        aiSummaryError: () => 'Selecciona un usuario para generar el resumen.',
      );
      return;
    }

    final selectedDate = date ?? state.aiSummaryDate ?? DateTime.now();
    final normalizedDate = DateTime(
      selectedDate.year,
      selectedDate.month,
      selectedDate.day,
    );
    state = state.copyWith(
      loadingAiSummary: true,
      aiSummaryError: () => null,
      aiSummaryDate: () => normalizedDate,
    );
    try {
      final raw = await _repo.summarizeDailyActivity(
        userId: user.id,
        date: normalizedDate,
      );
      state = state.copyWith(
        aiSummary: () => WaCrmDailyAiSummary.fromJson(raw),
        loadingAiSummary: false,
      );
    } catch (e, st) {
      debugPrint('[WaCrm] generateDailyAiSummary error: $e\n$st');
      state = state.copyWith(
        loadingAiSummary: false,
        aiSummaryError: () => 'No se pudo generar el resumen: $e',
      );
    }
  }

  // ─── Load conversations ───────────────────────────────────────────────

  Future<void> loadConversations(String userId) async {
    state = state.copyWith(loadingConversations: true, error: () => null);
    try {
      final convs = await _repo.getConversations(userId);
      state = state.copyWith(
        conversations: convs,
        loadingConversations: false,
      );
    } catch (e, st) {
      debugPrint('[WaCrm] loadConversations error: $e\n$st');
      state = state.copyWith(
        loadingConversations: false,
        error: () => 'Error cargando conversaciones: $e',
      );
    }
  }

  // ─── Select conversation (loads messages) ────────────────────────────

  Future<void> selectConversation(WaCrmConversation conv) async {
    state = state.copyWith(
      selectedConversation: () => conv,
      messages: [],
    );
    await loadMessages(conv.id);
    // Mark as read
    try {
      await _repo.markRead(conv.id);
      final updated = state.conversations.map((c) {
        return c.id == conv.id
            ? WaCrmConversation(
                id: c.id,
                instanceId: c.instanceId,
                remoteJid: c.remoteJid,
                remotePhone: c.remotePhone,
                remoteName: c.remoteName,
                lastMessageAt: c.lastMessageAt,
                unreadCount: 0,
              )
            : c;
      }).toList();
      state = state.copyWith(conversations: updated);
    } catch (_) {}
  }

  // ─── Load messages ───────────────────────────────────────────────────

  Future<void> loadMessages(String conversationId) async {
    state = state.copyWith(loadingMessages: true, error: () => null);
    try {
      final msgs = await _repo.getMessages(conversationId);
      state = state.copyWith(messages: msgs, loadingMessages: false);
    } catch (e, st) {
      debugPrint('[WaCrm] loadMessages error: $e\n$st');
      state = state.copyWith(
        loadingMessages: false,
        error: () => 'Error cargando mensajes: $e',
      );
    }
  }

  // ─── Send reply ──────────────────────────────────────────────────────

  Future<void> sendReply(String text) async {
    final conv = state.selectedConversation;
    if (conv == null || text.trim().isEmpty) return;

    state = state.copyWith(sending: true, error: () => null);
    try {
      await _repo.reply(conv.id, text.trim());
      state = state.copyWith(sending: false);
      // Silently refresh without clearing state or showing spinner
      _silentRefreshMessages(conv.id);
    } catch (e, st) {
      debugPrint('[WaCrm] sendReply error: $e\n$st');
      state = state.copyWith(
        sending: false,
        error: () => 'Error enviando mensaje: $e',
      );
    }
  }

  /// Refreshes messages in the background without the loading spinner.
  void _silentRefreshMessages(String conversationId) {
    _repo.getMessages(conversationId).then((msgs) {
      if (state.selectedConversation?.id == conversationId) {
        state = state.copyWith(messages: msgs);
      }
    }).catchError((e) {
      debugPrint('[WaCrm] _silentRefreshMessages error: $e');
    });
  }

  // ─── Real-time message push ───────────────────────────────────────────

  void handleRealtimeMessage(Map<String, dynamic> data) {
    try {
      final convId = data['conversationId'] as String?;
      final msgData = data['message'] as Map<String, dynamic>?;
      final convData = data['conversation'] as Map<String, dynamic>?;

      if (convId == null || msgData == null) return;

      // If this conversation is currently open, append message
      if (state.selectedConversation?.id == convId) {
        final msg = WaCrmMessage.fromJson({...msgData, 'conversation_id': convId});
        state = state.copyWith(messages: [...state.messages, msg]);
      }

      // Update conversation list (bump lastMessageAt + unreadCount)
      if (convData != null) {
        final updatedConv = WaCrmConversation.fromJson(convData);
        final existing = state.conversations.any((c) => c.id == convId);
        List<WaCrmConversation> updatedList;
        if (existing) {
          updatedList = state.conversations.map((c) {
            return c.id == convId ? updatedConv : c;
          }).toList();
        } else {
          updatedList = [updatedConv, ...state.conversations];
        }
        // Sort by lastMessageAt desc
        updatedList.sort((a, b) {
          final tA = a.lastMessageAt ?? DateTime(0);
          final tB = b.lastMessageAt ?? DateTime(0);
          return tB.compareTo(tA);
        });
        state = state.copyWith(conversations: updatedList);
      }
    } catch (e) {
      debugPrint('[WaCrm] handleRealtimeMessage error: $e');
    }
  }
}
