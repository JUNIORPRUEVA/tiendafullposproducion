import { Module } from '@nestjs/common';
import { MarketingApprovalService } from './marketing-approval.service';
import { MarketingAutomationScheduler } from './marketing-automation.scheduler';
import { MarketingConfigService } from './marketing-config.service';
import { MarketingController } from './marketing.controller';
import { MarketingGenerationService } from './marketing-generation.service';
import { MarketingLearningService } from './marketing-learning.service';
import { MarketingResearchService } from './marketing-research.service';
import { MarketingResearchSourceService } from './marketing-research-source.service';
import { MarketingService } from './marketing.service';

@Module({
  controllers: [MarketingController],
  providers: [
    MarketingService,
    MarketingGenerationService,
    MarketingApprovalService,
    MarketingConfigService,
    MarketingAutomationScheduler,
    MarketingResearchService,
    MarketingResearchSourceService,
    MarketingLearningService,
  ],
})
export class MarketingModule {}
