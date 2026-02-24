# Ventas - Pruebas manuales mínimas

## 1) Aislamiento por usuario
- Iniciar sesión como Usuario A.
- Crear una venta.
- Iniciar sesión como Usuario B y llamar `GET /sales` en el mismo rango.
- **Esperado:** la venta de A no aparece para B.

## 2) Venta no editable
- Intentar `PATCH /sales/:id` o `PUT /sales/:id`.
- **Esperado:** endpoint no existe / método no permitido.

## 3) Comisión cuando utilidad negativa
- Crear venta con item donde `priceSoldUnit < costUnitSnapshot` (fuera de inventario).
- Revisar respuesta y `GET /sales/summary`.
- **Esperado:** `totalProfit` negativo permitido y `commissionAmount` = `0`.

## 4) Fuera de inventario
- Crear venta con item sin `productId`, enviando `productName`, `qty`, `costUnitSnapshot`, `priceSoldUnit`.
- **Esperado:** venta creada correctamente con snapshots guardados.

## 5) Delete solo owner
- Usuario A crea venta.
- Usuario B intenta `DELETE /sales/:id`.
- **Esperado:** `403 Forbidden`.
- Usuario A elimina su venta.
- **Esperado:** `ok: true` y venta marcada con `isDeleted=true`, `deletedAt`, `deletedById`.
