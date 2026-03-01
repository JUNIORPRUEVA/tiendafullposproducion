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
3) La API expone el puerto 4000 y monta un volumen `uploads_data` en `/uploads` para imágenes (ajusta `UPLOAD_DIR`/nombre de volumen si lo cambias).
4) En EasyPanel define `PUBLIC_BASE_URL` con el dominio público HTTPS de la API para que las imágenes sean accesibles desde cualquier dispositivo.
5) El contenedor corre `npx prisma migrate deploy` antes de iniciar `node dist/main.js`.
6) Opcional: para crear/resetear el usuario ADMIN al desplegar, define `RUN_SEED=true` y `ADMIN_PASSWORD` en el entorno (EasyPanel / .env.docker). Esto ejecuta `npx prisma db seed` en el arranque.

## Subida de imágenes de productos
- Endpoint: `POST /products/upload` (roles ADMIN/ASISTENTE, header Authorization Bearer).
- Campo: `file` (multipart/form-data), formatos permitidos: PNG/JPG/WEBP, límite 5 MB.
- Respuesta: `{ filename, path, url }` donde `path`/`url` es relativo (`/uploads/<archivo>`). Sirve estático desde `UPLOAD_DIR`.

## Comandos (desde la raíz del repo)
- Instalar: `npm install`
- Migraciones (crea/aplica): `npm run api:migrate:dev`
- Migraciones (aplica en prod): `npm run api:migrate:deploy`
- Seed (upsert; crea/resetea ADMIN): `npm run api:seed`
- Dev server: `npm run api:dev`
- Smoke test: `npm run api:smoke`

## Diagnóstico de integridad (usuarios)
Cuando `GET /users` da 500 en producción de forma intermitente, suele ser por datos legacy (NULLs en campos requeridos, roles inválidos, duplicados, etc.) que hacen que Prisma lance errores runtime.

- Endpoint (ADMIN): `GET /admin/diagnostics/users-integrity`
	- Devuelve un reporte con `counts` + `samples` para ubicar los IDs problemáticos.

## Scripts de integridad (Prisma)
Ejecuta estos comandos dentro de `apps/api` o desde la raíz usando workspaces.

- Solo revisar (no cambia nada):
	- `npm --workspace apps/api run integrity:check`
- Aplicar fixes seguros (no borra data):
	- `npm --workspace apps/api run integrity:fix`

Notas:
- El fix normaliza strings vacíos a `NULL` en columnas opcionales.
- Para rellenar `NULL` en campos requeridos con defaults (más agresivo), usa:
	- `ts-node prisma/scripts/fix_integrity.ts --fix --fix-required-nulls`
- No se borran filas huérfanas automáticamente a menos que se habilite explícitamente `--allow-delete`.

## Seed (credenciales)
- `ADMIN_EMAIL` (si no se define, usa `admin@fulltech.local`)
- `ADMIN_PASSWORD` (requerido; define/actualiza la contraseña del ADMIN)

