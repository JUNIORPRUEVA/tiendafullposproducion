import { Injectable, Logger, OnModuleDestroy, OnModuleInit } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import Redis from 'ioredis';

@Injectable()
export class RedisService implements OnModuleInit, OnModuleDestroy {
  private readonly logger = new Logger(RedisService.name);
  private readonly enabled: boolean;
  private readonly redisUrl: string;
  private readonly prefix: string;
  private readonly defaultTtl: number;
  private client: Redis | null = null;
  private connectPromise: Promise<Redis | null> | null = null;

  constructor(private readonly config: ConfigService) {
    this.enabled = this.parseBoolean(this.config.get<string>('REDIS_ENABLED'));
    this.redisUrl = (this.config.get<string>('REDIS_URL') ?? '').trim();
    this.prefix = (this.config.get<string>('REDIS_PREFIX') ?? 'fulltech').trim() || 'fulltech';

    const ttlRaw = Number(this.config.get<string>('REDIS_TTL_DEFAULT') ?? '60');
    this.defaultTtl = Number.isFinite(ttlRaw) && ttlRaw > 0 ? Math.floor(ttlRaw) : 60;

    if (!this.enabled) {
      this.logger.log('Redis disabled via REDIS_ENABLED');
    }
  }

  isEnabled() {
    return this.enabled;
  }

  async onModuleInit() {
    if (!this.enabled) return;
    await this.getClient();
  }

  async get<T>(key: string): Promise<T | null> {
    try {
      const client = await this.getClient();
      if (!client) return null;

      const raw = await client.get(this.buildKey(key));
      if (raw == null) return null;

      return JSON.parse(raw) as T;
    } catch (error) {
      this.logError(`Redis GET failed for ${key}`, error);
      return null;
    }
  }

  async set(key: string, value: unknown, ttl?: number): Promise<boolean> {
    try {
      const client = await this.getClient();
      if (!client) return false;

      const effectiveTtl = Number.isFinite(ttl) && (ttl ?? 0) > 0
        ? Math.floor(ttl as number)
        : this.defaultTtl;
      const payload = JSON.stringify(value);

      if (effectiveTtl > 0) {
        await client.set(this.buildKey(key), payload, 'EX', effectiveTtl);
      } else {
        await client.set(this.buildKey(key), payload);
      }

      return true;
    } catch (error) {
      this.logError(`Redis SET failed for ${key}`, error);
      return false;
    }
  }

  async del(key: string): Promise<number> {
    try {
      const client = await this.getClient();
      if (!client) return 0;

      return await client.del(this.buildKey(key));
    } catch (error) {
      this.logError(`Redis DEL failed for ${key}`, error);
      return 0;
    }
  }

  async delByPattern(pattern: string): Promise<number> {
    try {
      const client = await this.getClient();
      if (!client) return 0;

      const namespacedPattern = this.buildKey(pattern);
      let cursor = '0';
      let deleted = 0;

      do {
        const [nextCursor, keys] = await client.scan(cursor, 'MATCH', namespacedPattern, 'COUNT', 100);
        cursor = nextCursor;

        if (keys.length > 0) {
          deleted += await client.del(...keys);
        }
      } while (cursor !== '0');

      return deleted;
    } catch (error) {
      this.logError(`Redis DEL PATTERN failed for ${pattern}`, error);
      return 0;
    }
  }

  async onModuleDestroy() {
    if (!this.client) return;

    try {
      await this.client.quit();
    } catch (error) {
      this.logError('Redis quit failed', error);
      this.client.disconnect();
    } finally {
      this.client = null;
      this.connectPromise = null;
    }
  }

  private parseBoolean(value?: string | null) {
    const normalized = (value ?? '').trim().toLowerCase();
    return normalized === '1' || normalized === 'true' || normalized === 'yes' || normalized === 'on';
  }

  private buildKey(key: string) {
    const normalized = (key ?? '').trim();
    return `${this.prefix}:${normalized}`;
  }

  private async getClient(): Promise<Redis | null> {
    if (!this.enabled) return null;

    if (!this.redisUrl) {
      this.logger.warn('Redis enabled but REDIS_URL is empty. Falling back to DB.');
      return null;
    }

    if (this.client && this.client.status !== 'end') {
      return this.client;
    }

    if (!this.connectPromise) {
      this.connectPromise = this.createClient();
    }

    return this.connectPromise;
  }

  private async createClient(): Promise<Redis | null> {
    const client = new Redis(this.redisUrl, {
      lazyConnect: true,
      maxRetriesPerRequest: 1,
      enableOfflineQueue: false,
    });

    client.on('connect', () => {
      this.logger.log('Redis connected');
    });

    client.on('ready', () => {
      this.logger.log('Redis ready');
    });

    client.on('reconnecting', () => {
      this.logger.warn('Redis reconnecting');
    });

    client.on('error', (error) => {
      this.logError('Redis client error', error);
    });

    client.on('end', () => {
      this.logger.warn('Redis connection closed');
      if (this.client === client) {
        this.client = null;
      }
    });

    try {
      await client.connect();
      this.client = client;
      return client;
    } catch (error) {
      this.logError('Redis connect failed. Falling back to DB.', error);
      client.disconnect();
      this.client = null;
      return null;
    } finally {
      this.connectPromise = null;
    }
  }

  private logError(message: string, error: unknown) {
    const detail = error instanceof Error ? error.message : String(error);
    this.logger.warn(`${message}: ${detail}`);
  }
}