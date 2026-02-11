# FULLTECH API (NestJS + Prisma)

## Requisitos
- Node.js 18+ (probado con Node 20)
- Una base de datos PostgreSQL **cloud** ya creada

## Configuración
1) Crear `apps/api/.env` (no se commitea) usando `apps/api/.env.example` como guía.
2) Asegurar `DATABASE_URL` apunta a tu Postgres cloud.

## Despliegue con Docker / EasyPanel
1) Copia variables: `cp .env.docker.example .env.docker` y ajusta secretos.
2) Construye y levanta: `docker compose up --build -d`.
3) La API expone el puerto 4000 y monta un volumen `uploads_data` en `/app/uploads` para imágenes (ajusta `UPLOAD_DIR`/nombre de volumen si lo cambias).
4) El contenedor corre `npx prisma migrate deploy` antes de iniciar `node dist/main.js`.

## Subida de imágenes de productos
- Endpoint: `POST /products/upload` (roles ADMIN/ASISTENTE, header Authorization Bearer).
- Campo: `file` (multipart/form-data), formatos permitidos: PNG/JPG/WEBP, límite 5 MB.
- Respuesta: `{ filename, path, url }` donde `path`/`url` es relativo (`/uploads/<archivo>`). Sirve estático desde `UPLOAD_DIR`.

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

