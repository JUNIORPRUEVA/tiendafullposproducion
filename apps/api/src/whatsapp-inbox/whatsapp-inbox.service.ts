import { Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { WhatsappMessageDirection, WhatsappMessageType } from '@prisma/client';
import { CatalogRealtimeRelayService } from '../products/catalog-realtime-relay.service';

export interface ParsedWhatsappMessage {
  evolutionId: string;
  remoteJid: string;
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

@Injectable()
export class WhatsappInboxService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly realtime: CatalogRealtimeRelayService,
  ) {}

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
        rawMessageType === 'conversation' ||
        rawMessageType === 'extendedTextMessage'
      ) {
        messageType = WhatsappMessageType.TEXT;
        body =
          (messageObj.conversation as string | undefined) ??
          ((messageObj.extendedTextMessage as Record<string, unknown> | undefined)
            ?.text as string | undefined) ??
          null;
      } else if (rawMessageType === 'imageMessage') {
        messageType = WhatsappMessageType.IMAGE;
        const img = messageObj.imageMessage as Record<string, unknown> | undefined;
        mediaUrl = (img?.url as string | undefined) ?? null;
        mediaMimeType = (img?.mimetype as string | undefined) ?? 'image/jpeg';
        caption = (img?.caption as string | undefined) ?? null;
        body = caption;
      } else if (rawMessageType === 'audioMessage' || rawMessageType === 'pttMessage') {
        messageType = WhatsappMessageType.AUDIO;
        const audio =
          (messageObj.audioMessage ?? messageObj.pttMessage) as
            | Record<string, unknown>
            | undefined;
        mediaUrl = (audio?.url as string | undefined) ?? null;
        mediaMimeType = (audio?.mimetype as string | undefined) ?? 'audio/ogg';
      } else if (rawMessageType === 'videoMessage') {
        messageType = WhatsappMessageType.VIDEO;
        const vid = messageObj.videoMessage as Record<string, unknown> | undefined;
        mediaUrl = (vid?.url as string | undefined) ?? null;
        mediaMimeType = (vid?.mimetype as string | undefined) ?? 'video/mp4';
        caption = (vid?.caption as string | undefined) ?? null;
        body = caption;
      } else if (rawMessageType === 'documentMessage') {
        messageType = WhatsappMessageType.DOCUMENT;
        const doc = messageObj.documentMessage as Record<string, unknown> | undefined;
        mediaUrl = (doc?.url as string | undefined) ?? null;
        mediaMimeType = (doc?.mimetype as string | undefined) ?? null;
        body = (doc?.fileName as string | undefined) ?? null;
      } else if (rawMessageType === 'stickerMessage') {
        messageType = WhatsappMessageType.STICKER;
        const sticker = messageObj.stickerMessage as Record<string, unknown> | undefined;
        mediaUrl = (sticker?.url as string | undefined) ?? null;
      } else {
        // Unknown type: store raw body if possible
        body = JSON.stringify(messageObj).substring(0, 500);
      }

      return {
        evolutionId,
        remoteJid,
        fromMe,
        messageType,
        body,
        mediaUrl,
        mediaMimeType,
        caption,
        senderName: fromMe ? null : pushName,
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

    const remotePhone = parsed.remoteJid.replace(/@.*$/, '');

    // Upsert conversation
    const conversation = await this.prisma.whatsappConversation.upsert({
      where: { instanceId_remoteJid: { instanceId, remoteJid: parsed.remoteJid } },
      create: {
        instanceId,
        remoteJid: parsed.remoteJid,
        remotePhone,
        remoteName: parsed.senderName,
        lastMessageAt: parsed.sentAt,
        unreadCount: direction === WhatsappMessageDirection.INCOMING ? 1 : 0,
      },
      update: {
        lastMessageAt: parsed.sentAt,
        ...(parsed.senderName ? { remoteName: parsed.senderName } : {}),
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
    return this.prisma.whatsappConversation.findMany({
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
  }

  // ─── Query messages for a conversation ───────────────────────────────

  async getMessages(conversationId: string, limit = 50, before?: Date) {
    return this.prisma.whatsappMessage.findMany({
      where: {
        conversationId,
        ...(before ? { sentAt: { lt: before } } : {}),
      },
      orderBy: { sentAt: 'desc' },
      take: limit,
    });
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
