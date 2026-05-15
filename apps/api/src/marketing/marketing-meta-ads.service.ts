import {
  Logger,
  Injectable,
  UnprocessableEntityException,
  ServiceUnavailableException,
} from '@nestjs/common';
import sharp from 'sharp';

export type MetaAdsDebugConfig = {
  hasAppId: boolean;
  hasAppSecret: boolean;
  hasBusinessId: boolean;
  hasAdAccountId: boolean;
  hasPageId: boolean;
  hasInstagramId: boolean;
  tokenPreview: string;
  tokenValid: boolean;
  scopes: string[];
  adAccountAccessible: boolean;
};

export type MetaAdsPermissionsDebugReport = {
  tokenValid: boolean;
  appId: string;
  tokenPreview: string;
  adAccountId: string;
  adAccountAccessible: boolean;
  adAccountStatus: number | null;
  adAccountDisableReason: string | null;
  hasAdsManagement: boolean;
  hasAdsRead: boolean;
  hasBusinessManagement: boolean;
  canReadAdImages: boolean;
  canUploadAdImage: boolean;
  canCreateCampaign: boolean;
  canCreateAdset: boolean;
  canCreateCreative: boolean;
  assignedUsersAccessible: boolean;
  assignedUsersCount: number | null;
  pageAccessible: boolean;
  instagramAccessible: boolean;
  whatsappPhoneAccessible: boolean;
  recommendedFixes: string[];
};

export type MetaAdAccountDebugProbe = {
  adAccountId: string;
  canCreateCampaign: boolean;
  canCreateAdset: boolean;
  canCreateCreative: boolean;
  canUploadImage: boolean;
  campaignError: string | null;
  adsetError: string | null;
  creativeError: string | null;
  uploadImageError: string | null;
  recommendedFixes: string[];
};

export type MetaRuntimeConfigDebug = {
  graphVersion: string;
  appId: string;
  appSecretConfigured: boolean;
  adAccountId: string;
  pageId: string;
  instagramBusinessId: string;
  whatsappPhoneNumberId: string;
  whatsappBusinessAccountId: string;
  businessId: string;
  adsTokenPreview: string;
  userTokenPreview: string;
  organicTokenPreview: string;
};

export type MetaWhatsappDebugReport = {
  hasMetaAccessToken: boolean;
  hasAdAccountId: boolean;
  hasFacebookPageId: boolean;
  hasInstagramBusinessId: boolean;
  hasWhatsappPhoneNumberId: boolean;
  hasWhatsappBusinessAccountId: boolean;
  whatsappPhoneNumberId: string;
  whatsappBusinessAccountId: string;
  businessId: string;
  tokenValid: boolean;
  tokenType: string | null;
  scopes: string[];
  phoneNumberProbe: {
    ok: boolean;
    message: string;
    code: string | null;
    subcode: string | null;
    fbtraceId: string | null;
  };
  whatsappBusinessProbe: {
    ok: boolean;
    message: string;
    code: string | null;
    subcode: string | null;
    fbtraceId: string | null;
  };
};

type MetaAdsIds = {
  campaignId: string;
  adSetId: string;
  creativeId: string;
  adId: string;
  imageHash: string | null;
  videoId: string | null;
  mediaType: MetaAdMediaType;
  mediaUrl: string;
};

export type MetaAdMediaType = 'IMAGE' | 'VIDEO';

export type MetaPublishStepId =
  | 'VALIDATING_META'
  | 'VALIDATING_AD_ACCOUNT'
  | 'VALIDATING_PAGE'
  | 'VALIDATING_INSTAGRAM'
  | 'VALIDATING_WHATSAPP'
  | 'VALIDATING_MEDIA'
  | 'UPLOADING_MEDIA'
  | 'CREATING_CAMPAIGN'
  | 'CREATING_ADSET'
  | 'CREATING_CREATIVE'
  | 'CREATING_AD'
  | 'PUBLISHING_META'
  | 'DONE';

export type MetaPublishStepStatus = 'PENDING' | 'RUNNING' | 'DONE' | 'ERROR';

export type MetaPublishStep = {
  id: MetaPublishStepId;
  label: string;
  status: MetaPublishStepStatus;
  detail?: string | null;
  at: string;
};

export type MetaAdsErrorDetails = {
  stage?: string | null;
  message: string;
  code?: string | null;
  subcode?: string | null;
  fbtraceId?: string | null;
  recommendation?: string | null;
};

export class MetaAdsException extends UnprocessableEntityException {
  constructor(public readonly metaDetails: MetaAdsErrorDetails) {
    const parts = [
      metaDetails.stage ? `Etapa: ${metaDetails.stage}` : null,
      metaDetails.message,
      metaDetails.code ? `code=${metaDetails.code}` : null,
      metaDetails.subcode ? `subcode=${metaDetails.subcode}` : null,
      metaDetails.fbtraceId ? `fbtrace_id=${metaDetails.fbtraceId}` : null,
      metaDetails.recommendation ? `Recomendacion: ${metaDetails.recommendation}` : null,
    ].filter(Boolean);
    super(parts.join(' · '));
  }
}

type CreateFlowInput = {
  name: string;
  objective: string;
  dailyBudget: number;
  totalBudget?: number | null;
  headline: string;
  primaryText: string;
  description?: string | null;
  cta: string;
  destinationUrl?: string | null;
  mediaUrl: string;
  mediaMimeType?: string | null;
  mediaFileName?: string | null;
  startTime?: Date | null;
  endTime?: Date | null;
  targeting: Record<string, unknown>;
  onStep?: (step: MetaPublishStep) => Promise<void> | void;
};

type MetaApiError = {
  stage?: string | null;
  message: string;
  code?: string | null;
  subcode?: string | null;
  fbtraceId?: string | null;
  recommendation?: string | null;
};

type PreparedAdImage = {
  buffer: Buffer;
  fileName: string;
  mimeType: 'image/jpeg' | 'image/png';
  width: number;
  height: number;
  sizeBytes: number;
  normalized: boolean;
};

type PreparedCreativeMedia = {
  mediaType: MetaAdMediaType;
  mediaUrl: string;
  imageHash: string | null;
  videoId: string | null;
  mode: 'DIRECT_PICTURE_URL' | 'DIRECT_VIDEO_URL' | 'UPLOADED_IMAGE_HASH';
};

@Injectable()
export class MarketingMetaAdsService {
  private readonly logger = new Logger(MarketingMetaAdsService.name);

  private get graphVersion() {
    return (process.env.META_GRAPH_VERSION ?? 'v23.0').trim() || 'v23.0';
  }

  private get appId() {
    const adsAppId = (process.env.META_ADS_APP_ID ?? '').trim();
    if (adsAppId.isNotEmpty) return adsAppId;
    return (process.env.META_APP_ID ?? '').trim();
  }

  private get appSecret() {
    const adsAppSecret = (process.env.META_ADS_APP_SECRET ?? '').trim();
    if (adsAppSecret.isNotEmpty) return adsAppSecret;
    return (process.env.META_APP_SECRET ?? '').trim();
  }

  private get businessId() {
    return (process.env.META_BUSINESS_ID ?? '').trim();
  }

  private get adAccountId() {
    return (process.env.META_AD_ACCOUNT_ID ?? '').trim();
  }

  private get pageId() {
    return (process.env.META_FACEBOOK_PAGE_ID ?? '').trim();
  }

  private get igBusinessId() {
    return (process.env.META_INSTAGRAM_BUSINESS_ID ?? '').trim();
  }

  private get whatsappPhoneNumberId() {
    return (process.env.META_WHATSAPP_PHONE_NUMBER_ID ?? '').trim();
  }

