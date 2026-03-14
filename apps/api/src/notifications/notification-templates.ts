import { NotificationPayload, NotificationTemplateKey } from './notification.types';

function nonEmpty(value: unknown): string {
  return typeof value === 'string' ? value.trim() : '';
}

function formatDateTime(iso?: string | null) {
  const v = nonEmpty(iso);
  if (!v) return '';
  const parsed = new Date(v);
  if (Number.isNaN(parsed.getTime())) return v;

  // Keep formatting simple and locale-independent.
  const pad = (n: number) => `${n}`.padStart(2, '0');
  return `${pad(parsed.getDate())}/${pad(parsed.getMonth() + 1)}/${parsed.getFullYear()} ${pad(parsed.getHours())}:${pad(parsed.getMinutes())}`;
}

export function buildNotificationMessage(payload: NotificationPayload): string {
  switch (payload.template) {
    case 'service_assigned': {
      const d = payload.data;
      const title = nonEmpty(d.serviceTitle) || 'Servicio';
      const customer = nonEmpty(d.customerName) || 'Cliente';
      const when = formatDateTime(d.scheduledStart);
      const phone = nonEmpty(d.customerPhone);
      const addr = nonEmpty(d.address);

      const parts: string[] = [];
      parts.push(`Nuevo servicio asignado: ${title}.`);
      parts.push(`Cliente: ${customer}.`);
      if (when) parts.push(`Agenda: ${when}.`);
      if (phone) parts.push(`Tel: ${phone}.`);
      if (addr) parts.push(`Dirección: ${addr}.`);
      parts.push(`ID: ${d.serviceId}.`);
      return parts.join(' ');
    }

    case 'service_status_changed': {
      const d = payload.data;
      const title = nonEmpty(d.serviceTitle) || 'Servicio';
      const oldS = nonEmpty(d.oldStatus) || 'N/D';
      const newS = nonEmpty(d.newStatus) || 'N/D';
      const note = nonEmpty(d.note);

      const parts: string[] = [];
      parts.push(`Actualización de servicio: ${title}.`);
      parts.push(`Estado: ${oldS} → ${newS}.`);
      if (note) parts.push(`Nota: ${note}.`);
      parts.push(`ID: ${d.serviceId}.`);
      return parts.join(' ');
    }
  }
}

export function isTemplateKey(value: string): value is NotificationTemplateKey {
  return value === 'service_assigned' || value === 'service_status_changed';
}
