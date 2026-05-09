================================================================================
ARQUITECTURA NUEVA DEL MÓDULO "ESTADOS" — FLUJO CONTROLADO Y PROFESIONAL
================================================================================

📋 PROBLEMA ANTERIOR
================================================================================
- La IA elegía automáticamente la imagen final
- No había control del usuario sobre la selección
- Generación automática sin aprobación visual
- Diseños genéricos sin personalización

================================================================================
✅ SOLUCIÓN NUEVA — 3 FASES BIEN DEFINIDAS
================================================================================

┌──────────────────────────────────────────────────────────────────────────┐
│ FASE 1: SELECCIÓN DE IMAGEN (Usuario elige)                            │
├──────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│ PANTALLA DIVIDIDA EN 2 COLUMNAS:                                       │
│                                                                          │
│ ┌─ IZQUIERDA (60%) ─────────────────┐  ┌─ DERECHA (40%) ──────────────┐
│ │ GALERÍA DE IMÁGENES               │  │ PANEL DE ANÁLISIS IA         │
│ │                                   │  │                              │
│ │ • Búsqueda rápida                │  │ "Selecciona una imagen"      │
│ │ • Filtros por categoría          │  │                              │
│ │ • Grid elegante                   │  │ [Instrucciones iniciales]   │
│ │ • Thumbnails profesionales       │  │                              │
│ │ • Información del producto        │  │                              │
│ │ • Ordenamiento inteligente        │  │ • Tipo de producto         │
│ │                                   │  │ • Recomendación IA         │
│ │ FUENTES:                         │  │ • Reasons                   │
│ │ ✓ Productos empresa              │  │ • Score de calidad         │
│ │ ✓ Galería publicidad             │  │ • Ángulo sugerido          │
│ │ ✓ Contenido subido               │  │ • Historial de uso         │
│ │ ✓ Publicado anteriormente        │  │                              │
│ │ ✓ Evidencias reales              │  │ [Botón: GENERAR CONTENIDO] │
│ │ ✓ Videos/imágenes sistema        │  │ (deshabilitado hasta sel.)  │
│ │                                   │  │                              │
│ └───────────────────────────────────┘  └──────────────────────────────┘
│                                                                          │
│ USUARIO INTERACCIÓN:                                                   │
│ 1. Abre modal de Estados                                               │
│ 2. Ve galería profesional                                              │
│ 3. Busca/filtra imágenes                                               │
│ 4. SELECCIONA UNA IMAGEN (click)                                       │
│                                                                          │
└──────────────────────────────────────────────────────────────────────────┘


┌──────────────────────────────────────────────────────────────────────────┐
│ FASE 2: ANÁLISIS IA Y CONFIRMACIÓN                                      │
├──────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│ CUANDO EL USUARIO SELECCIONA UNA IMAGEN:                               │
│                                                                          │
│ 1. Frontend llama API:                                                  │
│    POST /marketing/media-assets/analyze                                │
│    {                                                                   │
│      mediaAssetIds: ["uuid-elegida"],                                 │
│      storyType: "sales" | "trust" | "educational"                    │
│    }                                                                   │
│                                                                          │
│ 2. Backend ejecuta MarketingImageAnalyzerService:                      │
│    • Obtiene asset de base de datos                                    │
│    • Calcula score de calidad (0-100)                                 │
│    • Evalúa:                                                           │
│      - Iluminación                                                     │
│      - Claridad del producto                                           │
│      - Calidad del background                                          │
│      - Historial de uso                                                │
│      - Impacto de conversión                                           │
│    • Genera recomendación personalizada                                │
│    • Retorna ImageAnalysisResult                                       │
│                                                                          │
│ 3. Frontend muestra resultado en DERECHA:                              │
│    ✓ Preview grande de imagen                                         │
│    ✓ Score visual (0-100) con barra de progreso                       │
│    ✓ Recomendación: "Excelente para confianza y ventas"              │
│    ✓ Razones específicas (bullets)                                    │
│    ✓ Ángulo sugerido: "Énfasis en seguridad profesional"             │
│    ✓ Estimado: "+15% conversión"                                      │
│    ✓ Historial: 8 usos, 2.4K impresiones, 12% CTR                    │
│                                                                          │
│ USUARIO INTERACCIÓN:                                                   │
│ • Ve análisis completo de la imagen elegida                           │
│ • Revisa recomendaciones IA                                            │
│ • Puede cambiar imagen (volver a FASE 1)                              │
│ • O confirmar para generar contenido (→ FASE 3)                       │
│                                                                          │
└──────────────────────────────────────────────────────────────────────────┘


