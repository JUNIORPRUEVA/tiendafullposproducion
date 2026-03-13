export function normalizePhone(input: string): string {
  const raw = (input ?? '').trim();
  if (!raw) return '';

  // RD default normalization: keep digits only.
  const digitsOnly = raw.replace(/\D/g, '');
  if (!digitsOnly) return '';

  // If stored with country code +1 (11 digits), drop the leading 1.
  if (digitsOnly.length === 11 && digitsOnly.startsWith('1')) {
    return digitsOnly.slice(1);
  }

  return digitsOnly;
}

export function isLikelyPhoneSearch(input: string): boolean {
  const raw = (input ?? '').trim();
  if (!raw) return false;
  const digits = raw.replace(/\D/g, '');
  return digits.length >= 6;
}
