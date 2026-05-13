import {
  BadRequestException,
  Injectable,
  InternalServerErrorException,
  NotFoundException,
} from '@nestjs/common';
import { MarketingSocialAccountType, Prisma } from '@prisma/client';
import { createCipheriv, createDecipheriv, createHash, randomBytes } from 'node:crypto';
import { PrismaService } from '../prisma/prisma.service';
import {
  CreateMarketingSocialAccountDto,
  MarketingSocialAccountsQueryDto,
  UpdateMarketingSocialAccountDto,
} from './dto/marketing-social-account.dto';

@Injectable()
export class MarketingSocialAccountsService {
  constructor(private readonly prisma: PrismaService) {}

  async list(companyId: string, query: MarketingSocialAccountsQueryDto) {
    const search = this.toNullableTrimmed(query.search);
    const activeOnly = query.activeOnly === true;

    const where: Prisma.MarketingSocialAccountWhereInput = {
      companyId,
      deletedAt: null,
      ...(query.type ? { type: query.type } : {}),
      ...(activeOnly ? { isActive: true } : {}),
      ...(search
        ? {
            OR: [
              { accountName: { contains: search, mode: 'insensitive' } },
              { username: { contains: search, mode: 'insensitive' } },
              { whatsappNumber: { contains: search, mode: 'insensitive' } },
              { profileLink: { contains: search, mode: 'insensitive' } },
              { observations: { contains: search, mode: 'insensitive' } },
            ],
          }
        : {}),
    };

    const rows = await this.prisma.marketingSocialAccount.findMany({
      where,
      orderBy: [{ isActive: 'desc' }, { updatedAt: 'desc' }, { createdAt: 'desc' }],
    });

    return {
      items: rows.map((row) => this.mapRow(row)),
      total: rows.length,
    };
  }

  async create(companyId: string, dto: CreateMarketingSocialAccountDto, actorUserId: string) {
    const accountName = this.requiredValue(dto.accountName, 'Debes indicar el nombre de la cuenta.');
    this.validateByType(dto.type, dto.username, dto.whatsappNumber);

    const username = this.toNullableTrimmed(dto.username);
    const whatsappNumber = this.normalizeWhatsappNumber(dto.whatsappNumber);
    const encryptedPassword = this.encryptSecret(this.toNullableTrimmed(dto.password));

    const created = await this.prisma.marketingSocialAccount.create({
      data: {
        companyId,
        type: dto.type,
        accountName,
        username,
        passwordEncrypted: encryptedPassword,
        profileLink: this.toNullableTrimmed(dto.profileLink),
        whatsappNumber,
        whatsappWaLink: this.buildWhatsappWaLink(whatsappNumber),
        observations: this.toNullableTrimmed(dto.observations),
        avatarUrl: this.toNullableTrimmed(dto.avatarUrl),
        isActive: dto.isActive ?? true,
        createdByUserId: actorUserId || null,
        updatedByUserId: actorUserId || null,
      },
    });

    await this.logActivity(companyId, actorUserId, 'MARKETING_SOCIAL_ACCOUNT_CREATED', {
      id: created.id,
      type: created.type,
      accountName: created.accountName,
    });

    return this.mapRow(created);
  }

  async update(
    companyId: string,
    id: string,
    dto: UpdateMarketingSocialAccountDto,
    actorUserId: string,
  ) {
    const existing = await this.prisma.marketingSocialAccount.findFirst({
      where: { id, companyId, deletedAt: null },
    });
    if (!existing) {
      throw new NotFoundException('No se encontró la cuenta empresarial solicitada.');
    }

    const nextType = dto.type ?? existing.type;
    const nextUsername = dto.username !== undefined ? this.toNullableTrimmed(dto.username) : existing.username;
    const nextWhatsappNumber =
      dto.whatsappNumber !== undefined
        ? this.normalizeWhatsappNumber(dto.whatsappNumber)
        : existing.whatsappNumber;

    this.validateByType(nextType, nextUsername, nextWhatsappNumber);

    const data: Prisma.MarketingSocialAccountUncheckedUpdateInput = {
      ...(dto.type !== undefined ? { type: dto.type } : {}),
      ...(dto.accountName !== undefined
        ? {
            accountName: this.requiredValue(
              dto.accountName,
              'Debes indicar el nombre de la cuenta.',
            ),
          }
        : {}),
      ...(dto.username !== undefined ? { username: nextUsername } : {}),
      ...(dto.password !== undefined
        ? { passwordEncrypted: this.encryptSecret(this.toNullableTrimmed(dto.password)) }
        : {}),
      ...(dto.profileLink !== undefined ? { profileLink: this.toNullableTrimmed(dto.profileLink) } : {}),
      ...(dto.whatsappNumber !== undefined
        ? {
            whatsappNumber: nextWhatsappNumber,
            whatsappWaLink: this.buildWhatsappWaLink(nextWhatsappNumber),
          }
        : {}),
      ...(dto.observations !== undefined ? { observations: this.toNullableTrimmed(dto.observations) } : {}),
      ...(dto.avatarUrl !== undefined ? { avatarUrl: this.toNullableTrimmed(dto.avatarUrl) } : {}),
      ...(dto.isActive !== undefined ? { isActive: dto.isActive } : {}),
      updatedByUserId: actorUserId || null,
      updatedAt: new Date(),
    };

    const updated = await this.prisma.marketingSocialAccount.update({
      where: { id: existing.id },
      data,
    });

    await this.logActivity(companyId, actorUserId, 'MARKETING_SOCIAL_ACCOUNT_UPDATED', {
      id: updated.id,
      type: updated.type,
      accountName: updated.accountName,
    });

    return this.mapRow(updated);
  }