┌──────────────────────────────────────────────────────────────────────────┐
│ FASE 3: GENERACIÓN IA (SOLO DESPUÉS DE CONFIRMAR)                       │
├──────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│ CUANDO EL USUARIO HACE CLICK EN "GENERAR CONTENIDO":                   │
│                                                                          │
│ Backend recibe:                                                         │
│ • mediaAssetId: imagen elegida por usuario (NO CAMBIAR)               │
│ • storyType: sales | trust | educational                              │
│ • companyId, userId, date                                             │
│                                                                          │
│ Backend genera (BASADO EN LA IMAGEN ELEGIDA):                         │
│                                                                          │
│ 1. Análisis de imagen elegida:                                         │
│    • Tipo de producto detectado                                        │
│    • Características visuales                                          │
│    • Ángulo de composición                                             │
│                                                                          │
│ 2. Cruce de datos:                                                      │
│    • Investigación activa (tendencias locales)                        │
│    • Tipo de cliente objetivo                                          │
│    • Historial de contenido exitoso                                   │
│                                                                          │
│ 3. Generación de contenido:                                            │
│    ✓ Headline (corto y punzante)                                      │
│    ✓ Descripción corta (para estado)                                  │
│    ✓ Descripción larga (para marketplace)                             │
│    ✓ Hashtags relevantes                                              │
│    ✓ CTA optimizado                                                   │
│    ✓ Texto Facebook                                                   │
│    ✓ Texto Instagram                                                  │
│    ✓ Texto Marketplace                                                │
│    ✓ Idea para Reel (con hook)                                        │
│    ✓ Variaciones (3+ opciones)                                        │
│                                                                          │
│ 4. Generación de DISEÑO (NO CAMBIAR IMAGEN):                          │
│    ✓ Mejorar iluminación                                              │
│    ✓ Mejorar composición                                              │
│    ✓ Agregar overlay/branding                                         │
│    ✓ Agregar CTA visual                                               │
│    ✓ Agregar textos superpuestos                                      │
│    ✓ Estilo: Moderno, premium, elegante, minimalista                  │
│                                                                          │
│ 5. Almacenar:                                                           │
│    • Story creado (pending)                                            │
│    • mediaAssetId: id elegido por usuario                             │
│    • generatedImageUrl: imagen con diseño (NO PRODUCTO MODIFICADO)    │
│    • Metadata: referencia a imagen base                               │
│                                                                          │
│ RESULTADO:                                                              │
│ ✓ Estado profesional listo para publicar                              │
│ ✓ Basado en imagen REAL elegida                                       │
│ ✓ SIN cambiar producto/marca/modelo                                   │
│ ✓ Diseño moderno y premium                                            │
│ ✓ Contenido optimizado para plataforma                                │
│                                                                          │
└──────────────────────────────────────────────────────────────────────────┘

================================================================================
🏗️ ARQUITECTURA TÉCNICA (BACKEND)
================================================================================

NEW SERVICE: MarketingImageAnalyzerService
────────────────────────────────────────

