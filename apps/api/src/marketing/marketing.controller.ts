import { Body, Controller, Delete, Get, Param, Patch, Post, Query, Req, UseGuards } from '@nestjs/common';
import { AuthGuard } from '@nestjs/passport';
import type { Request } from 'express';
import { Role } from '@prisma/client';
import { Roles } from '../auth/roles.decorator';
import { RolesGuard } from '../auth/roles.guard';
import { MarketingService } from './marketing.service';
import { MarketingResearchService } from './marketing-research.service';
import { GenerateMarketingStoriesDto } from './dto/generate-marketing-stories.dto';
import { MarketingActionDto } from './dto/marketing-action.dto';
import { MarketingHistoryQueryDto, MarketingQueryDto } from './dto/marketing-query.dto';
import { CreateMarketingMediaAssetDto, MarketingMediaAssetQueryDto, UpdateMarketingMediaAssetDto } from './dto/marketing-media-asset.dto';
import { UpdateMarketingConfigDto } from './dto/update-marketing-config.dto';
import { UpdateMarketingStoryDto } from './dto/update-marketing-story.dto';
import { GenerateResearchDto, UpdateMarketingResearchConfigDto } from './dto/marketing-research.dto';

type RequestUser = {
  id?: string;
  role?: string;
};

@Controller('marketing')
@UseGuards(AuthGuard('jwt'), RolesGuard)
@Roles(Role.ADMIN)
export class MarketingController {
  constructor(
    private readonly marketing: MarketingService,
    private readonly research: MarketingResearchService,
  ) {}

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

  @Post('stories/:id/regenerate-image')
  async regenerateImage(
    @Req() req: Request,
    @Param('id') storyId: string,
    @Body() dto: MarketingActionDto,
  ) {
    const user = req.user as RequestUser;
    const companyId = this.marketing.resolveCompanyId();
    return this.marketing.regenerateStoryImage(companyId, storyId, user.id ?? '', dto.reason);
  }

  @Patch('stories/:id/base-image/:mediaAssetId')
  async changeBaseImage(
    @Req() req: Request,
    @Param('id') storyId: string,
    @Param('mediaAssetId') mediaAssetId: string,
  ) {
    const user = req.user as RequestUser;
    const companyId = this.marketing.resolveCompanyId();
    return this.marketing.changeStoryBaseImage(companyId, storyId, mediaAssetId, user.id ?? '');
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

  // Publicity media gallery
  @Get('media-assets')
  async listMediaAssets(@Query() query: MarketingMediaAssetQueryDto) {
    const companyId = this.marketing.resolveCompanyId();
    return this.marketing.listMediaAssets(companyId, query);
  }

  @Post('media-assets')
  async createMediaAsset(@Req() req: Request, @Body() dto: CreateMarketingMediaAssetDto) {
    const user = req.user as RequestUser;
    const companyId = this.marketing.resolveCompanyId();
    return this.marketing.createMediaAsset(companyId, dto, user.id ?? '');
  }

  @Patch('media-assets/:id')
  async updateMediaAsset(@Req() req: Request, @Param('id') id: string, @Body() dto: UpdateMarketingMediaAssetDto) {
    const user = req.user as RequestUser;
    const companyId = this.marketing.resolveCompanyId();
    return this.marketing.updateMediaAsset(companyId, id, dto, user.id ?? '');
  }

  @Delete('media-assets/:id')
  async deleteMediaAsset(@Req() req: Request, @Param('id') id: string) {
    const user = req.user as RequestUser;
    const companyId = this.marketing.resolveCompanyId();
    return this.marketing.deleteMediaAsset(companyId, id, user.id ?? '');
  }

  // Research endpoints
  @Get('research/config')
  async getResearchConfig() {
    const companyId = this.marketing.resolveCompanyId();
    return this.research.getOrCreateConfig(companyId);
  }

  @Patch('research/config')
  async updateResearchConfig(@Req() req: Request, @Body() dto: UpdateMarketingResearchConfigDto) {
    const user = req.user as RequestUser;
    const companyId = this.marketing.resolveCompanyId();
    return this.research.updateConfig(companyId, dto, user.id ?? '');
  }

  @Get('research/latest')
  async getLatestResearch() {
    const companyId = this.marketing.resolveCompanyId();
    return this.research.getLatestResearch(companyId);
  }

  @Get('research/list')
  async listResearches() {
    const companyId = this.marketing.resolveCompanyId();
    return this.research.getList(companyId);
  }

  @Post('research/generate')
  async generateResearch(@Req() req: Request, @Body() dto: GenerateResearchDto) {
    const user = req.user as RequestUser;
    const companyId = this.marketing.resolveCompanyId();
    return this.research.generate(companyId, dto, user.id ?? '');
  }

  @Post('research/force')
  async forceResearch(@Req() req: Request, @Body() dto: GenerateResearchDto) {
    const user = req.user as RequestUser;
    const companyId = this.marketing.resolveCompanyId();
    return this.research.generate(companyId, dto, user.id ?? '', true);
  }

  @Post('research/:id/approve')
  async approveResearch(@Req() req: Request, @Param('id') researchId: string) {
    const user = req.user as RequestUser;
    const companyId = this.marketing.resolveCompanyId();
    return this.research.approve(companyId, researchId, user.id ?? '');
  }

  @Post('research/:id/reject')
  async rejectResearch(@Req() req: Request, @Param('id') researchId: string, @Body() dto: MarketingActionDto) {
    const user = req.user as RequestUser;
    const companyId = this.marketing.resolveCompanyId();
    return this.research.reject(companyId, researchId, user.id ?? '', dto.reason);
  }

  @Get('research/learning-stats')
  async getLearningStats() {
    const companyId = this.marketing.resolveCompanyId();
    return this.research.getLearningStats(companyId);
  }
}
