import { Injectable } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { CreateCloseDto, UpdateCloseDto } from './close.dto';

@Injectable()
export class ContabilidadService {
  constructor(private prisma: PrismaService) {}

  async createClose(dto: CreateCloseDto) {
    return this.prisma.close.create({
      data: {
        type: dto.type,
        date: dto.date ? new Date(dto.date) : new Date(),
        status: dto.status,
        cash: dto.cash,
        transfer: dto.transfer,
        card: dto.card,
        expenses: dto.expenses,
        cashDelivered: dto.cashDelivered,
      },
    });
  }

  async getCloses(date?: string) {
    const where = date ? { date: new Date(date) } : {};
    return this.prisma.close.findMany({
      where,
      orderBy: { createdAt: 'desc' },
    });
  }

  async getCloseById(id: string) {
    return this.prisma.close.findUnique({
      where: { id },
    });
  }

  async updateClose(id: string, dto: UpdateCloseDto) {
    return this.prisma.close.update({
      where: { id },
      data: dto,
    });
  }

  async deleteClose(id: string) {
    return this.prisma.close.delete({
      where: { id },
    });
  }
}