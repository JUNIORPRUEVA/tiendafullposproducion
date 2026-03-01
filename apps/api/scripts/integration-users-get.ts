/*
  Lightweight “integration” check (ts-node) for GET /users resilience.

  It simulates the common production failure mode:
  Prisma throws "Inconsistent query result ... got null instead" due to legacy NULLs.

  Run:
    npm --workspace apps/api run ts-node scripts/integration-users-get.ts
*/

import assert from 'node:assert/strict';
import { UsersService } from '../src/users/users.service';

async function run() {
  const inconsistent = new Error(
    'Inconsistent query result: Field nombreCompleto is required to return data, got null instead.',
  );
  (inconsistent as any).name = 'PrismaClientUnknownRequestError';

  const prismaMock: any = {
    user: {
      findMany: async () => {
        throw inconsistent;
      },
    },
    $queryRaw: async () => [
      {
        id: '00000000-0000-0000-0000-000000000001',
        email: 'legacy@fulltech.local',
        nombreCompleto: '',
        telefono: '',
        telefonoFamiliar: null,
        cedula: null,
        fotoCedulaUrl: null,
        fotoLicenciaUrl: null,
        fotoPersonalUrl: null,
        edad: 0,
        tieneHijos: false,
        estaCasado: false,
        casaPropia: false,
        vehiculo: false,
        licenciaConducir: false,
        fechaIngreso: null,
        fechaNacimiento: null,
        cuentaNominaPreferencial: null,
        habilidades: null,
        role: 'ASISTENTE',
        blocked: false,
        createdAt: new Date(),
        updatedAt: new Date(),
      },
    ],
  };

  const configMock: any = {
    get: () => undefined,
  };

  const service = new UsersService(prismaMock, configMock);

  const users = await service.findAll();
  assert.ok(Array.isArray(users));
  assert.ok(users.length >= 1);

  // eslint-disable-next-line no-console
  console.log('[ok] users.findAll() fallback works (no throw)');
}

run().catch((e) => {
  // eslint-disable-next-line no-console
  console.error('[fail]', e);
  process.exitCode = 1;
});
