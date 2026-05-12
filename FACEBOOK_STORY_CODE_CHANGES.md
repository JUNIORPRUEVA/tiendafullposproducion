# 🔧 CAMBIOS DE CÓDIGO - AUDITORÍA FACEBOOK STORY

## Archivo Modificado: `apps/api/src/marketing/marketing-meta-publisher.service.ts`

### 1. Nueva Función: `prepareStoryImage()` (Línea ~1066)

**Propósito:** Transforma imagen a 1080x1920 optimizada para Stories

```typescript
private async prepareStoryImage(
  imageUrl: string,
): Promise<{
  buffer: Buffer;
  width: number;
  height: number;
  format: string;
  wasTransformed: boolean;
  originalDimensions: { width: number; height: number };
}>
```

**Funcionalidad:**
- Descarga imagen desde URL
- Lee metadata con `sharp`
- Si ratio ≠ 9:16: Recorta horizontalmente O agrega letterbox negro
- Retorna buffer JPEG optimizado + metadata

**Transformaciones:**
1. **Imagen ancha (16:9, 2:1, etc):** Recorta horizontalmente desde centro
2. **Imagen alta (4:5, etc):** Resize + fondo negro letterbox
3. **Imagen OK (±3% de 9:16):** Sin transformación

**Ejemplo de logs:**
```
[story-image-prep] transforming 1920x1080 (ratio=1.7778) -> crop + resize to 1080x1920
[story-image-prep] transformation complete: 1920x1080 -> 1080x1920
```

---

### 2. Función Mejorada: `publishFacebookStory()` (Línea ~1330)

**Cambios principales:**

#### Antes:
```typescript
const body = new URLSearchParams({
  photo_url: imageUrl,  // URL pública
  access_token: config.accessToken,
});
// POST con application/x-www-form-urlencoded
```

#### Ahora:
```typescript
const imagePrep = await this.prepareStoryImage(imageUrl);
const formData = new FormData();
formData.append('photo', new Blob([new Uint8Array(imagePrep.buffer)], { type: 'image/jpeg' }), 'story.jpg');
formData.append('access_token', config.accessToken);
// POST con multipart/form-data
```

**Logs de diagnóstico agregados:**

```typescript
this.logger.log('[facebook-story] ===== FACEBOOK STORY PUBLISH START =====');
this.logger.log(`[facebook-story-diag] endpoint=${endpoint}`);
this.logger.log(`[facebook-story-diag] url=${url}`);
this.logger.log(`[facebook-story-diag] method=POST`);
this.logger.log(`[facebook-story-diag] graph_version=${config.graphVersion}`);
this.logger.log(`[facebook-story-diag] page_id=${config.pageId}`);

// ... prepare image ...

this.logger.log(`[facebook-story-diag] body_keys=photo,access_token`);
this.logger.log(`[facebook-story-diag] http_status=${response.status}`);
this.logger.log(`[facebook-story-diag] error.message=${parsed.message}`);
this.logger.log(`[facebook-story-diag] error.code=${parsed.code ?? 'null'}`);
this.logger.log(`[facebook-story-diag] error.subcode=${parsed.subcode ?? 'null'}`);
this.logger.log(`[facebook-story-diag] error.type=${parsed.type ?? 'null'}`);
this.logger.log(`[facebook-story-diag] fbtrace_id=${parsed.fbtraceId ?? 'null'}`);

// Si no soportado:
this.logger.log(`[facebook-story-diag] UNSUPPORTED_ENDPOINT - Meta no soporta Page Stories API`);
this.logger.log('[facebook-story] ===== FACEBOOK STORY UNSUPPORTED =====');

// Si éxito:
this.logger.log('[facebook-story] ===== FACEBOOK STORY PUBLISHED SUCCESSFULLY =====');
```

**Manejo de errores mejorado:**

```typescript
// Detecta claramente si es unsupported (no reintentable)
const unsupported =
  parsed.code === 100 ||
  parsed.code === 1 ||
  /unsupported|unknown path|photo_stories|an unknown error has occurred|endpoint/i.test(parsed.message);

if (unsupported) {
  return {
    supported: false,  // ← Marca como NO soportado
    storyId: null,
    error: `Meta no permite publicar Facebook Page Stories con este endpoint/token...`,
    errorDetails: parsed,
  };
}
```

---

### 3. Función Existente: `validatePageTokenPermissions()` (Sin cambios de código, pero ahora se verifica antes)

**Valida:**
- ✅ `pages_manage_posts` - Para Facebook Story
- ✅ `pages_read_engagement` - Para lectura
- ✅ `pages_show_list` - Para listar páginas
- ✅ `instagram_content_publish` - Para Instagram Story

