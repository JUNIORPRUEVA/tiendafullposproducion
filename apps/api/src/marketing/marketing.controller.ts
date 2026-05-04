import { Body, Controller, Get, Param, Patch, Post, Query, Req, UseGuards } from '@nestjs/common';
import { AuthGuard } from '@nestjs/passport';
import type { Request } from 'express';
import { Role } from '@prisma/client';
import { Roles } from '../auth/roles.decorator';
import { RolesGuard } from '../auth/roles.guard';
import { MarketingService } from './marketing.service';
import { GenerateMarketingStoriesDto } from './dto/generate-marketing-stories.dto';
import { MarketingActionDto } from './dto/marketing-action.dto';
import { MarketingHistoryQueryDto, MarketingQueryDto } from './dto/marketing-query.dto';
import { UpdateMarketingConfigDto } from './dto/update-marketing-config.dto';
import { UpdateMarketingStoryDto } from './dto/update-marketing-story.dto';

type RequestUser = {
  id?: string;
  role?: string;
};

@Controller('marketing')
@UseGuards(AuthGuard('jwt'), RolesGuard)
@Roles(Role.ADMIN)
export class MarketingController {
  constructor(private readonly marketing: MarketingService) {}

  @Get('dashboard')
  async dashboard(@Query() query: MarketingQueryDto) {
    const companyId = this.marketing.resolveCompanyId();
    const date = this.marketing.parseDateOnly(query.date);
    return this.marketing.getDashboard(companyId, date);
  }

  @Get('stories')
  async stories(@Query() query: MarketingQueryDto) {
    const companyId = this.marketing.resolveCompanyId();
    const date = this.marketing.parseDateOnly(query.date);
    return this.marketing.listDailyStories(companyId, date);
  }

  @Post('stories/generate-missing')
  async generateMissing(
    @Req() req: Request,
    @Body() dto: GenerateMarketingStoriesDto,
  ) {
    const user = req.user as RequestUser;
    const companyId = this.marketing.resolveCompanyId();
    const date = this.marketing.parseDateOnly(dto.date);
    return this.marketing.generateMissingStories(companyId, date, user.id ?? '');
  }

  @Post('stories/:id/approve')
  async approve(@Req() req: Request, @Param('id') storyId: string) {
    const user = req.user as RequestUser;
    const companyId = this.marketing.resolveCompanyId();
    return this.marketing.approveStory(companyId, storyId, user.id ?? '');
  }

  @Post('stories/:id/reject')
  async reject(
    @Req() req: Request,
    @Param('id') storyId: string,
    @Body() dto: MarketingActionDto,
  ) {
    const user = req.user as RequestUser;
    const companyId = this.marketing.resolveCompanyId();
    return this.marketing.rejectStory(companyId, storyId, user.id ?? '', dto.reason);
  }

  @Post('stories/:id/regenerate')
  async regenerate(@Req() req: Request, @Param('id') storyId: string) {
    const user = req.user as RequestUser;
    const companyId = this.marketing.resolveCompanyId();
    return this.marketing.regenerateStory(companyId, storyId, user.id ?? '');
  }

  @Patch('stories/:id')
  async edit(
    @Req() req: Request,
    @Param('id') storyId: string,
    @Body() dto: UpdateMarketingStoryDto,
  ) {
    const user = req.user as RequestUser;
    const companyId = this.marketing.resolveCompanyId();
    return this.marketing.editStory(companyId, storyId, dto, user.id ?? '');
  }

  @Get('history')
  async history(@Query() query: MarketingHistoryQueryDto) {
    const companyId = this.marketing.resolveCompanyId();
    return this.marketing.getHistory(companyId, query);
  }

  @Get('config')
  async config() {
    const companyId = this.marketing.resolveCompanyId();
    return this.marketing.getConfig(companyId);
  }

  @Patch('config')
  async updateConfig(@Req() req: Request, @Body() dto: UpdateMarketingConfigDto) {
    const user = req.user as RequestUser;
    const companyId = this.marketing.resolveCompanyId();
    return this.marketing.updateConfig(companyId, dto, user.id ?? '');
  }

  @Post('flow/activate')
  async activateFlow(@Req() req: Request) {
    const user = req.user as RequestUser;
    const companyId = this.marketing.resolveCompanyId();
    return this.marketing.activateFlow(companyId, user.id ?? '');
  }

  @Post('flow/pause')
  async pauseFlow(@Req() req: Request) {
    const user = req.user as RequestUser;
    const companyId = this.marketing.resolveCompanyId();
    return this.marketing.pauseFlow(companyId, user.id ?? '');
  }

  @Post('flow/reset')
  async resetFlow(@Req() req: Request) {
    const user = req.user as RequestUser;
    const companyId = this.marketing.resolveCompanyId();
    return this.marketing.resetFlow(companyId, user.id ?? '');
  }
}
