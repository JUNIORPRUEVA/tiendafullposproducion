# AUDITORÍA: Pantalla Cierres Diarios - Cargamento Infinito

**Fecha**: 13/5/2026  
**Pantalla**: `cierres_diarios_screen.dart`  
**Módulo**: Contabilidad

---

## 🔍 SÍNTOMAS REPORTADOS

- Pantalla se queda en estado de cargamento (`loading = true`)
- No termina de cargar los cierres
- Interfaz congelada en indicador de progreso

---

## 📊 ESTRUCTURA DE CARGA

```
┌─ CierresDiariosScreen (ConsumerStatefulWidget)
│
├─ _CierresDiariosScreenState
│  ├─ cierresDiariosControllerProvider (Riverpod)
│  │  └─ CierresDiariosController (StateNotifier)
│  │     ├─ load() → INICIA EN CONSTRUCTOR
│  │     └─ refresh() → LLAMADO EN BUILD
│  │
│  └─ build()
│     ├─ watch(cierresDiariosControllerProvider) [OBSERVA ESTADO]
│     ├─ if (currentUserId != _lastLoadedUserId) → LLAMA refresh()
│     ├─ if (isAssistant && empty && !loading) → LLAMA refresh()
│     └─ RefreshIndicator.onRefresh → LLAMA controller.refresh()
│
└─ _HistoryFullScreenPage (Admin)
   └─ _HistoryFullScreenPageState
      ├─ initState()
      │  ├─ _setSummaryPreset(_FinancialSummaryPreset.hoy)
      │  └─ _fetchSummary() [ASYNC POST-FRAME]
      │
      └─ build()
         ├─ watch(cierresDiariosControllerProvider) [OBSERVA ESTADO]
         ├─ LinearProgressIndicator if state.loading
         └─ historyList() [RENDERIZA CIERRES]
```

---

## ⚠️ PROBLEMAS IDENTIFICADOS

### 1. **REINTENTO AUTOMÁTICO EN BUILD (Admin)**

**Ubicación**: `_HistoryFullScreenPageState.build()` línea 3051

```dart
final state = ref.watch(cierresDiariosControllerProvider);
// Si state.loading = true, el build se re-ejecuta constantemente
// porque Riverpod notifica cambios de estado
```

**Riesgo**: Si `load()` en el controlador NUNCA completa o siempre lanza error + reintenta, 
entrará en loop infinito.

---

### 2. **MÚLTIPLES PUNTOS DE TRIGGER DE CARGA (Pantalla Asistente)**

**Ubicación**: `_CierresDiariosScreenState.build()` líneas 270-300

```dart
// 1. Si cambia userId → refresh()
if (currentUserId != _lastLoadedUserId) {
  _lastLoadedUserId = currentUserId;
  WidgetsBinding.instance.addPostFrameCallback((_) {
    controller.refresh();
  });
}

// 2. Si está vacío y es asistente → refresh()
if (isAssistant &&
    !state.loading &&
    state.error == null &&
    state.closes.isEmpty &&
    !_assistantEmptyReloadRequested) {
  _assistantEmptyReloadRequested = true;
  WidgetsBinding.instance.addPostFrameCallback((_) {
    controller.refresh();
  });
}
```

**Riesgo**: Si `refresh()` completa pero retorna `[]` (vacío), el siguiente rebuild 
ejecutará el 2º if de nuevo, disparando refresh() nuevamente → LOOP INFINITO.

---

### 3. **FETCH DE RESUMEN FINANCIERO SIN VALIDACIÓN (Admin)**

**Ubicación**: `_HistoryFullScreenPageState.initState()` línea 2268

```dart
WidgetsBinding.instance.addPostFrameCallback((_) {
  if (!mounted) return;
  _fetchSummary(); // SIN MANEJO DE ERRORES SILENCIOSOS
});
```

**Ubicación**: `_fetchSummary()` línea 2482

