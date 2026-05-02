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
      id: sanitizeWaText(json['id']) ?? '',
      instanceName: sanitizeWaText(json['instanceName']) ?? '',
      status: sanitizeWaText(json['status']) ?? 'pending',
      webhookEnabled: json['webhookEnabled'] as bool? ?? false,
      isCompany: json['isCompany'] as bool? ?? false,
      userName: sanitizeWaText(json['userName']) ?? 'Sin nombre',
      userId: sanitizeWaText(json['userId']),
      userRole: sanitizeWaText(json['userRole']),
      phoneNumber: sanitizeWaText(json['phoneNumber']),
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

class WaCrmAiAlert {
  const WaCrmAiAlert({
    required this.type,
    required this.severity,
    required this.contact,
    required this.description,
  });

  final String
  type; // fraud | misconduct | no_response | angry_customer | spelling | unanswered
  final String severity; // high | medium | low
  final String contact;
  final String description;

  factory WaCrmAiAlert.fromJson(Map<String, dynamic> json) {
    return WaCrmAiAlert(
      type: sanitizeWaText(json['type']) ?? 'unknown',
      severity: sanitizeWaText(json['severity']) ?? 'low',
      contact: sanitizeWaText(json['contact']) ?? '',
      description: sanitizeWaText(json['description']) ?? '',
    );
  }
}

class WaCrmConversationAnalysis {
  const WaCrmConversationAnalysis({
    required this.contact,
    required this.messageCount,
    required this.status,
    required this.issues,
    required this.summary,
  });

  final String contact;
  final int messageCount;
  final String
  status; // interested | not_interested | angry | no_response | closed | pending
  final List<String> issues;
  final String summary;

  factory WaCrmConversationAnalysis.fromJson(Map<String, dynamic> json) {
    return WaCrmConversationAnalysis(
      contact: sanitizeWaText(json['contact']) ?? '',
      messageCount: (json['messageCount'] as num?)?.toInt() ?? 0,
      status: sanitizeWaText(json['status']) ?? 'pending',
      issues:
          (json['issues'] as List<dynamic>?)
              ?.map((e) => sanitizeWaText(e) ?? '')
              .where((s) => s.isNotEmpty)
              .toList() ??
          const [],
      summary: sanitizeWaText(json['summary']) ?? '',
    );
  }
}

class WaCrmDailyAiSummary {
  const WaCrmDailyAiSummary({
    required this.source,
    required this.summary,
    required this.stats,
    this.alerts = const [],
    this.conversationAnalysis = const [],
  });

  final String source;
  final String summary;
  final Map<String, dynamic> stats;
  final List<WaCrmAiAlert> alerts;
  final List<WaCrmConversationAnalysis> conversationAnalysis;

  factory WaCrmDailyAiSummary.fromJson(Map<String, dynamic> json) {
    return WaCrmDailyAiSummary(
      source: sanitizeWaText(json['source']) ?? 'rules-only',
      summary: sanitizeWaText(json['summary']) ?? '',
      stats: (json['stats'] as Map?)?.cast<String, dynamic>() ?? const {},
      alerts:
          (json['alerts'] as List<dynamic>?)
              ?.whereType<Map<String, dynamic>>()
              .map(WaCrmAiAlert.fromJson)
              .toList() ??
          const [],
      conversationAnalysis:
          (json['conversationAnalysis'] as List<dynamic>?)
              ?.whereType<Map<String, dynamic>>()
              .map(WaCrmConversationAnalysis.fromJson)
              .toList() ??
          const [],
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
      id: sanitizeWaText(user?['id'] ?? json['id']) ?? '',
      name: sanitizeWaText(user?['nombreCompleto']) ?? 'Sin nombre',
      role: sanitizeWaText(user?['role']) ?? '',
      instanceId: sanitizeWaText(json['id']),
      instanceStatus: sanitizeWaText(json['status']),
      phone: sanitizeWaText(json['phoneNumber'] ?? json['phone_number']),
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
    this.composerUnlocked = false,
    this.composerUnlockedConversationKey,
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
  final bool composerUnlocked;
  final String? composerUnlockedConversationKey;
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
    bool? composerUnlocked,
    String? Function()? composerUnlockedConversationKey,
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
      selectedUser: selectedUser != null ? selectedUser() : this.selectedUser,
      conversations: conversations ?? this.conversations,
      loadingConversations: loadingConversations ?? this.loadingConversations,
      selectedConversation: selectedConversation != null
          ? selectedConversation()
          : this.selectedConversation,
      messages: messages ?? this.messages,
      loadingMessages: loadingMessages ?? this.loadingMessages,
      sending: sending ?? this.sending,
      composerUnlocked: composerUnlocked ?? this.composerUnlocked,
      composerUnlockedConversationKey: composerUnlockedConversationKey != null
          ? composerUnlockedConversationKey()
          : this.composerUnlockedConversationKey,
      error: error != null ? error() : this.error,
      allInstances: allInstances ?? this.allInstances,
      loadingInstances: loadingInstances ?? this.loadingInstances,
      aiSummary: aiSummary != null ? aiSummary() : this.aiSummary,
      loadingAiSummary: loadingAiSummary ?? this.loadingAiSummary,
      aiSummaryError: aiSummaryError != null
          ? aiSummaryError()
          : this.aiSummaryError,
      aiSummaryDate: aiSummaryDate != null
          ? aiSummaryDate()
          : this.aiSummaryDate,
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
    state = state.copyWith(selectedConversation: () => null, messages: []);
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
      final webhookUrl = await _repo.setInstanceWebhook(
        instanceName,
        enabled: enabled,
      );
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
      state = state.copyWith(users: users, loadingUsers: false);
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
      composerUnlocked: false,
      composerUnlockedConversationKey: () => null,
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
      final fallback = _buildLocalDailyAiSummary(
        user: user,
        date: normalizedDate,
        reason: e,
      );
      state = state.copyWith(
        loadingAiSummary: false,
        aiSummary: () => fallback,
        aiSummaryError: () => null,
      );
    }
  }