  private get whatsappBusinessAccountId() {
    return (process.env.META_WHATSAPP_BUSINESS_ACCOUNT_ID ?? '').trim();
  }

  private get accessToken() {
    const adsAccessToken = (process.env.META_ADS_ACCESS_TOKEN ?? '').trim();
    if (adsAccessToken.isNotEmpty) return adsAccessToken;
    return (process.env.META_ACCESS_TOKEN ?? '').trim();
  }

  private tokenPreview(token: string) {
    if (!token) return '';
    if (token.length <= 14) return `${token.substring(0, 4)}***`;
    return `${token.substring(0, 8)}...${token.substring(token.length - 6)}`;
  }

  private graphUrl(path: string) {
    const safePath = path.startsWith('/') ? path.substring(1) : path;
    return `https://graph.facebook.com/${this.graphVersion}/${safePath}`;
  }

  private normalizeAccountId() {
    const raw = this.adAccountId;
    if (!raw) return '';
    return raw.startsWith('act_') ? raw : `act_${raw}`;
  }

  ensureAdsConfigured() {
    if (!this.accessToken) {
      throw new ServiceUnavailableException(
        'No se pudo crear la campaña porque falta META_ADS_ACCESS_TOKEN (o fallback META_ACCESS_TOKEN).',
      );
    }
    if (!this.normalizeAccountId()) {
      throw new ServiceUnavailableException(
        'No se pudo crear la campaña porque falta META_AD_ACCOUNT_ID.',
      );
    }
    if (!this.pageId) {
      throw new ServiceUnavailableException(
        'No se pudo crear la campaña porque falta META_FACEBOOK_PAGE_ID.',
      );
    }
    if (!this.igBusinessId) {
      throw new ServiceUnavailableException(
        'No se pudo crear la campaña porque falta META_INSTAGRAM_BUSINESS_ID.',
      );
    }
    if (!this.whatsappPhoneNumberId) {
      throw new ServiceUnavailableException(
        'No se pudo crear la campaña porque falta META_WHATSAPP_PHONE_NUMBER_ID.',
      );
    }
  }

  async debugAdsConfig(): Promise<MetaAdsDebugConfig> {
    const tokenValidResult = await this.inspectToken().catch(() => ({
      tokenValid: false,
      scopes: [] as string[],
    }));

    const adAccountAccessible = await this.checkAdAccountAccess().catch(() => false);

    return {
      hasAppId: this.appId.length > 0,
      hasAppSecret: this.appSecret.length > 0,
      hasBusinessId: this.businessId.length > 0,
      hasAdAccountId: this.normalizeAccountId().length > 0,
      hasPageId: this.pageId.length > 0,
      hasInstagramId: this.igBusinessId.length > 0,
      tokenPreview: this.tokenPreview(this.accessToken),
      tokenValid: tokenValidResult.tokenValid,
      scopes: tokenValidResult.scopes,
      adAccountAccessible,
    };
  }

  async debugMetaAdsPermissions(): Promise<MetaAdsPermissionsDebugReport> {
    return this.inspectMetaAdsPermissions();
  }

  async debugMetaAdAccounts() {
    const candidates = Array.from(new Set([
      this.normalizeAccountId(),
      this.normalizeProvidedAccountId('act_1425678481793809'),
      this.normalizeProvidedAccountId('act_596898948022113'),
    ].filter((value) => value.length > 0)));

    const accounts = await Promise.all(candidates.map(async (adAccountId) => {
      const report = await this.inspectMetaAdsPermissions(adAccountId);
      return this.buildMetaAdAccountProbe(report);
    }));

    return {
      activeAdAccountId: this.normalizeAccountId(),
      accounts,
    };
  }

  getRuntimeMetaConfig(): MetaRuntimeConfigDebug {
    const organicToken =
      (process.env.META_ACCESS_TOKEN ?? '').trim() ||
      (process.env.META_PAGE_ACCESS_TOKEN ?? '').trim();
    const userToken = (process.env.META_USER_ACCESS_TOKEN ?? '').trim();
    const adsToken =
      (process.env.META_ADS_ACCESS_TOKEN ?? '').trim() ||
      (process.env.META_ACCESS_TOKEN ?? '').trim();
    const runtimeAppId =
      (process.env.META_ADS_APP_ID ?? '').trim() ||
      (process.env.META_APP_ID ?? '').trim();
    const runtimeAppSecret =
      (process.env.META_ADS_APP_SECRET ?? '').trim() ||
      (process.env.META_APP_SECRET ?? '').trim();
    return {
      graphVersion: (process.env.META_GRAPH_VERSION ?? 'v23.0').trim() || 'v23.0',
      appId: runtimeAppId,
      appSecretConfigured: runtimeAppSecret.length > 0,
      adAccountId: this.normalizeAccountId(),
      pageId: (process.env.META_FACEBOOK_PAGE_ID ?? '').trim(),
      instagramBusinessId: (process.env.META_INSTAGRAM_BUSINESS_ID ?? '').trim(),
      whatsappPhoneNumberId: (process.env.META_WHATSAPP_PHONE_NUMBER_ID ?? '').trim(),
      whatsappBusinessAccountId: (process.env.META_WHATSAPP_BUSINESS_ACCOUNT_ID ?? '').trim(),
      businessId: (process.env.META_BUSINESS_ID ?? '').trim(),
      adsTokenPreview: this.tokenPreview(adsToken),
      userTokenPreview: this.tokenPreview(userToken),
      organicTokenPreview: this.tokenPreview(organicToken),
    };
  }

  updateRuntimeMetaConfig(input: {
    graphVersion?: string;
    appId?: string;
    appSecret?: string;
    adAccountId?: string;
    pageId?: string;
    instagramBusinessId?: string;
    whatsappPhoneNumberId?: string;
    whatsappBusinessAccountId?: string;
    businessId?: string;
    adsAccessToken?: string;
    userAccessToken?: string;
    organicPageAccessToken?: string;
  }) {
    const assign = (key: string, value: string | undefined) => {
      if (value == null) return;
      process.env[key] = value.trim();
    };

    assign('META_GRAPH_VERSION', input.graphVersion);
    assign('META_ADS_APP_ID', input.appId);
    assign('META_ADS_APP_SECRET', input.appSecret);
    assign('META_AD_ACCOUNT_ID', input.adAccountId);
    assign('META_FACEBOOK_PAGE_ID', input.pageId);
    assign('META_INSTAGRAM_BUSINESS_ID', input.instagramBusinessId);
    assign('META_WHATSAPP_PHONE_NUMBER_ID', input.whatsappPhoneNumberId);
    assign('META_WHATSAPP_BUSINESS_ACCOUNT_ID', input.whatsappBusinessAccountId);
    assign('META_BUSINESS_ID', input.businessId);
    assign('META_ADS_ACCESS_TOKEN', input.adsAccessToken);
    assign('META_USER_ACCESS_TOKEN', input.userAccessToken);
    assign('META_ACCESS_TOKEN', input.organicPageAccessToken);

    this.logger.log(
      `[meta-runtime-config] updated adsAppId=${process.env.META_ADS_APP_ID ?? ''} adAccountId=${this.normalizeAccountId() || 'missing'} pageId=${process.env.META_FACEBOOK_PAGE_ID ?? ''} adsToken=${this.tokenPreview(process.env.META_ADS_ACCESS_TOKEN ?? process.env.META_ACCESS_TOKEN ?? '')} userToken=${this.tokenPreview(process.env.META_USER_ACCESS_TOKEN ?? '')} organicToken=${this.tokenPreview(process.env.META_ACCESS_TOKEN ?? '')}`,
    );

    return this.getRuntimeMetaConfig();
  }

