import crypto from 'node:crypto';

import { Injectable } from '@nestjs/common';

import { CatalogRealtimeRelayService } from '../products/catalog-realtime-relay.service';

export type ServiceRealtimeEventType =
  | 'service.created'
  | 'service.updated'
  | 'service.status_changed'
  | 'service.assigned'
  | 'service.scheduled'
  | 'service.phase_changed'
  | 'service.admin_phase_changed'
  | 'service.admin_status_changed'
  | 'service.note_added'
  | 'service.execution_updated'
  | 'service.step_updated'
  | 'service.execution_report_updated'
  | 'service.execution_change_added'
  | 'service.execution_change_deleted';

@Injectable()
export class OperationsRealtimeService {
  constructor(private readonly relay: CatalogRealtimeRelayService) {}

  emitServiceEvent(params: {
    type: ServiceRealtimeEventType;
    service: unknown;
    actorUserId?: string;
  }) {
    const payload = {
      eventId: crypto.randomUUID(),
      type: params.type,
      happenedAt: new Date().toISOString(),
      actorUserId: (params.actorUserId ?? '').trim() || null,
      service: params.service,
    };

    // Broadcast to all authenticated clients. They will reconcile locally.
    this.relay.emitOps('service.event', payload);
  }
}
