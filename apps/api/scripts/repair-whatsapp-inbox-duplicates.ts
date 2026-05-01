import { PrismaClient } from '@prisma/client';
import { normalizeWhatsappIdentity, normalizeWhatsappPhone } from '../src/whatsapp-inbox/whatsapp-identity.util';

type ConversationWithMeta = {
  id: string;
  instanceId: string;
  remoteJid: string;
  remotePhone: string | null;
  remoteName: string | null;
  lastMessageAt: Date | null;
  createdAt: Date;
  instance: { phoneNumber: string | null };
  messages: Array<{ id: string; sentAt: Date; direction: string; rawPayload: unknown }>;
};

function asRecord(value: unknown): Record<string, unknown> | null {
  return value && typeof value === 'object' && !Array.isArray(value)
    ? (value as Record<string, unknown>)
    : null;
}

function rawKeyRemotePhone(rawPayload: unknown): string | null {
  const root = asRecord(rawPayload);
  const data = asRecord(root?.data) ?? asRecord(root?.message) ?? root;
  const message = asRecord(data?.message) ?? asRecord(data?.messageData) ?? asRecord(data?.messageContent);
  const key = asRecord(data?.key) ?? asRecord(message?.key) ?? asRecord(root?.key);
  return normalizeWhatsappPhone(key?.remoteJid);
}

function rawPreviousRemoteJid(rawPayload: unknown): string | null {
  const root = asRecord(rawPayload);
  const data = asRecord(root?.data) ?? asRecord(root?.message) ?? root;
  const message = asRecord(data?.message) ?? asRecord(data?.messageData) ?? asRecord(data?.messageContent);
  const key = asRecord(data?.key) ?? asRecord(message?.key) ?? asRecord(root?.key);
  return typeof key?.previousRemoteJid === 'string' ? key.previousRemoteJid : null;
}

function rawSenderPhone(rawPayload: unknown): string | null {
  const root = asRecord(rawPayload);
  const data = asRecord(root?.data) ?? asRecord(root?.message) ?? root;
  const message = asRecord(data?.message) ?? asRecord(data?.messageData) ?? asRecord(data?.messageContent);
  const key = asRecord(data?.key) ?? asRecord(message?.key) ?? asRecord(root?.key);
  return normalizeWhatsappPhone(key?.senderPn);
}

function groupingPhone(
  conv: ConversationWithMeta,
  aliasByLid: Map<string, string>,
): string | null {
  const directPhone =
    normalizeWhatsappPhone(conv.remotePhone) ??
    normalizeWhatsappPhone(conv.remoteJid);
  const local = conv.remoteJid.split('@')[0] ?? '';
  const alias = aliasByLid.get(`${local}@lid`);
  if (alias) return alias;
  const instancePhone = normalizeWhatsappPhone(conv.instance.phoneNumber);
  const suspiciousMe =
    (conv.remoteName ?? '').trim().toLowerCase() === 'me' ||
    (!!directPhone && !!instancePhone && directPhone === instancePhone);

  if (!suspiciousMe) return directPhone;

  for (const message of conv.messages) {
    const rawPhone = rawKeyRemotePhone(message.rawPayload);
    if (rawPhone && rawPhone !== instancePhone) return rawPhone;
  }

  return directPhone && directPhone !== instancePhone ? directPhone : null;
}

function pickKeeper(conversations: ConversationWithMeta[]): ConversationWithMeta {
  return [...conversations].sort((a, b) => {
    if (b.messages.length !== a.messages.length) return b.messages.length - a.messages.length;
    return a.createdAt.getTime() - b.createdAt.getTime();
  })[0]!;
}

async function recomputeConversation(prisma: PrismaClient, conversationId: string) {
  const latest = await prisma.whatsappMessage.findFirst({
    where: { conversationId },
    orderBy: { sentAt: 'desc' },
    select: { sentAt: true },
  });
  const unreadCount = await prisma.whatsappMessage.count({
    where: { conversationId, direction: 'INCOMING' },
  });
  await prisma.whatsappConversation.update({
    where: { id: conversationId },
    data: {
      lastMessageAt: latest?.sentAt ?? null,
      unreadCount,
    },
  });
}

