import {
  BadRequestException,
  ConflictException,
  Injectable,
  Logger,
  ServiceUnavailableException,
} from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { ConfigService } from '@nestjs/config';
import { PrismaService } from '../prisma/prisma.service';
import { MarketingStorageService } from './marketing-storage.service';

type MetaPublishResult = {
  facebookPostId: string | null;
  instagramPostId: string | null;
  publishedAt: Date | null;
  publishStatus: string;
  publishError: string | null;
  publishErrorCode: string | null;
  publishErrorDetails: Prisma.InputJsonValue | null;
  retryCount: number;
  shouldPublishFacebook: boolean;
  shouldPublishInstagram: boolean;
  message: string;
  item: any;
};

type MetaConfig = {
  graphVersion: string;
  pageId: string;
  instagramBusinessId: string;
  accessToken: string;
};

type MetaRawConfig = {
  graphVersion: string;
  pageId: string;
  instagramBusinessId: string;
  accessToken: string;
  appId: string;
  appSecret: string;
};

type MetaTokenInspection = {
  tokenPreview: string;
  isValid: boolean;
  tokenType: string | null;
  profileId: string | null;
  pageIdConfigured: boolean;
  pageId: string;
  hasPagesManagePosts: boolean;
  hasInstagramContentPublish: boolean;
  expiresAt: string | null;
  scopes: string[];
};

type MetaPublishErrorDetails = {
  channel: 'facebook' | 'instagram' | 'meta' | 'validation' | 'unknown';
  stage: string;
  message: string;
  type: string | null;
  code: number | null;
  subcode: number | null;
  fbtraceId: string | null;
  httpStatus: number | null;
  endpoint: string | null;
  details: Record<string, unknown> | null;
};

class MetaApiError extends Error {
  constructor(public readonly details: MetaPublishErrorDetails) {
    super(details.message);
  }
}

@Injectable()
export class MarketingMetaPublisherService {
  private readonly logger = new Logger(MarketingMetaPublisherService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly config: ConfigService,
    private readonly marketingStorage: MarketingStorageService,
  ) {}

