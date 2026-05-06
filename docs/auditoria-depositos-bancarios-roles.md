# Auditoria de Depositos Bancarios por Roles

## Archivos modificados

- apps/api/prisma/schema.prisma
- apps/api/src/contabilidad/deposit-order.dto.ts
- apps/api/src/contabilidad/contabilidad.controller.ts
- apps/api/src/contabilidad/contabilidad.service.ts
- apps/fulltech_app/lib/core/api/api_routes.dart
- apps/fulltech_app/lib/features/contabilidad/data/contabilidad_repository.dart
- apps/fulltech_app/lib/features/contabilidad/models/deposit_order_model.dart
- apps/fulltech_app/lib/features/contabilidad/depositos_bancarios_screen.dart

## Brechas encontradas

1. El deposito ejecutado podia editarse o borrarse sin proteccion fuerte en backend.
2. El asistente podia ver la pantalla completa, pero el backend no restringia por propietario en listado y detalle.
3. El flujo de voucher y ejecucion estaba mezclado: subir voucher marcaba el deposito como ejecutado sin aprobacion explicita.
4. No existia anulado auditado con motivo obligatorio ni soft delete para registros sensibles.
5. No existia soporte de correcciones vinculadas al deposito original.
6. La UI mostraba "Ejecuto" aun cuando el deposito seguia pendiente.
7. Faltaban filtros operativos claros para admin: pendientes, ejecutados, anulados y correcciones.
8. El backend no validaba integralmente ventana de fechas, suma por tipo, banco/cuenta y colaborador.

## Correcciones aplicadas

### Backend

- Se reforzo el esquema de `DepositOrder` con trazabilidad adicional:
  - `correctionOfDepositOrderId`
  - `correctionReason`
  - `deletedAt`
  - `deletedById`
  - `deletedByName`
  - `deletedReason`
- Se agrego validacion de negocio para depositos:
  - monto total mayor a cero
  - `windowFrom <= windowTo`
  - suma de `depositByType` igual a `depositTotal`
  - banco y cuenta validos contra el catalogo actual del modulo
  - colaborador valido en usuarios del sistema
  - cuentas por tipo alineadas con los montos por tipo
- Se separo el flujo de voucher del flujo de ejecucion:
  - subir voucher ya no ejecuta automaticamente
  - ejecutar/aprobar exige voucher previo
- Se limito la visibilidad del asistente a sus propios depositos en listado y detalle.
- Se bloqueo la edicion de depositos que no esten pendientes.
- Se elimino el borrado fisico operativo:
  - el endpoint delete ahora rechaza la eliminacion fisica
  - la anulacion real se hace por flujo auditado con motivo obligatorio
- Se agrego flujo de correccion vinculado al deposito original.

### Frontend

- La pantalla existente se mantuvo y se reorganizo por rol.
- Se corrigio la semantica visual del responsable:
  - pendiente: solicitado por
  - ejecutado: ejecutado por
  - anulado: anulado por
- Se agregaron filtros visibles:
  - Todos
  - Pendientes
  - Ejecutados
  - Rechazados/Anulados
  - Correcciones
- Se agrego aviso superior para asistente con la regla de no modificar registros anteriores.
- Se reemplazo la accion de eliminar por anular con motivo obligatorio.
- Se agregaron acciones admin sobre el mismo modulo actual:
  - subir voucher
  - ejecutar/aprobar
  - rechazar/anular
  - crear correccion
- Se enriquecio el detalle con:
  - solicitante
  - colaborador
  - ejecutor
  - anulador
  - motivo de anulacion
  - referencia de correccion
  - motivo de correccion

## Endpoints protegidos

- `POST /contabilidad/deposit-orders`
  - Admin y Asistente
  - permite correcciones vinculadas con motivo
- `GET /contabilidad/deposit-orders`
  - Admin ve todos
  - Asistente solo ve los suyos
- `GET /contabilidad/deposit-orders/:id`
  - Admin ve cualquiera
  - Asistente solo ve los suyos
- `PUT /contabilidad/deposit-orders/:id`
  - solo Admin
  - solo para pendientes no anulados
  - no permite cambiar estado, voucher ni correccion por esta via
- `POST /contabilidad/deposit-orders/:id/voucher`
  - solo Admin
  - adjunta voucher sin ejecutar automaticamente
  - bloqueado si el deposito ya fue ejecutado o anulado
- `POST /contabilidad/deposit-orders/:id/approve`
  - solo Admin
  - requiere voucher
  - ejecuta el deposito y sella ejecutor/fecha
