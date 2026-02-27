import { Controller, Get, Headers, Query, UseGuards } from '@nestjs/common';
import { AuthGuard } from '@nestjs/passport';
import { Role } from '@prisma/client';
import { Roles } from '../auth/roles.decorator';
import { RolesGuard } from '../auth/roles.guard';
import { AdminPanelService } from './admin.service';

@UseGuards(AuthGuard('jwt'), RolesGuard)
@Roles(Role.ADMIN)
@Controller('admin/panel')
export class AdminPanelController {
  constructor(private readonly panel: AdminPanelService) {}

  @Get('overview')
  overview(@Query('days') days?: string) {
    return this.panel.getOverview(this.panel.parseDays(days));
  }

  @Get('ai-insights')
  aiInsights(
    @Query('days') days?: string,
    @Headers('x-openai-api-key') openAiApiKey?: string,
    @Headers('x-openai-model') openAiModel?: string,
  ) {
    return this.panel.getAiInsights(this.panel.parseDays(days), {
      apiKey: openAiApiKey,
      model: openAiModel,
    });
  }
}
