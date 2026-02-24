export function normalizeJwtSecret(value: string | undefined | null): string | undefined {
  const trimmed = (value ?? '').trim();
  if (!trimmed) return undefined;

  const isWrappedInDoubleQuotes = trimmed.startsWith('"') && trimmed.endsWith('"');
  const isWrappedInSingleQuotes = trimmed.startsWith("'") && trimmed.endsWith("'");
  const unwrapped = isWrappedInDoubleQuotes || isWrappedInSingleQuotes ? trimmed.slice(1, -1) : trimmed;

  const normalized = unwrapped.trim();
  return normalized.length > 0 ? normalized : undefined;
}