  async createCampaignFlow(input: CreateFlowInput): Promise<MetaAdsIds> {
    this.ensureAdsConfigured();

    let media = this.prepareCreativeMedia(input);

    await this.emitStep(input, 'VALIDATING_META', 'Validando token Meta', 'RUNNING');
    await this.validateAccessToken();
    await this.emitStep(input, 'VALIDATING_META', 'Validando token Meta', 'DONE');

    await this.emitStep(input, 'VALIDATING_AD_ACCOUNT', 'Validando cuenta publicitaria', 'RUNNING');
    await this.validateAdAccount();
    await this.emitStep(input, 'VALIDATING_AD_ACCOUNT', 'Validando cuenta publicitaria', 'DONE');

    await this.emitStep(input, 'VALIDATING_PAGE', 'Validando pagina Facebook', 'RUNNING');
    await this.validateFacebookPage();
    await this.emitStep(input, 'VALIDATING_PAGE', 'Validando pagina Facebook', 'DONE');

    await this.emitStep(input, 'VALIDATING_INSTAGRAM', 'Validando Instagram Business', 'RUNNING');
    await this.validateInstagramBusiness();
    await this.emitStep(input, 'VALIDATING_INSTAGRAM', 'Validando Instagram Business', 'DONE');

    await this.emitStep(input, 'VALIDATING_WHATSAPP', 'Validando WhatsApp FullTech', 'RUNNING');
    const whatsappValidation = await this.validateWhatsappPhoneNumberFlexible();
    await this.emitStep(
      input,
      'VALIDATING_WHATSAPP',
      'Validando WhatsApp FullTech',
      'DONE',
      whatsappValidation.warningMessage?.trim().isNotEmpty == true
        ? whatsappValidation.warningMessage
        : this.whatsappPhoneNumberId,
    );

    // For image creatives, validate real Ad Account upload permissions before creating campaign/adset.
    if (media.mediaType === 'IMAGE') {
      await this.emitStep(input, 'UPLOADING_MEDIA', 'Subiendo imagen', 'RUNNING', 'Pre-validando permisos de subida /adimages');
      await this.validateImageUploadPreflight();
      await this.emitStep(input, 'UPLOADING_MEDIA', 'Subiendo imagen', 'DONE', 'Permisos de subida confirmados');
    }

    await this.emitStep(input, 'VALIDATING_MEDIA', 'Validando media publica HTTPS', 'RUNNING');
    await this.validatePublicMediaUrl(input.mediaUrl);
    await this.emitStep(input, 'VALIDATING_MEDIA', 'Validando media publica HTTPS', 'DONE');

    await this.emitStep(
      input,
      'UPLOADING_MEDIA',
      'Subiendo imagen',
      'DONE',
      media.mode === 'DIRECT_VIDEO_URL' ? 'Usando video_url directo' : 'Usando picture URL directa',
    );

    await this.emitStep(input, 'CREATING_CAMPAIGN', 'Creando campana', 'RUNNING');
    const campaign = await this.postForm(
      `/${this.normalizeAccountId()}/campaigns`,
      {
        name: input.name,
        objective: input.objective,
        buying_type: 'AUCTION',
        status: 'PAUSED',
        special_ad_categories: '[]',
      },
      'Creando Campaign',
      'Verifica que OUTCOME_ENGAGEMENT este disponible para la cuenta publicitaria y que el token tenga ads_management.',
    );

    const campaignId = `${campaign.id ?? ''}`.trim();
    if (!campaignId) {
      throw new ServiceUnavailableException('Meta no devolvió campaign_id al crear Campaign.');
    }
    await this.emitStep(input, 'CREATING_CAMPAIGN', 'Creando campana', 'DONE', campaignId);

    await this.emitStep(input, 'CREATING_ADSET', 'Creando segmentacion', 'RUNNING');
    const adsetPayload: Record<string, string> = {
      campaign_id: campaignId,
      name: `${input.name} - Ad Set`,
      billing_event: 'IMPRESSIONS',
      optimization_goal: 'REACH',
      status: 'PAUSED',
      targeting: JSON.stringify(input.targeting),
      daily_budget: `${Math.max(1, Math.round(input.dailyBudget * 100))}`,
      promoted_object: JSON.stringify(this.buildPromotedObject()),
    };

    if (input.totalBudget != null && input.totalBudget > 0) {
      adsetPayload.lifetime_budget = `${Math.round(input.totalBudget * 100)}`;
      delete adsetPayload.daily_budget;
    }
    if (input.startTime) {
      adsetPayload.start_time = input.startTime.toISOString();
    }
    if (input.endTime) {
      adsetPayload.end_time = input.endTime.toISOString();
    }

    const adset = await this.postForm(
      `/${this.normalizeAccountId()}/adsets`,
      adsetPayload,
      'Creando AdSet',
      'Verifica que el WhatsApp Phone Number ID este autorizado para esta cuenta publicitaria y que destination_type=WHATSAPP este disponible.',
    );
    const adSetId = `${adset.id ?? ''}`.trim();
    if (!adSetId) {
      throw new ServiceUnavailableException('Meta no devolvió adset_id al crear Ad Set.');
    }
    await this.emitStep(input, 'CREATING_ADSET', 'Creando segmentacion', 'DONE', adSetId);

    const finalCta = this.resolveMetaCta(input.cta);
    const link = this.resolveDestination(input.destinationUrl);

    await this.emitStep(input, 'CREATING_CREATIVE', 'Creando anuncio creativo', 'RUNNING');

    let creativePayload = this.buildCreativePayload(input, media, finalCta, link);
    let creative: Record<string, unknown>;
    try {
      creative = await this.createCreativeWithCtaFallback(creativePayload);
    } catch (error) {
      if (
        error instanceof MetaAdsException &&
        media.mediaType === 'IMAGE' &&
        media.mode === 'DIRECT_PICTURE_URL' &&
        this.shouldFallbackToImageHash(error)
      ) {
        await this.emitStep(input, 'UPLOADING_MEDIA', 'Subiendo imagen', 'RUNNING', 'Meta exige image_hash; intentando /adimages');
        await this.validateAdImageUploadPermissions();
        media = await this.uploadImageHashToAdAccount(input);
        await this.emitStep(input, 'UPLOADING_MEDIA', 'Subiendo imagen', 'DONE', media.imageHash);
        creativePayload = this.buildCreativePayload(input, media, finalCta, link);
        creative = await this.createCreativeWithCtaFallback(creativePayload);
      } else {
        throw error;
      }
    }
    const creativeId = `${creative.id ?? ''}`.trim();
    if (!creativeId) {
      throw new ServiceUnavailableException('Meta no devolvió creative_id al crear Creative.');
    }
    await this.emitStep(input, 'CREATING_CREATIVE', 'Creando anuncio creativo', 'DONE', creativeId);

    await this.emitStep(input, 'CREATING_AD', 'Creando anuncio', 'RUNNING');
    const ad = await this.postForm(
      `/${this.normalizeAccountId()}/ads`,
      {
        name: `${input.name} - Ad`,
        adset_id: adSetId,
        creative: JSON.stringify({ creative_id: creativeId }),
        status: 'PAUSED',
      },
      'Creando Ad',
      'Verifica que el AdSet y Creative hayan sido creados correctamente y sigan en estado PAUSED.',
    );
    const adId = `${ad.id ?? ''}`.trim();
    if (!adId) {
      throw new ServiceUnavailableException('Meta no devolvió ad_id al crear Ad.');
    }
    await this.emitStep(input, 'CREATING_AD', 'Creando anuncio', 'DONE', adId);

    await this.emitStep(input, 'PUBLISHING_META', 'Publicando en Meta', 'DONE');
    await this.emitStep(input, 'DONE', 'Campana creada en Meta Ads', 'DONE');

    return {
      campaignId,
      adSetId,
      creativeId,
      adId,
      imageHash: media.imageHash,
      videoId: media.videoId,
      mediaType: media.mediaType,
      mediaUrl: media.mediaUrl,
    };
  }

