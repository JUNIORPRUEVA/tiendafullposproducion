import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'features/contabilidad/contabilidad_init.dart';
import 'core/api/env.dart';
import 'core/routing/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/loading/app_loading_overlay.dart';
import 'core/loading/app_loading_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _initializeDesktopSqlite();
  runApp(const ProviderScope(child: AppBootstrap()));
}

class AppBootstrap extends StatefulWidget {
  const AppBootstrap({super.key});

  @override
  State<AppBootstrap> createState() => _AppBootstrapState();
}

class _AppBootstrapState extends State<AppBootstrap> {
  late Future<void> _init;

  @override
  void initState() {
    super.initState();
    _init = Future.wait([
      _ensureEnvLoaded(),
      ensureContabilidadLocale(),
    ]).then((_) => null);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: FutureBuilder<void>(
        future: _init,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const AppLoadingScreen(title: 'Iniciando…');
          }
          if (snapshot.hasError) {
            return AppLoadingScreen(
              title: 'No se pudo iniciar',
              subtitle: 'Revisa la configuración y vuelve a abrir la app.',
            );
          }
          return const MyApp();
        },
      ),
    );
  }
}

void _initializeDesktopSqlite() {
  if (kIsWeb) return;
  final platform = defaultTargetPlatform;
  if (platform == TargetPlatform.windows ||
      platform == TargetPlatform.linux ||
      platform == TargetPlatform.macOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }
}

Future<void> _ensureEnvLoaded() async {
  const candidates = <String>[
    '.env',
    'assets/.env',
    '.env.example',
    'assets/.env.example',
  ];

  var loaded = false;
  for (final file in candidates) {
    try {
      await dotenv.load(fileName: file);
      loaded = true;
      debugPrint('Loaded env file: $file');
      break;
    } on Object catch (error) {
      debugPrint('Could not load $file: $error');
    }
  }

  if (!loaded) {
    debugPrint('No env file could be loaded.');
  }

  // Validate and log the selected API base URL.
  try {
    final baseUrl = Env.apiBaseUrl;
    debugPrint('API_BASE_URL: $baseUrl');
  } on Object catch (error) {
    debugPrint('Invalid API_BASE_URL configuration: $error');
    // Do not block app startup. Downstream API calls will surface errors if any.
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (context, ref, _) {
        final router = ref.watch(routerProvider);
        return MaterialApp.router(
          title: 'FullTech',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          routerConfig: router,
          builder: (context, child) {
            return Stack(
              children: [if (child != null) child, const AppLoadingOverlay()],
            );
          },
        );
      },
    );
  }
}