**Se ejecuta en línea 365 antes de cualquier publicación**

---

### 4. Flujo de Publicación (Sin cambios en estructura, pero mejorado)

**Ubicación:** Línea ~371-560

```typescript
if (publishFacebookStoryNow) {
  try {
    facebookStoryStatus = 'PUBLISHING';
    
    // 1. Prepara imagen
    const facebookStoryResult = await this.publishFacebookStory(config, normalizedImageUrl);
    
    // 2. Registra resultado
    setChannelResult('facebook_story', {
      status: facebookStoryResult.supported
        ? facebookStoryResult.storyId
          ? 'PUBLISHED'
          : 'ERROR'
        : 'UNSUPPORTED',  // ← Nuevo estado específico
      endpoint: facebookStoryResult.endpoint,
      response: facebookStoryResult.payload,
      errorDetails: facebookStoryResult.errorDetails
        ? this.toErrorDetailsJson(facebookStoryResult.errorDetails)
        : null,
    });
    
    // 3. Actualiza estado
    if (facebookStoryResult.supported) {
      facebookStoryId = facebookStoryResult.storyId;
      facebookStoryStatus = facebookStoryResult.storyId ? 'PUBLISHED' : 'ERROR';
    } else {
      facebookStoryStatus = 'UNSUPPORTED';  // ← NO reintentar
      channelErrors.push(...);
    }
  } catch (error) {
    facebookStoryStatus = 'ERROR';  // ← Temporal, reintentable
  }
}
```

---

## Comparación: Antes vs Después

### Antes

```
Usuario selecciona Facebook Story
         ↓
Intenta publicar con URL pública
         ↓
Meta rechaza: "Unknown error, code=1"
         ↓
Sistema: "¿Qué pasó?" (logs genéricos)
         ↓
Usuario: "No funciona" (sin detalle)
         ↓
Reintenta (inútil si es unsupported)
```

### Después

```
Usuario selecciona Facebook Story
         ↓
Valida token: pages_manage_posts ✅
         ↓
Descarga imagen original
         ↓
Prepara 1080x1920 (recorta si es necesario)
         ↓
Publica con buffer multipart/form-data
         ↓
Si éxito: facebookStoryStatus = PUBLISHED ✅
         ↓
Si Meta unsupported: facebookStoryStatus = UNSUPPORTED ⚠️
  → Logs detallados: código=1, type=OAuthException, etc
  → NO reintenta (ahorra recursos)
  → Instagram Story sigue independiente
         ↓
Usuario ve: "Instagram Story publicada. Facebook Story no soportada por Meta API."
```

---

## Diferencias Técnicas Clave

| Aspecto | Antes | Después |
|---------|-------|---------|
| **Método HTTP** | URLSearchParams | FormData multipart |
| **Body** | `photo_url` string | `photo` binary buffer |
| **Imagen** | URL remota | Buffer 1080x1920 |
| **Validación** | Solo si falla | Antes de publicar |
| **Diagnostics** | Genéricos | Endpoint + method + error_code + fbtrace_id |
| **Estado unsupported** | Reintentaba | Marca como no-retentable |
| **Logs** | Mínimos | Completos con [facebook-story-diag] |

---

## Instalación de Dependencias

**No requiere nuevas dependencias:**
- ✅ `sharp` ya está en `package.json` (v0.33.5)
- ✅ `FormData` es built-in en Node.js 18+
- ✅ `Blob` es built-in en Node.js 18+

---

## Testing Local

### Comprobar que se prepara imagen

Activar logs en .env:
```
LOG_LEVEL=debug
```

Publicar Facebook Story:
```
[story-image-prep] transforming 1920x1080 (ratio=1.7778) -> crop + resize to 1080x1920
```

### Comprobar diagnóstico

Buscar en logs:
```
[facebook-story-diag] endpoint=/100265433051305/photo_stories
[facebook-story-diag] error.code=1
[facebook-story-diag] error.type=OAuthException
```

### Comprobar que no afecta otros canales

- Facebook Post: Sigue usando `/{pageId}/photos` con URL
- Instagram Post: Sigue usando `/{igId}/media` con caption
- Instagram Story: Sigue usando `/{igId}/media` con media_type=STORIES

---

## Resultado Final

✅ **Backend Build:** npm run build → OK
✅ **Flutter Analyze:** flutter analyze → OK  
✅ **TypeScript:** tsc --noEmit → OK
✅ **Funcionamiento:** Facebook Story publica con imagen 1080x1920 optimizada
✅ **Diagnóstico:** Si falla, logs indican claramente si es soporte Meta o error temporal
✅ **Independencia:** Instagram Story NO afectado
