import { Injectable, NotFoundException } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { CreateClientDto } from './dto/create-client.dto';
import { ClientsQueryDto } from './dto/clients-query.dto';
import { UpdateClientDto } from './dto/update-client.dto';

@Injectable()
export class ClientsService {
  constructor(private readonly prisma: PrismaService) {}

  create(ownerId: string, dto: CreateClientDto) {
    return this.prisma.client.create({ data: { ...dto, ownerId } });
  }

  async findAll(query: ClientsQueryDto) {
    const page = query.page && query.page > 0 ? query.page : 1;
    const pageSize = query.pageSize && query.pageSize > 0 ? query.pageSize : 20;
    const skip = (page - 1) * pageSize;

    const search = query.search?.trim();
    const where: Prisma.ClientWhereInput = {
      ...(query.onlyDeleted === true
        ? { isDeleted: true }
        : query.includeDeleted === true
          ? {}
          : { isDeleted: false }),
      ...(search
        ? {
            OR: [
              { nombre: { contains: search, mode: Prisma.QueryMode.insensitive } },
              { telefono: { contains: search, mode: Prisma.QueryMode.insensitive } },
              { email: { contains: search, mode: Prisma.QueryMode.insensitive } }
            ]
          }
        : {}),
    };

    const [items, total] = await Promise.all([
      this.prisma.client.findMany({ where, orderBy: { createdAt: 'desc' }, skip, take: pageSize }),
      this.prisma.client.count({ where })
    ]);

    return { items, total, page, pageSize, totalPages: Math.max(1, Math.ceil(total / pageSize)) };
  }

  async findOne(id: string) {
    const client = await this.prisma.client.findFirst({ where: { id } });
    if (!client) throw new NotFoundException('Client not found');
    return client;
  }

  async update(id: string, dto: UpdateClientDto) {
    await this.findOne(id);
    return this.prisma.client.update({ where: { id }, data: dto });
  }

  async remove(id: string) {
    await this.findOne(id);
    await this.prisma.client.update({ where: { id }, data: { isDeleted: true } });
    return { ok: true };
  }
}

