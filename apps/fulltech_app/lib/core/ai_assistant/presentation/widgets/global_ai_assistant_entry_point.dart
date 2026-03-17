import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../auth/auth_provider.dart';
import '../../../widgets/app_navigation.dart';
import '../../application/ai_assistant_controller.dart';
import '../../domain/models/ai_chat_context.dart';
import '../ai_chat_context_resolver.dart';
import 'ai_assistant_dock_button.dart';
import 'ai_assistant_sheet.dart';

class GlobalAiAssistantEntryPoint extends ConsumerWidget {
  const GlobalAiAssistantEntryPoint({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authStateProvider);
    if (!auth.isAuthenticated) return child;

    return Stack(
      children: [
        child,
        Builder(
          builder: (innerContext) {
            final location = _safeLocation(innerContext);
            if (_shouldHideEntryPoint(location)) {
              return const SizedBox.shrink();
            }

            final isDesktop = MediaQuery.sizeOf(innerContext).width >= 900;
            final desktopOpen = isDesktop
                ? ref.watch(desktopAiAssistantPanelOpenProvider)
                : false;

            if (isDesktop) {
              return Stack(
                children: [
                  Positioned.fill(
                    child: IgnorePointer(
                      ignoring: !desktopOpen,
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 90),
                        curve: Curves.easeOut,
                        opacity: desktopOpen ? 1 : 0,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTapDown: (_) => _closeDesktopPanel(ref),
                          child: Container(
                            color: Colors.black.withValues(alpha: 0.12),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 0,
                    right: 0,
                    bottom: 0,
                    child: IgnorePointer(
                      ignoring: !desktopOpen,
                      child: AnimatedSlide(
                        duration: const Duration(milliseconds: 110),
                        curve: Curves.easeOutCubic,
                        offset: desktopOpen ? Offset.zero : const Offset(1, 0),
                        child: AnimatedOpacity(
                          duration: const Duration(milliseconds: 90),
                          curve: Curves.easeOut,
                          opacity: desktopOpen ? 1 : 0,
                          child: RepaintBoundary(
                            child: GlobalAiChatSheet(
                              onClose: () => _closeDesktopPanel(ref),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            }

            final assistantContext = _buildAssistantContext(innerContext);
            final viewInsets = MediaQuery.viewInsetsOf(innerContext);
            final viewPadding = MediaQuery.viewPaddingOf(innerContext);
            final extraBottom = viewInsets.bottom > 0
                ? viewInsets.bottom
                : viewPadding.bottom;

            return Positioned(
              right: 16,
              bottom: 16,
              child: AnimatedPadding(
                duration: const Duration(milliseconds: 140),
                curve: Curves.easeOut,
                padding: EdgeInsets.only(bottom: extraBottom),
                child: AiAssistantDockButton(
                  compact: true,
                  onPressed: () =>
                      _openAssistant(innerContext, ref, assistantContext),
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  bool _shouldHideEntryPoint(String location) {
    final normalized = location.trim();
    final uri = Uri.tryParse(normalized) ?? Uri(path: normalized);
    final path = uri.path.trim().toLowerCase();

    if (path.startsWith('/operaciones')) return true;
    return false;
  }

  AiChatContext _buildAssistantContext(BuildContext context) {
    final location = _safeLocation(context);
    return buildAiChatContextFromLocation(location);
  }

  String _safeLocation(BuildContext context) {
    return safeCurrentLocation(context);
  }

  void _openAssistant(
    BuildContext context,
    WidgetRef ref,
    AiChatContext assistantContext,
  ) {
    final controller = ref.read(aiAssistantControllerProvider.notifier);
    final isDesktop = MediaQuery.sizeOf(context).width >= 900;

    controller.setContext(assistantContext);

    if (isDesktop) {
      final open = ref.read(desktopAiAssistantPanelOpenProvider);
      ref.read(desktopAiAssistantPanelOpenProvider.notifier).state = !open;
      return;
    }

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      isDismissible: true,
      enableDrag: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const GlobalAiChatSheet(),
    );
  }

  void _closeDesktopPanel(WidgetRef ref) {
    ref.read(desktopAiAssistantPanelOpenProvider.notifier).state = false;
  }
}
