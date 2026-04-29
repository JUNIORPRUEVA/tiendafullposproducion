import {
  Controller,
  Get,
  Post,
  Param,
  Query,
  Body,
  UseGuards,
  ParseUUIDPipe,
} from '@nestjs/common';
import { AuthGuard } from '@nestjs/passport';
import { RolesGuard } from '../auth/roles.guard';
import { Roles } from '../auth/roles.decorator';
import { Role } from '@prisma/client';
import { IsNotEmpty, IsOptional, IsString } from 'class-validator';
import { WhatsappInboxService } from './whatsapp-inbox.service';
import { WhatsappService } from '../whatsapp/whatsapp.service';
import { PrismaService } from '../prisma/prisma.service';

class SendMessageDto {
  @IsString()
  @IsNotEmpty()
  remoteJid!: string;

  @IsString()
  @IsNotEmpty()
  text!: string;

  @IsOptional()
  @IsString()
  userId?: string;
}

class ReplyDto {
  @IsString()
  @IsNotEmpty()
  text!: string;
}

/** Admin-only REST endpoints for the WhatsApp CRM inbox */
@Controller('whatsapp-inbox')
@UseGuards(AuthGuard('jwt'), RolesGuard)
@Roles(Role.ADMIN)
export class WhatsappInboxController {
  constructor(
    private readonly inboxService: WhatsappInboxService,
    private readonly whatsappService: WhatsappService,
    private readonly prisma: PrismaService,
  ) {}

  /** List all users that have a WhatsApp instance configured */
  @Get('users')
  listUsers() {
    return this.inboxService.listUsersWithInstances();
  }

  /** List conversations for a given user's instance */
  @Get('conversations')
  async getConversations(@Query('userId') userId: string) {
    const instance = await this.inboxService.getInstanceByUserId(userId);
    return this.inboxService.getConversations(instance.id);
  }

  /** List messages in a conversation (ascending for chat display) */
  @Get('conversations/:id/messages')
  async getMessages(
    @Param('id', ParseUUIDPipe) conversationId: string,
    @Query('limit') limit?: string,
    @Query('before') before?: string,
  ) {
    const lim = limit ? Math.min(parseInt(limit, 10) || 50, 100) : 50;
    const beforeDate = before ? new Date(before) : undefined;
    const messages = await this.inboxService.getMessages(
      conversationId,
      lim,
      beforeDate,
    );
    return messages.reverse();
  }

  /** Mark conversation messages as read */
  @Post('conversations/:id/read')
  markRead(@Param('id', ParseUUIDPipe) conversationId: string) {
    return this.inboxService.markRead(conversationId);
  }

  /** Reply to a specific conversation */
  @Post('conversations/:id/reply')
  async replyConversation(
    @Param('id', ParseUUIDPipe) conversationId: string,
    @Body() dto: ReplyDto,
  ) {
    const conversation = await this.prisma.whatsappConversation.findUnique({
      where: { id: conversationId },
      include: { instance: true },
    });
    if (!conversation) {
      return { ok: false, error: 'Conversation not found' };
    }

    const result = await this.whatsappService.sendTextMessage(
      conversation.instance.instanceName,
      conversation.remoteJid,
      dto.text,
    );

    const resultObj = result as Record<string, unknown>;
    const evolutionId =
      ((resultObj?.['key'] as Record<string, unknown>)?.['id']) as string | undefined;

    await this.inboxService.recordOutgoingMessage(
      conversation.instanceId,
      conversation.remoteJid,
      dto.text,
      evolutionId,
    );

    return { ok: true };
  }

  /** Send message from admin to any JID using a specific user's instance */
  @Post('send')
  async sendMessage(@Body() dto: SendMessageDto) {
    const instance = await this.inboxService.getInstanceByUserId(dto.userId!);

    const result2 = await this.whatsappService.sendTextMessage(
      instance.instanceName,
      dto.remoteJid,
      dto.text,
    );

    const result2Obj = result2 as Record<string, unknown>;
    const evolutionId2 =
      ((result2Obj?.['key'] as Record<string, unknown>)?.['id']) as string | undefined;

    await this.inboxService.recordOutgoingMessage(
      instance.id,
      dto.remoteJid,
      dto.text,
      evolutionId2,
    );

    return { ok: true };
  }
}

/** Webhook receiver for Evolution API — NO auth required */
@Controller('whatsapp-inbox/webhook')
export class WhatsappInboxWebhookController {
  constructor(private readonly inboxService: WhatsappInboxService) {}

  @Post(':instanceName')
  async receiveWebhook(
    @Param('instanceName') instanceName: string,
    @Body() payload: unknown,
  ) {
    try {
      // Access prisma through service private field using bracket notation
      const prismaService = (this.inboxService as unknown as { prisma: PrismaService }).prisma;
      let instance = await prismaService.userWhatsappInstance.findUnique({
        where: { instanceName },
        select: { id: true, userId: true },
      });

      // Fallback: check if this is the company-wide instance (stored in AppConfig)
      if (!instance) {
        const appConfig = await prismaService.appConfig.findUnique({
          where: { id: 'global' },
          select: { evolutionApiInstanceName: true },
        });
        if (appConfig?.evolutionApiInstanceName === instanceName) {
          // Find first admin user to own the company instance record
          const adminUser = await prismaService.user.findFirst({
            where: { role: 'ADMIN' },
            select: { id: true },
          });
          if (adminUser) {
            // Upsert a UserWhatsappInstance record for the company instance
            instance = await prismaService.userWhatsappInstance.upsert({
              where: { instanceName },
              create: {
                instanceName,
                userId: adminUser.id,
                status: 'connected',
                webhookEnabled: true,
              },
              update: {},
              select: { id: true, userId: true },
            });
          }
        }
      }

      if (!instance) {
        return { ok: true, ignored: true, reason: 'instance_not_registered' };
      }

      const parsed = this.inboxService.parseEvolutionPayload(payload);
      if (!parsed) {
        return { ok: true, ignored: true, reason: 'unparseable_payload' };
      }

      await this.inboxService.saveMessage(instance.id, parsed);
      return { ok: true };
    } catch (err) {
      console.error('[WhatsappInbox][Webhook] Error processing webhook:', err);
      return { ok: true, error: String(err) }; // Always return 200 to Evolution API
    }
  }
}

