# FULLTECH API (NestJS + Prisma)

## Requisitos
- Node.js 18+ (probado con Node 20)
- Una base de datos PostgreSQL **cloud** ya creada

## Configuración
1) Crear `apps/api/.env` (no se commitea) usando `apps/api/.env.example` como guía.
2) Asegurar `DATABASE_URL` apunta a tu Postgres cloud.

## Comandos (desde la raíz del repo)
- Instalar: `npm install`
- Migraciones (crea/aplica): `npm run api:migrate:dev`
- Migraciones (aplica en prod): `npm run api:migrate:deploy`
- Seed (crea admin si no existe): `npm run api:seed`
- Dev server: `npm run api:dev`
- Smoke test: `npm run api:smoke`

## Credenciales seed
- email: `admin@fulltech.local`
- password: `Admin12345!`

