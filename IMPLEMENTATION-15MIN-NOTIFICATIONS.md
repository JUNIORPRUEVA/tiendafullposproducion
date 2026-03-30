# Implementación: Notificaciones cada 15 minutos para órdenes PENDIENTES

## Resumen
Cuando se crea una orden de servicio en estado **PENDIENTE**, el sistema envía una notificación a **TODOS los técnicos** cada **15 minutos** hasta que la orden cambie de estado (en_proceso, finalizado, cancelado).

## Cambios Realizados

### 1. Backend - Listener de Notificaciones (`service-order-notifications.listener.ts`)

#### Cambio en `handleOrderCreated`
```typescript
async handleOrderCreated(orderId: string) {
  await this.scheduleThirtyMinuteReminder(orderId);
  await this.scheduleFifteenMinutePendingReminders(orderId); // ← NUEVO
}
```

#### Cambio en `handleStatusChanged`
```typescript
async handleStatusChanged(orderId: string, previousStatus: string, nextStatus: string) {
  if (nextStatus === 'en_proceso' || nextStatus === 'finalizado' || nextStatus === 'cancelado') {
    await this.cancelPendingReminderJobs(orderId, `Estado actualizado a ${nextStatus}`);
    await this.cancelFifteenMinuteReminderJobs(orderId, `Estado actualizado a ${nextStatus}`); // ← NUEVO
  }
  // ... resto del código
}
```

#### Nuevos Métodos

**`dispatchFifteenMinutePending(jobId: string)` - Dispatcher**
- Se ejecuta cada 15 minutos cuando hay un trabajo pendiente
- Verifica que la orden esté en estado PENDIENTE (si cambió, cancela el trabajo)
- Obtiene todos los técnicos con teléfono activos
- Envía mensaje WhatsApp a todos con detalles de la orden
- **Reprograma automáticamente el siguiente trabajo para 15 minutos después**
- El mensaje incluye: cliente, teléfono, ubicación, servicio, detalle, hora programada

**`scheduleFifteenMinutePendingReminders(orderId: string)` - Scheduler**
- Se llama al crear la orden
- Solo programa si la orden está en estado PENDIENTE
- Crea el primer trabajo (runAt = ahora) que disparará inmediatamente
- Los trabajos subsecuentes se crean en el dispatcher

**`cancelFifteenMinuteReminderJobs(orderId: string, reason: string)` - Cancelador**
- Se llama cuando la orden cambia de estado
- Cancela todos los trabajos pendientes/procesando del tipo FIFTEEN_MINUTES_PENDING
- Registra el motivo de la cancelación

### 2. Backend - Procesador de Trabajos (`service-order-notification-jobs.processor.ts`)

```typescript
if (row.kind === 'THIRTY_MINUTES_BEFORE') {
  await this.listener.dispatchThirtyMinuteReminder(row.id);
} else if (row.kind === 'FIFTEEN_MINUTES_PENDING') {
  await this.listener.dispatchFifteenMinutePending(row.id); // ← NUEVO
}
```

Ahora el procesador también maneja trabajos del tipo FIFTEEN_MINUTES_PENDING.

### 3. Base de Datos - Schema Prisma (`schema.prisma`)

```prisma
enum ServiceOrderNotificationJobKind {
  THIRTY_MINUTES_BEFORE
  FIFTEEN_MINUTES_PENDING  // ← NUEVO
}
```

### 4. Base de Datos - Migración

Archivo: `prisma/migrations/20260329140000_add_fifteen_minutes_pending_job/migration.sql`

Agrega el nuevo valor al enum de PostgreSQL de forma segura:
```sql
ALTER TYPE "ServiceOrderNotificationJobKind" ADD VALUE 'FIFTEEN_MINUTES_PENDING' AFTER 'THIRTY_MINUTES_BEFORE';
```

## Flujo Completo

### Al crear una orden en estado PENDIENTE:
1. ✓ Se programa un trabajo FIFTEEN_MINUTES_PENDING con runAt = ahora
2. ✓ El procesador toma el trabajo y lo ejecuta inmediatamente
3. ✓ Se envía notificación a TODOS los técnicos con teléfono activo
4. ✓ Se crea automáticamente el siguiente trabajo para 15 minutos después
5. ✓ Este ciclo se repite cada 15 minutos

### Cuando la orden cambia de estado (en_proceso, finalizado, cancelado):
1. ✓ Se cancelan todos los trabajos FIFTEEN_MINUTES_PENDING pendientes
2. ✓ Las notificaciones dejan de enviarse
3. ✓ Se registra el motivo de la cancelación en la BD

## Características de la Implementación

✅ **Atomicidad**: Cada trabajo reprograma el siguiente solo después de ejecutarse exitosamente

✅ **Resilencia**: Si falla un trabajo:
- Se reintenta con backoff exponencial (1 min, 5 min, 15 min, 1 hora, 3 horas)
- Máximo 6 intentos antes de marcar como FAILED
- El siguiente trabajo se sigue reprogramando si es PENDING

✅ **Dedunicación**: Cada notificación tiene un dedupeKey único:
```
service-order:15m-pending:{orderId}:{timestamp}:{technicianId}:{phoneNumber}
```

✅ **Cancelación Automática**: Cuando orden cambien de estado, todos los trabajos se cancelan automáticamente

✅ **Logging**: Se registra en BD:
- Cada intento del trabajo
- Razón de cancelación si aplica
- Errores si ocurren

## Mensaje Enviado (Ejemplo)

```
*¡Nuevo servicio disponible!*
Cliente: Juan Pérez
Teléfono cliente: 809-555-1234
Ubicación: https://maps.google.com/?q=18.4,-69.9
Servicio: instalacion / alarma
Detalle: Instalación de sistema de alarma perimetral + 2 sensores de movimiento
Programado para: 29/03/2025 2:30 PM
Abre la app y toma la orden para iniciar el servicio.
```

## Testing

Para probar esta funcionalidad, usar el E2E test ya creado:
```bash
cd apps/api
ADMIN_EMAIL=admin@fulltech.local ADMIN_PASSWORD=<secret> \
  NOTIFICATIONS_MOCK_SUCCESS=1 \
  node scripts/e2e-notification-orders.cjs
```

El test incluye un escenario de estrés (Scenario 6) que crea 5 órdenes simultáneamente para verificar que los trabajos se crean y programan correctamente.

## Modificaciones de BD Requeridas

1. Ejecutar migración de Prisma:
```bash
cd apps/api
npx prisma migrate deploy
```

Esto agregará 'FIFTEEN_MINUTES_PENDING' al enum de PostgreSQL automáticamente.

## Performance

- **Intervalo**: 15 minutos entre notificaciones
- **Destinatarios**: Todos los técnicos con rol TECNICO y teléfono/flota activos
- **Batch processing**: El procesador puede manejar múltiples trabajos simultáneamente (límite: 10 por lote)
- **Índices**: Reutiliza índices existentes en status/runAt para búsquedas rápidas

## Consideraciones

⚠️ Si una orden permanece en estado PENDIENTE indefinidamente, seguirá enviando notificaciones cada 15 minutos. Considere agregar un máximo de repeticiones si es necesario.

⚠️ El volumen de mensajes WhatsApp aumentará significativamente. Monitorear cuota de Evolution API.

⚠️ Los dedupeKeys cambian cada 15 minutos, por lo que cada notificación se envía a todos los técnicos (intención: recordarles que hay una orden disponible).