  WaCrmDailyAiSummary _buildLocalDailyAiSummary({
    required WaCrmUser user,
    required DateTime date,
    required Object reason,
  }) {
    final day =
        '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    final contacts = state.conversations.length;
    final loadedMessages = state.messages.length;
    final unread = state.conversations.fold<int>(
      0,
      (sum, conv) => sum + conv.unreadCount,
    );
    final recentContacts = state.conversations
        .take(5)
        .map((conv) => conv.displayName)
        .where((name) => name.trim().isNotEmpty)
        .join(', ');
    final reasonText = _friendlySummaryFailure(reason);
    final summary = [
      'Resumen parcial del $day para ${user.name}.',
      'No se pudo completar el analisis de IA en este intento ($reasonText), pero el reporte no se detuvo.',
      'Datos disponibles en pantalla: $contacts conversaciones cargadas, $loadedMessages mensajes de la conversacion abierta y $unread mensajes sin leer.',
      if (recentContacts.isNotEmpty) 'Contactos recientes: $recentContacts.',
      'Recomendacion: revisar primero conversaciones sin leer, clientes con mensajes recientes y cualquier chat que quedo sin respuesta.',
    ].join('\n\n');

    return WaCrmDailyAiSummary(
      source: 'local-fallback',
      summary: summary,
      stats: {
        'date': day,
        'userName': user.name,
        'totalMessages': loadedMessages,
        'incomingMessages': state.messages.where((m) => m.isIncoming).length,
        'outgoingMessages': state.messages.where((m) => m.isOutgoing).length,
        'contacts': contacts,
        'mediaMessages': state.messages
            .where((m) => m.messageType != WaMessageType.text)
            .length,
      },
      alerts: const [],
      conversationAnalysis: state.conversations
          .take(8)
          .map(
            (conv) => WaCrmConversationAnalysis(
              contact: conv.displayName,
              messageCount: conv.lastMessage == null ? 0 : 1,
              status: 'pending',
              issues: conv.unreadCount > 0
                  ? ['Tiene ${conv.unreadCount} mensaje(s) sin leer']
                  : const [],
              summary: conv.lastMessage?.previewText ?? 'Sin vista previa.',
            ),
          )
          .toList(),
    );
  }

  String _friendlySummaryFailure(Object error) {
    final text = error.toString();
    if (text.contains('receiveTimeout') || text.contains('timeout')) {
      return 'la API tardo mas de lo esperado';
    }
    if (text.contains('SocketException') || text.contains('connection')) {
      return 'hubo un problema de conexion';
    }
    return 'servicio no disponible temporalmente';
  }

  // ─── Load conversations ───────────────────────────────────────────────