  async activateCampaign(campaignId: string, adSetId?: string | null, adId?: string | null) {
    await this.updateEntityStatus(campaignId, 'ACTIVE');
    if (adSetId) await this.updateEntityStatus(adSetId, 'ACTIVE');
    if (adId) await this.updateEntityStatus(adId, 'ACTIVE');
  }

  async pauseCampaign(campaignId: string, adSetId?: string | null, adId?: string | null) {
    await this.updateEntityStatus(campaignId, 'PAUSED');
    if (adSetId) await this.updateEntityStatus(adSetId, 'PAUSED');
    if (adId) await this.updateEntityStatus(adId, 'PAUSED');
  }

  private resolveMetaCta(rawCta: string) {
    const normalized = (rawCta ?? '').trim().toUpperCase();
    if (normalized === 'SEND_MESSAGE') return 'SEND_MESSAGE';
    return 'WHATSAPP_MESSAGE';
  }

  private resolveDestination(destinationUrl?: string | null) {
    const cleanUrl = `${destinationUrl ?? ''}`.trim();
    if (cleanUrl) return cleanUrl;
    return `https://wa.me/18295344286`;
  }

  private buildPromotedObject() {
    return {
      page_id: this.pageId,
      ...(this.whatsappPhoneNumberId
        ? { whatsapp_phone_number: this.whatsappPhoneNumberId }
        : {}),
    };
  }

  private buildWhatsappCtaValue(link: string) {
    return {
      link,
      app_destination: 'WHATSAPP',
      whatsapp_phone_number: this.whatsappPhoneNumberId,
      whatsapp_destination: {
        phone_number_id: this.whatsappPhoneNumberId,
      },
    };
  }

  private buildCreativePayload(
    input: CreateFlowInput,
    media: PreparedCreativeMedia,
    finalCta: string,
    link: string,
  ) {
    return {
      name: `${input.name} - Creative`,
      degrees_of_freedom_spec: JSON.stringify({
        creative_features_spec: {
          standard_enhancements: { enroll_status: 'OPT_OUT' },
        },
      }),
      object_story_spec: JSON.stringify({
        page_id: this.pageId,
        ...(this.igBusinessId ? { instagram_actor_id: this.igBusinessId } : {}),
        ...(media.mediaType === 'IMAGE'
          ? {
              link_data: {
                link,
                ...(media.imageHash ? { image_hash: media.imageHash } : { picture: media.mediaUrl }),
                message: input.primaryText,
                name: input.headline,
                description: input.description ?? '',
                call_to_action: {
                  type: finalCta,
                  value: this.buildWhatsappCtaValue(link),
                },
              },
            }
          : {
              video_data: {
                video_url: media.mediaUrl,
                message: input.primaryText,
                title: input.headline,
                link_description: input.description ?? '',
                call_to_action: {
                  type: finalCta,
                  value: this.buildWhatsappCtaValue(link),
                },
              },
            }),
      }),
    };
  }

  private async createCreativeWithCtaFallback(creativePayload: Record<string, unknown>) {
    const primaryPayload = this.stringifyPayload(creativePayload);
    try {
      return await this.postForm(
        `/${this.normalizeAccountId()}/adcreatives`,
        primaryPayload,
        'Creando Creative',
        'Verifica que la pagina, Instagram Business y WhatsApp Phone Number ID esten conectados al mismo Business Manager.',
      );
    } catch (error) {
      if (!(error instanceof MetaAdsException)) throw error;
      const fallbackPayload = this.replaceCreativeCtaType(creativePayload, 'SEND_MESSAGE');
      return this.postForm(
        `/${this.normalizeAccountId()}/adcreatives`,
        this.stringifyPayload(fallbackPayload),
        'Creando Creative con CTA SEND_MESSAGE',
        'Meta rechazo WHATSAPP_MESSAGE. Se intento SEND_MESSAGE como CTA permitido para mensajeria.',
      );
    }
  }

  private replaceCreativeCtaType(payload: Record<string, unknown>, ctaType: 'WHATSAPP_MESSAGE' | 'SEND_MESSAGE') {
    const next = { ...payload };
    const rawSpec = `${next.object_story_spec ?? '{}'}`;
    const spec = JSON.parse(rawSpec) as Record<string, unknown>;
    for (const key of ['link_data', 'video_data']) {
      const data = spec[key] as Record<string, unknown> | undefined;
      const cta = data?.call_to_action as Record<string, unknown> | undefined;
      if (cta) cta.type = ctaType;
    }
    next.object_story_spec = JSON.stringify(spec);
    return next;
  }

  private stringifyPayload(payload: Record<string, unknown>) {
    const output: Record<string, string> = {};
    for (const [key, value] of Object.entries(payload)) {
      output[key] = typeof value === 'string' ? value : JSON.stringify(value);
    }
    return output;
  }

  private detectMediaType(input: CreateFlowInput): MetaAdMediaType {
    const value = [input.mediaMimeType ?? '', input.mediaFileName ?? '', input.mediaUrl ?? '']
      .join(' ')
      .toLowerCase();
    return value.includes('video') || /\.(mp4|mov|m4v|webm)(\?|$)/i.test(value) ? 'VIDEO' : 'IMAGE';
  }

  private prepareCreativeMedia(input: CreateFlowInput): PreparedCreativeMedia {
    const mediaUrl = `${input.mediaUrl ?? ''}`.trim();
    if (!mediaUrl) {
      throw new ServiceUnavailableException('No hay imagen o video seleccionado para subir a Meta Ads.');
    }

    const mediaType = this.detectMediaType(input);
    if (mediaType === 'VIDEO') {
      return { mediaType, imageHash: null, videoId: null, mediaUrl, mode: 'DIRECT_VIDEO_URL' };
    }

    return { mediaType, imageHash: null, videoId: null, mediaUrl, mode: 'DIRECT_PICTURE_URL' };
  }

  private async uploadImageHashToAdAccount(input: CreateFlowInput): Promise<PreparedCreativeMedia> {
    const prepared = await this.downloadAndPrepareAdImage(input);
    const response = await this.postMultipart(
      `/${this.normalizeAccountId()}/adimages`,
      {
        name: input.mediaFileName || prepared.fileName,
        filename: {
          buffer: prepared.buffer,
          fileName: prepared.fileName,
          mimeType: prepared.mimeType,
        },
      },
      'Subiendo imagen',
      'La imagen se descarga desde backend, se normaliza a JPEG/PNG valido y se sube como Ad Image al Ad Account.',
    );
    const images = response.images && typeof response.images === 'object'
      ? response.images as Record<string, Record<string, unknown>>
      : {};
    const firstImage = Object.values(images)[0] ?? {};
    const imageHash = `${firstImage.hash ?? response.hash ?? ''}`.trim();
    if (!imageHash) {
      throw new ServiceUnavailableException('Meta no devolvió image_hash al subir la imagen.');
    }
    return {
      mediaType: 'IMAGE',
      imageHash,
      videoId: null,
      mediaUrl: `${input.mediaUrl ?? ''}`.trim(),
      mode: 'UPLOADED_IMAGE_HASH',
    };
  }

  private shouldFallbackToImageHash(error: MetaAdsException) {
    const normalized = `${error.metaDetails.message ?? ''}`.toLowerCase();
    return [
      'image_hash',
      'picture',
      'image url',
      'invalid image',
      'object_story_spec',
      'link_data',
    ].some((fragment) => normalized.includes(fragment));
  }

