import { PrismaClient, Role, MarketingStoryStatus, MarketingStoryType } from '@prisma/client';
import { MarketingApprovalService } from '../src/marketing/marketing-approval.service';
import { MarketingConfigService } from '../src/marketing/marketing-config.service';
import { MarketingGenerationService } from '../src/marketing/marketing-generation.service';
import { MarketingService } from '../src/marketing/marketing.service';

function assert(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(message);
}

function sameUtcDate(left: Date, right: Date) {
  return (
    left.getUTCFullYear() === right.getUTCFullYear() &&
    left.getUTCMonth() === right.getUTCMonth() &&
    left.getUTCDate() === right.getUTCDate()
  );
}

async function main() {
  const prisma = new PrismaClient();

  try {
    const configService = new MarketingConfigService(prisma as any);
    const generationService = new MarketingGenerationService(prisma as any);
    const approvalService = new MarketingApprovalService(prisma as any);
    const marketing = new MarketingService(
      prisma as any,
      generationService,
      approvalService,
      configService,
    );

    const companyId = marketing.resolveCompanyId();
    const admin = await prisma.user.findFirst({ where: { role: Role.ADMIN }, select: { id: true } });
    assert(admin?.id, 'No se encontro usuario ADMIN para la prueba');
    const actorId = admin.id;

    const now = new Date();
    const date = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate()));

    await marketing.resetFlow(companyId, actorId);
    const activated = await marketing.activateFlow(companyId, actorId);
    assert(activated.active === true, 'El flujo no quedo activo');
    assert(activated.paused === false, 'El flujo no deberia estar pausado al activar');

    const generated = await marketing.generateMissingStories(companyId, date, actorId);
    assert(generated.length === 3, `Se esperaban 3 estados diarios y se obtuvieron ${generated.length}`);

    const types = generated.map((item) => item.type).sort();
    const expectedTypes = [MarketingStoryType.EDUCATIONAL, MarketingStoryType.SALES, MarketingStoryType.TRUST];
    assert(JSON.stringify(types) === JSON.stringify(expectedTypes), 'Los tipos generados no corresponden a SALES/TRUST/EDUCATIONAL');
    assert(generated.every((item) => item.status === MarketingStoryStatus.PENDING), 'Los estados iniciales no quedaron en PENDING');

    const sales = generated.find((item) => item.type === MarketingStoryType.SALES);
    const trust = generated.find((item) => item.type === MarketingStoryType.TRUST);
    const educational = generated.find((item) => item.type === MarketingStoryType.EDUCATIONAL);
    assert(sales && trust && educational, 'No se encontraron los 3 tipos esperados para pruebas');

    const approved = await marketing.approveStory(companyId, sales.id, actorId);
    assert(approved.status === MarketingStoryStatus.APPROVED, 'Aprobar no cambio el estado a APPROVED');

    const rejected = await marketing.rejectStory(companyId, trust.id, actorId, 'contenido no alineado');
    assert(rejected.status === MarketingStoryStatus.REJECTED, 'Rechazar no cambio el estado a REJECTED');

    const regenerated = await marketing.regenerateStory(companyId, trust.id, actorId);
    assert(regenerated.status === MarketingStoryStatus.REGENERATED, 'Regenerar no cambio el estado a REGENERATED');
    assert(regenerated.generationAttempt > trust.generationAttempt, 'Regenerar no incremento generationAttempt');

    const edited = await marketing.editStory(
      companyId,
      educational.id,
      {
        title: 'Titulo auditado',
        shortText: 'Texto corto auditado',
        longText: 'Texto largo auditado',
        hashtags: ['#Auditado', '#Fulltech'],
        imagePrompt: 'Prompt auditado de imagen',
        imageUrl: 'image_placeholder',
      },
      actorId,
    );
    assert(edited.title === 'Titulo auditado', 'Editar no actualizo el titulo');
    assert(edited.shortText === 'Texto corto auditado', 'Editar no actualizo el shortText');
    assert(edited.imagePrompt === 'Prompt auditado de imagen', 'Editar no actualizo imagePrompt');

    await marketing.pauseFlow(companyId, actorId);
    let pauseBlocked = false;
    try {
      await marketing.generateMissingStories(companyId, date, actorId);
    } catch {
      pauseBlocked = true;
    }
    assert(pauseBlocked, 'Con flujo pausado se permitio generar contenido');

    await marketing.activateFlow(companyId, actorId);
    await marketing.rejectStory(companyId, educational.id, actorId, 'forzar regeneracion tras activar');
    const afterActivate = await marketing.generateMissingStories(companyId, date, actorId);
    const educationalAfterActivate = afterActivate.find((item) => item.type === MarketingStoryType.EDUCATIONAL);
    assert(
      educationalAfterActivate?.status === MarketingStoryStatus.REGENERATED ||
        educationalAfterActivate?.status === MarketingStoryStatus.PENDING,
      'Tras activar no se permitio generar/reponer contenido',
    );

    const dashboard = await marketing.getDashboard(companyId, date);
    assert(typeof dashboard.pendingApprovalCount === 'number', 'Dashboard no devolvio pendingApprovalCount');
    assert(typeof dashboard.approvedTodayCount === 'number', 'Dashboard no devolvio approvedTodayCount');

    const storiesBeforeReset = await prisma.marketingDailyStory.count({ where: { companyId } });
    assert(storiesBeforeReset > 0, 'No hay historias previas para validar reset');

    await marketing.resetFlow(companyId, actorId);
    const storiesAfterReset = await prisma.marketingDailyStory.count({ where: { companyId } });
    assert(storiesAfterReset === 0, 'Reset no limpio los estados diarios');

    const cfgAfterReset = await marketing.getConfig(companyId);
    assert(cfgAfterReset.active === false && cfgAfterReset.paused === false, 'Reset no restablecio active/paused');
    assert(cfgAfterReset.dailyStoriesCount === 3, 'Reset no restablecio dailyStoriesCount=3');

    const logs = await prisma.marketingActivityLog.findMany({
      where: { companyId },
      orderBy: { createdAt: 'desc' },
      take: 20,
    });
    const logActions = logs.map((item) => item.action);
    const requiredActions = [
      'MARKETING_STORIES_GENERATED',
      'MARKETING_STORY_APPROVED',
      'MARKETING_STORY_REJECTED',
      'MARKETING_STORY_REGENERATED',
      'MARKETING_STORY_EDITED',
      'MARKETING_FLOW_PAUSED',
      'MARKETING_FLOW_ACTIVATED',
      'MARKETING_FLOW_RESET',
    ];
    for (const action of requiredActions) {
      assert(logActions.includes(action), `No se encontro log obligatorio: ${action}`);
    }

    const todays = await prisma.marketingDailyStory.findMany({ where: { companyId, date } });
    assert(todays.every((item) => sameUtcDate(item.date, date)), 'Se guardaron historias fuera de la fecha auditada');

    console.log('SMOKE_MARKETING_PHASE1_OK');
  } finally {
    await prisma.$disconnect();
  }
}

main().catch((error) => {
  console.error('SMOKE_MARKETING_PHASE1_FAILED', error);
  process.exit(1);
});