analyzeMediaAsset(mediaAssetId: string, companyId: string)
├─ Obtiene asset de BD
├─ Calcula calidad (0-100)
│  ├─ Iluminación: +20 si profesional, +12 si buena, +5 si aceptable
│  ├─ Claridad: +15 si >85, +10 si >70, +5 si >55
│  ├─ Background: +10 si profesional, +5 si aceptable
│  ├─ Recencia: +8 si <7 días, -5 si >90 días
│  └─ Featured bonus: +5
├─ Determina story types óptimos
│  ├─ Si score >= 75: ['trust', 'sales']
│  ├─ Si score >= 60: ['sales']
│  └─ Si score >= 55: ['educational']
├─ Genera recomendación personalizada
├─ Calcula lift de conversión estimado
├─ Retorna ImageAnalysisResult completo
└─ Return: {
  mediaAssetId, fileUrl, category, productType,
  visualQuality, qualityScore,
  recommendation, recommendationReason,
  bestForStoryTypes, estimatedConversionLift,
  suggestedAngle, lightingQuality, productClarityScore,
  backgroundQuality, usageHistory
}

rankMediaAssets(mediaAssetIds: string[], storyType: string)
├─ Analiza todos los assets
├─ Rankea por relevancia a storyType + calidad
└─ Return: ImageAnalysisResult[] (ordenado mejor-a-peor)


NEW ENDPOINT: POST /marketing/media-assets/analyze
────────────────────────────────────────────────

Request:
{
  mediaAssetIds: ["uuid1", "uuid2"],
  storyType: "sales" | "trust" | "educational"
}

