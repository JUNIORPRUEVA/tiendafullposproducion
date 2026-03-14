export type NotificationChannel = 'WHATSAPP';

export type NotificationTemplateKey =
  | 'service_assigned'
  | 'service_status_changed';

export type ServiceAssignedPayload = {
  serviceId: string;
  serviceTitle: string;
  customerName: string;
  customerPhone?: string | null;
  address?: string | null;
  scheduledStart?: string | null;
  scheduledEnd?: string | null;
};

export type ServiceStatusChangedPayload = {
  serviceId: string;
  serviceTitle: string;
  oldStatus: string;
  newStatus: string;
  note?: string | null;
};

export type NotificationPayload =
  | { template: 'service_assigned'; data: ServiceAssignedPayload }
  | { template: 'service_status_changed'; data: ServiceStatusChangedPayload };
