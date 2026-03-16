import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'core/routing/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/loading/app_loading_overlay.dart';
import 'core/loading/app_loading_screen.dart';
import 'core/auth/auth_provider.dart';
import 'core/debug/app_error_reporter.dart';
import 'core/debug/app_error_overlay.dart';
import 'core/realtime/catalog_realtime_service.dart';
import 'features/operaciones/application/operations_realtime_bootstrap_provider.dart';
import 'core/startup/app_startup_controller.dart';
import 'core/ai_assistant/presentation/widgets/global_ai_assistant_entry_point.dart';
import 'core/widgets/fulltech_global_background.dart';
import 'features/operaciones/application/operations_prefetch_provider.dart';

Future<void> main() async {
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      FlutterError.onError = (details) {
        FlutterError.presentError(details);
        AppErrorReporter.instance.recordFlutterError(details);
      };

      PlatformDispatcher.instance.onError = (error, stack) {
        AppErrorReporter.instance.record(error, stack, context: 'Platform');
        return true;
      };

      _initializeDesktopSqlite();
      runApp(const ProviderScope(child: AppBootstrap()));
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
  bool _startupRequested = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_startupRequested) return;
    _startupRequested = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(ref.read(appStartupProvider.notifier).start());
    });
  }

  @override
  Widget build(BuildContext context) {
    final startup = ref.watch(appStartupProvider);
    final startupController = ref.read(appStartupProvider.notifier);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      builder: (context, child) {
        return Stack(
          children: [
            const FulltechGlobalBackground(),
            if (child != null) child,
          ],
        );
      },
      home: startup.hasError
          ? AppLoadingScreen(
              title: startup.title,
              subtitle: startup.errorMessage ?? startup.subtitle,
              statusLabel: startup.statusLabel,
              showProgress: false,
              actionLabel: 'Reintentar',
              onAction: startupController.retry,
            )
          : startup.isReady
          ? const MyApp()
          : AppLoadingScreen(
              title: startup.title,
              subtitle: startup.subtitle,
              statusLabel: startup.statusLabel,
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

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (context, ref, _) {
        ref.watch(operationsPrefetchBootstrapProvider);
        ref.watch(operationsRealtimeBootstrapProvider);
        final router = ref.watch(routerProvider);
        final authState = ref.watch(authStateProvider);
        ref.listen<AuthState>(authStateProvider, (previous, next) {
          if (next.isAuthenticated) {
            unawaited(ref.read(catalogRealtimeServiceProvider).connect(next));
          } else if (previous?.isAuthenticated == true &&
              !next.isAuthenticated) {
            ref.read(catalogRealtimeServiceProvider).disconnect();
          }
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!context.mounted) return;
          if (authState.isAuthenticated) {
            unawaited(
              ref.read(catalogRealtimeServiceProvider).connect(authState),
            );
          } else {
            ref.read(catalogRealtimeServiceProvider).disconnect();
          }
        });
        return MaterialApp.router(
          title: 'FullTech',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          routerConfig: router,
          builder: (context, child) {
            return Stack(
              children: [
                const FulltechGlobalBackground(),
                if (child != null) GlobalAiAssistantEntryPoint(child: child),
                const AppLoadingOverlay(),
                const AppErrorOverlay(),
              ],
            );
          },
        );
      },
    );
  }
}
