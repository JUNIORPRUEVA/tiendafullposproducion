import {
  Controller,
  Get,
  Post,
  Param,
  Query,
  Body,
  UseGuards,
  ParseUUIDPipe,
  Req,
} from '@nestjs/common';
import { AuthGuard } from '@nestjs/passport';
import { RolesGuard } from '../auth/roles.guard';
import { Roles } from '../auth/roles.decorator';
import { Role } from '@prisma/client';
import { IsNotEmpty, IsOptional, IsString } from 'class-validator';
import { WhatsappInboxService } from './whatsapp-inbox.service';
import { WhatsappService } from '../whatsapp/whatsapp.service';
import { PrismaService } from '../prisma/prisma.service';
import { Request } from 'express';

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

class DailySummaryDto {
  @IsString()
  @IsNotEmpty()
  userId!: string;

  @IsString()
  @IsNotEmpty()
  date!: string;
}

class UnlockComposeDto {
  @IsString()
  @IsNotEmpty()
  password!: string;
}

function extractEvolutionMessageId(result: unknown): string | undefined {
  const root =
    result && typeof result === 'object'
      ? (result as Record<string, unknown>)
      : {};
  const key =
    root.key && typeof root.key === 'object'
      ? (root.key as Record<string, unknown>)
      : undefined;
  const message =
    root.message && typeof root.message === 'object'
      ? (root.message as Record<string, unknown>)
      : undefined;
  const nestedKey =
    message?.key && typeof message.key === 'object'
      ? (message.key as Record<string, unknown>)
      : undefined;

  return (
    (key?.id as string | undefined) ??
    (nestedKey?.id as string | undefined) ??
    (root.id as string | undefined) ??
    (root.messageId as string | undefined)
  );
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

  /** Generate a daily AI summary for one user's WhatsApp activity */
  @Post('daily-summary')
  summarizeDailyActivity(@Body() dto: DailySummaryDto) {
    return this.inboxService.summarizeDailyActivity(dto.userId, dto.date);
  }

  @Post('compose/unlock')
  unlockCompose(@Body() dto: UnlockComposeDto, @Req() req: Request) {
    return this.inboxService.validateAdminComposePassword(
      (req.user ?? {}) as { id?: string; role?: string },
      dto.password,
    );
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

    const saved = await this.inboxService.recordOutgoingMessage(
      conversation.instanceId,
      conversation.remoteJid,
      dto.text,
    );

    const result = await this.whatsappService.sendTextMessage(
      conversation.instance.instanceName,
      conversation.remoteJid,
      dto.text,
    );
    await this.inboxService.attachEvolutionIdToMessage(
      saved.message.id,
      extractEvolutionMessageId(result),
    );

    return { ok: true, messageId: saved.message.id };
  }

  /** Send message from admin to any JID using a specific user's instance */
  @Post('send')
  async sendMessage(@Body() dto: SendMessageDto) {
    const instance = await this.inboxService.getInstanceByUserId(dto.userId!);

    const saved = await this.inboxService.recordOutgoingMessage(
      instance.id,
      dto.remoteJid,
      dto.text,
    );

    const result2 = await this.whatsappService.sendTextMessage(
      instance.instanceName,
      dto.remoteJid,
      dto.text,
    );
    await this.inboxService.attachEvolutionIdToMessage(
      saved.message.id,
      extractEvolutionMessageId(result2),
    );

    return { ok: true, messageId: saved.message.id };
  }
}

/** Webhook receiver for Evolution API — NO auth required */
@Controller('whatsapp-inbox/webhook')
export class WhatsappInboxWebhookController {
  constructor(private readonly inboxService: WhatsappInboxService) {}

  @Post(':instanceName')
  async receiveWebhookLegacy(
    @Param('instanceName') instanceName: string,
    @Body() payload: unknown,
  ) {
    try {
      console.log(
        `[WhatsappInbox][Webhook] Payload recibido para instancia "${instanceName}" eventName=- via /whatsapp-inbox/webhook`,
      );
      return await this.inboxService.handleIncomingWebhook(
        instanceName,
        payload,
        undefined,
      );
    } catch (err) {
      console.error('[WhatsappInbox][Webhook] Error processing webhook:', err);
      return { ok: true, error: String(err) }; // Always return 200 to Evolution API
    }
  }

  @Post(':instanceName/:eventName')
  async receiveWebhookByEvent(
    @Param('instanceName') instanceName: string,
    @Param('eventName') eventName: string,
    @Body() payload: unknown,
  ) {
    try {
      console.log(
        `[WhatsappInbox][Webhook] Payload recibido para instancia "${instanceName}" eventName=${eventName} via /whatsapp-inbox/webhook`,
      );
      return await this.inboxService.handleIncomingWebhook(
        instanceName,
        payload,
        eventName,
      );
    } catch (err) {
      console.error('[WhatsappInbox][Webhook] Error processing webhook:', err);
      return { ok: true, error: String(err) }; // Always return 200 to Evolution API
    }
  }
}
