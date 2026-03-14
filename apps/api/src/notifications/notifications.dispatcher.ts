import { Injectable, OnModuleDestroy, OnModuleInit } from '@nestjs/common';
import { NotificationsService } from './notifications.service';

@Injectable()
export class NotificationsDispatcher implements OnModuleInit, OnModuleDestroy {
  constructor(private readonly notifications: NotificationsService) {}

  private timer: NodeJS.Timeout | null = null;
  private running = false;

  onModuleInit() {
    const enabled = (process.env.NOTIFICATIONS_ENABLED ?? '').trim().toLowerCase();
    if (enabled === '0' || enabled === 'false') return;

    this.timer = setInterval(() => {
      if (this.running) return;
      this.running = true;
      this.notifications
        .processOutboxBatch(25)
        .catch(() => {
          // best-effort
        })
        .finally(() => {
          this.running = false;
        });
    }, 8_000);

    // Don't keep the process alive just for this loop.
    this.timer.unref?.();
  }

  onModuleDestroy() {
    if (this.timer) {
      clearInterval(this.timer);
      this.timer = null;
    }
  }
}
