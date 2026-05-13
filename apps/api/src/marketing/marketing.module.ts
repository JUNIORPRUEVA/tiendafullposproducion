import { Module } from '@nestjs/common';
import { MarketingApprovalService } from './marketing-approval.service';
import { MarketingAutomationScheduler } from './marketing-automation.scheduler';
import { MarketingConfigService } from './marketing-config.service';
import { MarketingController } from './marketing.controller';
import { MarketingCreativeComposerService } from './marketing-creative-composer.service';
import { MarketingDebugController } from './marketing-debug.controller';
import { MarketingGenerationService } from './marketing-generation.service';
import { MarketingImageAnalyzerService } from './marketing-image-analyzer.service';
import { MarketingCampaignService } from './marketing-campaign.service';
import { MarketingImageGenerationService } from './marketing-image-generation.service';
import { MarketingImageJobService } from './marketing-image-job.service';
import { MarketingImageEditProvider } from './marketing-image-edit.provider';
import { MarketingLearningService } from './marketing-learning.service';
import { MarketingMetaAdsService } from './marketing-meta-ads.service';
import { MarketingMetaPublisherService } from './marketing-meta-publisher.service';
import { MarketingMediaAssetService } from './marketing-media-asset.service';
import { MarketingMediaSelectorService } from './marketing-media-selector.service';
import { MarketingResearchService } from './marketing-research.service';
import { MarketingResearchSourceService } from './marketing-research-source.service';
import { MarketingService } from './marketing.service';
import { MarketingStorageService } from './marketing-storage.service';
import { MarketingSocialAccountsService } from './marketing-social-accounts.service';
import { StorageModule } from '../storage/storage.module';
import { ProductsModule } from '../products/products.module';

@Module({
  imports: [StorageModule, ProductsModule],
  controllers: [MarketingController, MarketingDebugController],
  providers: [
    MarketingService,
    MarketingGenerationService,
    MarketingMediaSelectorService,
    MarketingMediaAssetService,
    MarketingCreativeComposerService,
    MarketingImageAnalyzerService,
    MarketingCampaignService,
    MarketingImageGenerationService,
    MarketingImageJobService,
    MarketingImageEditProvider,
    MarketingApprovalService,
    MarketingMetaAdsService,
    MarketingMetaPublisherService,
    MarketingConfigService,
    MarketingAutomationScheduler,
    MarketingResearchService,
    MarketingResearchSourceService,
    MarketingLearningService,
    MarketingStorageService,
    MarketingSocialAccountsService,
  ],
})
export class MarketingModule {}
