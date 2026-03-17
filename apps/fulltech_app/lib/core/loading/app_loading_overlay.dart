import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_provider.dart';
import 'app_loading_controller.dart';
import 'app_loading_screen.dart';

class AppLoadingOverlay extends ConsumerWidget {
  const AppLoadingOverlay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authStateProvider);
    final visible = ref.watch(appLoadingProvider.select((s) => s.visible));
    final suppressForStartup = !auth.initialized || auth.restoringSession;
    if (!visible || suppressForStartup) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;

    return Positioned.fill(
      child: IgnorePointer(
        // IMPORTANT: do not block input globally.
        // The loader should be visual-only; otherwise any background request can
        // prevent focusing text fields and make it feel like the keyboard is
        // "blocked".
        ignoring: true,
        child: Stack(
          children: [
            ModalBarrier(
              dismissible: false,
              color: scheme.scrim.withValues(alpha: 0.35),
            ),
            const AppLoadingScreen(),
          ],
        ),
      ),
    );
  }
}
