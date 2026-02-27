# Product Source Migration: FULLTECH -> FULLPOS Cloud (Multi-tenant safe)

Date: 2026-02-27

## Goal

- FULLTECH must **stop storing/managing products locally**.
- FULLTECH must **read products only from FULLPOS cloud**, scoped to **one tenant/company**.
- Tenant isolation must be enforced in FULLPOS_BACKEND **server-side** (token-bound), never by passing a tenant id from FULLTECH.
- Flutter client must not contain secrets.

## Audit (current code paths)

### FULLTECH (NestJS backend)

- Local products table/model:
  - apps/api/prisma/schema.prisma (model `Product`)
- Product CRUD endpoints:
  - apps/api/src/products/products.controller.ts
  - apps/api/src/products/products.service.ts
- Catalog UI + local CRUD actions:
  - apps/fulltech_app/lib/features/catalogo/catalogo_screen.dart
  - apps/fulltech_app/lib/features/catalogo/data/catalog_repository.dart

### FULLPOS_BACKEND (Express backend)

- Tenant isolation (JWT):
  - FULLPOS_BACKEND/src/middlewares/authGuard.ts (injects `req.user.companyId`)
- Products queries already scoped by companyId:
  - FULLPOS_BACKEND/src/modules/products/products.service.ts (filters by `companyId`)
- New integrations endpoint + token auth (Phase 1):
  - FULLPOS_BACKEND/src/modules/integrations/*

## Phase 1 (Read path migration; non-destructive)

### 1) FULLPOS_BACKEND: integration endpoint

- Endpoint: `GET /api/integrations/products`
- Auth: integration token (Bearer)
- Token-bound tenant isolation: middleware injects `req.integration.companyId`
- Supports: `limit`, `updated_since`, `cursor`

Setup:

1. Deploy FULLPOS_BACKEND with the migration applied.
2. Create an integration token bound to the correct `companyId`.
3. Store the raw token **server-side** in FULLTECH backend env.

Required env (FULLTECH backend):

- `PRODUCTS_SOURCE=FULLPOS` (default in non-prod; can fall back to `LOCAL`)
- `FULLPOS_INTEGRATION_BASE_URL=https://<fullpos-backend-host>`
- `FULLPOS_INTEGRATION_TOKEN=<raw token>`
- `FULLPOS_INTEGRATION_TIMEOUT_MS=8000` (optional)

### 2) FULLTECH backend: feature flag + read-only enforcement

- Reads:
  - apps/api/src/products/products.service.ts fetches products from FULLPOS when `PRODUCTS_SOURCE=FULLPOS`
- Writes:
  - Create/update/delete are blocked with a conflict error when read-only.

### 3) FULLTECH UI: no local product CRUD

- Catalog UI disables Add/Edit/Delete when settings report `productsReadOnly=true`:
  - apps/fulltech_app/lib/features/catalogo/catalogo_screen.dart
- `/settings` includes:
  - `productsSource` and `productsReadOnly`
  - apps/api/src/settings/settings.service.ts
  - apps/fulltech_app/lib/core/company/company_settings_model.dart

### 4) Verification checklist (staging)

1. FULLPOS_BACKEND
   - Migration applied (IntegrationToken table exists)
   - Integration token created and stored securely
   - `GET /api/integrations/products` returns only the correct tenant’s products
2. FULLTECH backend
   - `GET /products` returns products when `PRODUCTS_SOURCE=FULLPOS`
   - `POST/PATCH/DELETE /products` returns conflict (read-only)
3. FULLTECH app
   - Catalog loads products
   - Add/Edit/Delete product UI is disabled in read-only mode

### Rollback (Phase 1)

- Immediate rollback lever (no DB changes required in FULLTECH):
  - Set `PRODUCTS_SOURCE=LOCAL` in FULLTECH backend and restart.
- FULLPOS integration endpoint can remain deployed; it is additive.

## Phase 2 (Destructive; ONLY after Phase 1 verified)

Do not run Phase 2 until Phase 1 verification is complete.

1. Remove or permanently disable FULLTECH product CRUD endpoints/services.
2. Create a migration to drop FULLTECH `Product` table and any remaining foreign keys/indexes.
   - Only if there is no remaining code path reading/writing it.
3. Backup/rollback plan:
   - Snapshot DB before dropping.
   - Keep a down migration (or restore steps) prepared.
   - Emergency rollback: set `PRODUCTS_SOURCE=LOCAL` (if table restored).