  private async downloadAndPrepareAdImage(input: CreateFlowInput): Promise<PreparedAdImage> {
    const mediaUrl = `${input.mediaUrl ?? ''}`.trim();
    const response = await fetch(mediaUrl, {
      method: 'GET',
      headers: { Accept: 'image/jpeg,image/png,image/webp,image/*;q=0.8,*/*;q=0.5' },
    }).catch(() => null);

    if (!response || !response.ok) {
      throw new MetaAdsException({
        stage: 'Subiendo imagen',
        message: `No se pudo descargar la imagen seleccionada desde backend: ${mediaUrl}`,
        recommendation: 'Verifica que la URL sea HTTPS publica, responda 200 y no requiera autenticacion.',
      });
    }

    const contentType = `${response.headers.get('content-type') ?? ''}`.toLowerCase();
    if (!contentType.includes('image/')) {
      throw new MetaAdsException({
        stage: 'Subiendo imagen',
        message: `La URL seleccionada no devolvio una imagen valida. content-type=${contentType || 'desconocido'}`,
        recommendation: 'Selecciona una imagen publica JPEG o PNG desde la galeria de campanas.',
      });
    }

    const rawBuffer = Buffer.from(await response.arrayBuffer());
    if (rawBuffer.length <= 0) {
      throw new MetaAdsException({
        stage: 'Subiendo imagen',
        message: 'La imagen descargada esta vacia.',
        recommendation: 'Vuelve a publicar el diseño o selecciona otra imagen de la galeria.',
      });
    }
    if (rawBuffer.length > 30 * 1024 * 1024) {
      throw new MetaAdsException({
        stage: 'Subiendo imagen',
        message: `La imagen pesa demasiado para subirla a Meta Ads (${Math.round(rawBuffer.length / 1024 / 1024)} MB).`,
        recommendation: 'Usa una imagen menor de 30 MB o vuelve a exportarla desde el modulo de publicidad.',
      });
    }

    let metadata: sharp.Metadata;
    try {
      metadata = await sharp(rawBuffer).metadata();
    } catch {
      throw new MetaAdsException({
        stage: 'Subiendo imagen',
        message: 'La imagen descargada no pudo ser leida como JPEG/PNG valido.',
        recommendation: 'Selecciona otra imagen o regenera el diseño antes de publicar la campana.',
      });
    }

    const width = metadata.width ?? 0;
    const height = metadata.height ?? 0;
    if (width < 100 || height < 100) {
      throw new MetaAdsException({
        stage: 'Subiendo imagen',
        message: `La imagen tiene dimensiones invalidas para Meta Ads (${width}x${height}).`,
        recommendation: 'Usa una imagen de al menos 1080x1080 o vuelve a generar el diseno.',
      });
    }

    const isAlreadyJpegOrPng = metadata.format === 'jpeg' || metadata.format === 'png';
    const shouldNormalize = !isAlreadyJpegOrPng || width > 1080 || height > 1350 || metadata.space !== 'srgb';
    const normalizedBuffer = shouldNormalize
      ? await sharp(rawBuffer)
          .rotate()
          .resize({ width: 1080, height: 1350, fit: 'inside', withoutEnlargement: false })
          .flatten({ background: '#ffffff' })
          .toColorspace('srgb')
          .jpeg({ quality: 88, mozjpeg: true })
          .toBuffer()
      : rawBuffer;

    const finalMetadata = await sharp(normalizedBuffer).metadata();
    return {
      buffer: normalizedBuffer,
      fileName: this.normalizeAdImageFileName(input.mediaFileName),
      mimeType: 'image/jpeg',
      width: finalMetadata.width ?? width,
      height: finalMetadata.height ?? height,
      sizeBytes: normalizedBuffer.length,
      normalized: shouldNormalize,
    };
  }

  private normalizeAdImageFileName(raw?: string | null) {
    const clean = `${raw ?? ''}`.trim().replace(/[^a-zA-Z0-9._-]/g, '-');
    const base = clean.replace(/\.(jpeg|jpg|png|webp)$/i, '') || 'fulltech-campaign-image';
    return `${base}.jpg`;
  }

  private async validateAccessToken() {
    if (this.appId && this.appSecret) {
      const inspected = await this.inspectToken();
      if (!inspected.tokenValid) {
        throw new ServiceUnavailableException('El token Meta configurado no es válido.');
      }
      if (!inspected.scopes.includes('ads_management')) {
        throw new MetaAdsException({
          stage: 'Validando token Meta',
          message: 'El token Meta no tiene el permiso ads_management.',
          recommendation: 'Genera un token con ads_management para poder crear Campaign, AdSet, Creative y Ad.',
        });
      }
      return;
    }

    const query = new URLSearchParams({
      fields: 'id,name',
      access_token: this.accessToken,
    });
    const response = await fetch(`${this.graphUrl('/me')}?${query.toString()}`);
    if (!response.ok) {
      const payload = (await response.json().catch(() => ({}))) as Record<string, unknown>;
      throw new MetaAdsException(this.extractMetaError(payload, 'Validando token Meta', 'Verifica META_ADS_ACCESS_TOKEN (o fallback META_ACCESS_TOKEN) y permisos ads_management.'));
    }
  }

  private async validateAdAccount() {
    const report = await this.inspectMetaAdsPermissions();
    if (!report.adAccountAccessible) {
      throw new MetaAdsException({
        stage: 'Validando cuenta publicitaria',
        message: 'No se pudo acceder a la cuenta publicitaria de Meta Ads.',
        recommendation: 'Verifica META_AD_ACCOUNT_ID, el system user asignado y que la app tenga acceso aprobado al Ad Account.',
      });
    }
    if (!report.hasAdsManagement) {
      throw new MetaAdsException({
        stage: 'Validando cuenta publicitaria',
        message: 'El token Meta no tiene el permiso ads_management real sobre esta cuenta publicitaria.',
        recommendation: 'Usa un token de system user con ads_management y acceso real al Ad Account.',
      });
    }
  }

  private async validateFacebookPage() {
    const query = new URLSearchParams({
      fields: 'id,name,instagram_business_account{id,username}',
      access_token: this.accessToken,
    });
    const response = await fetch(`${this.graphUrl(`/${this.pageId}`)}?${query.toString()}`);
    const payload = (await response.json().catch(() => ({}))) as Record<string, unknown>;
    if (!response.ok) {
      throw new MetaAdsException(this.extractMetaError(payload, 'Validando pagina Facebook', 'Verifica META_FACEBOOK_PAGE_ID y permisos pages_read_engagement/pages_show_list.'));
    }
  }

  private async validateInstagramBusiness() {
    const query = new URLSearchParams({
      fields: 'id,username',
      access_token: this.accessToken,
    });
    const response = await fetch(`${this.graphUrl(`/${this.igBusinessId}`)}?${query.toString()}`);
    const payload = (await response.json().catch(() => ({}))) as Record<string, unknown>;
    if (!response.ok) {
      throw new MetaAdsException(this.extractMetaError(payload, 'Validando Instagram Business', 'Verifica META_INSTAGRAM_BUSINESS_ID y que este conectado a la pagina.'));
    }
  }

