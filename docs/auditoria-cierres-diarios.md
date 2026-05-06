# Informe de auditoria - Cierres diarios

Fecha: 2026-05-05

Modulo auditado: Contabilidad / Cierres diarios

Estado: auditado, con correcciones puntuales aplicadas en Flutter.

Actualizacion 2026-05-05: se aplico modificacion controlada por roles para separar acceso completo de administracion y vista limitada de asistente. Luego se agrego vista especial de asistente con formulario lateral y correcciones trazables.

## Resumen ejecutivo

Se audito el flujo completo del modulo de cierre diario, desde la pantalla Flutter hasta la persistencia en base de datos:

- Pantalla Flutter de captura, edicion, duplicado, historial y resumen financiero.
- Controller Riverpod de cierres diarios.
- Repositorio Flutter con llamadas Dio.
- Endpoints NestJS de contabilidad.
- DTOs de validacion de cierres, transferencias, vouchers y gastos.
- Servicio backend de calculo, guardado, PDF y notificaciones.
- Esquema Prisma de `Close`, `CloseTransfer` y `CloseTransferVoucher`.

El flujo base esta bien estructurado: la UI envia el cierre al backend, el backend calcula los totales autoritativos, evita duplicados por fecha/tipo, guarda transferencias y vouchers, y ejecuta PDF/notificaciones como procesos secundarios sin romper el cierre si esas tareas fallan.

Durante la auditoria se encontraron riesgos reales en la experiencia de guardado y en la preservacion de datos de gastos al editar cierres. Se corrigieron los problemas mas directos en la pantalla Flutter.

## Archivos revisados

- `apps/fulltech_app/lib/features/contabilidad/cierres_diarios_screen.dart`
- `apps/fulltech_app/lib/features/contabilidad/application/cierres_diarios_controller.dart`
- `apps/fulltech_app/lib/features/contabilidad/data/contabilidad_repository.dart`
- `apps/fulltech_app/lib/core/models/close_model.dart`
- `apps/api/src/contabilidad/contabilidad.controller.ts`
- `apps/api/src/contabilidad/contabilidad.service.ts`
- `apps/api/src/contabilidad/close.dto.ts`
- `apps/api/prisma/schema.prisma`

## Hallazgos

### 1. Mensaje generico al confirmar cierre

Se observo en la pantalla un toast generico: "Algo salio mal. No pudimos completar la accion. Intentalo nuevamente en unos segundos.".

No se pudo reproducir el error exacto sin una sesion/API autenticada en ejecucion, pero por codigo las causas mas probables son:

- Error real del backend no mostrado directamente en el toast principal.
- Cierre duplicado para la misma fecha y tipo.
- Sesion o permisos invalidos.
- Error de red/API.
- Error de validacion en transferencias, vouchers o gastos.

Riesgo: medio.

Recomendacion: hacer que el submit principal muestre siempre el mensaje especifico devuelto por el backend, ademas de dejarlo en el estado del formulario. Esto reduce soporte y evita que el usuario vea solo un error generico.

### 2. Perdida de detalle de gastos al editar cierres

Antes de la correccion, al editar un cierre existente con gastos, la pantalla no reconstruia correctamente `expenseDetails`. Si el cierre tenia conceptos y comprobantes de gastos, el formulario podia perderlos o convertirlos en una sola linea sin concepto.

Impacto:

- Riesgo de perdida visual de comprobantes/conceptos al editar.
- Posible bloqueo de guardado por validacion de concepto requerido.
- Inconsistencia entre total de gastos y detalle enviado.

Estado: corregido.

Correccion aplicada:

- Al editar o duplicar un cierre rechazado, la pantalla restaura los `expenseDetails` existentes.
- Si el cierre antiguo solo tiene total de gastos y no detalle estructurado, se crea una linea con concepto de respaldo: `Gastos del dia`.
- Se centralizo la conversion de JSON de gastos a `_ExpenseDraft`.

### 3. Errores silenciosos en carga de vouchers de transferencia/gasto

Las cargas de vouchers de transferencias y comprobantes de gastos tenian `try/finally`, pero no `catch`. Si fallaba la subida, el usuario podia quedarse sin mensaje claro del problema.

Impacto:

- Experiencia confusa al subir archivos.
- Posibilidad de intentar confirmar una transferencia sin voucher despues de una subida fallida.

Estado: corregido.

Correccion aplicada:

- Se agregaron mensajes claros con `SnackBar` para error al subir voucher de transferencia.
- Se agregaron mensajes claros con `SnackBar` para error al subir comprobante de gasto.

