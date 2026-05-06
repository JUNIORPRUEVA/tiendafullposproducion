import { Module } from '@nestjs/common';
import { MarketingApprovalService } from './marketing-approval.service';
import { MarketingAutomationScheduler } from './marketing-automation.scheduler';
import { MarketingConfigService } from './marketing-config.service';
import { MarketingController } from './marketing.controller';
import { MarketingDebugController } from './marketing-debug.controller';
import { MarketingGenerationService } from './marketing-generation.service';
import { MarketingImageGenerationService } from './marketing-image-generation.service';
import { MarketingImageJobService } from './marketing-image-job.service';
import { MarketingLearningService } from './marketing-learning.service';
import { MarketingMediaAssetService } from './marketing-media-asset.service';
import { MarketingMediaSelectorService } from './marketing-media-selector.service';
import { MarketingResearchService } from './marketing-research.service';
import { MarketingResearchSourceService } from './marketing-research-source.service';
import { MarketingService } from './marketing.service';
import { MarketingStorageService } from './marketing-storage.service';
import { StorageModule } from '../storage/storage.module';

@Module({
  imports: [StorageModule],
  controllers: [MarketingController, MarketingDebugController],
  providers: [
    MarketingService,
    MarketingGenerationService,
    MarketingMediaSelectorService,
    MarketingMediaAssetService,
    MarketingImageGenerationService,
    MarketingImageJobService,
    MarketingApprovalService,
    MarketingConfigService,
    MarketingAutomationScheduler,
    MarketingResearchService,
    MarketingResearchSourceService,
    MarketingLearningService,
    MarketingStorageService,
  ],
})
export class MarketingModule {}
