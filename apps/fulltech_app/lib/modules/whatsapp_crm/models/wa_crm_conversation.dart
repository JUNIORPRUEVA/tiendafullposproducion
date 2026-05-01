import 'wa_crm_message.dart';

String? _safeConversationText(dynamic value) {
  if (value is! String) return null;
  final units = value.codeUnits;
  final out = StringBuffer();
  for (var i = 0; i < units.length; i++) {
    final unit = units[i];
    if (unit >= 0xD800 && unit <= 0xDBFF) {
      if (i + 1 < units.length) {
        final next = units[i + 1];
        if (next >= 0xDC00 && next <= 0xDFFF) {
          out.writeCharCode(unit);
          out.writeCharCode(next);
          i++;
          continue;
        }
      }
      out.write('\uFFFD');
      continue;
    }
    if (unit >= 0xDC00 && unit <= 0xDFFF) {
      out.write('\uFFFD');
      continue;
    }
    out.writeCharCode(unit);
  }
  return out.toString();
}

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

  String? get cleanPhone {
    final candidates = [remotePhone, remoteJid];
    for (final value in candidates) {
      final raw = (value ?? '').trim().toLowerCase();
      if (raw.isEmpty) continue;
      final beforeAt = raw.split('@').first;
      final beforeDevice = beforeAt.split(':').first;
      final digits = beforeDevice.replaceAll(RegExp(r'\D'), '');
      if (digits.length >= 7 && digits.length <= 15) return digits;
    }
    return null;
  }

  String get mergeKey => '$instanceId:${cleanPhone ?? remoteJid}';

  String? get displayPhone {
    final phone = cleanPhone;
    if (phone == null) return null;
    return '+$phone';
  }

  bool _looksTechnicalId(String value) {
    if (value.contains('@')) return true;
    final digits = value.replaceAll(RegExp(r'\D'), '');
    return digits.length > 15;
  }

  String get displayName {
    final name = (remoteName ?? '').trim();
    if (name.isNotEmpty &&
        name.toLowerCase() != 'me' &&
        !_looksTechnicalId(name)) {
      return name;
    }
    final phone = displayPhone;
    if (phone != null) return phone;
    return 'Contacto WhatsApp';
  }

  factory WaCrmConversation.fromJson(Map<String, dynamic> json) {
    final msgs = json['messages'] as List<dynamic>?;
    WaCrmMessage? lastMsg;
    if (msgs != null && msgs.isNotEmpty) {
      try {
        lastMsg = WaCrmMessage.fromJson(msgs.first as Map<String, dynamic>);
      } catch (_) {}
    }
    return WaCrmConversation(
      id: _safeConversationText(json['id']) ?? '',
      instanceId:
          _safeConversationText(json['instanceId'] ?? json['instance_id']) ??
          '',
      remoteJid:
          _safeConversationText(json['remoteJid'] ?? json['remote_jid']) ?? '',
      remotePhone: _safeConversationText(
        json['remotePhone'] ?? json['remote_phone'],
      ),
      remoteName: _safeConversationText(
        json['remoteName'] ?? json['remote_name'],
      ),
      lastMessageAt: _parseDate(
        json['lastMessageAt'] ?? json['last_message_at'],
      ),
      unreadCount:
          (json['unreadCount'] as num?)?.toInt() ??
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
