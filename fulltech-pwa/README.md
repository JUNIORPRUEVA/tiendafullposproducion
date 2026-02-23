# FullTech Monorepo (Local First)

Este repo contiene:

- `apps/api`: Backend NestJS + Prisma + PostgreSQL
- `apps/web`: Frontend Next.js (responsive PC/móvil)

> Nota: existe una carpeta `apps/` en este workspace con archivos previos. Esta guía usa **`apps/api`** y **`apps/web`** (sin romper lo existente).

## Requisitos

- Node.js >= 18
- PostgreSQL local (o remoto)

## Variables de entorno

### API (`apps/api/.env`)

Parte de `apps/api/.env.example` y ajusta:

- `DATABASE_URL=postgresql://USER:PASS@HOST:5432/DBNAME?schema=public`
- `JWT_SECRET=...`
- `JWT_EXPIRES_IN=15m`
- `UPLOAD_DIR=...` (si se omite, usa `./uploads`)
- `PORT=4000`
- (opcional seed) `ADMIN_EMAIL` / `ADMIN_PASSWORD`

### WEB (`apps/web/.env.local`)

Parte de `apps/web/.env.local.example`:

- `NEXT_PUBLIC_API_URL=http://localhost:4000`

## Correr en local

### 0) PostgreSQL local (recomendado)

Si no tienes PostgreSQL instalado, usa Docker:

```bash
docker compose up -d
```

### 1) Instalar dependencias

```bash
npm install
```

### 2) Prisma (generate + migrate + seed)

```bash
npm run prisma:generate
npm run prisma:migrate
npm run seed
```

Seed (ADMIN):

- Define `ADMIN_PASSWORD` en `fulltech-pwa/apps/api/.env` y corre `npm run seed` para crear/actualizar el usuario ADMIN.
- `ADMIN_EMAIL` es opcional (si no lo defines, usa `admin@fulltech.local`).

### 3) Levantar API + Web

```bash
npm run dev
```

- API: `http://localhost:4000`
- Web: `http://localhost:3001`

### 4) Smoke test (API)

Con la API corriendo:

```bash
npm run test:smoke
```

## Endpoints principales

- `GET /health`
- `POST /auth/login`, `GET /auth/me`
- `CRUD /users` (solo ADMIN)
- `CRUD /products` + `POST /products/:id/photo`
- `CRUD /customers` (ADMIN/ASISTENTE) + alias `CRUD /clients`
- `GET /sales`, `POST /sales` + `GET /sales/all` (solo ADMIN)

## Uploads (EasyPanel)

Para persistir imágenes, monta un volumen y apunta `UPLOAD_DIR`.

- Mount path recomendado: `/data/uploads`
- Env: `UPLOAD_DIR=/data/uploads`

El backend expone estáticos en `GET /uploads/...`.