### 4. Validacion de gastos y payload

La UI valida que cada gasto tenga concepto y monto mayor a cero. El payload filtra los gastos sin concepto, lo cual es seguro cuando la validacion se ejecuta correctamente.

Riesgo residual: bajo.

Recomendacion: mantener la validacion del formulario como condicion obligatoria antes de guardar. Si en el futuro se permite autoguardado o envio parcial, el payload deberia rechazar filas incompletas con error visible en vez de filtrarlas silenciosamente.

### 5. Conversion de dinero invalido a cero

La funcion `_toMoney` convierte texto invalido a `0`. Esto evita crashes, pero puede ocultar errores de digitacion si un campo admite texto no numerico.

Riesgo residual: bajo a medio, dependiendo del uso real.

Recomendacion: reforzar validadores de campos monetarios para diferenciar entre valor vacio, valor invalido y valor cero legitimo.

### 6. Totales y fuente de verdad

El backend calcula los totales autoritativos. En especial, el total de transferencias se deriva de `transfers`, no del campo `transfer` enviado por el cliente.

Estado: correcto.

Observacion importante: la UI debe mantener sincronizado el resumen visual con las entradas reales de transferencias. Actualmente el resumen se calcula desde las entradas del formulario, lo cual coincide con la logica backend.

### 7. Duplicados por fecha/tipo

El sistema valida duplicados en dos capas:

- Frontend: revisa cierres activos en el estado local.
- Backend: valida contra base de datos antes de crear.

Estado: correcto.

Riesgo residual: bajo. La validacion backend es la fuente confiable, por lo que aunque el frontend tenga informacion desactualizada, el backend protege la integridad.

### 8. PDF y notificaciones posteriores al cierre

Despues de crear el cierre, el backend intenta generar PDF y enviar notificaciones. Esas operaciones estan manejadas como mejores esfuerzos: si fallan, el cierre no se pierde.

Estado: correcto.

Observacion: este diseno es adecuado para produccion, porque evita que una falla secundaria bloquee el registro contable principal.

### 9. Permisos de cierre

El backend permite crear cierres a varios roles operativos. No se detecto un error tecnico directo, pero conviene confirmar si la politica de negocio realmente permite que todos esos roles registren cierres.

Riesgo residual: depende de la politica interna.

Recomendacion: revisar con administracion si los roles actuales son correctos para crear, editar, revisar y eliminar cierres.

## Cambios aplicados

Archivo modificado:

- `apps/fulltech_app/lib/features/contabilidad/cierres_diarios_screen.dart`

Cambios:

- Se agrego manejo de error visible al subir vouchers de transferencias.
- Se agrego manejo de error visible al subir comprobantes de gastos.
- Se corrigio la restauracion de `expenseDetails` al editar cierres.
- Se reutilizo la misma conversion de gastos al duplicar cierres rechazados.
- Se agrego respaldo para cierres legacy con total de gastos pero sin detalle estructurado.

## Modificacion controlada por roles

### Admin

Administracion mantiene acceso completo:

- Puede crear cierres.
- Puede listar el historial completo.
- Puede abrir detalle avanzado.
- Puede editar cierres pendientes.
- Puede aprobar y rechazar.
- Puede eliminar uno o varios cierres con confirmacion de contrasena.
- Puede ver resumen financiero.
- Puede exportar PDF.
- Puede generar y ver informe IA.

### Asistente

Asistente queda limitado a una operacion segura y trazable:

- Puede crear cierres diarios.
- Puede crear cierres de correccion sin modificar el cierre anterior.
- Puede subir vouchers y comprobantes necesarios para su propio cierre.
- Puede listar solo los cierres que el/ella creo.
- Solo ve historial crudo propio con fecha, categoria, monto, estado, tipo de registro, referencia corregida si aplica, creado por y fecha de creacion.
- No puede editar cierres existentes.
- No puede eliminar.
- No puede aprobar ni rechazar.
- No puede ver resumen financiero.
- No puede ver panel inteligente, IA, reportes avanzados ni PDF.
- Si se equivoca, debe crear un cierre de correccion indicando cierre anterior y motivo obligatorio.

### Proteccion backend

La restriccion no depende solo de Flutter. Se reforzaron los endpoints de `contabilidad.controller.ts` y las validaciones de `contabilidad.service.ts`:

