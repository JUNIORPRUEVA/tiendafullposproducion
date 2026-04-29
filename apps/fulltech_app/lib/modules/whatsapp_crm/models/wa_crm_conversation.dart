import 'wa_crm_message.dart';

class WaCrmConversation {
  const WaCrmConversation({
    required this.id,
    required this.instanceId,
    required this.remoteJid,
    this.remotePhone,
    this.remoteName,
    this.lastMessageAt,
    this.unreadCount = 0,
    this.lastMessage,
  });

  final String id;
  final String instanceId;
  final String remoteJid;
  final String? remotePhone;
  final String? remoteName;
  final DateTime? lastMessageAt;
  final int unreadCount;
  final WaCrmMessage? lastMessage;

  String get displayName =>
      remoteName?.isNotEmpty == true
          ? remoteName!
          : (remotePhone?.isNotEmpty == true ? remotePhone! : remoteJid);

  factory WaCrmConversation.fromJson(Map<String, dynamic> json) {
    final msgs = json['messages'] as List<dynamic>?;
    WaCrmMessage? lastMsg;
    if (msgs != null && msgs.isNotEmpty) {
      try {
        lastMsg = WaCrmMessage.fromJson(msgs.first as Map<String, dynamic>);
      } catch (_) {}
    }
    return WaCrmConversation(
      id: json['id'] as String,
      instanceId: json['instanceId'] as String? ?? json['instance_id'] as String? ?? '',
      remoteJid: json['remoteJid'] as String? ?? json['remote_jid'] as String? ?? '',
      remotePhone: json['remotePhone'] as String? ?? json['remote_phone'] as String?,
      remoteName: json['remoteName'] as String? ?? json['remote_name'] as String?,
      lastMessageAt: _parseDate(json['lastMessageAt'] ?? json['last_message_at']),
      unreadCount: (json['unreadCount'] as num?)?.toInt() ??
          (json['unread_count'] as num?)?.toInt() ??
          0,
      lastMessage: lastMsg,
    );
  }

  static DateTime? _parseDate(dynamic v) {
    if (v == null) return null;
    if (v is String) return DateTime.tryParse(v);
    return null;
  }
}
