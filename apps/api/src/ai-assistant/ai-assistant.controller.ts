import { Body, Controller, Post, Req, UseGuards } from '@nestjs/common';
import { AuthGuard } from '@nestjs/passport';
import { Role } from '@prisma/client';
import { Request } from 'express';
import { Roles } from '../auth/roles.decorator';
import { RolesGuard } from '../auth/roles.guard';
import { ChatAiAssistantDto } from './dto/chat-ai-assistant.dto';
import { AiAssistantService } from './ai-assistant.service';

@UseGuards(AuthGuard('jwt'), RolesGuard)
@Controller('ai')
export class AiAssistantController {
  constructor(private readonly ai: AiAssistantService) {}

  @Post('chat')
  @Roles(Role.ADMIN, Role.ASISTENTE, Role.VENDEDOR, Role.MARKETING, Role.TECNICO)
  chat(@Req() req: Request, @Body() dto: ChatAiAssistantDto) {
    const user = req.user as { id: string; role: Role };
    return this.ai.chat(user, dto);
  }
}