  private async validateWhatsappPhoneNumberFlexible(): Promise<{
    validated: boolean;
    warningMessage: string | null;
  }> {
    const query = new URLSearchParams({
      fields: 'id,display_phone_number,verified_name',
      access_token: this.accessToken,
    });
    const response = await fetch(`${this.graphUrl(`/${this.whatsappPhoneNumberId}`)}?${query.toString()}`);
    const payload = (await response.json().catch(() => ({}))) as Record<string, unknown>;
    if (response.ok) {
      return { validated: true, warningMessage: null };
    }

    const details = this.extractMetaError(
      payload,
      'Validando WhatsApp Phone Number ID',
      'Verifica que META_WHATSAPP_PHONE_NUMBER_ID este autorizado para esta cuenta publicitaria y Business Manager.',
    );

    const canBypassValidation =
      details.code === '10' &&
      this.whatsappPhoneNumberId.length > 0 &&
      this.pageId.length > 0 &&
      this.normalizeAccountId().length > 0 &&
      this.accessToken.length > 0;

    if (canBypassValidation) {
      const warningMessage =
        'No se pudo validar el WhatsApp Phone Number ID por permisos, pero se continuara usando el ID configurado.';
      this.logger.warn(
        `[meta-ads] whatsapp-validation-warning code=10 phoneId=${this.whatsappPhoneNumberId} message=${details.message}`,
      );
      return { validated: false, warningMessage };
    }

    throw new MetaAdsException(details);
  }

  async debugMetaWhatsapp(): Promise<MetaWhatsappDebugReport> {
    const token = await this.inspectTokenDetails().catch(() => ({
      tokenValid: false,
      scopes: [] as string[],
      tokenType: null as string | null,
    }));

    const hasMetaAccessToken = this.accessToken.length > 0;
    const hasAdAccountId = this.normalizeAccountId().length > 0;
    const hasFacebookPageId = this.pageId.length > 0;
    const hasInstagramBusinessId = this.igBusinessId.length > 0;
    const hasWhatsappPhoneNumberId = this.whatsappPhoneNumberId.length > 0;
    const hasWhatsappBusinessAccountId = this.whatsappBusinessAccountId.length > 0;

    const probePhone = await this.probeMetaEntity(
      hasWhatsappPhoneNumberId ? this.whatsappPhoneNumberId : '',
      'id,display_phone_number,verified_name,quality_rating',
      'No se pudo validar WhatsApp Phone Number ID',
    );

    const probeWaba = await this.probeMetaEntity(
      hasWhatsappBusinessAccountId ? this.whatsappBusinessAccountId : '',
      'id,name,account_review_status',
      'No se pudo validar WhatsApp Business Account ID',
    );

    return {
      hasMetaAccessToken,
      hasAdAccountId,
      hasFacebookPageId,
      hasInstagramBusinessId,
      hasWhatsappPhoneNumberId,
      hasWhatsappBusinessAccountId,
      whatsappPhoneNumberId: this.whatsappPhoneNumberId,
      whatsappBusinessAccountId: this.whatsappBusinessAccountId,
      businessId: this.businessId,
      tokenValid: token.tokenValid,
      tokenType: token.tokenType,
      scopes: token.scopes,
      phoneNumberProbe: probePhone,
      whatsappBusinessProbe: probeWaba,
    };
  }

  private async probeMetaEntity(
    entityId: string,
    fields: string,
    emptyMessage: string,
  ): Promise<{
    ok: boolean;
    message: string;
    code: string | null;
    subcode: string | null;
    fbtraceId: string | null;
  }> {
    if (!entityId.trim()) {
      return {
        ok: false,
        message: 'No configurado.',
        code: null,
        subcode: null,
        fbtraceId: null,
      };
    }

    if (!this.accessToken.trim()) {
      return {
        ok: false,
        message: 'META_ADS_ACCESS_TOKEN no configurado (ni fallback META_ACCESS_TOKEN).',
        code: null,
        subcode: null,
        fbtraceId: null,
      };
    }

    const query = new URLSearchParams({
      fields,
      access_token: this.accessToken,
    });
    const response = await fetch(`${this.graphUrl(`/${entityId}`)}?${query.toString()}`);
    const payload = (await response.json().catch(() => ({}))) as Record<string, unknown>;
    if (response.ok) {
      return {
        ok: true,
        message: 'OK',
        code: null,
        subcode: null,
        fbtraceId: null,
      };
    }

    const details = this.extractMetaError(payload, emptyMessage, null);
    return {
      ok: false,
      message: details.message,
      code: details.code ?? null,
      subcode: details.subcode ?? null,
      fbtraceId: details.fbtraceId ?? null,
    };
  }

  private async validatePublicMediaUrl(mediaUrl: string) {
    const cleanUrl = `${mediaUrl ?? ''}`.trim();
    if (!cleanUrl.startsWith('https://')) {
      throw new MetaAdsException({
        stage: 'Validando media publica HTTPS',
        message: 'La imagen o video debe tener una URL publica HTTPS antes de subirla a Meta Ads.',
        recommendation: 'Publica el archivo en storage publico HTTPS o configura PUBLIC_BASE_URL/R2 publico.',
      });
    }

    try {
      new URL(cleanUrl);
    } catch {
      throw new MetaAdsException({
        stage: 'Validando media publica HTTPS',
        message: `La URL de media no es valida: ${cleanUrl}`,
        recommendation: 'Selecciona una imagen publicada con URL HTTPS valida.',
      });
    }
  }

  private async validateAdImageUploadPermissions() {
    const report = await this.inspectMetaAdsPermissions();
    if (report.canUploadAdImage) return;

    throw new MetaAdsException({
      stage: 'Subiendo imagen',
      message: 'No se pudo subir la imagen al Ad Account. El token/app no tiene permiso ads_management real sobre esta cuenta publicitaria o la app no tiene acceso aprobado para esta operación.',
      code: '200',
      subcode: '1815066',
      fbtraceId: null,
      recommendation: report.recommendedFixes[0] ?? 'Verifica permisos de Meta Ads sobre el Ad Account.',
    });
  }

  private async validateImageUploadPreflight() {
    const report = await this.inspectMetaAdsPermissions();
    if (report.canUploadAdImage) return;

    throw new MetaAdsException({
      stage: 'Subiendo imagen',
      message:
        'No se pudo subir la imagen al Ad Account. El token/app no tiene permiso ads_management real sobre esta cuenta publicitaria o la app no tiene acceso aprobado para esta operación.',
      code: '200',
      subcode: '1815066',
      fbtraceId: null,
      recommendation: report.recommendedFixes[0] ?? null,
    });
  }

  private async emitStep(
    input: CreateFlowInput,
    id: MetaPublishStepId,
    label: string,
    status: MetaPublishStepStatus,
    detail?: string | null,
  ) {
    await input.onStep?.({
      id,
      label,
      status,
      detail: detail ?? null,
      at: new Date().toISOString(),
    });
  }

  private async inspectToken() {
    if (!this.accessToken || !this.appId || !this.appSecret) {
      return { tokenValid: false, scopes: [] as string[] };
    }

    const appToken = `${this.appId}|${this.appSecret}`;
    const query = new URLSearchParams({
      input_token: this.accessToken,
      access_token: appToken,
    });

    const response = await fetch(`${this.graphUrl('/debug_token')}?${query.toString()}`);
    const payload = await response.json();
    if (!response.ok) {
      return { tokenValid: false, scopes: [] as string[] };
    }

    const data = payload?.data ?? {};
    const scopes = Array.isArray(data.scopes)
      ? data.scopes.map((item: unknown) => `${item}`)
      : [];

    return {
      tokenValid: data.is_valid === true,
      scopes,
    };
  }

