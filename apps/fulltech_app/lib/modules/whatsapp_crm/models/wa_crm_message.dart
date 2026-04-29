enum WaMessageDirection { incoming, outgoing }

enum WaMessageType { text, image, audio, video, document, sticker, other }

class WaCrmMessage {
  const WaCrmMessage({
    required this.id,
    required this.conversationId,
    required this.direction,
    required this.messageType,
    required this.sentAt,
    this.evolutionId,
    this.body,
    this.mediaUrl,
    this.mediaMimeType,
    this.caption,
    this.senderName,
  });

  final String id;
  final String conversationId;
  final WaMessageDirection direction;
  final WaMessageType messageType;
  final DateTime sentAt;
  final String? evolutionId;
  final String? body;
  final String? mediaUrl;
  final String? mediaMimeType;
  final String? caption;
  final String? senderName;

  bool get isOutgoing => direction == WaMessageDirection.outgoing;
  bool get isIncoming => direction == WaMessageDirection.incoming;

  String get previewText {
    switch (messageType) {
      case WaMessageType.image:
        return caption?.isNotEmpty == true ? '📷 ${caption!}' : '📷 Imagen';
      case WaMessageType.audio:
        return '🎵 Audio';
      case WaMessageType.video:
        return '🎬 Video';
      case WaMessageType.document:
        return '📄 ${body ?? 'Documento'}';
      case WaMessageType.sticker:
        return '😀 Sticker';
      default:
        return body ?? '';
    }
  }

  factory WaCrmMessage.fromJson(Map<String, dynamic> json) {
    return WaCrmMessage(
      id: json['id'] as String,
      conversationId: json['conversationId'] as String? ??
          json['conversation_id'] as String? ??
          '',
      direction: _parseDirection(
          json['direction'] as String? ?? 'INCOMING'),
      messageType: _parseType(
          json['messageType'] as String? ?? json['message_type'] as String? ?? 'TEXT'),
      sentAt: _parseDate(json['sentAt'] ?? json['sent_at']) ?? DateTime.now(),
      evolutionId: json['evolutionId'] as String? ?? json['evolution_id'] as String?,
      body: json['body'] as String?,
      mediaUrl: json['mediaUrl'] as String? ?? json['media_url'] as String?,
      mediaMimeType: json['mediaMimeType'] as String? ?? json['media_mime_type'] as String?,
      caption: json['caption'] as String?,
      senderName: json['senderName'] as String? ?? json['sender_name'] as String?,
    );
  }

  static WaMessageDirection _parseDirection(String v) {
    switch (v.toUpperCase()) {
      case 'OUTGOING':
        return WaMessageDirection.outgoing;
      default:
        return WaMessageDirection.incoming;
    }
  }

  static WaMessageType _parseType(String v) {
    switch (v.toUpperCase()) {
      case 'IMAGE':
        return WaMessageType.image;
      case 'AUDIO':
        return WaMessageType.audio;
      case 'VIDEO':
        return WaMessageType.video;
      case 'DOCUMENT':
        return WaMessageType.document;
      case 'STICKER':
        return WaMessageType.sticker;
      case 'OTHER':
        return WaMessageType.other;
      default:
        return WaMessageType.text;
    }
  }

  static DateTime? _parseDate(dynamic v) {
    if (v == null) return null;
    if (v is String) return DateTime.tryParse(v);
    return null;
  }
}
