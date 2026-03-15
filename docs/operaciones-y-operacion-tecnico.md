# Módulo de Operaciones y Operación Técnico (FULLTECH)

Este documento resume **qué está implementado hoy** en el sistema (API + base de datos + app Flutter) para:

- **Operaciones**: gestión completa de órdenes/servicios (creación, asignación, agenda, cambios de estado/fase, evidencias, garantía, dashboard).
- **Operación Técnico**: ejecución en campo (reporte técnico, evidencias, cambios/costos) y **Salidas Técnicas** (registro de traslados + pagos de combustible para vehículo propio).

> Nota: en la base de datos los enums están en MAYÚSCULAS (Prisma), mientras que la API y la app normalmente usan strings en minúsculas (ej. `scheduled`, `in_progress`, etc.).

---

## 1) Arquitectura (dónde vive cada cosa)

### Backend (NestJS)
- Operaciones:
  - Módulo y endpoints: `apps/api/src/operations/*`
  - Reglas de negocio principales: `apps/api/src/operations/operations-main.service.ts`
- Salidas Técnicas (traslados/pago combustible):
  - Servicio: `apps/api/src/salidas-tecnicas/salidas-tecnicas.service.ts`
  - Controladores: `apps/api/src/salidas-tecnicas/*controller.ts`

### Base de datos (Prisma)
- Enums / estados / fases (fuente de verdad): `apps/api/prisma/schema.prisma`

### App Flutter
- Operaciones (admin/asistente/vendedor): `apps/fulltech_app/lib/features/operaciones/*`
- Operaciones Técnico (ejecución): `apps/fulltech_app/lib/features/operaciones/tecnico/*`
- Salidas Técnicas: `apps/fulltech_app/lib/features/salidas_tecnicas/*`

---

## 2) Roles y alcance (quién ve qué)

Reglas centrales (backend):

- **ADMIN / ASISTENTE**: ve y opera **todo**.
- **VENDEDOR**: ve servicios donde `createdByUserId = vendedor.id` (los que él/ella creó).
- **TÉCNICO**:
  - Por defecto ve solo servicios donde está asignado (relación `assignments`).
  - Hay un flag configurable `AppConfig.operationsTechCanViewAllServices` que, si está activo, permite que el técnico vea todos los servicios.

Además, para acciones:
- Acciones “críticas” (ej. cancelar) exigen creador o admin-like.
- Acciones operativas (cambios normales) permiten creador / admin-like / técnico asignado.

---

## 3) Estados y fases (lo que el sistema entiende)

### 3.1 Estado del servicio (ServiceStatus)
**DB (Prisma enum)**: `RESERVED`, `SURVEY`, `SCHEDULED`, `IN_PROGRESS`, `COMPLETED`, `WARRANTY`, `CLOSED`, `CANCELLED`

**API/App (strings)**:
- `reserved` (Reserva / sin etapa)
- `survey` (Levantamiento)
- `scheduled` (Agendado)
- `in_progress` (En proceso)
- `completed` (Finalizado)
- `warranty` (Garantía)
- `closed` (Cerrado)
- `cancelled` (Cancelado)

**Transiciones válidas (backend)**:
- `reserved` → `survey` o `cancelled`
- `survey` → `scheduled` o `cancelled`
- `scheduled` → `in_progress` o `cancelled`
- `in_progress` → `completed` o `warranty` o `cancelled`
- `completed` → `warranty` o `closed`
- `warranty` → `in_progress` o `closed`
- `closed` → (sin transiciones)
- `cancelled` → (sin transiciones)

### 3.2 Estado interno de la orden (OrderState)
**DB (Prisma enum)**: `PENDING`, `CONFIRMED`, `ASSIGNED`, `IN_PROGRESS`, `FINALIZED`, `CANCELLED`, `RESCHEDULED`

**API/App (strings)**:
- `pending`, `confirmed`, `assigned`, `in_progress`, `finalized`, `cancelled`, `rescheduled`

> En la app hay una UI para cambiar `orderState` (además del `status`). Se usa para un control más “operativo/administrativo” del avance.

### 3.3 Fase (ServicePhaseType)
**DB (Prisma enum)**: `RESERVA`, `LEVANTAMIENTO`, `INSTALACION`, `MANTENIMIENTO`, `GARANTIA`

**API/App (strings)**:
- `reserva`, `levantamiento`, `instalacion`, `mantenimiento`, `garantia`

La fase vive como:
- `currentPhase` en el servicio.
- Historial en `ServicePhaseHistory` (quién cambió, de cuál a cuál, nota, timestamp).

### 3.4 Tipo de servicio (ServiceType)
**DB enum**: `INSTALLATION`, `MAINTENANCE`, `WARRANTY`, `POS_SUPPORT`, `OTHER`

**API/App (strings)**:
- `installation`, `maintenance`, `warranty`, `pos_support`, `other`

### 3.5 Tipo de orden (OrderType)
**DB enum**: `RESERVA`, `SERVICIO`, `LEVANTAMIENTO`, `GARANTIA`, `MANTENIMIENTO`, `INSTALACION`

