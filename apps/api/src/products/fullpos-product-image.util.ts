function trimTrailingSlash(value: string): string {
  return value.trim().replace(/\/+$/, '');
}

function normalizeSlashes(value: string): string {
  return value.replace(/\\/g, '/').trim();
}

export function classifyFullposImageValue(value: string | null | undefined): 'empty' | 'absolute' | 'relative' {
  const raw = (value ?? '').trim();
  if (!raw) return 'empty';
  return /^https?:\/\//i.test(raw) ? 'absolute' : 'relative';
}

export function normalizeFullposCatalogImageUrl(
  value: string | null | undefined,
  fullposBaseUrl: string,
): string | null {
  const raw = (value ?? '').trim();
  if (!raw || raw.toLowerCase() === 'null' || raw.toLowerCase() === 'undefined') {
    return null;
  }

  if (/^https?:\/\//i.test(raw)) {
    return raw;
  }

  const normalizedBase = trimTrailingSlash(fullposBaseUrl);
  if (!normalizedBase) {
    return raw;
  }

  const normalizedPath = normalizeSlashes(raw);
  if (!normalizedPath) {
    return null;
  }

  if (normalizedPath.startsWith('/')) {
    return `${normalizedBase}${normalizedPath}`;
  }

  return `${normalizedBase}/${normalizedPath}`;
}
