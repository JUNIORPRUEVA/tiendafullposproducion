import {
  Injectable,
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

export class MetaAdsException extends ServiceUnavailableException {
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

@Injectable()
export class MarketingMetaAdsService {
  private get graphVersion() {
    return (process.env.META_GRAPH_VERSION ?? 'v23.0').trim() || 'v23.0';
  }

  private get appId() {
    return (process.env.META_APP_ID ?? '').trim();
  }

  private get appSecret() {
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

  private get accessToken() {
    return (process.env.META_ACCESS_TOKEN ?? '').trim();
  }

  private tokenPreview(token: string) {
    if (!token) return '';
    if (token.length <= 10) return `${token.substring(0, 2)}***`;
    return `${token.substring(0, 6)}...${token.substring(token.length - 4)}`;
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
        'No se pudo crear la campaña porque falta META_ACCESS_TOKEN.',
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

  async createCampaignFlow(input: CreateFlowInput): Promise<MetaAdsIds> {
    this.ensureAdsConfigured();

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
    await this.validateWhatsappPhoneNumber();
    await this.emitStep(input, 'VALIDATING_WHATSAPP', 'Validando WhatsApp FullTech', 'DONE', this.whatsappPhoneNumberId);

    await this.emitStep(input, 'VALIDATING_MEDIA', 'Validando media publica HTTPS', 'RUNNING');
    await this.validatePublicMediaUrl(input.mediaUrl);
    await this.emitStep(input, 'VALIDATING_MEDIA', 'Validando media publica HTTPS', 'DONE');

    await this.emitStep(input, 'UPLOADING_MEDIA', 'Subiendo media', 'RUNNING');
    const media = await this.uploadCreativeMedia(input);
    await this.emitStep(input, 'UPLOADING_MEDIA', 'Subiendo media', 'DONE', media.mediaType === 'IMAGE' ? media.imageHash : media.videoId);

    await this.emitStep(input, 'CREATING_CAMPAIGN', 'Creando campana', 'RUNNING');
    const campaign = await this.postForm(
      `/${this.normalizeAccountId()}/campaigns`,
      {
        name: input.name,
        objective: input.objective,
        status: 'PAUSED',
        special_ad_categories: '[]',
      },
      'Creando Campaign',
      'Verifica que OUTCOME_MESSAGES este disponible para la cuenta publicitaria y que el token tenga ads_management.',
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
      optimization_goal: 'CONVERSATIONS',
      destination_type: 'WHATSAPP',
      bid_strategy: 'LOWEST_COST_WITHOUT_CAP',
      status: 'PAUSED',
      targeting: JSON.stringify(input.targeting),
      daily_budget: `${Math.max(1, Math.round(input.dailyBudget * 100))}`,
      promoted_object: JSON.stringify({
        page_id: this.pageId,
        whatsapp_phone_number: this.whatsappPhoneNumberId,
      }),
      multi_advertiser_opt_out: '1',
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

    const creativePayload = {
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
                image_hash: media.imageHash,
                message: input.primaryText,
                name: input.headline,
                description: input.description ?? '',
                call_to_action: {
                  type: finalCta,
                  value: {
                    link,
                    app_destination: 'WHATSAPP',
                    whatsapp_phone_number: this.whatsappPhoneNumberId,
                  },
                },
              },
            }
          : {
              video_data: {
                video_id: media.videoId,
                message: input.primaryText,
                title: input.headline,
                link_description: input.description ?? '',
                call_to_action: {
                  type: finalCta,
                  value: {
                    link,
                    app_destination: 'WHATSAPP',
                    whatsapp_phone_number: this.whatsappPhoneNumberId,
                  },
                },
              },
            }),
      }),
    };

    const creative = await this.createCreativeWithCtaFallback(creativePayload);
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

  private async uploadCreativeMedia(input: CreateFlowInput) {
    const mediaUrl = `${input.mediaUrl ?? ''}`.trim();
    if (!mediaUrl) {
      throw new ServiceUnavailableException('No hay imagen o video seleccionado para subir a Meta Ads.');
    }

    const mediaType = this.detectMediaType(input);
    if (mediaType === 'VIDEO') {
      const response = await this.postForm(`/${this.normalizeAccountId()}/advideos`, {
        file_url: mediaUrl,
        name: input.mediaFileName || `${input.name} video`,
      }, 'Subiendo video', 'Verifica que el video sea publico, HTTPS y compatible con Meta Ads.');
      const videoId = `${response.id ?? ''}`.trim();
      if (!videoId) {
        throw new ServiceUnavailableException('Meta no devolvió video_id al subir el video.');
      }
      return { mediaType, imageHash: null, videoId, mediaUrl };
    }

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
    return { mediaType, imageHash, videoId: null, mediaUrl };
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
      throw new MetaAdsException(this.extractMetaError(payload, 'Validando token Meta', 'Verifica META_ACCESS_TOKEN y permisos ads_management.'));
    }
  }

  private async validateAdAccount() {
    const query = new URLSearchParams({
      fields: 'id,account_status,name',
      access_token: this.accessToken,
    });
    const response = await fetch(`${this.graphUrl(`/${this.normalizeAccountId()}`)}?${query.toString()}`);
    const payload = (await response.json().catch(() => ({}))) as Record<string, unknown>;
    if (!response.ok) {
      throw new MetaAdsException(this.extractMetaError(payload, 'Validando cuenta publicitaria', 'Verifica META_AD_ACCOUNT_ID y acceso del token a la cuenta publicitaria.'));
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

  private async validateWhatsappPhoneNumber() {
    const query = new URLSearchParams({
      fields: 'id,display_phone_number,verified_name',
      access_token: this.accessToken,
    });
    const response = await fetch(`${this.graphUrl(`/${this.whatsappPhoneNumberId}`)}?${query.toString()}`);
    const payload = (await response.json().catch(() => ({}))) as Record<string, unknown>;
    if (!response.ok) {
      throw new MetaAdsException(this.extractMetaError(
        payload,
        'Validando WhatsApp Phone Number ID',
        'Verifica que META_WHATSAPP_PHONE_NUMBER_ID este autorizado para esta cuenta publicitaria y Business Manager.',
      ));
    }
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
    return {
      stage: stage ?? null,
      message: `${errorRaw.message ?? 'Error al conectar con Meta Ads'}`,
      code: errorRaw.code != null ? `${errorRaw.code}` : null,
      subcode: errorRaw.error_subcode != null ? `${errorRaw.error_subcode}` : null,
      fbtraceId: errorRaw.fbtrace_id != null ? `${errorRaw.fbtrace_id}` : null,
      recommendation: recommendation ?? null,
    };
  }
}
