import { Module } from '@nestjs/common';
import { MarketingApprovalService } from './marketing-approval.service';
import { MarketingConfigService } from './marketing-config.service';
import { MarketingController } from './marketing.controller';
import { MarketingGenerationService } from './marketing-generation.service';
import { MarketingService } from './marketing.service';

@Module({
  controllers: [MarketingController],
  providers: [
    MarketingService,
    MarketingGenerationService,
    MarketingApprovalService,
    MarketingConfigService,
  ],
})
export class MarketingModule {}
