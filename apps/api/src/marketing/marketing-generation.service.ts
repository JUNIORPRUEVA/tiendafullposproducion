import { Injectable, NotFoundException } from '@nestjs/common';
import { MarketingStoryType } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';

type StoryTemplate = {
  title: string;
  shortText: string;
  longText: string;
  hashtags: string[];
  imagePrompt: string;
};

@Injectable()
export class MarketingGenerationService {
  constructor(private readonly prisma: PrismaService) {}

  private readonly orderedTypes: MarketingStoryType[] = [
    MarketingStoryType.SALES,
    MarketingStoryType.TRUST,
    MarketingStoryType.EDUCATIONAL,
  ];

  private readonly templates: Record<MarketingStoryType, StoryTemplate[]> = {
    SALES: [
      {
        title: 'Protege tu negocio hoy mismo',
        shortText: 'Camaras Full HD con instalacion profesional y soporte local.',
        longText:
          'Mejora la seguridad de tu hogar o negocio con camaras Full HD, monitoreo remoto y acompanamiento tecnico de FULLTECH. Cotiza hoy y recibe asesoria personalizada.',
        hashtags: ['#SeguridadInteligente', '#Camaras', '#FullTech'],
        imagePrompt: 'Camara de seguridad moderna instalada en negocio con iluminacion profesional',
      },
      {
        title: 'POS rapido para vender mas',
        shortText: 'Controla ventas, inventario y caja desde un solo sistema POS.',
        longText:
          'Digitaliza tu punto de venta con un POS confiable, facil de usar y adaptado a tu operacion. En FULLTECH te instalamos y capacitamos para empezar a vender mejor desde el primer dia.',
        hashtags: ['#POS', '#Ventas', '#Negocios'],
        imagePrompt: 'Terminal POS en mostrador de tienda con cliente pagando',
      },
      {
        title: 'Portones automatizados sin complicaciones',
        shortText: 'Mas seguridad y comodidad con instalacion certificada.',
        longText:
          'Automatiza el acceso a tu propiedad con motores de alto rendimiento para portones. Incluye instalacion profesional y soporte tecnico de respuesta rapida.',
        hashtags: ['#Portones', '#Automatizacion', '#Seguridad'],
        imagePrompt: 'Porton electrico moderno abriendose en residencia',
      },
    ],
    TRUST: [
      {
        title: 'Tu compra respaldada por garantia real',
        shortText: 'Trabajamos con garantia y seguimiento postventa.',
        longText:
          'En FULLTECH no solo vendemos: te acompanamos antes, durante y despues. Nuestro compromiso incluye garantia clara, instalacion profesional y soporte oportuno.',
        hashtags: ['#Garantia', '#Confianza', '#Servicio'],
        imagePrompt: 'Equipo tecnico uniformado atendiendo cliente satisfecho en tienda',
      },
      {
        title: 'Tienda fisica + atencion humana',
        shortText: 'Estamos cerca de ti para asesorarte con transparencia.',
        longText:
          'Contamos con tienda fisica y equipo especializado para ayudarte a elegir la mejor solucion segun tu necesidad y presupuesto, sin promesas vacias.',
        hashtags: ['#TiendaFisica', '#Asesoria', '#FullTech'],
        imagePrompt: 'Interior de tienda de tecnologia con asesores atendiendo',
      },
      {
        title: 'Instalacion profesional certificada',
        shortText: 'Tecnicos entrenados y procesos estandarizados.',
        longText:
          'Nuestro equipo tecnico trabaja con protocolos claros de instalacion para garantizar seguridad, rendimiento y orden en cada proyecto.',
        hashtags: ['#InstalacionProfesional', '#SoporteTecnico', '#Calidad'],
        imagePrompt: 'Tecnico instalando camara con herramientas profesionales',
      },
    ],
    EDUCATIONAL: [
      {
        title: '3 puntos clave para proteger tu negocio',
        shortText: 'Ubicacion, cobertura y respaldo: la base de una seguridad efectiva.',
        longText:
          'Antes de instalar camaras, define zonas criticas, evita puntos ciegos y asegura almacenamiento de evidencia. Una estrategia correcta reduce riesgos y mejora el control operativo.',
        hashtags: ['#ConsejosDeSeguridad', '#NegocioSeguro', '#Educativo'],
        imagePrompt: 'Plano simple de negocio con zonas de camaras marcadas',
      },
      {
        title: 'Por que un POS mejora tu rentabilidad',
        shortText: 'Menos errores, mejor inventario y reportes en tiempo real.',
        longText:
          'Un sistema POS te da trazabilidad de ventas, control de inventario y decisiones con datos reales. Esto evita perdidas y acelera el crecimiento de tu negocio.',
        hashtags: ['#GestionComercial', '#POS', '#Productividad'],
        imagePrompt: 'Dashboard de ventas en pantalla con grafico de crecimiento',
      },
      {
        title: 'Mantenimiento preventivo de camaras',
        shortText: 'Limpieza, ajustes y revision periodica para evitar fallos.',
        longText:
          'El mantenimiento preventivo evita interrupciones en momentos clave. Revisar enfoque, grabacion y energia de forma periodica aumenta la vida util del sistema.',
        hashtags: ['#Mantenimiento', '#CamarasSeguridad', '#Tips'],
        imagePrompt: 'Tecnico revisando camara de seguridad con checklist',
      },
    ],
  };