```dart
Future<void> _fetchSummary() async {
  if (!_isAdmin) return;

  final from = _summaryFromDate ?? DateTime.now();
  final to = _summaryToDate ?? from;

  setState(() {
    _summaryLoading = true;
    _summaryError = null;
  });

  try {
    final summary = await ref
        .read(contabilidadRepositoryProvider)
        .getCloseFinancialSummary(
          fromDate: from,
          toDate: to,
          businessType: _summaryBusinessType,
        );
    // ... ACTUALIZA _summary
  } catch (e) {
    setState(() {
      _summaryError = e.toString(); // CAPTURE ERROR pero NO hace reintento
    });
  } finally {
    setState(() {
      _summaryLoading = false;
    });
  }
}
```

**Riesgo**: Si la petición `/contabilidad/closes/financial-summary` FALLA, el error 
se captura pero `_summaryLoading` se vuelve `false`, impidiendo que el admin vea 
que hay un problema.

---

### 4. **EL CONTROLADOR NUNCA LIMPIA `loading = false` CON ERROR SILENCIOSO**

**Ubicación**: `CierresDiariosController.load()` línea 87

```dart
Future<void> load() async {
  state = state.copyWith(loading: true, clearError: true);
  try {
    final rows = await ref
        .read(contabilidadRepositoryProvider)
        .listCloses(from: state.from, to: state.to, type: null);

    state = state.copyWith(loading: false, closes: rows);
  } catch (e) {
    final message = e is ApiException
        ? e.message
        : 'No se pudieron cargar los cierres';
    state = state.copyWith(loading: false, error: message);
  }
}
```

**Análisis**: El try/catch se ve correcto. PERO...

**Riesgo**: Si `listCloses()` hace una petición HTTP que:
- Está pendiente indefinidamente (timeout very large)
- El servidor no responde
- Hay un deadlock en Prisma

Entonces `await` NUNCA completa, y `loading` nunca se vuelve `false`.

---

### 5. **SIN TIMEOUT EN LA PETICIÓN HTTP**

**Ubicación**: `ContabilidadRepository.listCloses()` línea 119

```dart
Future<List<CloseModel>> listCloses({
  required DateTime from,
  required DateTime to,
  CloseType? type,
}) async {
  try {
    final res = await _dio.get(
      ApiRoutes.contabilidadCloses,
      queryParameters: {
        'from': _dateOnly(from),
        'to': _dateOnly(to),
        if (type != null) 'type': type.apiValue,
      },
    );
    // SIN OPTIONS -> SIN TIMEOUT
```

**Riesgo**: Si el backend está lento o caído, la petición esperará indefinidamente.

---

### 6. **BACKEND: QUERY LENTA O DEADLOCK**

**Ubicación**: `ContabilidadService.getCloses()` línea 864

```typescript
return this.prisma.close.findMany({
  where,
  orderBy: [{ date: 'desc' }, { createdAt: 'desc' }],
  include: {
    transfers: {
      include: { vouchers: true },
      orderBy: { createdAt: 'asc' },
    },
  },
});
```

**Riesgo**: Si hay muchos registros y no hay índices:
- JOIN con `transfers` puede ser muy lento
- JOIN con `vouchers` dentro de transfers puede ser N+1
- Pudiera estar bloqueado por una transacción

---

## ✅ DIAGNÓSTICO RECOMENDADO

### Paso 1: Verificar conectividad y logs
```bash
# En backend
npm run logs  # Ver si hay errores en contabilidad.service.ts
```

### Paso 2: Probar endpoint directamente
```bash
curl -H "Authorization: Bearer <TOKEN>" \
  "https://api.fulltech.local/contabilidad/closes?from=2026-05-01&to=2026-05-31"
```

### Paso 3: Revisar tiempos de respuesta
- ¿El backend responde en < 5 segundos?
- ¿La BD está lenta?