**Parsing en backend (importante)**:
- `servicio` se interpreta como **mantenimiento** (compatibilidad legacy).
- `mantenimiento` y `servicio` se filtran como `{ in: [MANTENIMIENTO, SERVICIO] }`.

---

## 4) Reglas de negocio clave (backend)

### 4.1 Cambio de fase (`PATCH /services/:id/phase`)
- Requiere `scheduledAt` (string de fecha) y `phase`.
- No permite volver a `reserva` (solo fase inicial).
- Si la fase seleccionada es la misma que `currentPhase`, falla.

**Validación al pasar a** `instalacion` / `mantenimiento` / `levantamiento`:
- Debe existir **monto cotizado** (`quotedAmount > 0`).
- Debe existir **monto total** (`orderExtras.finalCost > 0`).
- Debe existir **ubicación** válida (dirección, GPS o link).
- Si falta algo, responde `BadRequest` con `code: PHASE_VALIDATION`.

**Validación al pasar a** `garantia`:
- La orden debe estar finalizada (por `orderState=FINALIZED` o `status=COMPLETED/CLOSED`).
- Debe existir evidencia de que hubo una **instalación finalizada** del cliente (en el mismo servicio o en un servicio previo del cliente, por categoría).
- Si falla, responde con códigos:
  - `PHASE_WARRANTY_STATE`
  - `PHASE_WARRANTY_INSTALL`

### 4.2 Agendado (schedule)
- El backend persiste `scheduledStart` y `scheduledEnd`.
- En cambio de fase, calcula una duración por defecto (si ya había duración previa, la respeta; si no, asigna 1 hora).
- Hay validaciones de conflictos (especialmente para instalaciones) en el servicio de operaciones.

### 4.3 Cancelación
- Cancelar (`status=cancelled`) requiere permisos “críticos” (admin-like o creador).

### 4.4 Reporte técnico (Execution Report) y cambios
- `GET /services/:id/execution-report`: devuelve `{ report, changes }` para un técnico objetivo.
  - Si el usuario es TÉCNICO, el objetivo es él mismo.
  - Si es admin-like, puede pedir `technicianId`.
- `PUT /services/:id/execution-report`: upsert del reporte.
- `POST /services/:id/execution-report/changes`: agrega un cambio (material, costo extra, etc.).
- Si el servicio está `closed` o `cancelled` y el actor no es admin-like, el reporte/cambios quedan en **solo lectura**.

### 4.5 Evidencias / Archivos
- `POST /services/:id/files`: sube archivo (multer) a `/uploads` y guarda URL + mime.
- En el backend hay lógica para “decorar” URLs (base pública) y también convivir con archivos remotos (ej. R2), según configuración.

---

## 5) API de Operaciones (endpoints principales)

Controlador: `apps/api/src/operations/operations.controller.ts`

- `GET /services`: listado con filtros (status, type, orderType, orderState, technicianId, prioridad, customerId, etc.) + paginación.
- `GET /services/:id`: detalle.
- `POST /services`: crear servicio (admin/asistente/vendedor).
- `PATCH /services/:id`: editar (admin/asistente/vendedor).
- `DELETE /services/:id`: eliminación lógica (admin/asistente/vendedor).

Cambios operativos:
- `PATCH /services/:id/status`: cambiar `status`.
- `PATCH /services/:id/order-state`: cambiar `orderState`.
- `PATCH /services/:id/phase`: cambiar fase y (re)agendar por `scheduledAt`.
- `GET /services/:id/phases`: historial de fases.
- `PATCH /services/:id/schedule`: agendar.
- `POST /services/:id/assign`: asignar técnicos.
- `POST /services/:id/update`: agregar update/note.

Técnico:
- `GET/PUT /services/:id/execution-report`
- `POST/DELETE /services/:id/execution-report/changes`

Otros:
- `GET /technicians`
- `GET /customers/:id/services`
- `GET /dashboard/operations`

---

## 6) App Flutter: cómo se usa (Operaciones)

### 6.1 Flujo general
- La app usa un repositorio (`operations_repository.dart`) para llamar a la API y cachear respuestas.
- Un controller Riverpod (`operations_controller.dart`) maneja:
  - filtros
  - paginación / refresh
  - carga “cache-first” + refresh en background

### 6.2 Pantallas principales

- Operaciones (listado + filtros + acciones):
  - `apps/fulltech_app/lib/features/operaciones/operaciones_screen.dart`
  - Incluye navegación y apertura de panel de detalle.

- Agenda:
  - `OperacionesAgendaScreen` está dentro de `operaciones_screen.dart`.
  - Muestra servicios con `scheduledStart != null`.
  - Permite:
    - ver detalle (panel)
    - cambiar estado con confirmación
    - ver historial (dialog con lista)
    - crear una **orden genérica** desde agenda

- Mapa de clientes:
  - `operaciones_mapa_clientes_screen.dart` (usa GPS parseado desde el texto de dirección).