- `POST /contabilidad/closes`: permitido para `ADMIN` y `ASISTENTE`.
- `POST /contabilidad/closes` acepta `correctionOfCloseId` y `correctionReason` para registrar correcciones trazables.
- `GET /contabilidad/closes`: permitido para `ADMIN` y `ASISTENTE`; el servicio filtra asistentes por `createdById`.
- `GET /contabilidad/closes/:id`: permitido para `ADMIN` y `ASISTENTE`; el servicio bloquea que asistentes consulten cierres de otros usuarios.
- `POST /contabilidad/closes/vouchers/upload`: permitido para `ADMIN` y `ASISTENTE`.
- `PUT /contabilidad/closes/:id`: solo `ADMIN`.
- `DELETE /contabilidad/closes/:id`: solo `ADMIN`.
- `POST /contabilidad/closes/delete-bulk`: solo `ADMIN`.
- `POST /contabilidad/closes/:id/approve`: solo `ADMIN`.
- `POST /contabilidad/closes/:id/reject`: solo `ADMIN`.
- `POST /contabilidad/closes/:id/ai-report`: solo `ADMIN`.
- `GET /contabilidad/closes/financial-summary`: solo `ADMIN`.

Los intentos sin permisos responden `403 Forbidden` con mensaje claro desde el guard de roles o desde el servicio.

La validacion de correcciones queda en backend:

- Si `correctionOfCloseId` viene informado, el cierre original debe existir.
- Si hay correccion, `correctionReason` es obligatorio.
- Un asistente solo puede corregir cierres propios.
- El cierre original no se modifica ni se sobrescribe.
- Las correcciones quedan persistidas mediante `correctionOfCloseId` y `correctionReason` en `Close`.

### Proteccion Flutter

En la pantalla de cierres diarios:

- Admin conserva el flujo actual.
- Asistente tiene una vista especial: historial crudo propio a la izquierda y formulario de registro pegado a la derecha en desktop.
- En movil, el formulario queda arriba y el historial debajo.
- El panel derecho incluye el aviso: "Debe hacer un cierre diario por categoria. Ejemplo: Tecnologia y Phytoemagry.".
- El formulario permite marcar "Este cierre corrige uno anterior", seleccionar el cierre corregido y escribir motivo obligatorio.
- El boton principal muestra "Registrar cierre" o "Registrar cierre de correccion" segun corresponda.
- Asistente no ve boton de historial avanzado.
- Asistente no entra a edicion.
- Si un asistente llega al detalle por navegacion indirecta, se muestra una vista cruda sin PDF, IA ni acciones administrativas.

## Validacion realizada

- `dart analyze` / `flutter analyze`: sin errores nuevos en el modulo.
- `get_errors` sobre `cierres_diarios_screen.dart`: sin errores.
- Build backend NestJS/Prisma/TypeScript: completado correctamente durante la auditoria.
- `dart analyze` despues del blindaje por roles: completado con los mismos 12 avisos informativos preexistentes fuera de cierres diarios.
- `npm run build` backend despues del blindaje por roles: completado correctamente.
- `dart analyze` despues de vista asistente/correcciones: completado con los mismos 12 avisos informativos preexistentes fuera de cierres diarios.
- `npm run build` backend despues de campos de correccion y validacion API: completado correctamente.

Nota: el analisis Flutter del proyecto mantiene avisos informativos existentes en otros modulos, no relacionados con cierres diarios.

## Recomendaciones siguientes

1. Mejorar el submit principal para mostrar el mensaje exacto del backend cuando falle el cierre.
2. Reforzar validacion de campos monetarios para no convertir entradas invalidas a cero silenciosamente.
3. Confirmar politica de roles para creacion, revision y eliminacion de cierres.
4. Probar manualmente con sesion real estos escenarios:
   - Crear cierre sin transferencias ni gastos.
   - Crear cierre con transferencia y voucher obligatorio.
   - Crear cierre con gastos y comprobantes opcionales.
   - Editar cierre con `expenseDetails` existentes.
   - Duplicar cierre rechazado.
   - Intentar crear duplicado por misma fecha/tipo.

## Conclusion

El modulo de cierre diario tiene una arquitectura correcta y una separacion sana entre UI, estado, repositorio, backend y base de datos. La fuente de verdad de totales esta en backend, lo cual es adecuado para contabilidad.

Los problemas mas importantes encontrados estaban en la experiencia Flutter al editar gastos y al subir vouchers. Esos puntos ya fueron corregidos. El riesgo restante mas visible es el mensaje generico al confirmar cierre, que debe mejorarse para mostrar la causa exacta cuando el backend rechaza o falla la operacion.