  async publishStory(companyId: string, storyId: string, userId: string, contentType: string = 'post', retryOnlyMissing = false): Promise<MetaPublishResult> {
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

    const rawConfig = this.resolveMetaConfigRaw();
    const instagramRequested = rawConfig.instagramBusinessId.trim().length > 0;
    this.logger.log(`[meta-publish] start storyId=${story.id} contentType=${contentType}`);
    this.logger.log(`[meta-publish] imageUrl=${imageUrl}`);
    this.logger.log(`[meta-publish] captionLength=${caption.trim().length}`);
    this.logger.log(`[meta-publish] pageId=${rawConfig.pageId || 'missing'}`);
    this.logger.log(`[meta-publish] instagramBusinessId=${rawConfig.instagramBusinessId || 'missing'}`);
    this.logger.log(`[meta-publish] hasToken=${rawConfig.accessToken.length > 0}`);

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
    let publishErrorCode: string | null = null;
    let publishErrorDetails: Prisma.InputJsonValue | typeof Prisma.JsonNull = Prisma.JsonNull;
    let publishStatus = 'PUBLISHING';
    let publishedAt: Date | null = null;
    let retryCount = ((story as any).retryCount ?? 0) as number;
    const shouldPublishFacebook = !facebookPostId;
    const shouldPublishInstagram = !instagramPostId;

    await this.prisma.marketingDailyStory.updateMany({
      where: { id: story.id, companyId },
      data: {
        publishStatus: 'PUBLISHING',
        publishError: null,
        publishErrorCode: null,
        publishErrorDetails: Prisma.JsonNull,
        retryCount: { increment: 1 },
      },
    });
    retryCount += 1;

    try {
      const config = this.resolveMetaConfig(rawConfig);
      this.assertPrePublishInputs(normalizedImageUrl, caption);
      await this.assertImageUrlReachable(normalizedImageUrl);
      await this.validateMetaConnectivity(config);
      await this.validatePageTokenPermissions(config);

      const publishFacebookNow = retryOnlyMissing ? !facebookPostId : shouldPublishFacebook;
      const publishInstagramNow = instagramRequested && (retryOnlyMissing ? !instagramPostId : shouldPublishInstagram);

      if (publishFacebookNow) {
        this.logger.log(`[meta-facebook] publishing to pageId=${config.pageId}`);
        this.logger.log('[meta-facebook] endpoint=/{pageId}/photos');
        this.logger.log('[meta-facebook] never using publish_actions');
        const facebookResult = await this.publishFacebookPhoto(config, normalizedImageUrl, caption);
        facebookPostId = facebookResult;
        this.logger.log(`[meta-publish-facebook] success id=${facebookPostId}`);
      }

      if (publishInstagramNow) {
        const instagramResult = await this.publishInstagramFeedPost(config, normalizedImageUrl, caption);
        instagramPostId = instagramResult;
      }

      const facebookOk = !!facebookPostId;
      const instagramOk = !instagramRequested || !!instagramPostId;
      const fullSuccess = facebookOk && instagramOk;
      publishStatus = fullSuccess ? 'PUBLISHED' : facebookOk ? 'PARTIAL' : 'ERROR';
      publishedAt = facebookOk ? new Date() : null;
      publishError = fullSuccess ? null : facebookOk ? null : 'No se pudo publicar en Facebook.';
      publishErrorCode = fullSuccess ? null : publishErrorCode;
      publishErrorDetails = fullSuccess
        ? Prisma.JsonNull
        : facebookOk
          ? Prisma.JsonNull
          : {
              channel: 'facebook',
              stage: 'post-publish-check',
              message: 'No se pudo publicar en Facebook.',
            } as Prisma.InputJsonValue;
    } catch (error) {
      const parsed = this.parsePublishError(error);
      const isLegacyPublishActionsError =
        parsed.channel === 'facebook' && parsed.code === 200 && /publish_actions/i.test(parsed.message);
      const publishActionsGuidance =
        'Meta está rechazando el token como flujo antiguo/publish_actions. Genera un Page Access Token con pages_manage_posts y vuelve a conectar.';
      publishErrorCode = parsed.code != null ? `${parsed.code}` : null;
      publishErrorDetails = this.toErrorDetailsJson(parsed);
      if (facebookPostId && !instagramPostId) {
        publishStatus = 'PARTIAL';
        publishError = isLegacyPublishActionsError ? publishActionsGuidance : parsed.message;
      } else if (!facebookPostId && instagramPostId) {
        publishStatus = 'PARTIAL';
        publishError = isLegacyPublishActionsError ? publishActionsGuidance : parsed.message;
      } else {
        publishStatus = 'ERROR';
        publishError = isLegacyPublishActionsError ? publishActionsGuidance : parsed.message;
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
        publishErrorCode,
        publishErrorDetails,
        retryCount,
      },
      include: {
        approvedByUser: { select: { id: true, nombreCompleto: true } },
        mediaAsset: true,
      },
    });
    if (facebookPostId) {
      this.logger.log(`[meta-publish-facebook] saved facebookPostId=${facebookPostId}`);
    }
    this.logger.log(`[meta-publish] final publishStatus=${publishStatus}`);

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
            publishErrorCode,
            publishErrorDetails: this.jsonValueOrNull(publishErrorDetails),
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
      publishErrorCode,
      publishErrorDetails: this.jsonValueOrNull(publishErrorDetails),
      retryCount,
      shouldPublishFacebook,
      shouldPublishInstagram,
      message:
        publishStatus === 'PUBLISHED'
          ? 'Publicado correctamente en Facebook e Instagram.'
          : publishStatus === 'PARTIAL'
            ? publishError || 'Publicación parcial: uno de los destinos falló. Usa reintento para completar.'
            : `No se pudo publicar en Meta: ${publishError || 'error desconocido'}`,
      item: updated,
    };
  }

  async retryMissingPublication(companyId: string, storyId: string, userId: string): Promise<MetaPublishResult> {
    return this.publishStory(companyId, storyId, userId, 'post', true);
  }

  getDebugMetaConfig() {
    const raw = this.resolveMetaConfigRaw();
    const storage = this.marketingStorage.getDebugStorageConfig();
    return {
      hasToken: raw.accessToken.length > 0,
      pageIdConfigured: raw.pageId.length > 0,
      instagramIdConfigured: raw.instagramBusinessId.length > 0,
      graphVersion: raw.graphVersion,
      tokenPreview: this.maskToken(raw.accessToken),
      appIdConfigured: raw.appId.length > 0,
      appSecretConfigured: raw.appSecret.length > 0,
      publicBaseUrl: storage.publicBaseUrl,
      storageMode: storage.storageMode,
    };
  }

  async getDebugMetaToken() {
    const raw = this.resolveMetaConfigRaw();
    const tokenPreview = this.maskToken(raw.accessToken);
    if (!raw.accessToken || !raw.appId || !raw.appSecret) {
      return {
        tokenPreview,
        isValid: false,
        tokenType: null,
        profileId: null,
        pageIdConfigured: raw.pageId.length > 0,
        pageId: raw.pageId,
        hasPagesManagePosts: false,
        hasInstagramContentPublish: false,
        expiresAt: null,
        scopes: [] as string[],
      };
    }
    const config = this.resolveMetaConfig(raw);
    return this.inspectMetaToken(config);
  }

  async debugTestPublish(input: { imageUrl: string; caption: string; dryRun?: boolean }) {
    const raw = this.resolveMetaConfigRaw();
    const config = this.resolveMetaConfig(raw);
    const imageUrl = this.marketingStorage.getPublicUrl(`${input.imageUrl ?? ''}`.trim());
    const caption = `${input.caption ?? ''}`.trim();
    const dryRun = input.dryRun === true;

    this.assertPrePublishInputs(imageUrl, caption);
    await this.assertImageUrlReachable(imageUrl);
    await this.validateMetaConnectivity(config);

    if (dryRun) {
      return {
        ok: true,
        dryRun: true,
        imageUrl,
        captionLength: caption.length,
        config: this.getDebugMetaConfig(),
      };
    }

    const facebookPostId = await this.publishFacebookPhoto(config, imageUrl, caption);
    const instagramPostId = config.instagramBusinessId.trim()
      ? await this.publishInstagramFeedPost(config, imageUrl, caption)
      : null;
    return {
      ok: true,
      dryRun: false,
      imageUrl,
      captionLength: caption.length,
      facebookPostId,
      instagramPostId,
    };
  }

  private resolveMetaConfigRaw(): MetaRawConfig {
    const graphVersion = (this.config.get<string>('META_GRAPH_VERSION') ?? process.env.META_GRAPH_VERSION ?? 'v23.0').trim() || 'v23.0';
    const pageId = (
      this.config.get<string>('META_FACEBOOK_PAGE_ID') ??
      process.env.META_FACEBOOK_PAGE_ID ??
      this.config.get<string>('FACEBOOK_PAGE_ID') ??
      process.env.FACEBOOK_PAGE_ID ??
      ''
    ).trim();
    const instagramBusinessId = (
      this.config.get<string>('META_INSTAGRAM_BUSINESS_ID') ??
      process.env.META_INSTAGRAM_BUSINESS_ID ??
      this.config.get<string>('INSTAGRAM_BUSINESS_ACCOUNT_ID') ??
      process.env.INSTAGRAM_BUSINESS_ACCOUNT_ID ??
      this.config.get<string>('INSTAGRAM_BUSINESS_ID') ??
      process.env.INSTAGRAM_BUSINESS_ID ??
      ''
    ).trim();
    const accessToken = (
      this.config.get<string>('META_ACCESS_TOKEN') ??
      process.env.META_ACCESS_TOKEN ??
      this.config.get<string>('META_PAGE_ACCESS_TOKEN') ??
      process.env.META_PAGE_ACCESS_TOKEN ??
      this.config.get<string>('FACEBOOK_PAGE_ACCESS_TOKEN') ??
      process.env.FACEBOOK_PAGE_ACCESS_TOKEN ??
      ''
    ).trim();

    const appId = (
      this.config.get<string>('META_APP_ID') ??
      process.env.META_APP_ID ??
      this.config.get<string>('FACEBOOK_APP_ID') ??
      process.env.FACEBOOK_APP_ID ??
      ''
    ).trim();

    const appSecret = (
      this.config.get<string>('META_APP_SECRET') ??
      process.env.META_APP_SECRET ??
      this.config.get<string>('FACEBOOK_APP_SECRET') ??
      process.env.FACEBOOK_APP_SECRET ??
      ''
    ).trim();

    return { graphVersion, pageId, instagramBusinessId, accessToken, appId, appSecret };
  }

  private resolveMetaConfig(raw: MetaRawConfig): MetaConfig {
    if (!raw.pageId) {
      throw new MetaApiError({
        channel: 'validation',
        stage: 'config',
        message: 'Falta META_FACEBOOK_PAGE_ID',
        type: 'CONFIG_ERROR',
        code: null,
        subcode: null,
        fbtraceId: null,
        httpStatus: null,
        endpoint: null,
        details: { key: 'META_FACEBOOK_PAGE_ID' },
      });
    }
    if (!raw.accessToken) {
      throw new MetaApiError({
        channel: 'validation',
        stage: 'config',
        message: 'Falta META_ACCESS_TOKEN',
        type: 'CONFIG_ERROR',
        code: null,
        subcode: null,
        fbtraceId: null,
        httpStatus: null,
        endpoint: null,
        details: { key: 'META_ACCESS_TOKEN' },
      });
    }
    return {
      graphVersion: raw.graphVersion,
      pageId: raw.pageId,
      instagramBusinessId: raw.instagramBusinessId,
      accessToken: raw.accessToken,
    };
  }

  private async validateMetaConnectivity(config: MetaConfig) {
    const url = `https://graph.facebook.com/${config.graphVersion}/${config.pageId}?fields=id,name&access_token=${encodeURIComponent(config.accessToken)}`;
    const response = await fetch(url, { method: 'GET' });
    if (!response.ok) {
      const payload = await response.json().catch(() => ({} as any));
      const parsed = this.parseMetaErrorPayload(payload, {
        channel: 'meta',
        stage: 'validate-connectivity',
        endpoint: `/${config.pageId}`,
        httpStatus: response.status,
      });
      if (parsed.code === 190) {
        parsed.message = 'Meta token inválido o expirado';
      }
      throw new MetaApiError(parsed);
    }
  }

  private async validatePageTokenPermissions(config: MetaConfig) {
    const raw = this.resolveMetaConfigRaw();
    if (!raw.appId || !raw.appSecret) {
      throw new MetaApiError({
        channel: 'validation',
        stage: 'debug-token-config',
        message:
          'Faltan META_APP_ID o META_APP_SECRET. No se puede validar token antes de publicar.',
        type: 'CONFIG_ERROR',
        code: null,
        subcode: null,
        fbtraceId: null,
        httpStatus: null,
        endpoint: '/debug_token',
        details: {
          required: ['META_APP_ID', 'META_APP_SECRET'],
        },
      });
    }

    const token = await this.inspectMetaToken(config);
    if (!token.isValid) {
      throw new MetaApiError({
        channel: 'validation',
        stage: 'debug-token-validate',
        message:
          'Token de página inválido. Genera primero un user token extendido y luego usa el page access token de /me/accounts para Fulltech, srl.',
        type: 'TOKEN_INVALID',
        code: null,
        subcode: null,
        fbtraceId: null,
        httpStatus: null,
        endpoint: '/debug_token',
        details: token,
      });
    }

    if ((token.tokenType ?? '').toUpperCase() !== 'PAGE' || token.profileId !== config.pageId) {
      throw new MetaApiError({
        channel: 'validation',
        stage: 'debug-token-validate',
        message:
          'Meta está rechazando el token como flujo antiguo/publish_actions. Genera un Page Access Token con pages_manage_posts y vuelve a conectar.',
        type: 'TOKEN_TYPE_MISMATCH',
        code: null,
        subcode: null,
        fbtraceId: null,
        httpStatus: null,
        endpoint: '/debug_token',
        details: token,
      });
    }

    if (!token.hasPagesManagePosts) {
      throw new MetaApiError({
        channel: 'validation',
        stage: 'debug-token-validate',
        message:
          'Token de página sin pages_manage_posts. Genera un Page Access Token con permisos correctos.',
        type: 'MISSING_SCOPE',
        code: null,
        subcode: null,
        fbtraceId: null,
        httpStatus: null,
        endpoint: '/debug_token',
        details: token,
      });
    }
  }

  private async inspectMetaToken(config: MetaConfig): Promise<MetaTokenInspection> {
    const raw = this.resolveMetaConfigRaw();
    const appAccessToken = `${raw.appId}|${raw.appSecret}`;
    const url = `https://graph.facebook.com/${config.graphVersion}/debug_token?input_token=${encodeURIComponent(config.accessToken)}&access_token=${encodeURIComponent(appAccessToken)}`;
    const response = await fetch(url, { method: 'GET' });
    const payload = await response.json().catch(() => ({} as any));
    if (!response.ok) {
      const parsed = this.parseMetaErrorPayload(payload, {
        channel: 'meta',
        stage: 'debug-token-request',
        endpoint: '/debug_token',
        httpStatus: response.status,
      });
      throw new MetaApiError(parsed);
    }

    const data = payload?.data ?? {};
    const scopes = Array.isArray(data?.scopes)
      ? data.scopes.map((item: unknown) => `${item}`.trim()).filter((item: string) => item.length > 0)
      : [];
    const expiresAt = Number.isFinite(Number(data?.expires_at))
      ? new Date(Number(data.expires_at) * 1000).toISOString()
      : null;

    return {
      tokenPreview: this.maskToken(config.accessToken),
      isValid: data?.is_valid === true,
      tokenType: `${data?.type ?? ''}`.trim() || null,
      profileId: `${data?.profile_id ?? ''}`.trim() || null,
      pageIdConfigured: config.pageId.length > 0,
      pageId: config.pageId,
      hasPagesManagePosts: scopes.includes('pages_manage_posts'),
      hasInstagramContentPublish: scopes.includes('instagram_content_publish'),
      expiresAt,
      scopes,
    };
  }

  private async publishFacebookPhoto(config: MetaConfig, imageUrl: string, caption: string) {
    const url = `https://graph.facebook.com/${config.graphVersion}/${config.pageId}/photos`;
    this.logger.log(`[meta-facebook] publishing to pageId=${config.pageId}`);
    this.logger.log('[meta-facebook] endpoint=/{pageId}/photos');
    this.logger.log('[meta-facebook] never using publish_actions');
    this.logger.log(`[meta-publish-facebook] request /${config.pageId}/photos`);
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
    this.logger.log(`[meta-publish-facebook] response=${this.safeJson(payload)}`);
    if (!response.ok) {
      const parsed = this.parseMetaErrorPayload(payload, {
        channel: 'facebook',
        stage: 'facebook-photo-publish',
        endpoint: `/${config.pageId}/photos`,
        httpStatus: response.status,
      });
      this.logger.error(`[meta-publish-facebook] error=${parsed.message}`);
      throw new MetaApiError(parsed);
    }
    const postId = `${payload.post_id ?? payload.id ?? ''}`.trim();
    if (!postId) {
      const parsed: MetaPublishErrorDetails = {
        channel: 'facebook',
        stage: 'facebook-photo-publish',
        message: 'Facebook no devolvió ID de publicación.',
        type: 'MALFORMED_RESPONSE',
        code: null,
        subcode: null,
        fbtraceId: null,
        httpStatus: response.status,
        endpoint: `/${config.pageId}/photos`,
        details: { payload },
      };
      this.logger.error(`[meta-publish-facebook] error=${parsed.message}`);
      throw new MetaApiError(parsed);
    }
    this.logger.log(`[meta-publish-facebook] postId=${postId}`);
    return postId;
  }

  private async publishInstagramFeedPost(config: MetaConfig, imageUrl: string, caption: string) {
    if (!config.instagramBusinessId.trim()) {
      throw new MetaApiError({
        channel: 'validation',
        stage: 'instagram-config',
        message: 'Falta META_INSTAGRAM_BUSINESS_ID',
        type: 'CONFIG_ERROR',
        code: null,
        subcode: null,
        fbtraceId: null,
        httpStatus: null,
        endpoint: null,
        details: { key: 'META_INSTAGRAM_BUSINESS_ID' },
      });
    }
    const createUrl = `https://graph.facebook.com/${config.graphVersion}/${config.instagramBusinessId}/media`;
    this.logger.log('[meta-publish-instagram] create media container');
    const createBody = new URLSearchParams({
      image_url: imageUrl,
      caption,
      access_token: config.accessToken,
    });
    const createResponse = await fetch(createUrl, {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: createBody,
    });
    const createPayload = await createResponse.json().catch(() => ({} as any));
    this.logger.log(`[meta-publish-instagram] container response=${this.safeJson(createPayload)}`);
    if (!createResponse.ok) {
      const parsed = this.parseMetaErrorPayload(createPayload, {
        channel: 'instagram',
        stage: 'instagram-container-create',
        endpoint: `/${config.instagramBusinessId}/media`,
        httpStatus: createResponse.status,
      });
      this.logger.error(`[meta-publish-instagram] error=${parsed.message}`);
      throw new MetaApiError(parsed);
    }

    const creationId = `${createPayload.id ?? ''}`.trim();
    if (!creationId) {
      const parsed: MetaPublishErrorDetails = {
        channel: 'instagram',
        stage: 'instagram-container-create',
        message: 'Instagram no devolvió creation_id.',
        type: 'MALFORMED_RESPONSE',
        code: null,
        subcode: null,
        fbtraceId: null,
        httpStatus: createResponse.status,
        endpoint: `/${config.instagramBusinessId}/media`,
        details: { payload: createPayload },
      };
      this.logger.error(`[meta-publish-instagram] error=${parsed.message}`);
      throw new MetaApiError(parsed);
    }

    const publishUrl = `https://graph.facebook.com/${config.graphVersion}/${config.instagramBusinessId}/media_publish`;
    this.logger.log('[meta-publish-instagram] publish media');
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
    this.logger.log(`[meta-publish-instagram] publish response=${this.safeJson(publishPayload)}`);
    if (!publishResponse.ok) {
      const parsed = this.parseMetaErrorPayload(publishPayload, {
        channel: 'instagram',
        stage: 'instagram-media-publish',
        endpoint: `/${config.instagramBusinessId}/media_publish`,
        httpStatus: publishResponse.status,
      });
      this.logger.error(`[meta-publish-instagram] error=${parsed.message}`);
      throw new MetaApiError(parsed);
    }
    const postId = `${publishPayload.id ?? creationId}`.trim();
    this.logger.log(`[meta-publish-instagram] postId=${postId}`);
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

  private assertPrePublishInputs(imageUrl: string, caption: string) {
    if (!caption.trim()) {
      throw new MetaApiError({
        channel: 'validation',
        stage: 'pre-validate-caption',
        message: 'El caption/copy está vacío.',
        type: 'VALIDATION_ERROR',
        code: null,
        subcode: null,
        fbtraceId: null,
        httpStatus: null,
        endpoint: null,
        details: null,
      });
    }

    if (!imageUrl.trim()) {
      throw new MetaApiError({
        channel: 'validation',
        stage: 'pre-validate-image-url',
        message: 'No hay imagen para publicar.',
        type: 'VALIDATION_ERROR',
        code: null,
        subcode: null,
        fbtraceId: null,
        httpStatus: null,
        endpoint: null,
        details: null,
      });
    }

    const parsed = this.validatePublicHttpsImageUrl(imageUrl);
    if (!parsed.ok) {
      throw new MetaApiError({
        channel: 'validation',
        stage: 'pre-validate-image-url',
        message: parsed.message,
        type: 'VALIDATION_ERROR',
        code: null,
        subcode: null,
        fbtraceId: null,
        httpStatus: null,
        endpoint: null,
        details: { imageUrl },
      });
    }
  }

  private validatePublicHttpsImageUrl(imageUrl: string): { ok: boolean; message: string } {
    const raw = `${imageUrl ?? ''}`.trim();
    let parsed: URL;
    try {
      parsed = new URL(raw);
    } catch {
      return { ok: false, message: 'URL inválida para imagen final.' };
    }

    if (parsed.protocol !== 'https:') {
      return { ok: false, message: 'La URL de imagen debe ser HTTPS pública.' };
    }

    const hostname = `${parsed.hostname ?? ''}`.trim().toLowerCase();
    if (!hostname || hostname === 'localhost' || hostname.endsWith('.local')) {
      return { ok: false, message: 'La URL de imagen no es pública (localhost/local).' };
    }
    if (this.isPrivateHost(hostname)) {
      return { ok: false, message: 'La URL de imagen apunta a una red privada.' };
    }

    return { ok: true, message: '' };
  }

  private isPrivateHost(hostname: string) {
    if (hostname === '127.0.0.1' || hostname === '0.0.0.0') return true;
    if (hostname.startsWith('10.')) return true;
    if (hostname.startsWith('192.168.')) return true;
    if (/^172\.(1[6-9]|2[0-9]|3[0-1])\./.test(hostname)) return true;
    if (hostname === '::1') return true;
    return false;
  }

  private async assertImageUrlReachable(imageUrl: string) {
    const tryFetch = async (method: 'HEAD' | 'GET') => {
      const response = await fetch(imageUrl, {
        method,
        redirect: 'follow',
      });
      if (!response.ok) {
        return {
          ok: false,
          status: response.status,
          contentType: `${response.headers.get('content-type') ?? ''}`.toLowerCase(),
        };
      }
      const contentType = `${response.headers.get('content-type') ?? ''}`.toLowerCase();
      return { ok: true, status: response.status, contentType };
    };

    let check = await tryFetch('HEAD');
    if (!check.ok || !check.contentType.startsWith('image/')) {
      check = await tryFetch('GET');
    }

    if (!check.ok) {
      throw new MetaApiError({
        channel: 'validation',
        stage: 'pre-validate-image-reachability',
        message: `La URL de imagen no es alcanzable (${check.status}).`,
        type: 'VALIDATION_ERROR',
        code: check.status,
        subcode: null,
        fbtraceId: null,
        httpStatus: check.status,
        endpoint: imageUrl,
        details: { status: check.status },
      });
    }

    if (!check.contentType.startsWith('image/')) {
      throw new MetaApiError({
        channel: 'validation',
        stage: 'pre-validate-image-content-type',
        message: `La URL no responde como imagen (content-type: ${check.contentType || 'desconocido'}).`,
        type: 'VALIDATION_ERROR',
        code: null,
        subcode: null,
        fbtraceId: null,
        httpStatus: null,
        endpoint: imageUrl,
        details: { contentType: check.contentType || null },
      });
    }
  }

  private parseMetaErrorPayload(
    payload: any,
    input: { channel: MetaPublishErrorDetails['channel']; stage: string; endpoint: string | null; httpStatus: number | null },
  ): MetaPublishErrorDetails {
    const errorNode = payload?.error ?? payload ?? {};
    const message = `${errorNode?.message ?? payload?.message ?? 'Error de Graph API'}`.trim() || 'Error de Graph API';
    const type = `${errorNode?.type ?? ''}`.trim() || null;
    const code = Number.isFinite(Number(errorNode?.code)) ? Number(errorNode.code) : null;
    const subcode = Number.isFinite(Number(errorNode?.error_subcode)) ? Number(errorNode.error_subcode) : null;
    const fbtraceId = `${errorNode?.fbtrace_id ?? ''}`.trim() || null;

    return {
      channel: input.channel,
      stage: input.stage,
      message,
      type,
      code,
      subcode,
      fbtraceId,
      httpStatus: input.httpStatus,
      endpoint: input.endpoint,
      details: {
        response: payload,
      },
    };
  }

  private parsePublishError(error: unknown): MetaPublishErrorDetails {
    if (error instanceof MetaApiError) {
      return error.details;
    }
    if (error instanceof BadRequestException || error instanceof ConflictException || error instanceof ServiceUnavailableException) {
      const message = `${error.message ?? 'Error de publicación'}`.trim();
      return {
        channel: 'validation',
        stage: 'exception',
        message,
        type: error.name,
        code: null,
        subcode: null,
        fbtraceId: null,
        httpStatus: null,
        endpoint: null,
        details: null,
      };
    }

    const message = this.normalizeError(error);
    return {
      channel: 'unknown',
      stage: 'unknown',
      message: message || 'Error desconocido de publicación en Meta',
      type: null,
      code: null,
      subcode: null,
      fbtraceId: null,
      httpStatus: null,
      endpoint: null,
      details: null,
    };
  }

  private toErrorDetailsJson(details: MetaPublishErrorDetails): Prisma.InputJsonValue {
    return {
      channel: details.channel,
      stage: details.stage,
      message: details.message,
      type: details.type,
      code: details.code,
      subcode: details.subcode,
      fbtraceId: details.fbtraceId,
      httpStatus: details.httpStatus,
      endpoint: details.endpoint,
      details: details.details,
      happenedAt: new Date().toISOString(),
    } as Prisma.InputJsonValue;
  }

  private jsonValueOrNull(value: Prisma.InputJsonValue | typeof Prisma.JsonNull): Prisma.InputJsonValue | null {
    if ((value as unknown) === Prisma.JsonNull) {
      return null;
    }
    return value as Prisma.InputJsonValue;
  }

  private safeJson(value: unknown) {
    try {
      const raw = JSON.stringify(value);
      if (!raw) return '{}';
      if (raw.length > 1200) {
        return `${raw.slice(0, 1200)}...`;
      }
      return raw;
    } catch {
      return '{}';
    }
  }

  private maskToken(token: string) {
    const raw = `${token ?? ''}`.trim();
    if (!raw) return '';
    if (raw.length <= 8) return `${raw.slice(0, 2)}...${raw.slice(-2)}`;
    return `${raw.slice(0, 4)}...${raw.slice(-4)}`;
  }

  private normalizeError(error: unknown) {
    if (error instanceof Error) return error.message;
    return `${error}`.trim();
  }
}