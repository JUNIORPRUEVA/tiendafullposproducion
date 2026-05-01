import { BadRequestException, Injectable, NotFoundException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { PrismaService } from '../prisma/prisma.service';
import { WhatsappMessageDirection, WhatsappMessageType } from '@prisma/client';
import { CatalogRealtimeRelayService } from '../products/catalog-realtime-relay.service';
import { WhatsappService } from '../whatsapp/whatsapp.service';

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

function collectEvolutionMessageRecords(value: unknown): unknown[] {
  if (Array.isArray(value)) return value;
  const record = asRecord(value);
  if (!record) return [];
  for (const key of ['messages', 'records', 'data', 'items', 'rows']) {
    const nested = record[key];
    if (Array.isArray(nested)) return nested;
    const nestedRecord = asRecord(nested);
    if (nestedRecord) {
      const nestedMessages = collectEvolutionMessageRecords(nestedRecord);
      if (nestedMessages.length > 0) return nestedMessages;
    }
  }
  return [];
}

@Injectable()
export class WhatsappInboxService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly realtime: CatalogRealtimeRelayService,
    private readonly config: ConfigService,
    private readonly whatsappService: WhatsappService,
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

  parseEvolutionPayloads(payload: unknown): ParsedWhatsappMessage[] {
    const p = asRecord(payload);
    if (!p) return [];

    const records = collectEvolutionMessageRecords(payload);
    if (records.length > 0) {
      return records
          .map((item) => this.parseEvolutionPayload({ ...p, data: item }))
          .filter((item): item is ParsedWhatsappMessage => !!item);
    }

    const parsed = this.parseEvolutionPayload(payload);
    return parsed ? [parsed] : [];
  }

  parseEvolutionPayload(payload: unknown): ParsedWhatsappMessage | null {
    try {
      const p = asRecord(payload);
      if (!p) return null;
      // Evolution API wraps message data in p.data
      const data = asRecord(p.data) ?? asRecord(p.message) ?? p;
      const messageObj =
        asRecord(data.message) ??
        asRecord(data.messageData) ??
        asRecord(data.messageContent) ??
        {};
      const key = asRecord(data.key) ?? asRecord(messageObj.key) ?? asRecord(p.key);
      if (!key) return null;

      const remoteJid =
        asString(key.remoteJid) ??
        asString(data.remoteJid) ??
        asString(data.chatId) ??
        asString(data.to) ??
        asString(data.number) ??
        asString(data.recipient);
      if (!remoteJid || remoteJid === 'status@broadcast') return null;

      const eventName = asString(p.event)?.toUpperCase() ?? '';
      const fromMe = key.fromMe === undefined
        ? eventName === 'SEND_MESSAGE' || data.fromMe === true
        : Boolean(key.fromMe);
      const evolutionId =
        asString(key.id) ??
        asString(data.id) ??
        asString(data.messageId) ??
        '';
      const pushName = asString(data.pushName) ?? null;
      const rawMessageType =
        asString(data.messageType) ??
        asString(data.type) ??
        (asString(messageObj.conversation)
          ? 'conversation'
          : messageObj.extendedTextMessage
            ? 'extendedTextMessage'
            : '');
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
        data.number,
        data.to,
        data.recipient,
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
        const text =
          asString(messageObj.conversation) ??
          asString(asRecord(messageObj.extendedTextMessage)?.text) ??
          asString(data.text) ??
          asString(data.body) ??
          asString(data.messageText) ??
          null;
        if (text) {
          messageType = WhatsappMessageType.TEXT;
          body = text;
        } else {
          // Unknown type: store raw body if possible
          body = JSON.stringify(messageObj).substring(0, 500);
        }
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
    if (!before) {
      await this.syncConversationFromEvolution(conversationId).catch((error) => {
        console.warn(
          `[WhatsappInbox] No se pudo sincronizar conversacion ${conversationId}: ${
            error instanceof Error ? error.message : String(error)
          }`,
        );
      });
    }

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

  async syncConversationFromEvolution(conversationId: string) {
    const conversation = await this.prisma.whatsappConversation.findUnique({
      where: { id: conversationId },
      include: { instance: true },
    });
    if (!conversation) return { synced: 0 };

    const raw = await this.whatsappService.findChatMessages(
      conversation.instance.instanceName,
      conversation.remoteJid,
    );
    const records = collectEvolutionMessageRecords(raw);
    let synced = 0;

    for (const record of records) {
      const parsed = this.parseEvolutionPayload({ data: record });
      if (!parsed) continue;
      if (parsed.remoteJid !== conversation.remoteJid) continue;
      const result = await this.saveMessage(conversation.instanceId, parsed);
      if (!result.duplicate) synced++;
    }

    return { synced };
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

  async attachEvolutionIdToMessage(messageId: string, evolutionId?: string | null) {
    const cleanId = (evolutionId ?? '').trim();
    if (!cleanId) return null;

    const existing = await this.prisma.whatsappMessage.findUnique({
      where: { evolutionId: cleanId },
      select: { id: true },
    });
    if (existing) return existing;

    return this.prisma.whatsappMessage.update({
      where: { id: messageId },
      data: { evolutionId: cleanId },
      select: { id: true },
    });
  }

  async summarizeDailyActivity(userId: string, dateIso: string) {
    const date = /^\d{4}-\d{2}-\d{2}$/.test(dateIso)
      ? dateIso
      : new Date(dateIso).toISOString().slice(0, 10);
    if (!date) throw new BadRequestException('Fecha invalida');

    const instance = await this.prisma.userWhatsappInstance.findUnique({
      where: { userId },
      include: {
        user: { select: { id: true, nombreCompleto: true, role: true } },
      },
    });
    if (!instance) throw new NotFoundException('Instance not found for user');

    const start = new Date(`${date}T00:00:00-04:00`);
    const end = new Date(start.getTime() + 24 * 60 * 60 * 1000);

    const messages = await this.prisma.whatsappMessage.findMany({
      where: {
        sentAt: { gte: start, lt: end },
        conversation: { instanceId: instance.id },
      },
      orderBy: { sentAt: 'asc' },
      include: {
        conversation: {
          select: {
            id: true,
            remoteJid: true,
            remotePhone: true,
            remoteName: true,
          },
        },
      },
      take: 1200,
    });

    const contacts = new Set(messages.map((m) => m.conversationId));
    const incoming = messages.filter((m) => m.direction === WhatsappMessageDirection.INCOMING);
    const outgoing = messages.filter((m) => m.direction === WhatsappMessageDirection.OUTGOING);
    const media = messages.filter((m) => m.messageType !== WhatsappMessageType.TEXT);

    const stats = {
      date,
      userName: instance.user?.nombreCompleto ?? instance.instanceName,
      instanceName: instance.instanceName,
      totalMessages: messages.length,
      incomingMessages: incoming.length,
      outgoingMessages: outgoing.length,
      contacts: contacts.size,
      mediaMessages: media.length,
    };

    if (messages.length === 0) {
      return {
        source: 'rules-only',
        stats,
        summary:
          'No hay mensajes registrados para este usuario en la fecha seleccionada. Verifica que el webhook de la instancia este activo y que Evolution este enviando los eventos MESSAGES_UPSERT y SEND_MESSAGE.',
      };
    }

    const transcript = messages.map((m) => ({
      time: m.sentAt.toISOString().slice(11, 16),
      direction: m.direction === WhatsappMessageDirection.OUTGOING ? 'usuario' : 'cliente',
      contact: readableSenderName(m.conversation.remoteName, m.conversation.remotePhone) ??
        m.conversation.remotePhone ??
        m.conversation.remoteJid,
      type: m.messageType,
      text: (m.body ?? m.caption ?? '').replace(/\s+/g, ' ').trim().slice(0, 900),
    }));

    const runtime = await this.getOpenAiRuntimeConfig();
    if (!runtime.apiKey) {
      return {
        source: 'rules-only',
        stats,
        summary: this.buildDeterministicDailySummary(stats, transcript),
      };
    }

    try {
      const ai = await this.requestDailySummaryFromOpenAi(runtime, {
        stats,
        transcript,
      });
      return {
        source: 'openai',
        stats,
        summary: ai.summary || this.buildDeterministicDailySummary(stats, transcript),
      };
    } catch {
      return {
        source: 'rules-only',
        stats,
        summary: this.buildDeterministicDailySummary(stats, transcript),
      };
    }
  }

  private async getOpenAiRuntimeConfig() {
    const envKey = (this.config.get<string>('OPENAI_API_KEY') ?? process.env.OPENAI_API_KEY ?? '').trim();
    const envModel = (this.config.get<string>('OPENAI_MODEL') ?? process.env.OPENAI_MODEL ?? '').trim();
    const appConfig = await this.prisma.appConfig.findUnique({
      where: { id: 'global' },
      select: { openAiApiKey: true, openAiModel: true, companyName: true },
    }).catch(() => null);

    return {
      apiKey: envKey.length > 0 ? envKey : (appConfig?.openAiApiKey ?? '').trim(),
      model: envModel.length > 0 ? envModel : ((appConfig?.openAiModel ?? '').trim() || 'gpt-4o-mini'),
      companyName: (appConfig?.companyName ?? 'FULLTECH').trim() || 'FULLTECH',
    };
  }

  private buildDeterministicDailySummary(
    stats: {
      date: string;
      userName: string;
      totalMessages: number;
      incomingMessages: number;
      outgoingMessages: number;
      contacts: number;
      mediaMessages: number;
    },
    transcript: Array<{ direction: string; text: string; contact: string }>,
  ) {
    const interestWords = ['precio', 'cotizacion', 'cotización', 'quiero', 'interesa', 'disponible', 'comprar', 'instalar'];
    const followWords = ['mañana', 'luego', 'despues', 'después', 'pendiente', 'seguimiento', 'confirmar'];
    const interested = new Set<string>();
    const followups = new Set<string>();

    for (const item of transcript) {
      const text = item.text.toLowerCase();
      if (interestWords.some((word) => text.includes(word))) interested.add(item.contact);
      if (followWords.some((word) => text.includes(word))) followups.add(item.contact);
    }

    return [
      `Resumen del ${stats.date} para ${stats.userName}.`,
      `Actividad: ${stats.totalMessages} mensajes en ${stats.contacts} contactos. Recibidos: ${stats.incomingMessages}. Enviados desde la instancia: ${stats.outgoingMessages}. Multimedia: ${stats.mediaMessages}.`,
      `Interes comercial detectado: ${interested.size} contacto(s) con señales de compra, cotizacion o disponibilidad.`,
      `Seguimientos detectados: ${followups.size} contacto(s) con menciones de pendiente, confirmar o retomar.`,
      'Recomendacion: revisar los contactos con interes y confirmar que cada conversacion tenga proximo paso claro, monto/categoria y responsable.',
    ].join('\n\n');
  }

  private async requestDailySummaryFromOpenAi(
    runtime: { apiKey: string; model: string; companyName: string },
    payload: unknown,
  ): Promise<{ summary?: string }> {
    const candidates = [runtime.model, 'gpt-5', 'gpt-4.1', 'gpt-4o', 'gpt-4o-mini']
      .filter((value, index, list) => value && list.indexOf(value) === index);
    const systemPrompt =
      `Eres un analista CRM de ${runtime.companyName}. Resume actividad diaria de WhatsApp para auditar ventas y seguimiento. ` +
      'Usa solo los mensajes enviados. No inventes ventas. Escribe en espanol profesional, claro y accionable.';
    const userPrompt =
      `${JSON.stringify(payload)}\n\n` +
      'Devuelve JSON exacto {"summary":"string"}. El summary debe incluir: panorama del dia, rendimiento del usuario, clientes/interesados/no interesados si se puede inferir, categorias mencionadas, seguimientos dados/no dados, oportunidades y alertas.';

    for (const model of candidates) {
      try {
        const response = await fetch('https://api.openai.com/v1/chat/completions', {
          method: 'POST',
          headers: {
            Authorization: `Bearer ${runtime.apiKey}`,
            'Content-Type': 'application/json',
          },
          body: JSON.stringify({
            model,
            temperature: 0.2,
            messages: [
              { role: 'system', content: systemPrompt },
              { role: 'user', content: userPrompt },
            ],
          }),
        });
        if (!response.ok) continue;
        const data = (await response.json()) as { choices?: Array<{ message?: { content?: string } }> };
        const content = data.choices?.[0]?.message?.content?.trim();
        if (!content) continue;
        const first = content.indexOf('{');
        const last = content.lastIndexOf('}');
        const json = first >= 0 && last > first ? content.slice(first, last + 1) : content;
        return JSON.parse(json) as { summary?: string };
      } catch {
        continue;
      }
    }
    throw new BadRequestException('No se pudo generar el resumen de IA.');
  }
}
