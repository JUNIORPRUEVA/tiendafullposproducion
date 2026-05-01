import {
  BadRequestException,
  ForbiddenException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { PrismaService } from '../prisma/prisma.service';
import { WhatsappMessageDirection, WhatsappMessageType } from '@prisma/client';
import { CatalogRealtimeRelayService } from '../products/catalog-realtime-relay.service';
import { WhatsappService } from '../whatsapp/whatsapp.service';
import * as bcrypt from 'bcryptjs';
import {
  normalizeInstanceName,
  normalizeWhatsappIdentity,
  normalizeWhatsappPhone,
} from './whatsapp-identity.util';

export interface ParsedWhatsappMessage {
  evolutionId: string;
  externalMessageId: string;
  instanceName: string | null;
  eventName: string | null;
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

function asBoolean(value: unknown): boolean | undefined {
  if (typeof value === 'boolean') return value;
  if (typeof value === 'string') {
    const v = value.trim().toLowerCase();
    if (v === 'true' || v === '1' || v === 'yes') return true;
    if (v === 'false' || v === '0' || v === 'no') return false;
  }
  if (typeof value === 'number') {
    if (value === 1) return true;
    if (value === 0) return false;
  }
  return undefined;
}

function normalizeEventName(value: unknown): string | null {
  const raw = asString(value);
  if (!raw) return null;
  return raw.toUpperCase().replace(/\./g, '_').replace(/\s+/g, '_');
}

function isOutgoingEventName(value: string | null): boolean {
  if (!value) return false;
  return value.includes('SEND_MESSAGE') || value.includes('MESSAGES_UPDATE');
}

function parseTimestamp(value: unknown): Date | null {
  if (value === null || value === undefined) return null;
  if (value instanceof Date) return value;

  if (typeof value === 'number' && Number.isFinite(value)) {
    const ms = value > 1e12 ? value : value * 1000;
    const date = new Date(ms);
    return Number.isNaN(date.getTime()) ? null : date;
  }

  if (typeof value === 'string') {
    const trimmed = value.trim();
    if (!trimmed) return null;
    if (/^\d+$/.test(trimmed)) {
      return parseTimestamp(Number(trimmed));
    }
    const parsed = new Date(trimmed);
    return Number.isNaN(parsed.getTime()) ? null : parsed;
  }

  return null;
}

function phoneFromIdentifier(value: unknown): string | null {
  return normalizeWhatsappPhone(value);
}

function firstPhone(...values: unknown[]): string | null {
  for (const value of values) {
    const phone = phoneFromIdentifier(value);
    if (phone) return phone;
  }
  return null;
}

async function findExistingWhatsappConversation(
  prisma: PrismaService,
  instanceId: string,
  normalizedJid: string,
  remotePhone: string | null,
) {
  if (remotePhone) {
    const byPhone = await prisma.whatsappConversation.findFirst({
      where: {
        instanceId,
        remotePhone,
      },
      orderBy: [{ lastMessageAt: 'desc' }, { updatedAt: 'desc' }],
    });
    if (byPhone) {
      if (
        byPhone.remoteJid !== normalizedJid &&
        !normalizedJid.startsWith('me@')
      ) {
        const updated = await prisma.whatsappConversation.update({
          where: { id: byPhone.id },
          data: {
            remoteJid: normalizedJid,
            remotePhone,
          },
        });
        return { conversation: updated, merged: true };
      }
      return { conversation: byPhone, merged: false };
    }
  }

  const byJid = await prisma.whatsappConversation.findUnique({
    where: {
      instanceId_remoteJid: { instanceId, remoteJid: normalizedJid },
    },
  });
  if (byJid) return { conversation: byJid, merged: false };

  return null;
}

function readableSenderName(
  name: unknown,
  fallbackPhone: string | null,
): string | null {
  const raw = asString(name);
  if (!raw) return fallbackPhone;
  if (raw.includes('@')) return fallbackPhone;
  const digits = raw.replace(/\D/g, '');
  if (digits.length > 15) return fallbackPhone;
  return raw;
}

function mediaMime(
  media: JsonRecord | undefined,
  data: JsonRecord,
  fallback: string | null,
) {
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

function mediaNeedsEvolutionBase64(mediaUrl: string | null): boolean {
  if (!mediaUrl) return true;
  const lower = mediaUrl.toLowerCase();
  return lower.includes('mmg.whatsapp.net') || lower.includes('.enc?');
}

function findBase64InResponse(value: unknown): string | null {
  if (!value) return null;
  if (typeof value === 'string') {
    const trimmed = value.trim();
    if (!trimmed) return null;
    if (trimmed.startsWith('data:') || trimmed.length > 100) return trimmed;
    return null;
  }
  if (Array.isArray(value)) {
    for (const item of value) {
      const found = findBase64InResponse(item);
      if (found) return found;
    }
    return null;
  }
  const record = asRecord(value);
  if (!record) return null;
  for (const key of [
    'base64',
    'media',
    'data',
    'file',
    'buffer',
    'mediaBase64',
    'base64Data',
  ]) {
    const found = findBase64InResponse(record[key]);
    if (found) return found;
  }
  return null;
}

function collectEvolutionMessageRecords(value: unknown): unknown[] {
  if (Array.isArray(value)) return value;
  const record = asRecord(value);
  if (!record) return [];

  for (const key of [
    'messages',
    'records',
    'data',
    'items',
    'rows',
    'message',
    'messageData',
    'messageContent',
  ]) {
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

function payloadKeyRemoteJid(value: unknown): string | null {
  const root = asRecord(value);
  const data = asRecord(root?.data) ?? asRecord(root?.message) ?? root;
  const message =
    asRecord(data?.message) ??
    asRecord(data?.messageData) ??
    asRecord(data?.messageContent);
  const key =
    asRecord(data?.key) ?? asRecord(message?.key) ?? asRecord(root?.key);
  return asString(key?.remoteJid) ?? null;
}

function payloadPreviousRemoteJid(value: unknown): string | null {
  const root = asRecord(value);
  const data = asRecord(root?.data) ?? asRecord(root?.message) ?? root;
  const message =
    asRecord(data?.message) ??
    asRecord(data?.messageData) ??
    asRecord(data?.messageContent);
  const key =
    asRecord(data?.key) ?? asRecord(message?.key) ?? asRecord(root?.key);
  return asString(key?.previousRemoteJid) ?? null;
}

export type ResolvedWhatsappConversationIdentity = {
  customerJid: string;
  customerPhone: string | null;
  customerName: string | null;
  fromMe: boolean;
  messageId: string;
  text: string | null;
  keyRemoteJid: string | null;
  participant: string | null;
  sender: string | null;
  instancePhone: string | null;
};

export function resolveWhatsappConversationIdentity(
  payload: unknown,
  instance?: {
    phoneNumber?: string | null;
    instanceName?: string | null;
  } | null,
  context?: { eventName?: string | null },
): ResolvedWhatsappConversationIdentity | null {
  const p = asRecord(payload);
  if (!p) return null;
  const data = asRecord(p.data) ?? asRecord(p.message) ?? p;
  const messageObj =
    asRecord(data.message) ??
    asRecord(data.messageData) ??
    asRecord(data.messageContent) ??
    {};
  const key = asRecord(data.key) ?? asRecord(messageObj.key) ?? asRecord(p.key);
  if (!key) return null;

  const eventName =
    normalizeEventName(p.event) ??
    normalizeEventName((p as JsonRecord).eventName) ??
    normalizeEventName((p as JsonRecord).type) ??
    normalizeEventName(data.event) ??
    normalizeEventName((data as JsonRecord).eventName) ??
    normalizeEventName((data as JsonRecord).type) ??
    normalizeEventName(context?.eventName) ??
    null;
  const fromMe =
    asBoolean(key.fromMe) ??
    asBoolean(data.fromMe) ??
    asBoolean(asRecord(data.contextInfo)?.fromMe) ??
    asBoolean(p.fromMe) ??
    asBoolean((p as JsonRecord)['from_me']) ??
    (isOutgoingEventName(eventName) ||
      asString(data.from)?.toLowerCase() === 'me' ||
      asString(data.from)?.toLowerCase() === 'self' ||
      asString(data.owner)?.toLowerCase() === 'me');

  const keyRemoteJid = asString(key.remoteJid);
  const participant =
    asString(key.participant) ??
    asString(data.participant) ??
    asString(data.sender) ??
    asString(data.senderPn) ??
    null;
  const sender = asString(data.sender) ?? asString(data.from) ?? null;

  // Baileys/Evolution keeps the customer chat in key.remoteJid for both incoming
  // and outgoing messages. Never resolve a conversation from "sender", "from",
  // the company instance phone, or the literal "me".
  const customerRaw =
    keyRemoteJid ??
    asString(data.remoteJid) ??
    asString(data.chatId) ??
    asString(data.to) ??
    asString(data.number) ??
    asString(data.recipient) ??
    null;
  const customerIdentity = normalizeWhatsappIdentity(customerRaw);
  const customerJid = customerIdentity.normalizedJid ?? customerRaw;
  if (!customerJid || customerJid === 'status@broadcast') return null;

  const instancePhone = normalizeWhatsappPhone(instance?.phoneNumber);
  const customerPhone =
    customerIdentity.normalizedPhone ??
    firstPhone(
      data.remotePhone,
      data.phone,
      data.number,
      data.to,
      data.recipient,
      customerJid,
    );

  const pushName =
    asString(data.pushName) ??
    asString(data.notifyName) ??
    asString(data.contactName) ??
    null;
  const customerName = fromMe
    ? null
    : readableSenderName(pushName, customerPhone);
  const messageId =
    asString(key.id) ??
    asString(data.id) ??
    asString(asRecord(data.message)?.['id']) ??
    asString(asRecord(data.message)?.['messageId']) ??
    asString(asRecord(data.messageInfo)?.['id']) ??
    asString(data.messageId) ??
    '';
  const text =
    asString(messageObj.conversation) ??
    asString(asRecord(messageObj.extendedTextMessage)?.text) ??
    asString(data.text) ??
    asString(data.body) ??
    asString(data.messageText) ??
    null;

  return {
    customerJid,
    customerPhone,
    customerName,
    fromMe,
    messageId,
    text,
    keyRemoteJid: keyRemoteJid ?? null,
    participant,
    sender,
    instancePhone,
  };
}

@Injectable()
export class WhatsappInboxService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly realtime: CatalogRealtimeRelayService,
    private readonly config: ConfigService,
    private readonly whatsappService: WhatsappService,
  ) {}

  private normalizeConversationForResponse<
    T extends {
      remoteJid: string;
      remotePhone: string | null;
      remoteName: string | null;
    },
  >(conversation: T): T {
    const cleanPhone =
      phoneFromIdentifier(conversation.remotePhone) ??
      phoneFromIdentifier(conversation.remoteJid);
    return {
      ...conversation,
      remotePhone: cleanPhone,
      remoteName: readableSenderName(conversation.remoteName, cleanPhone),
    };
  }

  private hydrateMessageMedia<
    T extends {
      mediaUrl: string | null;
      mediaMimeType: string | null;
      rawPayload?: unknown;
    },
  >(message: T): T {
    if (message.mediaUrl || !message.rawPayload) return message;
    const parsed = this.parseEvolutionPayload(message.rawPayload);
    if (!parsed?.mediaUrl) return message;
    return {
      ...message,
      mediaUrl: parsed.mediaUrl,
      mediaMimeType: parsed.mediaMimeType ?? message.mediaMimeType,
    };
  }

  private async hydratePlayableMessageMedia<
    T extends {
      id: string;
      mediaUrl: string | null;
      mediaMimeType: string | null;
      rawPayload?: unknown;
    },
  >(message: T, instanceName?: string | null): Promise<T> {
    const hydrated = this.hydrateMessageMedia(message);
    if (
      !instanceName ||
      !hydrated.rawPayload ||
      !mediaNeedsEvolutionBase64(hydrated.mediaUrl)
    ) {
      return hydrated;
    }

    try {
      const raw = await this.whatsappService.getBase64FromMediaMessage(
        instanceName,
        hydrated.rawPayload,
      );
      const base64 = findBase64InResponse(raw);
      if (!base64) return hydrated;
      const mediaUrl = base64.startsWith('data:')
        ? base64
        : `data:${hydrated.mediaMimeType ?? 'application/octet-stream'};base64,${base64}`;
      await this.prisma.whatsappMessage.update({
        where: { id: hydrated.id },
        data: { mediaUrl },
      });
      return { ...hydrated, mediaUrl };
    } catch (error) {
      console.warn(
        `[WhatsappInbox] No se pudo obtener media base64 para mensaje ${message.id}: ${
          error instanceof Error ? error.message : String(error)
        }`,
      );
      return hydrated;
    }
  }

  // ─── Parse Evolution API webhook payload ───────────────────────────────

  parseEvolutionPayloads(
    payload: unknown,
    context?: {
      instanceName?: string | null;
      eventName?: string | null;
      instance?: {
        phoneNumber?: string | null;
        instanceName?: string | null;
      } | null;
    },
  ): ParsedWhatsappMessage[] {
    const p = asRecord(payload);
    if (!p) return [];

    const records = collectEvolutionMessageRecords(payload);
    if (records.length > 0) {
      return records
        .map((item) =>
          this.parseEvolutionPayload({ ...p, data: item }, context),
        )
        .filter((item): item is ParsedWhatsappMessage => !!item);
    }

    const parsed = this.parseEvolutionPayload(payload, context);
    return parsed ? [parsed] : [];
  }

  async handleIncomingWebhook(
    instanceName: string,
    payload: unknown,
    eventNameFromRoute?: string,
  ) {
    const instance = await this.findInstanceByName(instanceName);
    if (!instance) {
      console.warn(
        `[WhatsappInbox][Webhook] instanceName=${instanceName} eventName=${eventNameFromRoute ?? '-'} action=ignored reason=instance_not_registered`,
      );
      return { ok: true, ignored: true, reason: 'instance_not_registered' };
    }

    const payloadRecord = asRecord(payload);
    const payloadEvent =
      normalizeEventName(payloadRecord?.event) ??
      normalizeEventName(payloadRecord?.eventName) ??
      normalizeEventName(payloadRecord?.type);
    const eventName =
      normalizeEventName(eventNameFromRoute) ??
      payloadEvent ??
      'MESSAGES_UPSERT';

    const parsedMessages = this.parseEvolutionPayloads(payload, {
      instanceName,
      eventName,
      instance,
    });
    console.log(
      `[WhatsappInbox][Webhook] instanceName=${instanceName} eventName=${eventName} parsed=${parsedMessages.length} instanceId=${instance.id}`,
    );
    if (parsedMessages.length === 0) {
      console.warn(
        `[WhatsappInbox][Webhook] instanceName=${instanceName} eventName=${eventName} action=invalid reason=unparseable_payload`,
      );
      if (isOutgoingEventName(eventName) || eventName === 'UNKNOWN') {
        console.warn(
          'Manual WhatsApp outgoing event not received from Evolution. Check webhook events configuration.',
        );
      }
      return { ok: true, ignored: true, reason: 'unparseable_payload' };
    }

    let saved = 0;
    let duplicates = 0;
    let outgoingObserved = false;
    for (const parsed of parsedMessages) {
      const normalizedIdentity = normalizeWhatsappIdentity(parsed.remoteJid);
      const normalizedJid =
        normalizedIdentity.normalizedJid ?? parsed.remoteJid;
      const customerPhone =
        parsed.remotePhone ??
        normalizedIdentity.normalizedPhone ??
        phoneFromIdentifier(parsed.remoteJid);
      const existingByPhone = customerPhone
        ? await this.prisma.whatsappConversation.findFirst({
            where: { instanceId: instance.id, remotePhone: customerPhone },
            select: { id: true },
            orderBy: [{ lastMessageAt: 'desc' }, { updatedAt: 'desc' }],
          })
        : null;
      const existingByJid = existingByPhone
        ? null
        : await this.prisma.whatsappConversation.findUnique({
            where: {
              instanceId_remoteJid: {
                instanceId: instance.id,
                remoteJid: normalizedJid,
              },
            },
            select: { id: true },
          });
      const identity = resolveWhatsappConversationIdentity(
        parsed.rawPayload,
        instance,
        { eventName: parsed.eventName ?? eventName },
      );
      console.log('[WA-INBOX][IDENTITY]', {
        eventName: parsed.eventName ?? eventName,
        fromMe: parsed.fromMe,
        keyRemoteJid: identity?.keyRemoteJid ?? parsed.remoteJid,
        participant: identity?.participant ?? null,
        sender: identity?.sender ?? null,
        resolvedCustomerJid: parsed.remoteJid,
        resolvedCustomerPhone: customerPhone,
        instancePhone:
          identity?.instancePhone ??
          normalizeWhatsappPhone(instance.phoneNumber),
        existingConversationId:
          existingByPhone?.id ?? existingByJid?.id ?? null,
        willCreateNewConversation: !existingByPhone && !existingByJid,
      });
      const result = await this.saveMessage(instance.id, parsed);
      const action = result.action;
      if (result.duplicate) {
        duplicates++;
      } else {
        saved++;
      }
      if (parsed.fromMe) outgoingObserved = true;

      console.log('[WA-INBOX][SAVED]', {
        messageId: parsed.externalMessageId || result.message.id,
        direction: parsed.fromMe ? 'outgoing' : 'incoming',
        conversationId: result.conversation.id,
        customerPhone: parsed.remotePhone ?? null,
        action,
      });
    }

    if (
      !outgoingObserved &&
      (isOutgoingEventName(eventName) || eventName === 'UNKNOWN')
    ) {
      console.warn(
        'Manual WhatsApp outgoing event not received from Evolution. Check webhook events configuration.',
      );
    }

    return { ok: true, saved, duplicate: duplicates };
  }

  private async findInstanceByName(instanceName: string) {
    let instance = await this.prisma.userWhatsappInstance.findUnique({
      where: { instanceName },
      select: { id: true, userId: true, instanceName: true, phoneNumber: true },
    });

    if (!instance) {
      const normalizedInput = normalizeInstanceName(instanceName);
      if (normalizedInput) {
        const instances = await this.prisma.userWhatsappInstance.findMany({
          select: {
            id: true,
            userId: true,
            instanceName: true,
            phoneNumber: true,
          },
        });
        const byNormalized = instances.find(
          (item) =>
            normalizeInstanceName(item.instanceName) === normalizedInput,
        );
        if (byNormalized) {
          instance = {
            id: byNormalized.id,
            userId: byNormalized.userId,
            instanceName: byNormalized.instanceName,
            phoneNumber: byNormalized.phoneNumber,
          };
        }
      }
    }

    if (!instance) {
      const appConfig = await this.prisma.appConfig.findUnique({
        where: { id: 'global' },
        select: { evolutionApiInstanceName: true },
      });
      const configName = appConfig?.evolutionApiInstanceName ?? '';
      const sameCompanyInstance =
        configName === instanceName ||
        normalizeInstanceName(configName) ===
          normalizeInstanceName(instanceName);
      if (sameCompanyInstance) {
        const adminUser = await this.prisma.user.findFirst({
          where: { role: 'ADMIN' },
          select: { id: true },
        });
        if (adminUser) {
          instance = await this.prisma.userWhatsappInstance.upsert({
            where: { instanceName },
            create: {
              instanceName,
              userId: adminUser.id,
              status: 'connected',
              webhookEnabled: true,
            },
            update: {},
            select: {
              id: true,
              userId: true,
              instanceName: true,
              phoneNumber: true,
            },
          });
        }
      }
    }

    return instance;
  }

  parseEvolutionPayload(
    payload: unknown,
    context?: {
      instanceName?: string | null;
      eventName?: string | null;
      instance?: {
        phoneNumber?: string | null;
        instanceName?: string | null;
      } | null;
    },
  ): ParsedWhatsappMessage | null {
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
      const key =
        asRecord(data.key) ?? asRecord(messageObj.key) ?? asRecord(p.key);
      if (!key) return null;
      const identity = resolveWhatsappConversationIdentity(
        payload,
        context?.instance ?? null,
        { eventName: context?.eventName ?? null },
      );
      if (!identity) return null;

      const eventName =
        normalizeEventName(p.event) ??
        normalizeEventName((p as JsonRecord).eventName) ??
        normalizeEventName((p as JsonRecord).type) ??
        normalizeEventName(data.event) ??
        normalizeEventName((data as JsonRecord).eventName) ??
        normalizeEventName((data as JsonRecord).type) ??
        normalizeEventName(context?.eventName) ??
        null;
      const instanceName =
        asString(p.instance) ??
        asString(p.instanceName) ??
        asString(p.instance_name) ??
        asString(data.instance) ??
        asString(data.instanceName) ??
        asString(data.instance_name) ??
        asString(context?.instanceName) ??
        null;

      const remoteJid = identity.customerJid;
      const remoteJidLower = remoteJid.toLowerCase();
      if (
        !remoteJid ||
        remoteJid === 'status@broadcast' ||
        remoteJidLower.endsWith('@g.us') ||
        remoteJidLower.includes('@g.us')
      ) {
        return null;
      }

      const fromMe = identity.fromMe;
      const evolutionId = identity.messageId;
      const pushName = asString(data.pushName) ?? null;
      const rawMessageType =
        asString(data.messageType) ??
        asString(data.type) ??
        (asString(messageObj.conversation)
          ? 'conversation'
          : messageObj.extendedTextMessage
            ? 'extendedTextMessage'
            : '');
      const participantJid = identity.participant;
      const remotePhone = identity.customerPhone;
      const senderName = fromMe
        ? readableSenderName(context?.instance?.instanceName, remotePhone)
        : readableSenderName(pushName, remotePhone);
      const normalizedMessageType = rawMessageType.toLowerCase();
      const sentAt =
        parseTimestamp(data.messageTimestamp) ??
        parseTimestamp(data.timestamp) ??
        parseTimestamp(asRecord(data.message)?.['timestamp']) ??
        parseTimestamp((asRecord(data.messageInfo) ?? {})['timestamp']) ??
        new Date();

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
          ((
            messageObj.extendedTextMessage as
              | Record<string, unknown>
              | undefined
          )?.text as string | undefined) ??
          null;
      } else if (
        normalizedMessageType === 'imagemessage' ||
        normalizedMessageType === 'image' ||
        messageObj.imageMessage
      ) {
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
          asRecord(messageObj.audioMessage) ??
          asRecord(messageObj.pttMessage) ??
          messageObj;
        mediaMimeType = mediaMime(audio, data, 'audio/ogg');
        mediaUrl = mediaUrlFromPayload(audio, messageObj, data, mediaMimeType);
      } else if (
        normalizedMessageType === 'videomessage' ||
        normalizedMessageType === 'video' ||
        messageObj.videoMessage
      ) {
        messageType = WhatsappMessageType.VIDEO;
        const vid = asRecord(messageObj.videoMessage) ?? messageObj;
        mediaMimeType = mediaMime(vid, data, 'video/mp4');
        mediaUrl = mediaUrlFromPayload(vid, messageObj, data, mediaMimeType);
        caption = (vid?.caption as string | undefined) ?? null;
        body = caption;
      } else if (
        normalizedMessageType === 'documentmessage' ||
        normalizedMessageType === 'document' ||
        messageObj.documentMessage
      ) {
        messageType = WhatsappMessageType.DOCUMENT;
        const doc = asRecord(messageObj.documentMessage) ?? messageObj;
        mediaMimeType = mediaMime(doc, data, null);
        mediaUrl = mediaUrlFromPayload(doc, messageObj, data, mediaMimeType);
        body = (doc?.fileName as string | undefined) ?? null;
      } else if (
        normalizedMessageType === 'stickermessage' ||
        normalizedMessageType === 'sticker' ||
        messageObj.stickerMessage
      ) {
        messageType = WhatsappMessageType.STICKER;
        const sticker = asRecord(messageObj.stickerMessage) ?? messageObj;
        mediaMimeType = mediaMime(sticker, data, 'image/webp');
        mediaUrl = mediaUrlFromPayload(
          sticker,
          messageObj,
          data,
          mediaMimeType,
        );
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
        externalMessageId: evolutionId,
        instanceName,
        eventName,
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

    const normalizedIdentity = normalizeWhatsappIdentity(parsed.remoteJid);
    let normalizedJid = normalizedIdentity.normalizedJid ?? parsed.remoteJid;
    let remotePhone =
      parsed.remotePhone ??
      normalizedIdentity.normalizedPhone ??
      phoneFromIdentifier(parsed.remoteJid);
    const aliasPhone = await this.resolveKnownCustomerPhoneAlias(
      instanceId,
      parsed.rawPayload,
      remotePhone,
    );
    if (aliasPhone) {
      remotePhone = aliasPhone;
      normalizedJid = `${aliasPhone}@s.whatsapp.net`;
    }
    const remoteName =
      direction === WhatsappMessageDirection.INCOMING
        ? readableSenderName(parsed.senderName, remotePhone)
        : remotePhone;

    const existingConversation = await findExistingWhatsappConversation(
      this.prisma,
      instanceId,
      normalizedJid,
      remotePhone,
    );

    const wasMerged = existingConversation?.merged ?? false;

    const conversation = existingConversation
      ? await this.prisma.whatsappConversation.update({
          where: { id: existingConversation.conversation.id },
          data: {
            lastMessageAt: parsed.sentAt,
            remoteJid: normalizedJid,
            ...(remotePhone ? { remotePhone } : {}),
            ...(direction === WhatsappMessageDirection.INCOMING && remoteName
              ? { remoteName }
              : {}),
            ...(direction === WhatsappMessageDirection.INCOMING
              ? { unreadCount: { increment: 1 } }
              : {}),
          },
        })
      : await this.prisma.whatsappConversation.create({
          data: {
            instanceId,
            remoteJid: normalizedJid,
            remotePhone,
            remoteName,
            lastMessageAt: parsed.sentAt,
            unreadCount:
              direction === WhatsappMessageDirection.INCOMING ? 1 : 0,
          },
        });
    await this.mergePreviousRemoteJidConversation(
      instanceId,
      conversation.id,
      parsed.rawPayload,
      remotePhone,
    );

    // Skip duplicate Evolution IDs
    if (parsed.evolutionId) {
      const existing = await this.prisma.whatsappMessage.findUnique({
        where: { evolutionId: parsed.evolutionId },
        select: { id: true },
      });
      if (existing) {
        const updatedExisting = await this.prisma.whatsappMessage.update({
          where: { id: existing.id },
          data: {
            rawPayload: parsed.rawPayload as object,
            mediaUrl: parsed.mediaUrl,
            mediaMimeType: parsed.mediaMimeType,
            caption: parsed.caption,
            body: parsed.body,
          },
        });
        return {
          conversation,
          message: updatedExisting,
          duplicate: true,
          action: wasMerged ? 'merged' : 'duplicate',
        };
      }

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
          return {
            conversation,
            message: updated,
            duplicate: false,
            action: wasMerged ? 'merged' : 'saved',
          };
        }
      }
    }

    // Fallback idempotency for events without message id: prevent duplicates within the same second.
    if (!parsed.evolutionId) {
      const dupeByFingerprint = await this.prisma.whatsappMessage.findFirst({
        where: {
          conversationId: conversation.id,
          direction,
          body: parsed.body,
          messageType: parsed.messageType,
          sentAt: parsed.sentAt,
        },
        orderBy: { createdAt: 'desc' },
      });
      if (dupeByFingerprint) {
        return {
          conversation,
          message: dupeByFingerprint,
          duplicate: true,
          action: wasMerged ? 'merged' : 'duplicate',
        };
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
        createdAt: message.sentAt,
        messageType: message.messageType,
        text: message.body,
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

    return {
      conversation,
      message,
      duplicate: false,
      action: wasMerged ? 'merged' : 'saved',
    };
  }

  // ─── Query conversations for an instance ──────────────────────────────

  async getConversations(instanceId: string, limit = 50) {
    await this.syncRecentChatsFromEvolution(instanceId).catch((error) => {
      console.warn(
        `[WhatsappInbox] No se pudieron sincronizar chats recientes para instancia ${instanceId}: ${
          error instanceof Error ? error.message : String(error)
        }`,
      );
    });

    const conversations = await this.prisma.whatsappConversation.findMany({
      where: {
        instanceId,
        NOT: [{ remoteJid: { contains: '@g.us' } }],
      },
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

  async syncRecentChatsFromEvolution(instanceId: string) {
    const instance = await this.prisma.userWhatsappInstance.findUnique({
      where: { id: instanceId },
      select: { id: true, instanceName: true, phoneNumber: true },
    });
    if (!instance) return { synced: 0 };

    const raw = await this.whatsappService.findChats(instance.instanceName, 40);
    const chats = Array.isArray(raw)
      ? raw
      : collectEvolutionMessageRecords(raw);
    let synced = 0;

    for (const chat of chats) {
      const chatRecord = asRecord(chat);
      if (!chatRecord) continue;
      const lastMessage = asRecord(chatRecord.lastMessage);
      if (!lastMessage) continue;
      const chatRemoteJid = asString(chatRecord.remoteJid);
      const payload = {
        data: {
          ...lastMessage,
          pushName:
            asString(lastMessage.pushName) ??
            asString(chatRecord.pushName) ??
            null,
          key: {
            ...(asRecord(lastMessage.key) ?? {}),
            remoteJid:
              asString(asRecord(lastMessage.key)?.remoteJid) ?? chatRemoteJid,
          },
        },
      };
      const parsed = this.parseEvolutionPayload(payload, {
        instanceName: instance.instanceName,
        instance,
        eventName: 'CHAT_RECENT_SYNC',
      });
      if (!parsed) continue;
      const result = await this.saveMessage(instance.id, parsed);
      if (!result.duplicate) synced++;
    }

    return { synced };
  }

  private async resolveKnownCustomerPhoneAlias(
    instanceId: string,
    rawPayload: unknown,
    currentPhone: string | null,
  ): Promise<string | null> {
    const remoteJid = payloadKeyRemoteJid(rawPayload);
    if (!remoteJid?.toLowerCase().endsWith('@lid')) return null;

    const rows = await this.prisma.$queryRaw<
      Array<{ remote_phone: string | null }>
    >`
      SELECT c.remote_phone
      FROM whatsapp_messages m
      JOIN whatsapp_conversations c ON c.id = m.conversation_id
      WHERE c.instance_id = ${instanceId}::uuid
        AND c.remote_phone IS NOT NULL
        AND (
          m.raw_payload #>> '{data,key,previousRemoteJid}' = ${remoteJid}
          OR m.raw_payload #>> '{data,key,remoteJid}' = ${remoteJid}
        )
        AND c.remote_phone <> ${currentPhone ?? ''}
      ORDER BY m.sent_at DESC
      LIMIT 1
    `;

    const alias = normalizeWhatsappPhone(rows[0]?.remote_phone);
    return alias && alias !== currentPhone ? alias : null;
  }

  private async mergePreviousRemoteJidConversation(
    instanceId: string,
    keepConversationId: string,
    rawPayload: unknown,
    remotePhone: string | null,
  ) {
    const previousRemoteJid = payloadPreviousRemoteJid(rawPayload);
    const previousPhone = normalizeWhatsappPhone(previousRemoteJid);
    if (!previousRemoteJid?.toLowerCase().endsWith('@lid') || !previousPhone) {
      return;
    }
    if (remotePhone && previousPhone === remotePhone) return;

    const duplicate = await this.prisma.whatsappConversation.findFirst({
      where: {
        instanceId,
        remotePhone: previousPhone,
        id: { not: keepConversationId },
      },
      select: { id: true },
    });
    if (!duplicate) return;

    await this.prisma.whatsappMessage.updateMany({
      where: { conversationId: duplicate.id },
      data: { conversationId: keepConversationId },
    });
    await this.prisma.whatsappConversation.delete({
      where: { id: duplicate.id },
    });
    console.log('[WA-INBOX][MERGED_ALIAS]', {
      instanceId,
      previousRemoteJid,
      previousPhone,
      remotePhone,
      keepConversationId,
      duplicateConversationId: duplicate.id,
    });
  }

  async getMessages(conversationId: string, limit = 50, before?: Date) {
    if (!before) {
      await this.syncConversationFromEvolution(conversationId).catch(
        (error) => {
          console.warn(
            `[WhatsappInbox] No se pudo sincronizar conversacion ${conversationId}: ${
              error instanceof Error ? error.message : String(error)
            }`,
          );
        },
      );
    }

    const conversation = await this.prisma.whatsappConversation.findUnique({
      where: { id: conversationId },
      include: { instance: { select: { instanceName: true } } },
    });

    const messages = await this.prisma.whatsappMessage.findMany({
      where: {
        conversationId,
        ...(before ? { sentAt: { lt: before } } : {}),
      },
      orderBy: { sentAt: 'desc' },
      take: limit,
    });
    return Promise.all(
      messages.map((message) =>
        this.hydratePlayableMessageMedia(
          message,
          conversation?.instance.instanceName,
        ),
      ),
    );
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
      const parsed = this.parseEvolutionPayload(
        { data: record },
        {
          instanceName: conversation.instance.instanceName,
          instance: conversation.instance,
        },
      );
      if (!parsed) continue;
      const parsedPhone =
        parsed.remotePhone ?? phoneFromIdentifier(parsed.remoteJid);
      const conversationPhone =
        phoneFromIdentifier(conversation.remotePhone) ??
        phoneFromIdentifier(conversation.remoteJid);
      const sameConversation =
        parsed.remoteJid === conversation.remoteJid ||
        (!!parsedPhone &&
          !!conversationPhone &&
          parsedPhone === conversationPhone);
      if (!sameConversation) continue;
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
          select: {
            id: true,
            nombreCompleto: true,
            role: true,
            telefono: true,
          },
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

  async validateAdminComposePassword(
    actor: { id?: string; role?: string },
    password: string,
  ) {
    if (actor.role !== 'ADMIN') {
      throw new ForbiddenException(
        'Solo un administrador puede desbloquear el envio.',
      );
    }
    if (!actor.id) {
      throw new ForbiddenException('No autorizado.');
    }
    const cleaned = (password ?? '').trim();
    if (!cleaned) {
      throw new BadRequestException(
        'Debes colocar la contrasena de administrador.',
      );
    }
    const user = await this.prisma.user.findUnique({
      where: { id: actor.id },
      select: { passwordHash: true },
    });
    if (!user) throw new ForbiddenException('No autorizado.');
    const ok = await bcrypt.compare(cleaned, user.passwordHash);
    if (!ok) throw new ForbiddenException('Contrasena incorrecta.');
    return { ok: true };
  }

  // ─── Record a message sent via Evolution API (outgoing) ──────────────

  async recordOutgoingMessage(
    instanceId: string,
    remoteJid: string,
    body: string,
    evolutionId?: string,
  ) {
    const instance = await this.prisma.userWhatsappInstance.findUnique({
      where: { id: instanceId },
      select: { instanceName: true },
    });
    const parsed: ParsedWhatsappMessage = {
      evolutionId: evolutionId ?? '',
      externalMessageId: evolutionId ?? '',
      instanceName: null,
      eventName: 'APP_SEND',
      remoteJid,
      remotePhone: phoneFromIdentifier(remoteJid),
      fromMe: true,
      messageType: WhatsappMessageType.TEXT,
      body,
      mediaUrl: null,
      mediaMimeType: null,
      caption: null,
      senderName: instance?.instanceName ?? null,
      sentAt: new Date(),
      rawPayload: null,
    };
    return this.saveMessage(instanceId, parsed);
  }

  async attachEvolutionIdToMessage(
    messageId: string,
    evolutionId?: string | null,
  ) {
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
    const incoming = messages.filter(
      (m) => m.direction === WhatsappMessageDirection.INCOMING,
    );
    const outgoing = messages.filter(
      (m) => m.direction === WhatsappMessageDirection.OUTGOING,
    );
    const media = messages.filter(
      (m) => m.messageType !== WhatsappMessageType.TEXT,
    );

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
      direction:
        m.direction === WhatsappMessageDirection.OUTGOING
          ? 'usuario'
          : 'cliente',
      contact:
        readableSenderName(
          m.conversation.remoteName,
          m.conversation.remotePhone,
        ) ??
        m.conversation.remotePhone ??
        m.conversation.remoteJid,
      type: m.messageType,
      text: (m.body ?? m.caption ?? '')
        .replace(/\s+/g, ' ')
        .trim()
        .slice(0, 900),
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
        summary:
          ai.summary || this.buildDeterministicDailySummary(stats, transcript),
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
    const envKey = (
      this.config.get<string>('OPENAI_API_KEY') ??
      process.env.OPENAI_API_KEY ??
      ''
    ).trim();
    const envModel = (
      this.config.get<string>('OPENAI_MODEL') ??
      process.env.OPENAI_MODEL ??
      ''
    ).trim();
    const appConfig = await this.prisma.appConfig
      .findUnique({
        where: { id: 'global' },
        select: { openAiApiKey: true, openAiModel: true, companyName: true },
      })
      .catch(() => null);

    return {
      apiKey:
        envKey.length > 0 ? envKey : (appConfig?.openAiApiKey ?? '').trim(),
      model:
        envModel.length > 0
          ? envModel
          : (appConfig?.openAiModel ?? '').trim() || 'gpt-4o-mini',
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
    const interestWords = [
      'precio',
      'cotizacion',
      'cotización',
      'quiero',
      'interesa',
      'disponible',
      'comprar',
      'instalar',
    ];
    const followWords = [
      'mañana',
      'luego',
      'despues',
      'después',
      'pendiente',
      'seguimiento',
      'confirmar',
    ];
    const interested = new Set<string>();
    const followups = new Set<string>();

    for (const item of transcript) {
      const text = item.text.toLowerCase();
      if (interestWords.some((word) => text.includes(word)))
        interested.add(item.contact);
      if (followWords.some((word) => text.includes(word)))
        followups.add(item.contact);
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
    const candidates = [
      runtime.model,
      'gpt-5',
      'gpt-4.1',
      'gpt-4o',
      'gpt-4o-mini',
    ].filter((value, index, list) => value && list.indexOf(value) === index);
    const systemPrompt =
      `Eres un analista CRM de ${runtime.companyName}. Resume actividad diaria de WhatsApp para auditar ventas y seguimiento. ` +
      'Usa solo los mensajes enviados. No inventes ventas. Escribe en espanol profesional, claro y accionable.';
    const userPrompt =
      `${JSON.stringify(payload)}\n\n` +
      'Devuelve JSON exacto {"summary":"string"}. El summary debe incluir: panorama del dia, rendimiento del usuario, clientes/interesados/no interesados si se puede inferir, categorias mencionadas, seguimientos dados/no dados, oportunidades y alertas.';

    for (const model of candidates) {
      try {
        const response = await fetch(
          'https://api.openai.com/v1/chat/completions',
          {
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
          },
        );
        if (!response.ok) continue;
        const data = (await response.json()) as {
          choices?: Array<{ message?: { content?: string } }>;
        };
        const content = data.choices?.[0]?.message?.content?.trim();
        if (!content) continue;
        const first = content.indexOf('{');
        const last = content.lastIndexOf('}');
        const json =
          first >= 0 && last > first ? content.slice(first, last + 1) : content;
        return JSON.parse(json) as { summary?: string };
      } catch {
        continue;
      }
    }
    throw new BadRequestException('No se pudo generar el resumen de IA.');
  }
}
