import 'package:js/js.dart';

String? runtimeEnvGet(String key) {
  // Keep this file small and stable: we only need the two runtime keys.
  // Values are injected by `env.js` (generated at container start).
  switch (key) {
    case 'API_BASE_URL':
      return _envApiBaseUrl() ?? _apiBaseUrl();
    case 'API_TIMEOUT_MS':
      return _envApiTimeoutMs() ?? _apiTimeoutMs();
    default:
      return null;
  }
}

@JS('__ENV.API_BASE_URL')
external String? _envApiBaseUrl();

@JS('__ENV.API_TIMEOUT_MS')
external String? _envApiTimeoutMs();

@JS('API_BASE_URL')
external String? _apiBaseUrl();

@JS('API_TIMEOUT_MS')
external String? _apiTimeoutMs();
