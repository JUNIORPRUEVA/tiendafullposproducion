import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'features/contabilidad/contabilidad_init.dart';
import 'core/routing/app_router.dart';
import 'core/theme/app_theme.dart';


Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _ensureEnvLoaded();
  await ensureContabilidadLocale();
  runApp(const ProviderScope(child: MyApp()));
}

Future<void> _ensureEnvLoaded() async {
  const envFile = '.env';
  const fallbackFile = '.env.example';

  try {
    await dotenv.load(fileName: envFile);
  } on Object catch (error) {
    debugPrint('Could not load $envFile: $error');
    try {
      await dotenv.load(fileName: fallbackFile);
    } on Object catch (fallbackError) {
      debugPrint('Could not load $fallbackFile either: $fallbackError');
    }
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
          theme: AppTheme.light,
          routerConfig: router,
        );
      },
    );
  }
}
