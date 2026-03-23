import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'core/routing/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/loading/app_loading_overlay.dart';
import 'core/auth/auth_provider.dart';
import 'core/debug/app_error_reporter.dart';
import 'core/debug/app_error_overlay.dart';
import 'core/offline/sync_queue_service.dart';
import 'core/realtime/catalog_realtime_service.dart';
import 'core/startup/app_startup_controller.dart';
import 'core/widgets/fulltech_global_background.dart';
import 'features/contabilidad/contabilidad_init.dart';

class _GlobalErrorFallback extends StatefulWidget {
  final FlutterErrorDetails details;

  const _GlobalErrorFallback({required this.details});

  @override
  State<_GlobalErrorFallback> createState() => _GlobalErrorFallbackState();
}

class _GlobalErrorFallbackState extends State<_GlobalErrorFallback> {
  bool _reported = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_reported) return;
    _reported = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      AppErrorReporter.instance.recordFlutterError(widget.details);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Card(
            margin: const EdgeInsets.all(24),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.error_outline_rounded,
                    size: 40,
                    color: theme.colorScheme.error,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Ocurrió un error inesperado',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'La app siguió funcionando y el detalle quedó registrado.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> main() async {
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      await ensureContabilidadLocale(
        locale: PlatformDispatcher.instance.locale.toString(),
      );
      final authLaunchSnapshot = await loadAuthLaunchSnapshot();

      FlutterError.onError = (details) {
        FlutterError.presentError(details);
        AppErrorReporter.instance.recordFlutterError(details);
      };

      ErrorWidget.builder = (details) {
        return _GlobalErrorFallback(details: details);
      };

      PlatformDispatcher.instance.onError = (error, stack) {
        AppErrorReporter.instance.record(error, stack, context: 'Platform');
        return true;
      };

      _initializeDesktopSqlite();
      runApp(
        ProviderScope(
          overrides: [
            authLaunchSnapshotProvider.overrideWithValue(authLaunchSnapshot),
          ],
          child: const AppBootstrap(),
        ),
      );
    },
    (error, stack) {
      AppErrorReporter.instance.record(error, stack, context: 'Zone');
    },
  );
}

class AppBootstrap extends ConsumerStatefulWidget {
  const AppBootstrap({super.key});

  @override
  ConsumerState<AppBootstrap> createState() => _AppBootstrapState();
}

class _AppBootstrapState extends ConsumerState<AppBootstrap> {
  @override
  Widget build(BuildContext context) {
    return const MyApp();
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

class MyApp extends ConsumerStatefulWidget {
  const MyApp({super.key, this.enableBackgroundStartup = true});

  final bool enableBackgroundStartup;

  @override
  ConsumerState<MyApp> createState() => _MyAppState();
}

class _MyAppState extends ConsumerState<MyApp> {
  bool _backgroundStartupStarted = false;

  @override
  void initState() {
    super.initState();
    if (!widget.enableBackgroundStartup) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _backgroundStartupStarted = true);
      unawaited(prepareAppFirstFrame());

      final authState = ref.read(authStateProvider);
      if (authState.isAuthenticated) {
        unawaited(ref.read(catalogRealtimeServiceProvider).connect(authState));
      } else {
        ref.read(catalogRealtimeServiceProvider).disconnect();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.enableBackgroundStartup && _backgroundStartupStarted) {
      ref.watch(syncQueueBootstrapProvider);
    }
    final router = ref.watch(routerProvider);
    ref.watch(authStateProvider);

    ref.listen<AuthState>(authStateProvider, (previous, next) {
      if (!widget.enableBackgroundStartup || !_backgroundStartupStarted) {
        return;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (next.isAuthenticated) {
          unawaited(ref.read(catalogRealtimeServiceProvider).connect(next));
        } else if (previous?.isAuthenticated == true && !next.isAuthenticated) {
          ref.read(catalogRealtimeServiceProvider).disconnect();
        }
      });
    });

    return MaterialApp.router(
      title: 'FullTech',
      debugShowCheckedModeBanner: false,
      locale: const Locale('es', 'DO'),
      supportedLocales: const [Locale('es', 'DO'), Locale('es')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: AppTheme.light,
      routerConfig: router,
      builder: (context, child) {
        final effectiveChild = child == null
            ? null
            : MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(alwaysUse24HourFormat: false),
                child: child,
              );

        return Stack(
          children: [
            FulltechGlobalBackground(
              enableBlurEffects:
                  widget.enableBackgroundStartup && _backgroundStartupStarted,
            ),
            if (effectiveChild != null) effectiveChild,
            const AppLoadingOverlay(),
            const AppErrorOverlay(),
          ],
        );
      },
    );
  }
}
