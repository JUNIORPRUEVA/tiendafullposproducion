import { PrismaClient } from '@prisma/client';

async function main() {
  const prisma = new PrismaClient();

  try {
    const confirmed = process.env.CONFIRM_RESET_WHATSAPP_INBOX === 'true';
    if (!confirmed) {
      console.log(
        '[whatsapp-inbox][reset] Skipped. Set CONFIRM_RESET_WHATSAPP_INBOX=true to execute.',
      );
      return;
    }

    const result = await prisma.$transaction(async (tx) => {
      const deletedMessages = await tx.whatsappMessage.deleteMany({});
      const deletedConversations = await tx.whatsappConversation.deleteMany({});
      return {
        deletedMessages: deletedMessages.count,
        deletedConversations: deletedConversations.count,
      };
    });

    console.log('[whatsapp-inbox][reset] completed.');
    console.log('[whatsapp-inbox][reset] deletedMessages=', result.deletedMessages);
    console.log(
      '[whatsapp-inbox][reset] deletedConversations=',
      result.deletedConversations,
    );
    console.log(
      '[whatsapp-inbox][reset] NOTE: No whatsapp contacts/event-log tables exist in current schema, so only inbox messages/conversations were deleted.',
    );
  } finally {
    await prisma.$disconnect();
  }
}

main().catch((error) => {
  console.error('[whatsapp-inbox][reset] failed:', error);
  process.exitCode = 1;
});