### Paso 4: Verificar índices de BD
```sql
SELECT * FROM "Close" WHERE date BETWEEN '2026-05-01' AND '2026-05-31';
EXPLAIN ANALYZE ... -- Ver plan de ejecución
```

---

## 🔧 SOLUCIONES PROPUESTAS

### 1. **Agregar timeout a la petición HTTP**

**Archivo**: `contabilidad_repository.dart`

```dart
Future<List<CloseModel>> listCloses({
  required DateTime from,
  required DateTime to,
  CloseType? type,
}) async {
  try {
    final res = await _dio.get(
      ApiRoutes.contabilidadCloses,
      queryParameters: {
        'from': _dateOnly(from),
        'to': _dateOnly(to),
        if (type != null) 'type': type.apiValue,
      },
      options: Options(
        receiveTimeout: const Duration(seconds: 30),
        sendTimeout: const Duration(seconds: 10),
      ),
    ).timeout(
      const Duration(seconds: 35),
      onTimeout: () => throw ApiException('Tiempo agotado al cargar cierres'),
    );
```

### 2. **Evitar reintento infinito en caso de lista vacía**

**Archivo**: `_cierres_diarios_screen.dart` línea 290

```dart
// ANTES (problematico):
if (isAssistant &&
    !state.loading &&
    state.error == null &&
    state.closes.isEmpty &&
    !_assistantEmptyReloadRequested) {
  _assistantEmptyReloadRequested = true;
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!mounted) return;
    controller.refresh();
  });
}

// DESPUES (corregido):
// Solo reintentar UNA VEZ, no indefinidamente
// Si la lista sigue vacía después del reintento, no volver a intentar
```

### 3. **Agregar timeout a _fetchSummary()**

**Archivo**: `_cierres_diarios_screen.dart` línea 2482

```dart
Future<void> _fetchSummary() async {
  if (!_isAdmin) return;

  setState(() {
    _summaryLoading = true;
    _summaryError = null;
  });

  try {
    final summary = await ref
        .read(contabilidadRepositoryProvider)
        .getCloseFinancialSummary(...)
        .timeout(
          const Duration(seconds: 20),
          onTimeout: () => throw TimeoutException('Resumen financiero tardó mucho'),
        );
    // ...
  } catch (e) {
    // ...
  }
}
```

### 4. **Verificar y agregar índices en BD**

**Archivo**: `prisma/schema.prisma`

```prisma
model Close {
  // ...
  @@index([date])
  @@index([createdById])
  @@index([date, type])
  @@index([createdById, date])
}
```

### 5. **Optimizar query en backend**

**Archivo**: `contabilidad.service.ts`

```typescript
// AGREGAR PAGINACIÓN si hay muchos registros
return this.prisma.close.findMany({
  where,
  orderBy: [{ date: 'desc' }, { createdAt: 'desc' }],
  include: {
    transfers: {
      include: { vouchers: true },
      orderBy: { createdAt: 'asc' },
    },
  },
  take: 500, // Limitar a últimos 500 cierres
  skip: 0,
});
```

---

## 📋 RESUMEN DE CAUSAS POSIBLES

| **Causa** | **Probabilidad** | **Impacto** |
|-----------|-----------------|-----------|
| Backend no responde / timeout | 🔴 ALTA | Cargamento infinito |
| Loop infinito en reintento (lista vacía) | 🟡 MEDIA | Cargamento indefinido |
| Query Prisma muy lenta | 🟡 MEDIA | Cargamento lento → infinito perceptivamente |
| Sin timeout en HTTP | 🟡 MEDIA | Espera indefinida |
| Deadlock en BD | 🟠 BAJA | Cuelga total |

---

## 📝 PRÓXIMOS PASOS

1. **Implementar timeouts** en todas las peticiones HTTP
2. **Eliminar loop de reintento** en caso de lista vacía
3. **Añadir índices de BD** para optimizar queries
4. **Poner paginación** en endpoint de cierres si hay >1000 registros
5. **Logging detallado** para debuggear qué está pasando en backend