  private async inspectMetaAdsPermissions(accountIdOverride?: string): Promise<MetaAdsPermissionsDebugReport> {
    this.logMetaAdsContext('inspect-permissions');

    const tokenInspection = await this.inspectTokenDetails();
    const accountId = this.normalizeProvidedAccountId(accountIdOverride || this.normalizeAccountId());

    const adAccount = accountId
      ? await this.fetchGraphObject<Record<string, unknown>>(
          accountId,
          'id,name,account_status,disable_reason,currency,business,capabilities',
          this.accessToken,
        )
      : null;

    const assignedUsers = accountId
      ? await this.fetchGraphObject<{ data?: Array<Record<string, unknown>> }>(
          `${accountId}/assigned_users`,
          'id,name,role',
          this.accessToken,
          { limit: '1' },
        )
      : null;

    const adImages = accountId
      ? await this.fetchGraphObject<Record<string, unknown>>(
          `${accountId}/adimages`,
          'id,hash',
          this.accessToken,
          { limit: '1' },
        )
      : null;

    const pageAccessible = this.pageId
      ? await this.fetchGraphObject<Record<string, unknown>>(
          this.pageId,
          'id,name,instagram_business_account{id,username}',
          this.accessToken,
        ).then(() => true)
      : false;

    const instagramAccessible = this.igBusinessId
      ? await this.fetchGraphObject<Record<string, unknown>>(
          this.igBusinessId,
          'id,username',
          this.accessToken,
        ).then(() => true)
      : false;

    const whatsappPhoneAccessible = this.whatsappPhoneNumberId
      ? await this.fetchGraphObject<Record<string, unknown>>(
          this.whatsappPhoneNumberId,
          'id,display_phone_number,verified_name',
          this.accessToken,
        ).then(() => true)
      : false;

    const scopes = tokenInspection.scopes;
    const hasAdsManagement = scopes.includes('ads_management');
    const hasAdsRead = scopes.includes('ads_read');
    const hasBusinessManagement = scopes.includes('business_management');
    const hasPagesManageAds = scopes.includes('pages_manage_ads');
    const hasPagesManagePosts = scopes.includes('pages_manage_posts');
    const adAccountAccessible = adAccount !== null;
    const canReadAdImages = adImages !== null;
    const assignedUsersAccessible = assignedUsers !== null;
    const assignedUsersCount = Array.isArray(assignedUsers?.data) ? assignedUsers.data.length : null;
    const capabilities = Array.isArray(adAccount?.capabilities)
      ? adAccount.capabilities.map((item) => `${item}`.trim()).filter((item) => item.length > 0)
      : [];

    const recommendedFixes = this.buildPermissionRecommendations({
      tokenValid: tokenInspection.tokenValid,
      tokenType: tokenInspection.tokenType,
      hasAdsManagement,
      hasAdsRead,
      hasBusinessManagement,
      hasPagesManageAds,
      hasPagesManagePosts,
      adAccountAccessible,
      adAccountStatus: this.asNumber(adAccount?.account_status),
      adAccountDisableReason: this.asString(adAccount?.disable_reason),
      canReadAdImages,
      assignedUsersAccessible,
      pageAccessible,
      instagramAccessible,
      whatsappPhoneAccessible,
      accountId,
      scopes,
      capabilities,
    });

    return {
      tokenValid: tokenInspection.tokenValid,
      appId: this.appId,
      tokenPreview: this.tokenPreview(this.accessToken),
      adAccountId: accountId,
      adAccountAccessible,
      adAccountStatus: this.asNumber(adAccount?.account_status),
      adAccountDisableReason: this.asString(adAccount?.disable_reason),
      hasAdsManagement,
      hasAdsRead,
      hasBusinessManagement,
      canReadAdImages,
      canUploadAdImage:
        tokenInspection.tokenValid &&
        hasAdsManagement &&
        adAccountAccessible &&
        assignedUsersAccessible &&
        canReadAdImages,
      canCreateCampaign:
        tokenInspection.tokenValid &&
        hasAdsManagement &&
        adAccountAccessible,
      canCreateAdset:
        tokenInspection.tokenValid &&
        hasAdsManagement &&
        adAccountAccessible &&
        pageAccessible,
      canCreateCreative:
        tokenInspection.tokenValid &&
        hasAdsManagement &&
        adAccountAccessible &&
        pageAccessible &&
        instagramAccessible,
      assignedUsersAccessible,
      assignedUsersCount,
      pageAccessible,
      instagramAccessible,
      whatsappPhoneAccessible,
      recommendedFixes,
    };
  }

  private async fetchGraphObject<T>(
    path: string,
    fields: string,
    accessToken: string,
    extraParams?: Record<string, string>,
  ): Promise<T | null> {
    const query = new URLSearchParams({
      fields,
      access_token: accessToken,
      ...(extraParams ?? {}),
    });

    const response = await fetch(`${this.graphUrl(`/${path}`)}?${query.toString()}`);
    if (!response.ok) {
      return null;
    }

    return (await response.json().catch(() => ({}))) as T;
  }

  private async inspectTokenDetails() {
    if (!this.accessToken || !this.appId || !this.appSecret) {
      return { tokenValid: false, scopes: [] as string[], tokenType: null as string | null };
    }

    const appToken = `${this.appId}|${this.appSecret}`;
    const query = new URLSearchParams({
      input_token: this.accessToken,
      access_token: appToken,
    });

    const response = await fetch(`${this.graphUrl('/debug_token')}?${query.toString()}`);
    const payload = (await response.json().catch(() => ({}))) as Record<string, unknown>;
    if (!response.ok) {
      return { tokenValid: false, scopes: [] as string[], tokenType: null as string | null };
    }

    const data = (payload?.data ?? {}) as Record<string, unknown>;
    const scopes = Array.isArray(data.scopes)
      ? data.scopes.map((item: unknown) => `${item}`.trim()).filter((item: string) => item.length > 0)
      : [];

    return {
      tokenValid: data.is_valid === true,
      scopes,
      tokenType: `${data.type ?? ''}`.trim() || null,
    };
  }

  private logMetaAdsContext(context: string) {
    this.logger.log(
      `[meta-ads] ${context} tokenPreview=${this.tokenPreview(this.accessToken)} adAccountId=${this.normalizeAccountId() || 'missing'} appId=${this.appId || 'missing'} pageId=${this.pageId || 'missing'}`,
    );
  }

  private normalizeProvidedAccountId(raw: string) {
    const clean = `${raw ?? ''}`.trim();
    if (!clean) return '';
    return clean.startsWith('act_') ? clean : `act_${clean}`;
  }

  private buildMetaAdAccountProbe(report: MetaAdsPermissionsDebugReport): MetaAdAccountDebugProbe {
    return {
      adAccountId: report.adAccountId,
      canCreateCampaign: report.tokenValid && report.hasAdsManagement && report.adAccountAccessible,
      canCreateAdset:
        report.tokenValid &&
        report.hasAdsManagement &&
        report.adAccountAccessible &&
        report.pageAccessible,
      canCreateCreative:
        report.tokenValid &&
        report.hasAdsManagement &&
        report.adAccountAccessible &&
        report.pageAccessible &&
        report.instagramAccessible,
      canUploadImage: report.canUploadAdImage,
      campaignError: this.resolveDebugAccountError('campaign', report),
      adsetError: this.resolveDebugAccountError('adset', report),
      creativeError: this.resolveDebugAccountError('creative', report),
      uploadImageError: this.resolveDebugAccountError('upload', report),
      recommendedFixes: report.recommendedFixes,
    };
  }

  private resolveDebugAccountError(
    stage: 'campaign' | 'adset' | 'creative' | 'upload',
    report: MetaAdsPermissionsDebugReport,
  ) {
    if (!report.tokenValid) return 'META_ADS_ACCESS_TOKEN inválido o no corresponde a la app actual (ni fallback META_ACCESS_TOKEN).';
    if (!report.adAccountAccessible) return `No hay acceso al Ad Account ${report.adAccountId}.`;
    if (!report.hasAdsManagement) return 'Falta ads_management real sobre esta cuenta publicitaria.';
    if (stage === 'adset' && !report.pageAccessible) return 'La página configurada no es accesible con este token.';
    if (stage === 'creative' && !report.instagramAccessible) return 'El instagram_actor_id configurado no es accesible con este token.';
    if (stage === 'upload' && !report.canUploadAdImage) {
      return 'No se puede subir imagen por /adimages con este Ad Account; usa picture URL directa, video_url directo o cambia de cuenta.';
    }
    return null;
  }

