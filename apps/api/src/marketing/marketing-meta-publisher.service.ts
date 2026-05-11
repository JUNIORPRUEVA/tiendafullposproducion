import {
  BadRequestException,
  ConflictException,
  Injectable,
  Logger,
  ServiceUnavailableException,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { PrismaService } from '../prisma/prisma.service';
import { MarketingStorageService } from './marketing-storage.service';

type MetaPublishResult = {
  facebookPostId: string | null;
  instagramPostId: string | null;
  publishedAt: Date | null;
  publishStatus: string;
  publishError: string | null;
  retryCount: number;
  message: string;
  item: any;
};

type MetaConfig = {
  graphVersion: string;
  pageId: string;
  instagramBusinessId: string;
  accessToken: string;
};

@Injectable()
export class MarketingMetaPublisherService {
  private readonly logger = new Logger(MarketingMetaPublisherService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly config: ConfigService,
    private readonly marketingStorage: MarketingStorageService,
  ) {}

  async publishStory(companyId: string, storyId: string, userId: string, retryOnlyMissing = false): Promise<MetaPublishResult> {
    const story = await this.prisma.marketingDailyStory.findFirst({
      where: { id: storyId, companyId },
      include: { mediaAsset: true, approvedByUser: true },
    });
    if (!story) throw new BadRequestException('Contenido no encontrado');

    const imageUrl = this.resolveImageUrl(story as any);
    if (!imageUrl) {
      throw new BadRequestException('No hay imagen lista para publicar.');
    }

    const caption = this.buildCaption(story as any);
    if (!caption.trim()) {
      throw new BadRequestException('El copy del anuncio está vacío.');
    }

    const currentPublishStatus = `${(story as any).publishStatus ?? 'PENDING'}`.toUpperCase();
    if (!retryOnlyMissing && currentPublishStatus === 'PUBLISHING') {
      throw new ConflictException('Ya existe una publicación en curso.');
    }

    const currentFacebookPostId = `${(story as any).facebookPostId ?? ''}`.trim();
    const currentInstagramPostId = `${(story as any).instagramPostId ?? ''}`.trim();
    if (!retryOnlyMissing && currentPublishStatus === 'PUBLISHED' && currentFacebookPostId && currentInstagramPostId) {
      throw new ConflictException('Este anuncio ya está publicado en Facebook e Instagram.');
    }

    const normalizedImageUrl = this.marketingStorage.getPublicUrl(imageUrl);
    let facebookPostId = currentFacebookPostId || null;
    let instagramPostId = currentInstagramPostId || null;
    let publishError: string | null = null;
    let publishStatus = 'PUBLISHING';
    let publishedAt: Date | null = null;
    let retryCount = ((story as any).retryCount ?? 0) as number;
    let attemptRecorded = false;

    try {
      const config = await this.resolveMetaConfig();
      await this.validateMetaConnectivity(config);

      await this.prisma.marketingDailyStory.updateMany({
        where: { id: story.id, companyId },
        data: {
          publishStatus: 'PUBLISHING',
          publishError: null,
          retryCount: { increment: 1 },
        },
      });
      attemptRecorded = true;
      retryCount += 1;

      const shouldPublishFacebook = !retryOnlyMissing ? !facebookPostId : !facebookPostId;
      const shouldPublishInstagram = !retryOnlyMissing ? !instagramPostId : !instagramPostId;

      if (shouldPublishFacebook) {
        const facebookResult = await this.publishFacebookPhoto(config, normalizedImageUrl, caption);
        facebookPostId = facebookResult;
      }

      if (shouldPublishInstagram) {
        const instagramResult = await this.publishInstagramFeedPost(config, normalizedImageUrl, caption);
        instagramPostId = instagramResult;
      }

      const fullSuccess = !!facebookPostId && !!instagramPostId;
      publishStatus = fullSuccess ? 'PUBLISHED' : 'PARTIAL';
      publishedAt = fullSuccess ? new Date() : null;
      publishError = fullSuccess ? null : 'Publicación parcial: uno de los destinos sigue pendiente.';
    } catch (error) {
      publishError = this.normalizeError(error);
      publishStatus = facebookPostId || instagramPostId ? 'PARTIAL' : 'ERROR';
      if (!attemptRecorded) {
        retryCount += 1;
      }
      this.logger.error(`[meta-publish] story=${story.id} error=${publishError}`);
    }

    const updated = await this.prisma.marketingDailyStory.update({
      where: { id: story.id },
      data: {
        publishedAt,
        facebookPostId,
        instagramPostId,
        publishStatus,
        publishError,
        retryCount,
      },
      include: {
        approvedByUser: { select: { id: true, nombreCompleto: true } },
        mediaAsset: true,
      },
    });

    try {
      await this.prisma.marketingActivityLog.create({
        data: {
          companyId,
          action: publishStatus === 'PUBLISHED' ? 'MARKETING_STORY_PUBLISHED' : 'MARKETING_STORY_PUBLISH_PARTIAL',
          description: `Publicación Meta ejecutada para contenido ${story.id}`,
          userId,
          metadata: {
            storyId: story.id,
            facebookPostId,
            instagramPostId,
            publishStatus,
            publishError,
          },
        },
      });
    } catch (logError) {
      this.logger.warn(`[meta-publish] activity-log skipped: ${logError instanceof Error ? logError.message : String(logError)}`);
    }

    return {
      facebookPostId,
      instagramPostId,
      publishedAt,
      publishStatus,
      publishError,
      retryCount,
      message:
        publishStatus === 'PUBLISHED'
          ? 'Publicado correctamente en Facebook e Instagram.'
          : facebookPostId || instagramPostId
            ? 'Publicación parcial: uno de los destinos falló. Usa reintento para completar.'
            : 'No se pudo publicar en Meta.',
      item: updated,
    };
  }

  async retryMissingPublication(companyId: string, storyId: string, userId: string): Promise<MetaPublishResult> {
    return this.publishStory(companyId, storyId, userId, true);
  }

  private async resolveMetaConfig(): Promise<MetaConfig> {
    const graphVersion = (this.config.get<string>('META_GRAPH_VERSION') ?? process.env.META_GRAPH_VERSION ?? 'v23.0').trim() || 'v23.0';
    const pageId = (this.config.get<string>('FACEBOOK_PAGE_ID') ?? process.env.FACEBOOK_PAGE_ID ?? '').trim();
    const instagramBusinessId = (this.config.get<string>('INSTAGRAM_BUSINESS_ID') ?? process.env.INSTAGRAM_BUSINESS_ID ?? '').trim();
    const accessToken = (this.config.get<string>('META_PAGE_ACCESS_TOKEN') ?? process.env.META_PAGE_ACCESS_TOKEN ?? '').trim();

    if (!pageId) {
      throw new BadRequestException('Falta FACEBOOK_PAGE_ID en la configuración.');
    }
    if (!instagramBusinessId) {
      throw new BadRequestException('Falta INSTAGRAM_BUSINESS_ID en la configuración.');
    }
    if (!accessToken) {
      throw new BadRequestException('Falta META_PAGE_ACCESS_TOKEN en la configuración.');
    }

    return { graphVersion, pageId, instagramBusinessId, accessToken };
  }

  private async validateMetaConnectivity(config: MetaConfig) {
    const url = `https://graph.facebook.com/${config.graphVersion}/${config.pageId}?fields=id,name&access_token=${encodeURIComponent(config.accessToken)}`;
    const response = await fetch(url, { method: 'GET' });
    if (!response.ok) {
      const body = await response.text().catch(() => '');
      throw new ServiceUnavailableException(`No se pudo validar la conexión con Meta: ${body || response.statusText}`);
    }
  }

  private async publishFacebookPhoto(config: MetaConfig, imageUrl: string, caption: string) {
    const url = `https://graph.facebook.com/${config.graphVersion}/${config.pageId}/photos`;
    const body = new URLSearchParams({
      url: imageUrl,
      caption,
      published: 'true',
      access_token: config.accessToken,
    });
    const response = await fetch(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body,
    });
    const payload = await response.json().catch(() => ({} as any));
    if (!response.ok) {
      throw new ServiceUnavailableException(`Facebook falló: ${this.extractMetaError(payload)}`);
    }
    const postId = `${payload.post_id ?? payload.id ?? ''}`.trim();
    if (!postId) {
      throw new ServiceUnavailableException('Facebook no devolvió ID de publicación.');
    }
    this.logger.log(`[meta-publish] Facebook OK postId=${postId}`);
    return postId;
  }

  private async publishInstagramFeedPost(config: MetaConfig, imageUrl: string, caption: string) {
    const createUrl = `https://graph.facebook.com/${config.graphVersion}/${config.instagramBusinessId}/media`;
    const createBody = new URLSearchParams({
      image_url: imageUrl,
      caption,
      access_token: config.accessToken,
      share_to_feed: 'true',
    });
    const createResponse = await fetch(createUrl, {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: createBody,
    });
    const createPayload = await createResponse.json().catch(() => ({} as any));
    if (!createResponse.ok) {
      throw new ServiceUnavailableException(`Instagram media container falló: ${this.extractMetaError(createPayload)}`);
    }

    const creationId = `${createPayload.id ?? ''}`.trim();
    if (!creationId) {
      throw new ServiceUnavailableException('Instagram no devolvió creation_id.');
    }

    const publishUrl = `https://graph.facebook.com/${config.graphVersion}/${config.instagramBusinessId}/media_publish`;
    const publishBody = new URLSearchParams({
      creation_id: creationId,
      access_token: config.accessToken,
    });
    const publishResponse = await fetch(publishUrl, {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: publishBody,
    });
    const publishPayload = await publishResponse.json().catch(() => ({} as any));
    if (!publishResponse.ok) {
      throw new ServiceUnavailableException(`Instagram falló: ${this.extractMetaError(publishPayload)}`);
    }
    const postId = `${publishPayload.id ?? creationId}`.trim();
    this.logger.log(`[meta-publish] Instagram OK postId=${postId}`);
    return postId;
  }

  private buildCaption(story: any) {
    const title = `${story.title ?? ''}`.trim();
    const shortText = `${story.shortText ?? ''}`.trim();
    const cta = `${story.usedCTA ?? ''}`.trim();
    const hashtags = Array.isArray(story.hashtags)
      ? story.hashtags.map((item: unknown) => `${item}`.trim()).filter((item: string) => item.length > 0)
      : [];

    return [title, shortText, cta, hashtags.join(' ')].filter((item) => item.trim().length > 0).join('\n\n');
  }

  private resolveImageUrl(story: any) {
    const imageUrl = `${story.imageUrl ?? ''}`.trim();
    if (imageUrl) return imageUrl;
    const generatedImageUrl = `${story.generatedImageUrl ?? ''}`.trim();
    if (generatedImageUrl) return generatedImageUrl;
    const assetUrl = `${story.mediaAsset?.fileUrl ?? ''}`.trim();
    return assetUrl;
  }

  private extractMetaError(payload: any) {
    const message = `${payload?.error?.message ?? payload?.message ?? ''}`.trim();
    const type = `${payload?.error?.type ?? ''}`.trim();
    const code = `${payload?.error?.code ?? ''}`.trim();
    return [type, code, message].filter((item) => item.length > 0).join(' · ') || 'Error desconocido de Meta';
  }

  private normalizeError(error: unknown) {
    if (error instanceof Error) return error.message;
    return `${error}`.trim();
  }
}