- `POST /contabilidad/deposit-orders/:id/cancel`
  - solo Admin
  - requiere motivo obligatorio
  - bloqueado si el deposito ya fue ejecutado
- `DELETE /contabilidad/deposit-orders/:id`
  - solo Admin
  - ahora rechaza borrado fisico para preservar trazabilidad

## Pruebas realizadas

### Exitosas — sesion de blindaje controlado (Mayo 2026)

- `flutter analyze` — `apps/fulltech_app`
  - sin errores en ningun archivo del modulo de depositos
  - archivos verificados:
    - `depositos_bancarios_screen.dart` — sin errores
    - `data/contabilidad_repository.dart` — sin errores
    - `models/deposit_order_model.dart` — sin errores
- `npm.cmd exec -- tsc -p tsconfig.build.json --noEmit` en `apps/api`
  - compilacion TypeScript sin errores
  - archivos verificados:
    - `contabilidad.controller.ts` — sin errores
    - `contabilidad.service.ts` — sin errores
    - `deposit-order.dto.ts` — sin errores
- Prisma schema auditado — todos los campos requeridos presentes:
  - `correctionOfDepositOrderId`, `correctionReason`
  - `deletedAt`, `deletedById`, `deletedByName`, `deletedReason`
  - `executedAt`, `executedById`, `executedByName`
  - `createdById`, `createdByName`
  - indices en `status`, `createdById`, `correctionOfDepositOrderId`, `deletedById`

### Comportamiento verificado por analisis de codigo

| Endpoint | Admin | Asistente |
|---|---|---|
| POST /deposit-orders | PERMITIDO | PERMITIDO (solo pendiente) |
| GET /deposit-orders | VE TODOS | SOLO LOS SUYOS (filtro por createdById) |
| GET /deposit-orders/:id | CUALQUIERA | SOLO LOS SUYOS (403 si no es dueno) |
| PUT /deposit-orders/:id | SOLO ADMIN + SOLO PENDIENTES | 403 (ADMIN-only @Roles) |
| POST /deposit-orders/:id/approve | SOLO ADMIN + REQUIERE VOUCHER | 403 |
| POST /deposit-orders/:id/cancel | SOLO ADMIN + MOTIVO OBLIGATORIO | 403 |
| POST /deposit-orders/:id/voucher | SOLO ADMIN | 403 |
| DELETE /deposit-orders/:id | SOLO ADMIN + RECHAZA BORRADO FISICO | 403 |

### UI verificada por analisis de codigo

- `_isAdmin` controla visibilidad de botones administrativos en tiles y detalle
- `_isAssistant` muestra `_AssistantNoticeCard` con aviso normativo
- Tile muestra semantica correcta del responsable segun estado:
  - pendiente → "Solicitado por" (createdByName)
  - ejecutado → "Ejecutado por" (executedByName)
  - anulado → anulador o creador
- Filtros visibles: Todos, Pendientes, Ejecutados, Rechazados/Anulados, Correcciones
- Detalle muestra: solicitante, colaborador, ejecutor, anulador, motivo anulacion, correccion vinculada
- Anulacion requiere motivo obligatorio con validacion en dialog
- Ejecutar requiere voucher previo (guarda a `item.hasVoucher`)
- PDF y visualizacion de voucher sin cambios (funcionalidad preservada)

### Pendientes de prueba en entorno vivo

- prueba funcional con usuario admin real
- prueba funcional con usuario asistente real
- prueba API autenticada directa como asistente para confirmar 403 en endpoints prohibidos

## Estado final

APROBADO — CODIGO

El modulo de Depositos Bancarios cumple todos los requerimientos de blindaje controlado:
- Inmutabilidad de ejecutados: IMPLEMENTADA (backend bloquea update/delete si no PENDING)
- Soft delete auditado: IMPLEMENTADO (deletedAt/By/Reason en lugar de borrado fisico)
- Correcciones vinculadas: IMPLEMENTADAS (correctionOfDepositOrderId + correctionReason)
- Permisos Admin/Asistente: SEPARADOS (ADMIN-only en @Roles del controller + filtro en service)
- Validaciones backend: ACTIVAS (monto > 0, windowFrom <= windowTo, voucher para ejecutar, motivo para anular)
- UI por rol: IMPLEMENTADA (filtros, semantica, aviso asistente, botones admin condicionales)
- Trazabilidad completa: IMPLEMENTADA (quien creo, quien ejecuto, cuando, quien anulo, motivo)
- Analisis/compilacion: SIN ERRORES (flutter analyze + tsc --noEmit pasaron limpio)

Queda pendiente la validacion funcional en entorno vivo con usuarios reales para cerrar APROBADO OPERATIVO.