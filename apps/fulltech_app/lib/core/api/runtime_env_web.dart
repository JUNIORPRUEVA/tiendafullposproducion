import 'package:js/js.dart';

String? runtimeEnvGet(String key) {
  // Keep this file small and stable: we only need the two runtime keys.
  // Values are injected by `env.js` (generated at container start).
  switch (key) {
    case 'API_BASE_URL':
      return _apiBaseUrl;
    case 'API_TIMEOUT_MS':
      return _apiTimeoutMs;
    default:
      return null;
  }
}

@JS('API_BASE_URL')
external String? get _apiBaseUrl;

@JS('API_TIMEOUT_MS')
external String? get _apiTimeoutMs;
