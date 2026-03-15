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

    case 'service_closing_pending_approval': {
      const d = payload.data;
      const title = nonEmpty(d.serviceTitle) || 'Servicio';
      const customer = nonEmpty(d.customerName) || 'Cliente';
      return `Cierre de servicio pendiente de aprobación: ${title}. Cliente: ${customer}. ID: ${d.serviceId}.`;
    }

    case 'service_closing_approved': {
      const d = payload.data;
      const title = nonEmpty(d.serviceTitle) || 'Servicio';
      const by = nonEmpty(d.approvedByName);
      return `Cierre aprobado: ${title}.${by ? ` Aprobado por: ${by}.` : ''} ID: ${d.serviceId}.`;
    }

    case 'service_closing_rejected': {
      const d = payload.data;
      const title = nonEmpty(d.serviceTitle) || 'Servicio';
      const by = nonEmpty(d.rejectedByName);
      const reason = nonEmpty(d.reason);
      const parts: string[] = [];
      parts.push(`Cierre rechazado: ${title}.`);
      if (by) parts.push(`Rechazado por: ${by}.`);
      if (reason) parts.push(`Motivo: ${reason}.`);
      parts.push(`ID: ${d.serviceId}.`);
      return parts.join(' ');
    }

    case 'service_closing_ready_for_signature': {
      const d = payload.data;
      const title = nonEmpty(d.serviceTitle) || 'Servicio';
      return `Documentos listos para firma del cliente: ${title}. ID: ${d.serviceId}.`;
    }

    case 'service_closing_sent_to_client': {
      const d = payload.data;
      const title = nonEmpty(d.serviceTitle) || 'Servicio';
      return `Documentos enviados al cliente: ${title}. ID: ${d.serviceId}.`;
    }
  }
}

export function isTemplateKey(value: string): value is NotificationTemplateKey {
  return (
    value === 'service_assigned' ||
    value === 'service_status_changed' ||
    value === 'service_closing_pending_approval' ||
    value === 'service_closing_approved' ||
    value === 'service_closing_rejected' ||
    value === 'service_closing_ready_for_signature' ||
    value === 'service_closing_sent_to_client'
  );
}
