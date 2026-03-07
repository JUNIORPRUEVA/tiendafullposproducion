# FullTech App (Flutter + PWA)

App mobile-first (Android/iOS) y Web (PWA) consumiendo un backend cloud.

## Requisitos

- Flutter 3.x

## Variables de entorno

La app carga configuración desde `apps/fulltech_app/.env` (ver `.env.example`).

- `API_BASE_URL` (ej: `https://api.midominio.com`)
- `API_TIMEOUT_MS` (opcional)

## Ejecutar

Desde `apps/fulltech_app/`:

- Web: `flutter run -d chrome`
- Android: `flutter run -d android`
- iOS: `flutter run -d ios`

## Build PWA (Web Release)

Desde `apps/fulltech_app/`:

- Generar build instalable (PWA): `flutter build web --release`

Salida: `apps/fulltech_app/build/web/` (incluye `manifest.json` y `flutter_service_worker.js`).

### Hosting

- La PWA requiere servir por **HTTPS** (excepto `localhost`).
- Si sirves la app bajo un sub-path (ej. `/fulltech/`), usa: `flutter build web --release --base-href /fulltech/`
- Si tu hosting es “static only”, el modo por defecto con hash URLs evita configuraciones extra para refresh.

## Deploy en EasyPanel (desde Git + Dockerfile)

Esta app incluye un Dockerfile listo para EasyPanel que:
- Compila Flutter Web en modo release.
- Sirve `build/web` con Nginx.

Archivos:
- `apps/fulltech_app/Dockerfile`
- `apps/fulltech_app/nginx.conf`

Pasos (resumen):
1) Sube el repo a Git (GitHub/GitLab).
2) En EasyPanel crea una nueva App desde Git.
3) Selecciona:
	- Build context: `apps/fulltech_app`
	- Dockerfile: `Dockerfile`
	- Puerto: `80`
4) Asigna el dominio genérico de EasyPanel y despliega.

Nota de configuración:
- En **Web/PWA**, EasyPanel debe inyectar `API_BASE_URL` como variable de entorno del contenedor.
- El contenedor genera `/env.js` al arrancar (no queda cacheado por el service worker) y la app lo lee en runtime.
- `.env` (asset) sigue existiendo como fallback, pero para cloud lo ideal es **no depender** de editar `.env.example`.

Variables a definir en EasyPanel (Runtime Env):
- `API_BASE_URL` (ej: `https://tu-api.tudominio.com`)
- `API_TIMEOUT_MS` (opcional)

## Arquitectura

- `lib/core/`: api, auth storage, routing, theme, widgets, errors
- `lib/features/`: auth, splash, home, user, ponche, operaciones, ventas, contabilidad

## Backend contract

Endpoints centralizados en `lib/core/api/api_routes.dart` para ajustar rápido si tu backend difiere.