  private buildPermissionRecommendations(input: {
    tokenValid: boolean;
    tokenType: string | null;
    hasAdsManagement: boolean;
    hasAdsRead: boolean;
    hasBusinessManagement: boolean;
    hasPagesManageAds: boolean;
    hasPagesManagePosts: boolean;
    adAccountAccessible: boolean;
    adAccountStatus: number | null;
    adAccountDisableReason: string | null;
    canReadAdImages: boolean;
    assignedUsersAccessible: boolean;
    pageAccessible: boolean;
    instagramAccessible: boolean;
    whatsappPhoneAccessible: boolean;
    accountId: string;
    scopes: string[];
    capabilities: string[];
  }) {
    const fixes = new Set<string>();

    if (!this.accessToken) fixes.add('Configura META_ADS_ACCESS_TOKEN (o fallback META_ACCESS_TOKEN) con un token de system user válido.');
    if (!input.tokenValid) fixes.add('Regenera el token y reinicia el backend si cambió recientemente.');
    if (input.tokenType && input.tokenType !== 'SYSTEM_USER') fixes.add(`El token no es de system user. type=${input.tokenType}.`);
    if (!input.hasAdsManagement) fixes.add('El token debe incluir ads_management real para el Ad Account.');
    if (!input.hasAdsRead) fixes.add('Agrega ads_read al token para poder diagnosticar y leer objetos de Ads.');
    if (!input.hasBusinessManagement) fixes.add('Agrega business_management si el acceso depende de Business Manager.');
    if (!input.hasPagesManageAds) fixes.add('Agrega pages_manage_ads si la app necesita operar sobre recursos de páginas vinculados a Ads.');
    if (!input.hasPagesManagePosts) fixes.add('Agrega pages_manage_posts si el flujo depende de publicación vinculada a páginas.');
    if (input.scopes.length === 0) fixes.add('No se pudieron leer scopes desde debug_token; valida que el token pertenezca a la app correcta.');
    if (!input.adAccountAccessible) fixes.add(`Verifica que META_AD_ACCOUNT_ID sea correcto y corresponda a la cuenta ${input.accountId || 'publicitaria'}.`);
    if (!input.assignedUsersAccessible) fixes.add('Confirma que el system user esté asignado al Ad Account con acceso total.');
    if (!input.canReadAdImages) fixes.add('El token no puede leer adimages; el acceso real a Ads no está resuelto todavía.');
    if (!input.pageAccessible) fixes.add('Verifica acceso a META_FACEBOOK_PAGE_ID con el mismo token.');
    if (!input.instagramAccessible) fixes.add('Verifica acceso a META_INSTAGRAM_BUSINESS_ID y que esté conectado a la página.');
    if (!input.whatsappPhoneAccessible) fixes.add('Verifica acceso a META_WHATSAPP_PHONE_NUMBER_ID en el mismo Business Manager.');
    if (input.adAccountStatus != null && input.adAccountStatus !== 1) {
      fixes.add(`La cuenta publicitaria no está activa. account_status=${input.adAccountStatus}.`);
    }
    if (input.adAccountDisableReason) {
      fixes.add(`La cuenta publicitaria tiene disable_reason=${input.adAccountDisableReason}.`);
    }
    if (input.capabilities.length === 0) {
      fixes.add('La cuenta no expone capabilities; revisa si la app tiene acceso aprobado a Marketing API.');
    }

    if (fixes.size === 0) {
      fixes.add('La configuración parece correcta para subir Ad Images. Si persiste 1815066, el token pertenece a otra app o Business Manager.');
    }

    return Array.from(fixes);
  }

  private asString(value: unknown) {
    const clean = `${value ?? ''}`.trim();
    return clean.length > 0 ? clean : null;
  }

  private asNumber(value: unknown) {
    const numeric = Number(value);
    return Number.isFinite(numeric) ? numeric : null;
  }

  private async checkAdAccountAccess() {
    const accountId = this.normalizeAccountId();
    if (!accountId || !this.accessToken) return false;

    const query = new URLSearchParams({
      fields: 'id,account_status,name',
      access_token: this.accessToken,
    });

    const response = await fetch(`${this.graphUrl(`/${accountId}`)}?${query.toString()}`);
    return response.ok;
  }

  private async updateEntityStatus(id: string, status: 'ACTIVE' | 'PAUSED') {
    if (!id.trim()) return;
    await this.postForm(`/${id}`, { status }, 'Actualizando estado Meta', 'Verifica que el objeto Meta exista y que el token tenga ads_management.');
  }

  private async postForm(
    path: string,
    payload: Record<string, string>,
    stage?: string,
    recommendation?: string,
  ): Promise<Record<string, unknown>> {
    const params = new URLSearchParams();
    for (const [key, value] of Object.entries(payload)) {
      params.set(key, value);
    }
    params.set('access_token', this.accessToken);

    const response = await fetch(this.graphUrl(path), {
      method: 'POST',
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: params.toString(),
    });

    const json = (await response.json().catch(() => ({}))) as Record<string, unknown>;
    if (response.ok) {
      return json;
    }

    const details = this.extractMetaError(json, stage, recommendation);
    throw new MetaAdsException(details);
  }

  private async postMultipart(
    path: string,
    payload: Record<string, string | { buffer: Buffer; fileName: string; mimeType: string }>,
    stage?: string,
    recommendation?: string,
  ): Promise<Record<string, unknown>> {
    const form = new FormData();
    for (const [key, value] of Object.entries(payload)) {
      if (typeof value === 'string') {
        form.set(key, value);
      } else {
        form.set(
          key,
          new Blob([new Uint8Array(value.buffer)], { type: value.mimeType }),
          value.fileName,
        );
      }
    }
    form.set('access_token', this.accessToken);

    const response = await fetch(this.graphUrl(path), {
      method: 'POST',
      body: form,
    });

    const json = (await response.json().catch(() => ({}))) as Record<string, unknown>;
    if (response.ok) {
      return json;
    }

    const details = this.extractMetaError(json, stage, recommendation);
    throw new MetaAdsException(details);
  }

  private extractMetaError(payload: Record<string, unknown>, stage?: string | null, recommendation?: string | null): MetaApiError {
    const errorRaw = (payload?.error ?? {}) as Record<string, unknown>;
    const code = errorRaw.code != null ? `${errorRaw.code}` : null;
    const subcode = errorRaw.error_subcode != null ? `${errorRaw.error_subcode}` : null;
    const isAdImagePermissionError = code === '200' && subcode === '1815066';
    return {
      stage: stage ?? null,
      message: isAdImagePermissionError
        ? 'No se pudo subir la imagen al Ad Account. El token/app no tiene permiso ads_management real sobre esta cuenta publicitaria o la app no tiene acceso aprobado para esta operación.'
        : `${errorRaw.message ?? 'Error al conectar con Meta Ads'}`,
      code,
      subcode,
      fbtraceId: errorRaw.fbtrace_id != null ? `${errorRaw.fbtrace_id}` : null,
      recommendation: isAdImagePermissionError
        ? 'Verifica que META_ADS_ACCESS_TOKEN (o fallback META_ACCESS_TOKEN) pertenezca a un system user con acceso real al Ad Account, que la app tenga Marketing API aprobada y que META_AD_ACCOUNT_ID sea la cuenta correcta. Si necesitas compatibilidad inmediata, usa video_url directo o cambia a un Ad Account con permisos de adimages.'
        : recommendation ?? null,
    };
  }
}
