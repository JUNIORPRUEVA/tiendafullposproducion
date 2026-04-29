import { Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { WhatsappMessageDirection, WhatsappMessageType } from '@prisma/client';
import { CatalogRealtimeRelayService } from '../products/catalog-realtime-relay.service';

export interface ParsedWhatsappMessage {
  evolutionId: string;
  remoteJid: string;
  remotePhone: string | null;
  fromMe: boolean;
  messageType: WhatsappMessageType;
  body: string | null;
  mediaUrl: string | null;
  mediaMimeType: string | null;
  caption: string | null;
  senderName: string | null;
  sentAt: Date;
  rawPayload: unknown;
}

type JsonRecord = Record<string, unknown>;

function asRecord(value: unknown): JsonRecord | undefined {
  return value && typeof value === 'object' && !Array.isArray(value)
    ? (value as JsonRecord)
    : undefined;
}

function asString(value: unknown): string | undefined {
  return typeof value === 'string' && value.trim().length > 0
    ? value.trim()
    : undefined;
}

function stripWhatsappSuffix(value: unknown): string | null {
  const raw = asString(value);
  if (!raw) return null;
  return raw.split('@')[0]?.trim() || null;
}

function phoneFromIdentifier(value: unknown): string | null {
  const base = stripWhatsappSuffix(value);
  if (!base) return null;
  const digits = base.replace(/\D/g, '');
  // Human phone numbers are normally 7-15 digits. Longer numeric IDs are often LID/internal IDs.
  if (digits.length < 7 || digits.length > 15) return null;
  return digits;
}

function firstPhone(...values: unknown[]): string | null {
  for (const value of values) {
    const phone = phoneFromIdentifier(value);
    if (phone) return phone;
  }
  return null;
}

function readableSenderName(name: unknown, fallbackPhone: string | null): string | null {
  const raw = asString(name);
  if (!raw) return fallbackPhone;
  if (raw.includes('@')) return fallbackPhone;
  const digits = raw.replace(/\D/g, '');
  if (digits.length > 15) return fallbackPhone;
  return raw;
}

function mediaMime(media: JsonRecord | undefined, data: JsonRecord, fallback: string | null) {
  return (
    asString(media?.mimetype) ??
    asString(media?.mimeType) ??
    asString(data.mimetype) ??
    asString(data.mimeType) ??
    fallback
  );
}

function mediaUrlFromPayload(
  media: JsonRecord | undefined,
  messageObj: JsonRecord,
  data: JsonRecord,
  mimeType: string | null,
) {
  const base64 =
    asString(media?.base64) ??
    asString(messageObj.base64) ??
    asString(data.base64) ??
    null;
  if (base64) {
    if (base64.startsWith('data:')) return base64;
    return `data:${mimeType ?? 'application/octet-stream'};base64,${base64}`;
  }

  return (
    asString(media?.mediaUrl) ??
    asString(media?.url) ??
    asString(messageObj.mediaUrl) ??
    asString(messageObj.url) ??
    asString(data.mediaUrl) ??
    asString(data.url) ??
    null
  );
}

@Injectable()
export class WhatsappInboxService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly realtime: CatalogRealtimeRelayService,
  ) {}

  private normalizeConversationForResponse<T extends { remoteJid: string; remotePhone: string | null; remoteName: string | null }>(
    conversation: T,
  ): T {
    const cleanPhone =
      phoneFromIdentifier(conversation.remotePhone) ??
      phoneFromIdentifier(conversation.remoteJid);
    return {
      ...conversation,
      remotePhone: cleanPhone,
      remoteName: readableSenderName(conversation.remoteName, cleanPhone),
    };
  }

  private hydrateMessageMedia<T extends { mediaUrl: string | null; mediaMimeType: string | null; rawPayload?: unknown }>(
    message: T,
  ): T {
    if (message.mediaUrl || !message.rawPayload) return message;
    const parsed = this.parseEvolutionPayload(message.rawPayload);
    if (!parsed?.mediaUrl) return message;
    return {
      ...message,
      mediaUrl: parsed.mediaUrl,
      mediaMimeType: parsed.mediaMimeType ?? message.mediaMimeType,
    };
  }

  // ─── Parse Evolution API webhook payload ───────────────────────────────

  parseEvolutionPayload(payload: unknown): ParsedWhatsappMessage | null {
    try {
      const p = payload as Record<string, unknown>;
      // Evolution API wraps message data in p.data
      const data = (p.data ?? p) as Record<string, unknown>;
      const key = data.key as Record<string, unknown> | undefined;
      if (!key) return null;

      const remoteJid = key.remoteJid as string | undefined;
      if (!remoteJid || remoteJid === 'status@broadcast') return null;

      const fromMe = Boolean(key.fromMe);
      const evolutionId = (key.id as string | undefined) ?? '';
      const pushName = (data.pushName as string | undefined) ?? null;
      const rawMessageType = (data.messageType as string | undefined) ?? '';
      const messageObj = (data.message as Record<string, unknown> | undefined) ?? {};
      const participantJid =
        asString(key.participant) ??
        asString(data.participant) ??
        asString(data.sender) ??
        asString(data.senderPn) ??
        null;
      const remotePhone = firstPhone(
        data.senderPn,
        data.phone,
        data.remotePhone,
        participantJid,
        remoteJid,
      );
      const senderName = fromMe ? null : readableSenderName(pushName, remotePhone);
      const normalizedMessageType = rawMessageType.toLowerCase();
      const ts = data.messageTimestamp;
      const sentAt = ts
        ? new Date(typeof ts === 'number' ? ts * 1000 : Number(ts) * 1000)
        : new Date();

      let messageType: WhatsappMessageType = WhatsappMessageType.OTHER;
      let body: string | null = null;
      let mediaUrl: string | null = null;
      let mediaMimeType: string | null = null;
      let caption: string | null = null;

      if (
        normalizedMessageType === 'conversation' ||
        normalizedMessageType === 'extendedtextmessage' ||
        normalizedMessageType === 'text'
      ) {
        messageType = WhatsappMessageType.TEXT;
        body =
          (messageObj.conversation as string | undefined) ??
          ((messageObj.extendedTextMessage as Record<string, unknown> | undefined)
            ?.text as string | undefined) ??
          null;
      } else if (normalizedMessageType === 'imagemessage' || normalizedMessageType === 'image' || messageObj.imageMessage) {
        messageType = WhatsappMessageType.IMAGE;
        const img = asRecord(messageObj.imageMessage) ?? messageObj;
        mediaMimeType = mediaMime(img, data, 'image/jpeg');
        mediaUrl = mediaUrlFromPayload(img, messageObj, data, mediaMimeType);
        caption = (img?.caption as string | undefined) ?? null;
        body = caption;
      } else if (
        normalizedMessageType === 'audiomessage' ||
        normalizedMessageType === 'pttmessage' ||
        normalizedMessageType === 'audio' ||
        normalizedMessageType === 'ptt' ||
        messageObj.audioMessage ||
        messageObj.pttMessage
      ) {
        messageType = WhatsappMessageType.AUDIO;
        const audio =
          asRecord(messageObj.audioMessage) ?? asRecord(messageObj.pttMessage) ?? messageObj;
        mediaMimeType = mediaMime(audio, data, 'audio/ogg');
        mediaUrl = mediaUrlFromPayload(audio, messageObj, data, mediaMimeType);
      } else if (normalizedMessageType === 'videomessage' || normalizedMessageType === 'video' || messageObj.videoMessage) {
        messageType = WhatsappMessageType.VIDEO;
        const vid = asRecord(messageObj.videoMessage) ?? messageObj;
        mediaMimeType = mediaMime(vid, data, 'video/mp4');
        mediaUrl = mediaUrlFromPayload(vid, messageObj, data, mediaMimeType);
        caption = (vid?.caption as string | undefined) ?? null;
        body = caption;
      } else if (normalizedMessageType === 'documentmessage' || normalizedMessageType === 'document' || messageObj.documentMessage) {
        messageType = WhatsappMessageType.DOCUMENT;
        const doc = asRecord(messageObj.documentMessage) ?? messageObj;
        mediaMimeType = mediaMime(doc, data, null);
        mediaUrl = mediaUrlFromPayload(doc, messageObj, data, mediaMimeType);
        body = (doc?.fileName as string | undefined) ?? null;
      } else if (normalizedMessageType === 'stickermessage' || normalizedMessageType === 'sticker' || messageObj.stickerMessage) {
        messageType = WhatsappMessageType.STICKER;
        const sticker = asRecord(messageObj.stickerMessage) ?? messageObj;
        mediaMimeType = mediaMime(sticker, data, 'image/webp');
        mediaUrl = mediaUrlFromPayload(sticker, messageObj, data, mediaMimeType);
      } else {
        // Unknown type: store raw body if possible
        body = JSON.stringify(messageObj).substring(0, 500);
      }

      return {
        evolutionId,
        remoteJid,
        remotePhone,
        fromMe,
        messageType,
        body,
        mediaUrl,
        mediaMimeType,
        caption,
        senderName,
        sentAt,
        rawPayload: payload,
      };
    } catch (err) {
      console.error('[WhatsappInbox] parseEvolutionPayload error:', err);
      return null;
    }
  }

  // ─── Save incoming/outgoing message to DB ──────────────────────────────

  async saveMessage(instanceId: string, parsed: ParsedWhatsappMessage) {
    const direction = parsed.fromMe
      ? WhatsappMessageDirection.OUTGOING
      : WhatsappMessageDirection.INCOMING;

    const remotePhone = parsed.remotePhone ?? phoneFromIdentifier(parsed.remoteJid);
    const remoteName = parsed.senderName ?? remotePhone;

    // Upsert conversation
    const conversation = await this.prisma.whatsappConversation.upsert({
      where: { instanceId_remoteJid: { instanceId, remoteJid: parsed.remoteJid } },
      create: {
        instanceId,
        remoteJid: parsed.remoteJid,
        remotePhone,
        remoteName,
        lastMessageAt: parsed.sentAt,
        unreadCount: direction === WhatsappMessageDirection.INCOMING ? 1 : 0,
      },
      update: {
        lastMessageAt: parsed.sentAt,
        ...(remotePhone ? { remotePhone } : {}),
        ...(remoteName ? { remoteName } : {}),
        ...(direction === WhatsappMessageDirection.INCOMING
          ? { unreadCount: { increment: 1 } }
          : {}),
      },
    });

    // Skip duplicate Evolution IDs
    if (parsed.evolutionId) {
      const existing = await this.prisma.whatsappMessage.findUnique({
        where: { evolutionId: parsed.evolutionId },
        select: { id: true },
      });
      if (existing) return { conversation, message: existing, duplicate: true };

      // For outgoing messages: if a local optimistic record exists (null evolutionId,
      // same body, sent within the last 90 seconds), update it instead of creating a duplicate.
      if (direction === WhatsappMessageDirection.OUTGOING) {
        const since = new Date(Date.now() - 90_000);
        const optimistic = await this.prisma.whatsappMessage.findFirst({
          where: {
            conversationId: conversation.id,
            direction: WhatsappMessageDirection.OUTGOING,
            evolutionId: null,
            sentAt: { gte: since },
            body: parsed.body,
          },
          orderBy: { sentAt: 'desc' },
        });
        if (optimistic) {
          const updated = await this.prisma.whatsappMessage.update({
            where: { id: optimistic.id },
            data: {
              evolutionId: parsed.evolutionId,
              mediaUrl: parsed.mediaUrl ?? optimistic.mediaUrl,
              mediaMimeType: parsed.mediaMimeType ?? optimistic.mediaMimeType,
            },
          });
          return { conversation, message: updated, duplicate: false };
        }
      }
    }

    const message = await this.prisma.whatsappMessage.create({
      data: {
        conversationId: conversation.id,
        evolutionId: parsed.evolutionId || null,
        direction,
        messageType: parsed.messageType,
        body: parsed.body,
        mediaUrl: parsed.mediaUrl,
        mediaMimeType: parsed.mediaMimeType,
        caption: parsed.caption,
        senderName: parsed.senderName,
        sentAt: parsed.sentAt,
        rawPayload: parsed.rawPayload as object,
      },
    });

    // Emit realtime event to all admin sockets
    this.realtime.emitTo('ops:role:admin', 'whatsapp.message', {
      eventId: message.id,
      conversationId: conversation.id,
      instanceId,
      message: {
        id: message.id,
        direction,
        messageType: message.messageType,
        body: message.body,
        mediaUrl: message.mediaUrl,
        mediaMimeType: message.mediaMimeType,
        caption: message.caption,
        senderName: message.senderName,
        sentAt: message.sentAt,
        evolutionId: message.evolutionId,
      },
      conversation: {
        id: conversation.id,
        instanceId,
        remoteJid: conversation.remoteJid,
        remotePhone: conversation.remotePhone,
        remoteName: conversation.remoteName,
        lastMessageAt: conversation.lastMessageAt,
        unreadCount: conversation.unreadCount,
      },
    });

    return { conversation, message, duplicate: false };
  }

  // ─── Query conversations for an instance ──────────────────────────────

  async getConversations(instanceId: string, limit = 50) {
    const conversations = await this.prisma.whatsappConversation.findMany({
      where: { instanceId },
      orderBy: { lastMessageAt: 'desc' },
      take: limit,
      include: {
        messages: {
          orderBy: { sentAt: 'desc' },
          take: 1,
          select: {
            id: true,
            direction: true,
            messageType: true,
            body: true,
            caption: true,
            sentAt: true,
          },
        },
      },
    });
    return conversations.map((conversation) =>
      this.normalizeConversationForResponse(conversation),
    );
  }

  // ─── Query messages for a conversation ───────────────────────────────

  async getMessages(conversationId: string, limit = 50, before?: Date) {
    const messages = await this.prisma.whatsappMessage.findMany({
      where: {
        conversationId,
        ...(before ? { sentAt: { lt: before } } : {}),
      },
      orderBy: { sentAt: 'desc' },
      take: limit,
    });
    return messages.map((message) => this.hydrateMessageMedia(message));
  }

  // ─── Mark conversation as read ────────────────────────────────────────

  async markRead(conversationId: string) {
    return this.prisma.whatsappConversation.update({
      where: { id: conversationId },
      data: { unreadCount: 0 },
    });
  }

  // ─── List users with whatsapp instances (for admin user selector) ────

  async listUsersWithInstances() {
    return this.prisma.userWhatsappInstance.findMany({
      include: {
        user: {
          select: { id: true, nombreCompleto: true, role: true, telefono: true },
        },
      },
      orderBy: { createdAt: 'asc' },
    });
  }

  // ─── Get instance by userId ──────────────────────────────────────────

  async getInstanceByUserId(userId: string) {
    const instance = await this.prisma.userWhatsappInstance.findUnique({
      where: { userId },
    });
    if (!instance) throw new NotFoundException('Instance not found for user');
    return instance;
  }

  // ─── Record a message sent via Evolution API (outgoing) ──────────────

  async recordOutgoingMessage(
    instanceId: string,
    remoteJid: string,
    body: string,
    evolutionId?: string,
  ) {
    const parsed: ParsedWhatsappMessage = {
      evolutionId: evolutionId ?? '',
      remoteJid,
      remotePhone: phoneFromIdentifier(remoteJid),
      fromMe: true,
      messageType: WhatsappMessageType.TEXT,
      body,
      mediaUrl: null,
      mediaMimeType: null,
      caption: null,
      senderName: null,
      sentAt: new Date(),
      rawPayload: null,
    };
    return this.saveMessage(instanceId, parsed);
  }
}
