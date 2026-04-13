# Smoke test manual - Módulo Clientes

Checklist sugerido para validar el flujo completo:

1. Abrir el menú lateral (Drawer) y entrar a **Clientes**.
2. Verificar estado vacío inicial y usar el botón **Nuevo cliente**.
3. Crear cliente con `nombre` y `telefono` válidos.
4. Confirmar que aparece en la lista.
5. Abrir detalle del cliente y validar datos (teléfono, correo, dirección).
6. Editar cliente desde lista o detalle y guardar cambios.
7. Validar que el listado refleja la edición.
8. Intentar crear otro cliente con el mismo teléfono y verificar bloqueo de duplicado.
9. Probar búsqueda en AppBar por nombre y por teléfono.
10. Abrir filtros y validar:
   - Orden A-Z / Z-A
   - Todos / Con correo / Sin correo
   - Activos / Eliminados / Todos
11. Abrir el botón **Mapa** al lado del filtro y validar:
   - Leyenda verde / amarillo / rojo
   - Conteo de ubicaciones y tarjetas resumen
   - Tap en un punto del mapa abre el detalle del cliente
12. Eliminar cliente y confirmar diálogo de advertencia.
13. Validar mensaje de éxito y actualización de lista.
