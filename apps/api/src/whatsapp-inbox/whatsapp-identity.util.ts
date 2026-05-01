export interface NormalizedWhatsappIdentity {
  normalizedPhone: string | null;
  normalizedJid: string | null;
}

function normalizeString(value: unknown): string {
  return typeof value === 'string' ? value.trim() : '';
}

function normalizeJidDomain(domain: string): string {
  const lower = domain.trim().toLowerCase();
  if (!lower) return '';
  if (lower === 'c.us') return 's.whatsapp.net';
  return lower;
}

export function normalizeInstanceName(value: unknown): string {
  const raw = normalizeString(value).toLowerCase();
  if (!raw) return '';
  return raw.replace(/[^a-z0-9]/g, '');
}

export function normalizeWhatsappIdentity(input: unknown): NormalizedWhatsappIdentity {
  const raw = normalizeString(input);
  if (!raw) {
    return { normalizedPhone: null, normalizedJid: null };
  }

  const lowered = raw.toLowerCase();
  const atIndex = lowered.indexOf('@');
  const localPartRaw = atIndex >= 0 ? lowered.slice(0, atIndex) : lowered;
  const domainRaw = atIndex >= 0 ? lowered.slice(atIndex + 1) : '';

  // Some payloads include device/resource suffixes in local part: 1809xxxxxxx:12
  const localNoResource = localPartRaw.split(':')[0]?.trim() ?? '';
  const digits = localNoResource.replace(/\D/g, '');
  const normalizedPhone =
    digits.length >= 7 && digits.length <= 15 ? digits : null;

  const canonicalLocal = normalizedPhone ?? localNoResource.replace(/\s+/g, '');
  if (!canonicalLocal) {
    return { normalizedPhone, normalizedJid: null };
  }

  const domain = normalizeJidDomain(domainRaw);
  const canonicalDomain = normalizedPhone ? 's.whatsapp.net' : (domain || 's.whatsapp.net');
  const normalizedJid = `${canonicalLocal}@${canonicalDomain}`;

  return { normalizedPhone, normalizedJid };
}
