import {
  Injectable,
  ServiceUnavailableException,
} from '@nestjs/common';

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
  | 'VALIDATING_PAGE'
  | 'VALIDATING_INSTAGRAM'
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
  message: string;
  code?: string | null;
  subcode?: string | null;
  fbtraceId?: string | null;
};

export class MetaAdsException extends ServiceUnavailableException {
  constructor(public readonly metaDetails: MetaAdsErrorDetails) {
    super(metaDetails.fbtraceId ? `${metaDetails.message} fbtrace_id=${metaDetails.fbtraceId}` : metaDetails.message);
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
  whatsappPhone?: string | null;
  mediaUrl: string;
  mediaMimeType?: string | null;
  mediaFileName?: string | null;
  startTime?: Date | null;
  endTime?: Date | null;
  targeting: Record<string, unknown>;
  onStep?: (step: MetaPublishStep) => Promise<void> | void;
};

type MetaApiError = {
  message: string;
  code?: string | null;
  subcode?: string | null;
  fbtraceId?: string | null;
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
    await this.validateAdAccount();
    await this.emitStep(input, 'VALIDATING_META', 'Validando token Meta', 'DONE');

    await this.emitStep(input, 'VALIDATING_PAGE', 'Validando pagina Facebook', 'RUNNING');
    await this.validateFacebookPage();
    await this.emitStep(input, 'VALIDATING_PAGE', 'Validando pagina Facebook', 'DONE');

    await this.emitStep(input, 'VALIDATING_INSTAGRAM', 'Validando Instagram Business', 'RUNNING');
    await this.validateInstagramBusiness();
    await this.emitStep(input, 'VALIDATING_INSTAGRAM', 'Validando Instagram Business', 'DONE');

    await this.emitStep(input, 'UPLOADING_MEDIA', 'Subiendo media', 'RUNNING');
    const media = await this.uploadCreativeMedia(input);
    await this.emitStep(input, 'UPLOADING_MEDIA', 'Subiendo media', 'DONE', media.mediaType === 'IMAGE' ? media.imageHash : media.videoId);

    await this.emitStep(input, 'CREATING_CAMPAIGN', 'Creando campana', 'RUNNING');
    const campaign = await this.postForm(`/${this.normalizeAccountId()}/campaigns`, {
      name: input.name,
      objective: input.objective,
      status: 'PAUSED',
      special_ad_categories: '[]',
    });

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

    const adset = await this.postForm(`/${this.normalizeAccountId()}/adsets`, adsetPayload);
    const adSetId = `${adset.id ?? ''}`.trim();
    if (!adSetId) {
      throw new ServiceUnavailableException('Meta no devolvió adset_id al crear Ad Set.');
    }
    await this.emitStep(input, 'CREATING_ADSET', 'Creando segmentacion', 'DONE', adSetId);

    const finalCta = this.resolveMetaCta(input.cta, input.whatsappPhone, input.destinationUrl);
    const link = this.resolveDestination(input.destinationUrl, input.whatsappPhone);

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
                  },
                },
              },
            }),
      }),
    };

    const creative = await this.postForm(`/${this.normalizeAccountId()}/adcreatives`, creativePayload);
    const creativeId = `${creative.id ?? ''}`.trim();
    if (!creativeId) {
      throw new ServiceUnavailableException('Meta no devolvió creative_id al crear Creative.');
    }
    await this.emitStep(input, 'CREATING_CREATIVE', 'Creando anuncio creativo', 'DONE', creativeId);

    await this.emitStep(input, 'CREATING_AD', 'Creando anuncio', 'RUNNING');
    const ad = await this.postForm(`/${this.normalizeAccountId()}/ads`, {
      name: `${input.name} - Ad`,
      adset_id: adSetId,
      creative: JSON.stringify({ creative_id: creativeId }),
      status: 'PAUSED',
    });
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

  private resolveMetaCta(rawCta: string, whatsappPhone?: string | null, destinationUrl?: string | null) {
    const normalized = (rawCta ?? '').trim().toUpperCase();
    if (normalized === 'WHATSAPP_MESSAGE' && whatsappPhone) return 'WHATSAPP_MESSAGE';
    if (normalized === 'MESSAGE_PAGE') return 'MESSAGE_PAGE';
    if (destinationUrl) return 'LEARN_MORE';
    return whatsappPhone ? 'WHATSAPP_MESSAGE' : 'LEARN_MORE';
  }

  private resolveDestination(destinationUrl?: string | null, whatsappPhone?: string | null) {
    const cleanUrl = `${destinationUrl ?? ''}`.trim();
    if (cleanUrl) return cleanUrl;
    const phone = `${whatsappPhone ?? ''}`.replace(/[^0-9]/g, '');
    if (!phone) return 'https://facebook.com';
    return `https://wa.me/${phone}`;
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
      });
      const videoId = `${response.id ?? ''}`.trim();
      if (!videoId) {
        throw new ServiceUnavailableException('Meta no devolvió video_id al subir el video.');
      }
      return { mediaType, imageHash: null, videoId, mediaUrl };
    }

    const response = await this.postForm(`/${this.normalizeAccountId()}/adimages`, {
      url: mediaUrl,
      name: input.mediaFileName || `${input.name} image`,
    });
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

  private async validateAccessToken() {
    if (this.appId && this.appSecret) {
      const inspected = await this.inspectToken();
      if (!inspected.tokenValid) {
        throw new ServiceUnavailableException('El token Meta configurado no es válido.');
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
      throw new MetaAdsException(this.extractMetaError(payload));
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
      throw new MetaAdsException(this.extractMetaError(payload));
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
      throw new MetaAdsException(this.extractMetaError(payload));
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
      throw new MetaAdsException(this.extractMetaError(payload));
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
    await this.postForm(`/${id}`, { status });
  }

  private async postForm(path: string, payload: Record<string, string>): Promise<Record<string, unknown>> {
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

    const details = this.extractMetaError(json);
    throw new MetaAdsException(details);
  }

  private extractMetaError(payload: Record<string, unknown>): MetaApiError {
    const errorRaw = (payload?.error ?? {}) as Record<string, unknown>;
    return {
      message: `${errorRaw.message ?? 'Error al conectar con Meta Ads'}`,
      code: errorRaw.code != null ? `${errorRaw.code}` : null,
      subcode: errorRaw.error_subcode != null ? `${errorRaw.error_subcode}` : null,
      fbtraceId: errorRaw.fbtrace_id != null ? `${errorRaw.fbtrace_id}` : null,
    };
  }
}
