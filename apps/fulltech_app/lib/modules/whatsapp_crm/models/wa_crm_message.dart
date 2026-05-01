enum WaMessageDirection { incoming, outgoing }

enum WaMessageType { text, image, audio, video, document, sticker, other }

String? sanitizeWaText(dynamic value) {
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
        return caption?.isNotEmpty == true ? 'Imagen: ${caption!}' : 'Imagen';
      case WaMessageType.audio:
        return 'Audio';
      case WaMessageType.video:
        return 'Video';
      case WaMessageType.document:
        return body ?? 'Documento';
      case WaMessageType.sticker:
        return 'Sticker';
      default:
        return body ?? '';
    }
  }

  factory WaCrmMessage.fromJson(Map<String, dynamic> json) {
    return WaCrmMessage(
      id: sanitizeWaText(json['id']) ?? '',
      conversationId:
          sanitizeWaText(json['conversationId'] ?? json['conversation_id']) ??
          '',
      direction: _parseDirection(
        sanitizeWaText(json['direction']) ?? 'INCOMING',
      ),
      messageType: _parseType(
        sanitizeWaText(json['messageType'] ?? json['message_type']) ?? 'TEXT',
      ),
      sentAt: _parseDate(json['sentAt'] ?? json['sent_at']) ?? DateTime.now(),
      evolutionId: sanitizeWaText(json['evolutionId'] ?? json['evolution_id']),
      body: sanitizeWaText(json['body']),
      mediaUrl: sanitizeWaText(json['mediaUrl'] ?? json['media_url']),
      mediaMimeType: sanitizeWaText(
        json['mediaMimeType'] ?? json['media_mime_type'],
      ),
      caption: sanitizeWaText(json['caption']),
      senderName: sanitizeWaText(json['senderName'] ?? json['sender_name']),
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
