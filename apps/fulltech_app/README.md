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

## Arquitectura

- `lib/core/`: api, auth storage, routing, theme, widgets, errors
- `lib/features/`: auth, splash, home, user, ponche, operaciones, ventas, contabilidad

## Backend contract

Endpoints centralizados en `lib/core/api/api_routes.dart` para ajustar rápido si tu backend difiere.