Response:
{
  storyType: "sales",
  analysisCount: 2,
  ranked: [ImageAnalysisResult[], // mejor a peor
  recommended: ImageAnalysisResult // top 1
}


MODIFIED ENDPOINT: POST /marketing/stories/generate-missing
────────────────────────────────────────────────────────

Request CAMBIO (ahora OBLIGATORIO):
{
  date: "2026-05-09",
  selected_media_asset_ids: ["uuid-elegida"]  // ← OBLIGATORIO
}

Backend CAMBIO:
├─ Valida que selected_media_asset_ids tiene exactamente 1 ID
├─ Para cada story type (sales, trust, educational):
│  ├─ Usa SOLO la imagen elegida (NO SELECTOR)
│  ├─ Genera contenido basado en:
│  │  ├─ Imagen elegida
│  │  ├─ Investigación activa
│  │  ├─ Story type específico
│  │  └─ Contexto comercial
│  ├─ mediaSelector.select() usa preferredAssetIds = [elegida]
│  ├─ Crea story con imageUrl = elegida
│  └─ Encola job de image generation
└─ Return: [MarketingStory] con mediaAssetId = elegida

================================================================================
🎨 UI/UX IMPLEMENTACIÓN (FLUTTER)
================================================================================

NEW SCREEN: EstadosNuevoFlujoScreen
─────────────────────────────────────

Arguments:
- initialStoryType: 'sales' | 'trust' | 'educational'
- onGenerateConfirmed: Future<void> Function(String selectedImageId)

State:
- _selectedStoryType: string
- _selectedImageId: string | null
- _selectedImageAnalysis: ImageAnalysisResult | null
- _analyzing: bool
- _generating: bool
- _filterCategory: string | null
- _searchQuery: string

UI Layout (2-column):
┌─────────────────────────────────────────────────┐
│ AppBar: "Generar Estado"                        │
├─────────────────────────────────────────────────┤
│ Story Type Filter: [Sales] [Trust] [Educational]│
├─────────────────────────────────────────────────┤
│                                                 │
│ ┌──────────────────┐ │ ┌────────────────────┐   │
│ │ GALERÍA (60%)    │ │ │ PANEL IA (40%)     │   │
│ │                  │ │ │                    │   │
│ │ Buscar...        │ │ │ [Preview Imagen]   │   │
│ │ [Categorías]     │ │ │                    │   │
│ │                  │ │ │ ⭐ Score: 85/100   │   │
│ │ [Grid 2x]        │ │ │                    │   │
│ │ [Imagen elegida] │ │ │ 💡 Recomendación  │   │
│ │ con checkmark    │ │ │ • Razón 1          │   │
│ │                  │ │ │ • Razón 2          │   │
│ │                  │ │ │                    │   │
│ │                  │ │ │ 🎯 Ángulo: ...    │   │
│ │                  │ │ │                    │   │
│ │                  │ │ │ 📊 Historial       │   │
│ │                  │ │ │                    │   │
│ │                  │ │ │ [GENERAR CONTENIDO]│   │
│ └──────────────────┘ │ └────────────────────┘   │
│                                                 │
└─────────────────────────────────────────────────┘

Flujo de Interacción:
1. Usuario abre pantalla
2. Ve galería profesional (izquierda vacía, derecha con instrucciones)
3. Selecciona imagen
4. Derecha muestra análisis IA (loading → resultado)
5. Usuario revisa análisis
6. Usuario hace click en "GENERAR CONTENIDO"
7. Backend genera todo
8. Se cierra modal y vuelve a States view

================================================================================
📱 DIFERENCIAS CON SISTEMA ANTERIOR
================================================================================

ANTES                                AHORA
─────────────────────────────────────────────────────────────────────────
❌ IA elige imagen automática         ✅ Usuario ELIGE imagen obligatoria
❌ Sin control visual                 ✅ Panel análisis profesional
❌ Generación sin aprobación          ✅ Confirmación antes de generar
❌ UI simple                          ✅ UI moderna 2 columnas
❌ Dialog pequeño                     ✅ Full-screen optimizado
❌ Sin recomendaciones                ✅ IA recomienda CON razones
❌ Genera automáticamente             ✅ ESPERA confirmación usuario
❌ Sin score de calidad               ✅ Score visual 0-100
❌ Sin ángulo sugerido                ✅ Content angle personalizado
❌ Sin historial visualizado          ✅ Uso y conversión visible

================================================================================
🔄 EJEMPLO REAL DE USO
================================================================================

PASO 1: Usuario abre "Generar Estado"
┌─────────────────────┐
│ Publicidad          │
│ ────────────────    │
│ [+ Nueva Investi]   │
│ [Estados (5)]       │
│                     │
│ Click: "Generar"    │
└─────────────────────┘

PASO 2: Se abre EstadosNuevoFlujoScreen
┌─────────────────────────────────────┐
│ Generar Estado                      │
├─ [Sales] [Trust] [Educational]  ──┤
│                                 │   │
│ GALERÍA:                        │PANEL│
│ Buscar...                       │:    │
│ [Todas][Cámaras][Motors]...     │Sel. │
│                                 │una  │
│ [Img 1][Img 2][Img 3]          │img. │
│ [Img 4][Img 5][Img 6]          │     │
│                                 │     │
└─────────────────────────────────────┘

PASO 3: Usuario selecciona Img 2 (Hikvision 5MP)
┌─────────────────────────────────────┐
│ Generar Estado                      │
├─ [Sales] [Trust] [Educational]  ──┤
│                                 │PANEL│
│ GALERÍA:                        │:    │
│ Buscar...                       │     │
│ [Todas][Cámaras][Motors]...     │[IMG]│
│                                 │     │
│ [Img 1][Img 2✓][Img 3]         │ ⭐ │
│ [Img 4][Img 5][Img 6]          │85/  │
│ ↑ Img 2 tiene checkmark         │100  │
│                                 │     │
│                                 │💡   │
│                                 │Exce │
│                                 │lente│
│                                 │para│
│                                 │con  │
│                                 │...  │
│                                 │     │
│                                 │[GEN]│
│                                 │     │
└─────────────────────────────────────┘

PASO 4: Backend analiza imagen
API Call: POST /marketing/media-assets/analyze
{
  mediaAssetIds: ["uuid-img2"],
  storyType: "sales"
}

Backend:
1. Obtiene Hikvision 5MP del asset
2. Calcula score: 82/100 (buena iluminación, producto claro)
3. Determina best types: ['sales', 'trust']
4. Recomienda: "Excelente para confianza y ventas"
5. Razones:
   • Iluminación profesional
   • Producto perfectamente visible
   • Probada con 8 usos exitosos
   • +12% conversión estimada
6. Ángulo: "Énfasis en características de seguridad y claridad visual"
7. Retorna ImageAnalysisResult

PASO 5: Panel IA muestra:
┌──────────────┐
│[IMG Hikvision│
│              │
│⭐ 82/100    │
│Buena calidad│
│              │
│💡 Excelente │
│  para       │
│  confianza y│
│  ventas     │
│• Iluminación│
│  prof.      │
│• Producto   │
│  visible    │
│• Probada (8)│
│• +12% conv. │
│              │
│🎯 Énfasis en│
│  seguridad  │
│              │
│📊 8 usos   │
│  2.4K imp.  │
│  12% CTR    │
│              │
│[GENERAR ✓]  │
└──────────────┘

PASO 6: Usuario hace click en "GENERAR CONTENIDO"

Backend recibe:
{
  date: "2026-05-09",
  selected_media_asset_ids: ["uuid-img2"]
}

Backend genera:
✓ Story tipo SALES con Hikvision 5MP como base
✓ Headline: "Vigilancia profesional que se ve"
✓ Copy: "Claridad total en cualquier iluminación..."
✓ CTA: "Cotiza tu sistema hoy"
✓ FacebookText: "Protege tu negocio con tecnología..."
✓ InstagramText: "Estado corto y punzante"
✓ MarketplaceText: "Completa descripción"
✓ Reel idea: "Hook + demostración + CTA"
✓ Variaciones: 3 opciones diferentes
✓ Hashtags: #Vigilancia #Seguridad #Profesional

AI Image Generation (NO CAMBIA PRODUCTO):
✓ Usa imagen original (Hikvision)
✓ Mejora iluminación
✓ Mejora composición
✓ Agrega overlay con logo empresa
✓ Agrega CTA visual
✓ Agrega textos: "Vigilancia 24/7"
✓ Estilo: Moderno, premium, minimalista
✓ Resultado: Diseño profesional SIN deformar cámara

PASO 7: Estado creado exitosamente
┌────────────────────────────┐
│ Estados para 9/5/26        │
├────────────────────────────┤
│ ✓ Estado SALES (approved)  │
│   "Vigilancia que se ve"   │
│   [Img con diseño]         │
│                            │
│ ⏳ Estado TRUST (pending)  │
│   "Confía en tecnología"   │
│   [Awaiting approval]      │
│                            │
│ ⏳ Estado EDUCATIONAL      │
│   (pending)                │
│                            │
└────────────────────────────┘

================================================================================
✨ RESUMEN DE BENEFICIOS
================================================================================

PARA EL USUARIO:
✅ Control total sobre imagen elegida
✅ Recomendaciones personalizadas de IA
✅ Razones claras para cada recomendación
✅ Preview profesional antes de generar
✅ UI moderna y limpia
✅ Proceso rápido (3 clicks)
✅ Contenido profesional garantizado

PARA LA MARCA:
✅ Producto NUNCA se modifica
✅ Imagen base respetada
✅ Diseño premium consistente
✅ Contenido optimizado para cada tipo
✅ Score de calidad visible
✅ Recomendaciones data-driven

PARA EL NEGOCIO:
✅ Mayor conversión (control = confianza)
✅ Contenido más profesional
✅ Menos rechazos de usuarios
✅ Mejor ROI en publicidad
✅ Menos necesidad de editar después

================================================================================
🚀 PRÓXIMOS PASOS
================================================================================

1. Integrar EstadosNuevoFlujoScreen en publicidad_screen.dart
   └─ Reemplazar _SelectGenerationImagesDialog con nueva pantalla

2. Conectar flujo completo:
   └─ Selección → Análisis → Confirmación → Generación

3. Testing end-to-end:
   └─ Validar que imagen elegida se usa SIEMPRE

4. Optimizaciones UI:
   └─ Responsive para móvil
   └─ Loading states
   └─ Error handling

5. Analytics:
   └─ Trackear qué imágenes se seleccionan
   └─ Trackear recomendaciones usadas
   └─ Trackear scores de calidad

================================================================================