  async remove(companyId: string, id: string, actorUserId: string) {
    const existing = await this.prisma.marketingSocialAccount.findFirst({
      where: { id, companyId, deletedAt: null },
    });
    if (!existing) {
      throw new NotFoundException('No se encontró la cuenta empresarial solicitada.');
    }

    await this.prisma.marketingSocialAccount.update({
      where: { id: existing.id },
      data: {
        deletedAt: new Date(),
        updatedByUserId: actorUserId || null,
        updatedAt: new Date(),
      },
    });

    await this.logActivity(companyId, actorUserId, 'MARKETING_SOCIAL_ACCOUNT_DELETED', {
      id: existing.id,
      type: existing.type,
      accountName: existing.accountName,
    });

    return { ok: true };
  }

  private mapRow(row: {
    id: string;
    type: MarketingSocialAccountType;
    accountName: string;
    username: string | null;
    passwordEncrypted: string | null;
    profileLink: string | null;
    whatsappNumber: string | null;
    whatsappWaLink: string | null;
    observations: string | null;
    avatarUrl: string | null;
    isActive: boolean;
    createdAt: Date;
    updatedAt: Date;
  }) {
    return {
      id: row.id,
      type: row.type,
      accountName: row.accountName,
      username: row.username,
      password: this.decryptSecret(row.passwordEncrypted),
      profileLink: row.profileLink,
      whatsappNumber: row.whatsappNumber,
      whatsappWaLink: row.whatsappWaLink,
      observations: row.observations,
      avatarUrl: row.avatarUrl,
      isActive: row.isActive,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
    };
  }

  private validateByType(type: MarketingSocialAccountType, username?: string | null, whatsappNumber?: string | null) {
    if (type === MarketingSocialAccountType.WHATSAPP) {
      if (!whatsappNumber || whatsappNumber.length < 8) {
        throw new BadRequestException('Debes indicar un número válido para WhatsApp.');
      }
      return;
    }

    if (!username || username.length < 3) {
      throw new BadRequestException('Debes indicar usuario o correo para la cuenta.');
    }
  }

  private toNullableTrimmed(value?: string | null): string | null {
    const text = (value ?? '').trim();
    return text.length === 0 ? null : text;
  }

  private requiredValue(value: string | undefined, message: string): string {
    const text = (value ?? '').trim();
    if (text.length === 0) {
      throw new BadRequestException(message);
    }
    return text;
  }

  private normalizeWhatsappNumber(value?: string | null): string | null {
    const raw = (value ?? '').trim();
    if (!raw) return null;
    const digits = raw.replace(/[^0-9]/g, '');
    return digits.length === 0 ? null : digits;
  }

  private buildWhatsappWaLink(number?: string | null): string | null {
    const digits = this.normalizeWhatsappNumber(number);
    if (!digits) return null;
    return `https://wa.me/${digits}`;
  }

  private resolveSecretKey(): Buffer {
    const raw =
      process.env.MARKETING_SOCIAL_ACCOUNTS_SECRET?.trim() ||
      process.env.SECURE_CREDENTIALS_KEY?.trim() ||
      process.env.JWT_SECRET?.trim() ||
      process.env.APP_SECRET?.trim() ||
      '';

    if (!raw) {
      throw new InternalServerErrorException(
        'Falta MARKETING_SOCIAL_ACCOUNTS_SECRET para cifrar credenciales empresariales.',
      );
    }

    return createHash('sha256').update(raw).digest();
  }

  private encryptSecret(value: string | null): string | null {
    if (!value) return null;
    const key = this.resolveSecretKey();
    const iv = randomBytes(12);
    const cipher = createCipheriv('aes-256-gcm', key, iv);
    const encrypted = Buffer.concat([cipher.update(value, 'utf8'), cipher.final()]);
    const tag = cipher.getAuthTag();
    return `v1:${iv.toString('base64')}:${tag.toString('base64')}:${encrypted.toString('base64')}`;
  }

  private decryptSecret(value: string | null): string | null {
    if (!value) return null;

    try {
      const parts = value.split(':');
      if (parts.length !== 4 || parts[0] !== 'v1') return null;
      const [, ivB64, tagB64, payloadB64] = parts;
      const key = this.resolveSecretKey();
      const decipher = createDecipheriv('aes-256-gcm', key, Buffer.from(ivB64, 'base64'));
      decipher.setAuthTag(Buffer.from(tagB64, 'base64'));
      const plain = Buffer.concat([
        decipher.update(Buffer.from(payloadB64, 'base64')),
        decipher.final(),
      ]);
      return plain.toString('utf8');
    } catch {
      return null;
    }
  }

  private async logActivity(
    companyId: string,
    userId: string,
    action: string,
    metadata: Record<string, unknown>,
  ) {
    try {
      await this.prisma.marketingActivityLog.create({
        data: {
          companyId,
          userId: userId || null,
          action,
          description: action,
          metadata: metadata as Prisma.InputJsonValue,
        },
      });
    } catch {
      // Keep action non-blocking.
    }
  }
}