  Future<void> loadConversations(String userId) async {
    state = state.copyWith(loadingConversations: true, error: () => null);
    try {
      final convs = _mergeConversationsByPhone(
        await _repo.getConversations(userId),
      );
      final selected = state.selectedConversation;
      final selectedReplacement = selected == null
          ? null
          : convs.cast<WaCrmConversation?>().firstWhere(
              (conv) =>
                  conv?.id == selected.id ||
                  (conv?.instanceId == selected.instanceId &&
                      conv?.cleanPhone != null &&
                      conv?.cleanPhone == selected.cleanPhone),
              orElse: () => selected,
            );
      state = state.copyWith(
        conversations: convs,
        loadingConversations: false,
        selectedConversation: () => selectedReplacement,
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
      composerUnlocked: false,
      composerUnlockedConversationKey: () => null,
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
                remoteAvatarUrl: c.remoteAvatarUrl,
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

  Future<void> refreshActiveView() async {
    final user = state.selectedUser;
    if (user == null) return;
    try {
      final convs = _mergeConversationsByPhone(
        await _repo.getConversations(user.id),
      );
      final selected = state.selectedConversation;
      WaCrmConversation? selectedReplacement;
      if (selected != null) {
        selectedReplacement = convs.cast<WaCrmConversation?>().firstWhere(
          (conv) =>
              conv?.id == selected.id ||
              (conv?.instanceId == selected.instanceId &&
                  conv?.cleanPhone != null &&
                  conv?.cleanPhone == selected.cleanPhone),
          orElse: () => selected,
        );
      }

      List<WaCrmMessage>? messages;
      if (selectedReplacement != null) {
        messages = await _repo.getMessages(selectedReplacement.id);
      }

      state = state.copyWith(
        conversations: convs,
        selectedConversation: () => selectedReplacement,
        messages: messages ?? state.messages,
      );
    } catch (e) {
      debugPrint('[WaCrm] refreshActiveView error: $e');
    }
  }

  Future<void> sendReply(String text) async {
    final conv = state.selectedConversation;
    final canWrite =
        conv != null &&
        state.composerUnlocked &&
        state.composerUnlockedConversationKey == conv.mergeKey;
    if (conv == null || text.trim().isEmpty || !canWrite) return;

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

  Future<bool> unlockComposer(String password) async {
    try {
      await _repo.unlockCompose(password);
      final conv = state.selectedConversation;
      state = state.copyWith(
        composerUnlocked: conv != null,
        composerUnlockedConversationKey: () => conv?.mergeKey,
        error: () => null,
      );
      return true;
    } catch (e, st) {
      debugPrint('[WaCrm] unlockComposer error: $e\n$st');
      state = state.copyWith(
        composerUnlocked: false,
        composerUnlockedConversationKey: () => null,
        error: () => 'No se pudo desbloquear el envio: $e',
      );
      return false;
    }
  }

  /// Refreshes messages in the background without the loading spinner.
  void _silentRefreshMessages(String conversationId) {
    _repo
        .getMessages(conversationId)
        .then((msgs) {
          if (state.selectedConversation?.id == conversationId) {
            state = state.copyWith(messages: msgs);
          }
        })
        .catchError((e) {
          debugPrint('[WaCrm] _silentRefreshMessages error: $e');
        });
  }

  String? _normalizedPhoneFromRaw(String? value) {
    final raw = (value ?? '').trim();
    if (raw.isEmpty) return null;
    final local = raw.split('@').first.split(':').first;
    final digits = local.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 7 || digits.length > 15) return null;
    return digits;
  }

  WaCrmConversation? _findConversationByPhone(String? normalizedPhone) {
    if (normalizedPhone == null || normalizedPhone.isEmpty) return null;
    for (final conv in state.conversations) {
      if (conv.cleanPhone == normalizedPhone) return conv;
    }
    return null;
  }

  List<WaCrmConversation> _mergeConversationsByPhone(
    List<WaCrmConversation> conversations,
  ) {
    final byKey = <String, WaCrmConversation>{};
    for (final conv in conversations) {
      if (conv.isGroup) continue;
      final phone = conv.cleanPhone;
      final key = phone == null || phone.isEmpty
          ? '${conv.instanceId}:${conv.remoteJid}'
          : '${conv.instanceId}:$phone';
      final existing = byKey[key];
      if (existing == null) {
        byKey[key] = conv;
        continue;
      }
      final existingTime = existing.lastMessageAt ?? DateTime(0);
      final convTime = conv.lastMessageAt ?? DateTime(0);
      final newest = convTime.isAfter(existingTime) ? conv : existing;
      final oldest = convTime.isAfter(existingTime) ? existing : conv;
      byKey[key] = WaCrmConversation(
        id: newest.id,
        instanceId: newest.instanceId,
        remoteJid: newest.remoteJid.isNotEmpty
            ? newest.remoteJid
            : oldest.remoteJid,
        remotePhone: newest.cleanPhone ?? oldest.cleanPhone,
        remoteName:
            newest.remoteName != null &&
                newest.remoteName!.trim().toLowerCase() != 'me'
            ? newest.remoteName
            : oldest.remoteName,
        remoteAvatarUrl:
            (newest.remoteAvatarUrl != null &&
                newest.remoteAvatarUrl!.trim().isNotEmpty)
            ? newest.remoteAvatarUrl
            : oldest.remoteAvatarUrl,
        lastMessageAt: newest.lastMessageAt ?? oldest.lastMessageAt,
        unreadCount: newest.unreadCount + oldest.unreadCount,
        lastMessage: newest.lastMessage ?? oldest.lastMessage,
      );
    }
    final merged = byKey.values.toList();
    merged.sort((a, b) {
      final tA = a.lastMessageAt ?? DateTime(0);
      final tB = b.lastMessageAt ?? DateTime(0);
      return tB.compareTo(tA);
    });
    return merged;
  }

  // ─── Real-time message push ───────────────────────────────────────────

  void handleRealtimeMessage(Map<String, dynamic> data) {
    try {
      final convData = data['conversation'] as Map<String, dynamic>?;
      final convId =
          sanitizeWaText(data['conversationId']) ??
          sanitizeWaText(data['conversation_id']) ??
          sanitizeWaText(convData?['id']);
      final payloadMessage = data['message'] as Map<String, dynamic>?;
      final msgData = payloadMessage ?? (data['id'] != null ? data : null);

      if (convId == null || msgData == null) return;

      final incomingConv = convData != null
          ? WaCrmConversation.fromJson(convData)
          : null;
      final incomingPhone =
          incomingConv?.cleanPhone ??
          _normalizedPhoneFromRaw(sanitizeWaText(msgData['remotePhone'])) ??
          _normalizedPhoneFromRaw(sanitizeWaText(msgData['remoteJid']));
      final byPhone = _findConversationByPhone(incomingPhone);

      final targetConversationId = (byPhone != null && byPhone.id != convId)
          ? byPhone.id
          : convId;
      final requiresConversationRefresh =
          byPhone != null && byPhone.id != convId;

      final normalizedMsg = <String, dynamic>{
        ...msgData,
        'conversation_id': targetConversationId,
        if (msgData['sentAt'] == null && msgData['createdAt'] != null)
          'sentAt': msgData['createdAt'],
        if (msgData['body'] == null && msgData['text'] != null)
          'body': msgData['text'],
      };
      final msg = WaCrmMessage.fromJson(normalizedMsg);

      final selected = state.selectedConversation;
      final selectedPhone = selected?.cleanPhone;
      final sameSelectedConversation =
          selected?.id == targetConversationId ||
          (selected != null &&
              selected.instanceId ==
                  (incomingConv?.instanceId ?? selected.instanceId) &&
              selectedPhone != null &&
              selectedPhone == incomingPhone);

      // If this conversation is currently open, append message
      if (sameSelectedConversation) {
        final alreadyExists = state.messages.any((m) => m.id == msg.id);
        if (!alreadyExists) {
          state = state.copyWith(messages: [...state.messages, msg]);
        }
        if (selected?.id != targetConversationId && incomingConv != null) {
          state = state.copyWith(
            selectedConversation: () => WaCrmConversation(
              id: targetConversationId,
              instanceId: incomingConv.instanceId,
              remoteJid: incomingConv.remoteJid,
              remotePhone: incomingConv.remotePhone,
              remoteName: incomingConv.remoteName,
              remoteAvatarUrl: incomingConv.remoteAvatarUrl,
              lastMessageAt: incomingConv.lastMessageAt,
              unreadCount: incomingConv.unreadCount,
              lastMessage: incomingConv.lastMessage,
            ),
          );
        }
      }

      // Update conversation list (bump lastMessageAt + unreadCount)
      if (incomingConv != null) {
        final updatedConv = WaCrmConversation(
          id: targetConversationId,
          instanceId: incomingConv.instanceId,
          remoteJid: incomingConv.remoteJid,
          remotePhone: incomingConv.remotePhone,
          remoteName: incomingConv.remoteName,
          remoteAvatarUrl: incomingConv.remoteAvatarUrl,
          lastMessageAt: incomingConv.lastMessageAt,
          unreadCount: incomingConv.unreadCount,
          lastMessage: incomingConv.lastMessage,
        );
        final existing = state.conversations.any(
          (c) => c.id == targetConversationId,
        );
        List<WaCrmConversation> updatedList;
        if (existing) {
          updatedList = state.conversations.map((c) {
            return c.id == targetConversationId ? updatedConv : c;
          }).toList();
        } else {
          updatedList = [updatedConv, ...state.conversations];
        }
        state = state.copyWith(
          conversations: _mergeConversationsByPhone(updatedList),
        );
      }

      if (requiresConversationRefresh && state.selectedUser != null) {
        unawaited(loadConversations(state.selectedUser!.id));
      }
    } catch (e) {
      debugPrint('[WaCrm] handleRealtimeMessage error: $e');
    }
  }
}