- Finalizados:
  - `operaciones_finalizados_screen.dart`

- Reglas:
  - `operaciones_reglas_screen.dart` (placeholder)

- Panel (archivo existente):
  - `apps/fulltech_app/lib/features/operaciones/operations_panel_screen.dart` (actualmente vacío / sin implementación)

### 6.3 Acciones en el detalle
En el panel de detalle / actions sheet (Flutter):
- cambiar `status`
- cambiar `orderState`
- agendar
- asignar técnicos
- subir evidencia
- crear garantía
- togglear pasos (`steps`) y agregar notas (`updates`)

> La UI aplica permisos (qué botones aparecen) usando `operations_permissions.dart`, que replica el flujo/roles del backend.

---

## 7) Operación Técnico (Ejecución del servicio)

### 7.1 Pantallas/archivos
- Lista para técnicos: `apps/fulltech_app/lib/features/operaciones/tecnico/operaciones_tecnico_screen.dart`
  - Tabs: Hoy / Pendientes / En proceso / Finalizados
  - Oculta “reservas” y prioriza servicios asignados.

- Ejecución técnica (reporte + evidencias):
  - UI: `technical_service_execution_screen.dart`
  - Controller: `technical_service_execution_controller.dart`
  - Evidencias pendientes: `technical_evidence_upload.dart`

### 7.2 Qué registra el técnico
- Reporte técnico por servicio y por técnico:
  - timestamps (llegada / inicio / fin)
  - notas
  - checklist (JSON)
  - datos por fase (JSON)
  - aprobación del cliente (bool)

- Cambios (extra):
  - items con tipo, descripción, cantidad, costo extra, aprobación del cliente, nota

- Evidencias (fotos/videos/archivos):
  - carga a backend y se asocian al servicio
  - controller maneja cola/pending uploads

### 7.3 Restricciones
- Si el servicio está `closed` o `cancelled`, el reporte/cambios quedan en modo lectura para no admin-like.

---

## 8) Salidas Técnicas (traslados) y pago de combustible

### 8.1 Estados (SalidaTecnicaEstado)
En DB:
- `INICIADA` → `LLEGADA` → `FINALIZADA` → `APROBADA`/`RECHAZADA` → `PAGADA`

### 8.2 Flujo técnico
- El técnico puede tener **una sola salida abierta** a la vez.
- Iniciar salida:
  - valida que el servicio esté asignado al técnico
  - registra GPS de salida
  - guarda vehículo (empresa o propio)
  - si es vehículo propio:
    - exige rendimiento km/l
    - calcula luego combustible estimado

- Marcar llegada:
  - registra GPS de llegada

- Finalizar:
  - registra GPS final
  - calcula km por haversine
  - si aplica pago combustible: calcula litros y monto estimado

En cada paso se registra una nota en el historial del servicio (`ServiceUpdate`), por ejemplo:
- “En camino” / “En sitio” / “Salida técnica finalizada”.

Además (mejor esfuerzo): al iniciar salida, si el servicio estaba `scheduled`, el backend intenta moverlo a `in_progress`.

### 8.3 Vehículos
- Listado para técnico incluye:
  - vehículos de empresa
  - vehículos propios activos
- El técnico puede crear/editar sus vehículos propios.

### 8.4 Flujo admin (aprobación y pagos)
- Admin lista salidas y puede:
  - aprobar una salida `FINALIZADA` → `APROBADA`
  - rechazar una salida `FINALIZADA` → `RECHAZADA`

Pagos de combustible (vehículo propio):
- Un admin crea un pago por período:
  - agrupa salidas `APROBADA` sin pago asignado en rango de fechas
  - crea `PagoCombustibleTecnico` estado `PENDIENTE`
- Marcar pago como pagado:
  - `PagoCombustibleTecnico` pasa a `PAGADO`
  - salidas `APROBADA` del pago pasan a `PAGADA`
  - intenta (mejor esfuerzo) importar a nómina si existe un período abierto que cubra la fecha de pago

Estados del pago (PagoCombustibleTecnicoEstado):
- `PENDIENTE`, `PAGADO`, `CANCELADO`

---

## 9) “Qué se ha hecho” (resumen de features implementadas)

- CRUD y ciclo de vida de servicios (Operaciones) con:
  - status + orderState
  - fases + historial
  - agenda (scheduledStart)
  - asignaciones de técnicos
  - notas/updates, pasos/checklist, evidencias
  - garantía (con reglas)
  - dashboard y servicios por cliente

- Módulo Técnico:
  - listado de órdenes asignadas
  - ejecución técnica (reporte, checklist, cambios/costos, evidencias)
  - restricciones de edición cuando el servicio está cerrado/cancelado

- Salidas Técnicas:
  - vehículos (empresa/propio)
  - salida única abierta
  - inicio/llegada/finalización con GPS
  - cálculo de km y combustible estimado (si vehículo propio)
  - aprobación/rechazo por admin
  - pagos por período + marcado pagado + intento de importación a nómina
