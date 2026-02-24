# Pruebas manuales - Módulo de Operaciones

Fecha base: 2026-02-23

## 1) Vendedor crea reserva -> aparece en tablero
1. Iniciar sesión como `VENDEDOR`.
2. Ir a `Operaciones` > pestaña `Nueva reserva`.
3. Buscar/crear cliente, completar tipo/categoría/prioridad/título/descripción y guardar.
4. Verificar en pestaña `Tablero` que la tarjeta aparece en columna `Reserva`.
5. Verificar en backend que existe registro en `ServiceUpdate` con tipo `STATUS_CHANGE` y mensaje `Reserva creada`.

## 2) Operaciones mueve a levantamiento -> técnico ve asignación
1. Iniciar sesión como `ASISTENTE` o `ADMIN`.
2. Abrir el ticket y cambiar estado a `survey`.
3. Asignar técnicos desde detalle (`Asignar técnicos`, UUIDs válidos).
4. Iniciar sesión como `TECNICO` asignado.
5. Confirmar que el ticket aparece en su tablero y no aparecen tickets de otros equipos.

## 3) Técnico marca en proceso/finalizada con evidencias
1. Como `TECNICO`, abrir ticket asignado.
2. Usar acciones rápidas: `Llegué al sitio`, `Inicié` y luego cambiar estado a `in_progress`.
3. Subir evidencia con `Subir evidencia`.
4. Marcar checklist y cambiar estado a `completed`.
5. Confirmar en historial que hay eventos `NOTE`, `STEP_UPDATE`, `FILE_UPLOAD` y `STATUS_CHANGE`.

## 4) Cliente reporta -> garantía -> resolver -> cerrado
1. Como `ASISTENTE` o `ADMIN`, abrir servicio `completed`.
2. Ejecutar `Crear garantía`.
3. Confirmar creación de ticket hijo con tipo `warranty` y vínculo `warrantyParentServiceId`.
4. Procesar garantía (`in_progress`) y finalmente `closed`.
5. Verificar logs en `ServiceUpdate` del ticket padre e hijo (`WARRANTY_CREATED`, `STATUS_CHANGE`).

## 5) Cliente con 2 servicios distintos en perfil cliente
1. Crear dos tickets para mismo cliente (ej. `installation` y `maintenance`).
2. Ir al perfil del cliente en módulo `Clientes`.
3. Verificar sección `Historial de servicios` con ambos tickets, estado y prioridad.
4. Validar que la navegación a `Operaciones` permite crear un nuevo servicio para ese cliente.

## Validaciones de reglas clave
- No permitir transición inválida (`reserved -> completed`) sin `force`.
- Si hay conflicto de agenda con instalación prioritaria, bloqueo para mantenimiento.
- `DELETE /services/:id` solo rol `ADMIN` y soft delete.
- `VENDEDOR` solo ve sus tickets; `TECNICO` solo tickets asignados; `ADMIN/ASISTENTE` ven todo.
- Cada cambio crítico genera fila en `ServiceUpdate`.
