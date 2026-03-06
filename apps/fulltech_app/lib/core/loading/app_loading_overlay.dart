import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_loading_controller.dart';
import 'app_loading_screen.dart';

class AppLoadingOverlay extends ConsumerWidget {
  const AppLoadingOverlay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final visible = ref.watch(appLoadingProvider.select((s) => s.visible));
    if (!visible) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;

    return Positioned.fill(
      child: IgnorePointer(
        ignoring: false,
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
