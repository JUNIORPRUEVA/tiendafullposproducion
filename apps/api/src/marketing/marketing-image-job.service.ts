import { Injectable, Logger } from '@nestjs/common';
import { MarketingGenerationService } from './marketing-generation.service';

@Injectable()
export class MarketingImageJobService {
  private readonly logger = new Logger(MarketingImageJobService.name);
  private readonly activeJobs = new Set<string>();
  private readonly maxAttempts = 2;

  constructor(private readonly generation: MarketingGenerationService) {}

  enqueueStoryImageGeneration(storyId: string, companyId: string, userId: string, customPrompt?: string) {
    if (this.activeJobs.has(storyId)) {
      this.logger.log(`[marketing-image-job] queued storyId=${storyId} already-active=true`);
      return;
    }

    this.activeJobs.add(storyId);
    this.logger.log(`[marketing-image-job] queued storyId=${storyId}`);

    setImmediate(() => {
      void this.runStoryImageJob(storyId, companyId, userId, customPrompt);
    });
  }

  async processStoryImageGeneration(storyId: string, companyId: string, userId: string, customPrompt?: string) {
    if (this.activeJobs.has(storyId)) {
      return;
    }

    this.activeJobs.add(storyId);
    await this.runStoryImageJob(storyId, companyId, userId, customPrompt);
  }

  private async runStoryImageJob(storyId: string, companyId: string, userId: string, customPrompt?: string) {
    try {
      for (let attempt = 1; attempt <= this.maxAttempts; attempt += 1) {
        try {
          this.logger.log(`[marketing-image-job] processing storyId=${storyId}`);
          await this.generation.markStoryImageProcessing(companyId, storyId, attempt);
          const updated = await this.generation.processQueuedStoryImage(companyId, storyId, userId, customPrompt);
          this.logger.log(
            `[marketing-image-job] generated storyId=${storyId} url=${updated.generatedImageUrl ?? ''}`,
          );
          return;
        } catch (error) {
          const reason = error instanceof Error ? error.message : String(error);
          if (attempt < this.maxAttempts) {
            await this.generation.markStoryImageQueued(companyId, storyId, userId, customPrompt, {
              queuedAt: new Date().toISOString(),
              retryAttempt: attempt + 1,
              retryReason: reason,
              queueReason: 'retry-after-failure',
            });
            continue;
          }

          await this.generation.markStoryImageFailed(companyId, storyId, reason, attempt);
          this.logger.error(`[marketing-image-job] failed storyId=${storyId} reason=${reason}`);
          return;
        }
      }
    } finally {
      this.activeJobs.delete(storyId);
    }
  }
}