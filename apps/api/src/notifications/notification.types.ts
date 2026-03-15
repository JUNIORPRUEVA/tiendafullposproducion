export type NotificationChannel = 'WHATSAPP';

export type NotificationTemplateKey =
  | 'service_assigned'
  | 'service_status_changed'
  | 'service_closing_pending_approval'
  | 'service_closing_approved'
  | 'service_closing_rejected'
  | 'service_closing_ready_for_signature'
  | 'service_closing_sent_to_client';

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
  | { template: 'service_status_changed'; data: ServiceStatusChangedPayload }
  | {
      template: 'service_closing_pending_approval';
      data: {
        serviceId: string;
        serviceTitle: string;
        customerName: string;
      };
    }
  | {
      template: 'service_closing_approved';
      data: {
        serviceId: string;
        serviceTitle: string;
        approvedByName?: string | null;
      };
    }
  | {
      template: 'service_closing_rejected';
      data: {
        serviceId: string;
        serviceTitle: string;
        rejectedByName?: string | null;
        reason?: string | null;
      };
    }
  | {
      template: 'service_closing_ready_for_signature';
      data: {
        serviceId: string;
        serviceTitle: string;
      };
    }
  | {
      template: 'service_closing_sent_to_client';
      data: {
        serviceId: string;
        serviceTitle: string;
      };
    };
