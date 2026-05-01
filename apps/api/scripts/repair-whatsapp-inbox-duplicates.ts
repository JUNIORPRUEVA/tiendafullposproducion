import { PrismaClient } from '@prisma/client';
import {
  normalizeInstanceName,
  normalizeWhatsappIdentity,
} from '../src/whatsapp-inbox/whatsapp-identity.util';

type ConversationWithMeta = {
  id: string;
  instanceId: string;
  remoteJid: string;
  remotePhone: string | null;
  remoteName: string | null;
  createdAt: Date;
  updatedAt: Date;
  instance: { instanceName: string };
  _count: { messages: number };
};

type MergePlan = {
  groupKey: string;
  normalizedPhone: string;
  normalizedInstanceName: string;
  keepConversationId: string;
  duplicateConversationIds: string[];
  movedMessages: number;
};

function pickKeeper(conversations: ConversationWithMeta[]): ConversationWithMeta {
  const sorted = [...conversations].sort((a, b) => {
    if (b._count.messages !== a._count.messages) {
      return b._count.messages - a._count.messages;
    }
    return a.createdAt.getTime() - b.createdAt.getTime();
  });
  return sorted[0]!;
}

function buildMergePlan(conversations: ConversationWithMeta[]): MergePlan[] {
  const grouped = new Map<string, ConversationWithMeta[]>();

  for (const conv of conversations) {
    const identity = normalizeWhatsappIdentity(conv.remotePhone ?? conv.remoteJid);
    if (!identity.normalizedPhone) continue;

    const normalizedInst = normalizeInstanceName(conv.instance.instanceName);
    if (!normalizedInst) continue;

    const key = `${normalizedInst}::${identity.normalizedPhone}`;
    const list = grouped.get(key) ?? [];
    list.push(conv);
    grouped.set(key, list);
  }

  const plans: MergePlan[] = [];
  for (const [groupKey, list] of grouped.entries()) {
    if (list.length <= 1) continue;

    const keeper = pickKeeper(list);
    const duplicates = list.filter((item) => item.id !== keeper.id);
    const movedMessages = duplicates.reduce(
      (total, item) => total + item._count.messages,
      0,
    );

    plans.push({
      groupKey,
      normalizedPhone: normalizeWhatsappIdentity(keeper.remotePhone ?? keeper.remoteJid)
        .normalizedPhone!,
      normalizedInstanceName: normalizeInstanceName(keeper.instance.instanceName),
      keepConversationId: keeper.id,
      duplicateConversationIds: duplicates.map((item) => item.id),
      movedMessages,
    });
  }

  return plans;
}

async function main() {
  const prisma = new PrismaClient();
  const execute = process.argv.includes('--execute');

  try {
    const conversations = await prisma.whatsappConversation.findMany({
      include: {
        instance: { select: { instanceName: true } },
        _count: { select: { messages: true } },
      },
      orderBy: { createdAt: 'asc' },
    }) as ConversationWithMeta[];

    const plans = buildMergePlan(conversations);
    const totalDuplicates = plans.reduce(
      (sum, plan) => sum + plan.duplicateConversationIds.length,
      0,
    );
    const totalMessagesToMove = plans.reduce(
      (sum, plan) => sum + plan.movedMessages,
      0,
    );

    console.log('[whatsapp-inbox][repair] mode=', execute ? 'EXECUTE' : 'DRY-RUN');
    console.log('[whatsapp-inbox][repair] groups=', plans.length);
    console.log('[whatsapp-inbox][repair] duplicateConversations=', totalDuplicates);
    console.log('[whatsapp-inbox][repair] messagesToMove=', totalMessagesToMove);

    for (const plan of plans) {
      console.log(
        `[whatsapp-inbox][repair][plan] key=${plan.groupKey} keep=${plan.keepConversationId} duplicates=${plan.duplicateConversationIds.join(',')} moveMessages=${plan.movedMessages}`,
      );
    }

    if (!execute) {
      console.log('[whatsapp-inbox][repair] Dry-run completed. No DB changes were made.');
      return;
    }

    const result = await prisma.$transaction(async (tx) => {
      let movedMessages = 0;
      let deletedConversations = 0;

      for (const plan of plans) {
        const move = await tx.whatsappMessage.updateMany({
          where: { conversationId: { in: plan.duplicateConversationIds } },
          data: { conversationId: plan.keepConversationId },
        });
        movedMessages += move.count;

        const del = await tx.whatsappConversation.deleteMany({
          where: { id: { in: plan.duplicateConversationIds } },
        });
        deletedConversations += del.count;
      }

      return { movedMessages, deletedConversations };
    });

    console.log('[whatsapp-inbox][repair] Execute completed.');
    console.log('[whatsapp-inbox][repair] movedMessages=', result.movedMessages);
    console.log('[whatsapp-inbox][repair] deletedConversations=', result.deletedConversations);
    console.log('[whatsapp-inbox][repair] NOTE: No whatsapp contacts table exists in current schema, so only conversations/messages were repaired.');
  } finally {
    await prisma.$disconnect();
  }
}

main().catch((error) => {
  console.error('[whatsapp-inbox][repair] failed:', error);
  process.exitCode = 1;
});
