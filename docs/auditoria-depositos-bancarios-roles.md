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

### Exitosas

- `flutter analyze` en `apps/fulltech_app`
  - sin errores del modulo de depositos
  - quedaron solo infos preexistentes en otros modulos
- `npm.cmd run build` en `apps/api`
  - ejecucion exitosa inmediatamente despues del blindaje backend
- `npm.cmd exec -- tsc -p tsconfig.build.json` en `apps/api`
  - compilacion TypeScript final exitosa

### Incidencias de entorno

- Un segundo `npm.cmd run build` finalizo con bloqueo de archivo de Prisma en Windows:
  - `EPERM ... query_engine-windows.dll.node`
  - el problema fue del entorno/local file lock durante `prisma generate`, no de tipos del codigo
  - por eso se valido el estado final del backend con `tsc` directo del paquete

### Pendientes no ejecutados en este entorno

- prueba funcional con usuario admin real
- prueba funcional con usuario asistente real
- prueba API autenticada directa como asistente para verificar `403` en:
  - editar
  - eliminar
  - ejecutar
  - rechazar/anular

## Estado final

REQUIERE AJUSTES

Motivo: el blindaje de codigo, validaciones, permisos y UI quedo implementado y validado por analisis/compilacion, pero faltan pruebas funcionales autenticadas en entorno vivo con usuarios reales para cerrar la auditoria operativa completa.