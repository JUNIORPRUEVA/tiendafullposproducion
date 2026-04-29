import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/wa_crm_repository.dart';
import '../models/wa_crm_conversation.dart';
import '../models/wa_crm_message.dart';

// ─── User selector ────────────────────────────────────────────────────────

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

  // ─── Clear selection (mobile back) ──────────────────────────────────

  void clearSelection() {
    state = state.copyWith(
      selectedConversation: () => null,
      messages: [],
    );
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
      print('[WaCrm] loadUsers error: $e\n$st');
      state = state.copyWith(
        loadingUsers: false,
        error: () => 'Error cargando usuarios: $e',
      );
    }
  }

  // ─── Select user (loads conversations) ───────────────────────────────

  Future<void> selectUser(WaCrmUser user) async {
    state = state.copyWith(
      selectedUser: () => user,
      conversations: [],
      selectedConversation: () => null,
      messages: [],
    );
    await loadConversations(user.id);
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
      print('[WaCrm] loadConversations error: $e\n$st');
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
      print('[WaCrm] loadMessages error: $e\n$st');
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
      // Reload messages after send
      await loadMessages(conv.id);
      state = state.copyWith(sending: false);
    } catch (e, st) {
      print('[WaCrm] sendReply error: $e\n$st');
      state = state.copyWith(
        sending: false,
        error: () => 'Error enviando mensaje: $e',
      );
    }
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
      print('[WaCrm] handleRealtimeMessage error: $e');
    }
  }
}