async function main() {
  const prisma = new PrismaClient();
  const execute = process.argv.includes('--execute');

  try {
    const conversations = (await prisma.whatsappConversation.findMany({
      include: {
        instance: { select: { phoneNumber: true } },
        messages: {
          select: { id: true, sentAt: true, direction: true, rawPayload: true },
          orderBy: { sentAt: 'desc' },
        },
      },
      orderBy: { createdAt: 'asc' },
    })) as ConversationWithMeta[];

    const aliasByLid = new Map<string, string>();
    for (const conv of conversations) {
      for (const message of conv.messages) {
        const previous = rawPreviousRemoteJid(message.rawPayload);
        const sender = rawSenderPhone(message.rawPayload);
        if (previous?.toLowerCase().endsWith('@lid') && sender) {
          aliasByLid.set(previous, sender);
        }
      }
    }

    const groups = new Map<string, ConversationWithMeta[]>();
    for (const conv of conversations) {
      const phone = groupingPhone(conv, aliasByLid);
      if (!phone) continue;
      const key = `${conv.instanceId}:${phone}`;
      groups.set(key, [...(groups.get(key) ?? []), conv]);
    }

    const plans = [...groups.entries()]
      .filter(([, list]) => list.length > 1)
      .map(([key, list]) => {
        const keeper = pickKeeper(list);
        return {
          key,
          phone: key.split(':').pop()!,
          keeper,
          duplicates: list.filter((item) => item.id !== keeper.id),
        };
      });

    console.log('[whatsapp-inbox][repair] mode=', execute ? 'EXECUTE' : 'DRY-RUN');
    console.log('[whatsapp-inbox][repair] groups=', plans.length);
    console.log('[whatsapp-inbox][repair] duplicateConversations=', plans.reduce((sum, p) => sum + p.duplicates.length, 0));
    console.log('[whatsapp-inbox][repair] messagesToMove=', plans.reduce((sum, p) => sum + p.duplicates.reduce((s, d) => s + d.messages.length, 0), 0));

    for (const plan of plans) {
      console.log(
        `[whatsapp-inbox][repair][plan] key=${plan.key} keep=${plan.keeper.id} duplicates=${plan.duplicates.map((d) => d.id).join(',')} moveMessages=${plan.duplicates.reduce((sum, d) => sum + d.messages.length, 0)}`,
      );
    }

    if (!execute) {
      console.log('[whatsapp-inbox][repair] Dry-run completed. No DB changes were made.');
      return;
    }

    for (const plan of plans) {
      await prisma.$transaction(async (tx) => {
        const duplicateIds = plan.duplicates.map((item) => item.id);
        await tx.whatsappMessage.updateMany({
          where: { conversationId: { in: duplicateIds } },
          data: { conversationId: plan.keeper.id },
        });
        await tx.whatsappConversation.update({
          where: { id: plan.keeper.id },
          data: {
            remotePhone: plan.phone,
            remoteJid: normalizeWhatsappIdentity(plan.keeper.remoteJid).normalizedJid ?? plan.keeper.remoteJid,
            remoteName:
              (plan.keeper.remoteName ?? '').trim().toLowerCase() === 'me'
                ? plan.phone
                : plan.keeper.remoteName,
          },
        });
        await tx.whatsappConversation.deleteMany({
          where: { id: { in: duplicateIds } },
        });
      });
      await recomputeConversation(prisma, plan.keeper.id);
      console.log(
        `[whatsapp-inbox][repair][merged] key=${plan.key} keep=${plan.keeper.id} removed=${plan.duplicates.length}`,
      );
    }

    console.log('[whatsapp-inbox][repair] Execute completed. No messages were deleted.');
  } finally {
    await prisma.$disconnect();
  }
}

main().catch((error) => {
  console.error('[whatsapp-inbox][repair] failed:', error);
  process.exitCode = 1;
});
