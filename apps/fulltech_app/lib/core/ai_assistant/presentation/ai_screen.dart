import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/auth_provider.dart';
import '../../routing/app_navigator.dart';
import '../../widgets/app_drawer.dart';
import '../../widgets/app_navigation.dart';
import '../application/ai_assistant_controller.dart';
import 'ai_chat_context_resolver.dart';
import 'widgets/ai_assistant_sheet.dart';

class AiScreen extends ConsumerStatefulWidget {
  const AiScreen({super.key});

  @override
  ConsumerState<AiScreen> createState() => _AiScreenState();
}

class _AiScreenState extends ConsumerState<AiScreen> {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final location = safeCurrentLocation(context);
      final assistantContext = buildAiChatContextFromLocation(location);
      ref
          .read(aiAssistantControllerProvider.notifier)
          .setContext(assistantContext);
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authStateProvider).user;
    final isDesktop =
        MediaQuery.sizeOf(context).width >= kDesktopShellBreakpoint;

    return Scaffold(
      appBar: AppBar(
        leading: AppNavigator.maybeBackButton(context),
        title: const Text('IA'),
      ),
      drawer: buildAdaptiveDrawer(context, currentUser: user),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: isDesktop ? 980 : double.infinity,
            ),
            child: const GlobalAiChatSheet(),
          ),
        ),
      ),
    );
  }
}
