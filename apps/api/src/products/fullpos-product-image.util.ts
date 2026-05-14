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
  // Empty or null-like values → null
  if (!raw || raw.toLowerCase() === 'null' || raw.toLowerCase() === 'undefined') {
    return null;
  }

  // Already absolute URL (http/https) → return as-is
  if (/^https?:\/\//i.test(raw)) {
    return raw;
  }

  // Relative or partial path → try to build full URL from base
  const normalizedBase = trimTrailingSlash(fullposBaseUrl);
  if (!normalizedBase) {
    // No base URL configured, return raw path (will be handled client-side or by proxy)
    return raw.startsWith('/') ? raw : `/${raw}`;
  }

  const normalizedPath = normalizeSlashes(raw);
  if (!normalizedPath) {
    // Empty path after normalization
    return null;
  }

  // Build full URL
  if (normalizedPath.startsWith('/')) {
    return `${normalizedBase}${normalizedPath}`;
  }

  return `${normalizedBase}/${normalizedPath}`;
}