  async generateMissingStories(companyId: string, date: Date, userId: string) {
    const existing = await this.prisma.marketingDailyStory.findMany({
      where: {
        companyId,
        date,
      },
      orderBy: { createdAt: 'asc' },
    });

    const generated: string[] = [];

    for (const type of this.orderedTypes) {
      const current = existing.find((item) => item.type === type);
      if (!current) {
        const content = this.pickTemplate(type);
        await this.prisma.marketingDailyStory.create({
          data: {
            companyId,
            date,
            type,
            title: content.title,
            shortText: content.shortText,
            longText: content.longText,
            hashtags: content.hashtags,
            imagePrompt: content.imagePrompt,
            imageUrl: 'image_placeholder',
            status: 'PENDING',
            generationAttempt: 1,
          },
        });
        generated.push(type);
        continue;
      }

      if (current.status === 'PENDING' || current.status === 'APPROVED') {
        continue;
      }

      const content = this.pickTemplate(type);
      await this.prisma.marketingDailyStory.update({
        where: { id: current.id },
        data: {
          title: content.title,
          shortText: content.shortText,
          longText: content.longText,
          hashtags: content.hashtags,
          imagePrompt: content.imagePrompt,
          imageUrl: 'image_placeholder',
          status: 'REGENERATED',
          generationAttempt: { increment: 1 },
          approvedAt: null,
          approvedByUserId: null,
          rejectedAt: null,
        },
      });
      generated.push(type);
    }

    if (generated.length > 0) {
      await this.prisma.marketingActivityLog.create({
        data: {
          companyId,
          action: 'MARKETING_STORIES_GENERATED',
          description: `Se generaron contenidos: ${generated.join(', ')}`,
          userId,
          metadata: { date: this.toDateOnly(date), generatedTypes: generated },
        },
      });
    }

    return this.prisma.marketingDailyStory.findMany({
      where: { companyId, date },
      orderBy: { type: 'asc' },
      include: {
        approvedByUser: {
          select: {
            id: true,
            nombreCompleto: true,
          },
        },
      },
    });
  }

  async regenerateStory(companyId: string, storyId: string, userId: string) {
    const story = await this.prisma.marketingDailyStory.findFirst({
      where: { id: storyId, companyId },
    });
    if (!story) {
      throw new NotFoundException('Contenido no encontrado');
    }

    const content = this.pickTemplate(story.type);
    const updated = await this.prisma.marketingDailyStory.update({
      where: { id: story.id },
      data: {
        title: content.title,
        shortText: content.shortText,
        longText: content.longText,
        hashtags: content.hashtags,
        imagePrompt: content.imagePrompt,
        imageUrl: 'image_placeholder',
        status: 'REGENERATED',
        generationAttempt: { increment: 1 },
        approvedAt: null,
        approvedByUserId: null,
        rejectedAt: null,
      },
      include: {
        approvedByUser: {
          select: {
            id: true,
            nombreCompleto: true,
          },
        },
      },
    });

    await this.prisma.marketingActivityLog.create({
      data: {
        companyId,
        action: 'MARKETING_STORY_REGENERATED',
        description: `Se regenero el contenido ${story.id}`,
        userId,
        metadata: {
          storyId: story.id,
          type: story.type,
          generationAttempt: updated.generationAttempt,
        },
      },
    });

    return updated;
  }

  private pickTemplate(type: MarketingStoryType): StoryTemplate {
    const options = this.templates[type] ?? [];
    if (options.length == 0) {
      return {
        title: 'Contenido del dia',
        shortText: 'Actualizacion de FULLTECH para nuestros clientes.',
        longText: 'Contenido temporal generado por plantilla.',
        hashtags: ['#FullTech'],
        imagePrompt: 'Diseno promocional tecnologico',
      };
    }
    const index = Math.floor(Math.random() * options.length);
    return options[index];
  }

  private toDateOnly(value: Date) {
    const year = value.getUTCFullYear();
    const month = `${value.getUTCMonth() + 1}`.padStart(2, '0');
    const day = `${value.getUTCDate()}`.padStart(2, '0');
    return `${year}-${month}-${day}`;
  }
}
