import { Body, Controller, Get, Param, Post } from '@nestjs/common';
import { MarketingService } from './marketing.service';

@Controller('marketing/debug')
export class MarketingDebugController {
  constructor(private readonly marketing: MarketingService) {}

  @Get('version')
  async version() {
    const companyId = this.marketing.resolveCompanyId();
    return this.marketing.getDebugVersion(companyId);
  }

  @Post('test-image')
  async testImage(@Body() body: { prompt?: string }) {
    const companyId = this.marketing.resolveCompanyId();
    return this.marketing.debugTestImage(companyId, `${body?.prompt ?? ''}`.trim());
  }

  @Post('test-image-edit')
  async testImageEdit(@Body() body: { imageUrl?: string; prompt?: string }) {
    const companyId = this.marketing.resolveCompanyId();
    return this.marketing.debugTestImageEdit(
      companyId,
      `${body?.imageUrl ?? ''}`.trim(),
      `${body?.prompt ?? ''}`.trim(),
    );
  }

  @Get('meta-config')
  async metaConfig() {
    return this.marketing.debugMetaConfig();
  }

  @Get('meta-token')
  async metaToken() {
    return this.marketing.debugMetaToken();
  }

  @Post('test-meta-publish')
  async testMetaPublish(
    @Body() body: { imageUrl?: string; caption?: string; dryRun?: boolean },
  ) {
    return this.marketing.debugTestMetaPublish({
      imageUrl: `${body?.imageUrl ?? ''}`.trim(),
      caption: `${body?.caption ?? ''}`.trim(),
      dryRun: body?.dryRun === true,
    });
  }

  @Post('story/:id/regenerate-image')
  async debugRegenerateStoryImage(
    @Param('id') storyId: string,
    @Body() body: { prompt?: string; mode?: string },
  ) {
    const companyId = this.marketing.resolveCompanyId();
    const normalizedMode = `${body?.mode ?? ''}`.trim().toLowerCase();
    const sync = normalizedMode === 'sync' || normalizedMode === 'direct';
    return this.marketing.regenerateStoryImage(
      companyId,
      storyId,
      '00000000-0000-0000-0000-000000000001',
      `${body?.prompt ?? ''}`.trim() || undefined,
      sync,
    );
  }

  @Get('stories/today')
  async debugStoriesForToday() {
    const companyId = this.marketing.resolveCompanyId();
    const now = new Date();
    const today = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate()));
    const result = await this.marketing.listDailyStories(companyId, today);
    return {
      companyId,
      queryDate: today.toISOString(),
      timestamp: new Date().toISOString(),
      ...result,
    };
  }
}