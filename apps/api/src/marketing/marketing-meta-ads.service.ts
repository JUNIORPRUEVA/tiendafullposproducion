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
};

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
  startTime?: Date | null;
  endTime?: Date | null;
  targeting: Record<string, unknown>;
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
    if (!this.normalizeAccountId()) {
      throw new ServiceUnavailableException(
        'No se pudo crear la campaña porque falta META_AD_ACCOUNT_ID.',
      );
    }
    if (!this.accessToken) {
      throw new ServiceUnavailableException(
        'No se pudo crear la campaña porque falta META_ACCESS_TOKEN.',
      );
    }
    if (!this.pageId) {
      throw new ServiceUnavailableException(
        'No se pudo crear la campaña porque falta META_FACEBOOK_PAGE_ID.',
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

    const adsetPayload: Record<string, string> = {
      campaign_id: campaignId,
      name: `${input.name} - Ad Set`,
      billing_event: 'IMPRESSIONS',
      optimization_goal: 'LINK_CLICKS',
      bid_strategy: 'LOWEST_COST_WITHOUT_CAP',
      status: 'PAUSED',
      targeting: JSON.stringify(input.targeting),
      daily_budget: `${Math.max(1, Math.round(input.dailyBudget * 100))}`,
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

    const finalCta = this.resolveMetaCta(input.cta, input.whatsappPhone, input.destinationUrl);
    const link = this.resolveDestination(input.destinationUrl, input.whatsappPhone);

    const creativePayload = {
      name: `${input.name} - Creative`,
      object_story_spec: JSON.stringify({
        page_id: this.pageId,
        ...(this.igBusinessId ? { instagram_actor_id: this.igBusinessId } : {}),
        link_data: {
          link,
          message: input.primaryText,
          name: input.headline,
          description: input.description ?? '',
          call_to_action: {
            type: finalCta,
            value: { link },
          },
        },
      }),
    };

    const creative = await this.postForm(`/${this.normalizeAccountId()}/adcreatives`, creativePayload);
    const creativeId = `${creative.id ?? ''}`.trim();
    if (!creativeId) {
      throw new ServiceUnavailableException('Meta no devolvió creative_id al crear Creative.');
    }

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

    return { campaignId, adSetId, creativeId, adId };
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
    const suffix = details.fbtraceId ? ` fbtrace_id=${details.fbtraceId}` : '';
    throw new ServiceUnavailableException(
      `${details.message}${suffix}`,
    );
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
