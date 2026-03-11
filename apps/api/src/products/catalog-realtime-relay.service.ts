import crypto from 'node:crypto';
import http from 'node:http';
import { Injectable, Logger, OnModuleDestroy } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import jwt from 'jsonwebtoken';
import { Server } from 'socket.io';
import { io as createClient, Socket as ClientSocket } from 'socket.io-client';

import { normalizeJwtSecret } from '../auth/jwt.util';

const FULLTECH_ALLOWED_FULLPOS_COMPANY_ID = 2;

@Injectable()
export class CatalogRealtimeRelayService implements OnModuleDestroy {
  private readonly logger = new Logger(CatalogRealtimeRelayService.name);
  private readonly jwtSecret: string;
  private readonly fullposBaseUrl: string;
  private readonly fullposIntegrationToken: string;
  private io: Server | null = null;
  private upstream: ClientSocket | null = null;
  private started = false;

  constructor(private readonly config: ConfigService) {
    this.jwtSecret =
      normalizeJwtSecret(config.get<string>('JWT_SECRET')) ?? 'change-me';
    this.fullposBaseUrl = (
      config.get<string>('FULLPOS_INTEGRATION_BASE_URL') ?? ''
    )
      .trim()
      .replace(/\/$/, '');
    this.fullposIntegrationToken = (
      config.get<string>('FULLPOS_INTEGRATION_TOKEN') ?? ''
    ).trim();
  }

  attach(server: http.Server) {
    if (this.io) return;

    this.io = new Server(server, {
      cors: {
        origin: true,
        credentials: true,
      },
      transports: ['websocket', 'polling'],
    });

    this.io.use((socket, next) => {
      try {
        const token =
          (socket.handshake.auth?.token as string | undefined) ??
          (socket.handshake.headers.authorization as string | undefined)?.replace(
            /^Bearer\s+/i,
            '',
          );

        if (!token) {
          return next(new Error('No autorizado'));
        }

        jwt.verify(token, this.jwtSecret);
        return next();
      } catch {
        return next(new Error('No autorizado'));
      }
    });

    this.io.on('connection', (socket) => {
      socket.join('catalog');
    });
  }

  start() {
    if (this.started) return;
    this.started = true;

    if (!this.fullposBaseUrl || !this.fullposIntegrationToken) {
      this.logger.warn(
        'Realtime relay disabled: FULLPOS_INTEGRATION_BASE_URL or FULLPOS_INTEGRATION_TOKEN missing',
      );
      return;
    }

    const upstream = createClient(this.fullposBaseUrl, {
      transports: ['websocket'],
      autoConnect: false,
      reconnection: true,
      reconnectionAttempts: Infinity,
      reconnectionDelay: 1500,
      auth: {
        token: this.fullposIntegrationToken,
        expectedCompanyId: FULLTECH_ALLOWED_FULLPOS_COMPANY_ID,
      },
    });

    upstream.on('connect', () => {
      this.logger.log(
        `Catalog realtime relay connected to FULLPOS company ${FULLTECH_ALLOWED_FULLPOS_COMPANY_ID}`,
      );
    });

    upstream.on('connect_error', (error: Error) => {
      this.logger.warn(`Catalog realtime relay connect error: ${error.message}`);
    });

    upstream.on('disconnect', (reason: string) => {
      this.logger.warn(`Catalog realtime relay disconnected: ${reason}`);
    });

    upstream.on('product.event', (payload: unknown) => {
      if (!this.io) return;
      if (!payload || typeof payload !== 'object') return;

      this.io.to('catalog').emit('product.event', {
        eventId:
          (payload as { eventId?: unknown }).eventId?.toString() ??
          crypto.randomUUID(),
        type:
          (payload as { type?: unknown }).type?.toString() ?? 'product.updated',
        product: (payload as { product?: unknown }).product,
      });
    });

    upstream.connect();
    this.upstream = upstream;
  }

  onModuleDestroy() {
    this.upstream?.disconnect();
    this.upstream = null;
    this.io?.close();
    this.io = null;
  }
}