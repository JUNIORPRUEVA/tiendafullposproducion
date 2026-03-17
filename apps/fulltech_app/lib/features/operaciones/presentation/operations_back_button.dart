import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class OperationsBackButton extends StatelessWidget {
  final String fallbackRoute;
  final String tooltip;

  const OperationsBackButton({
    super.key,
    required this.fallbackRoute,
    this.tooltip = 'Regresar',
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      icon: const Icon(Icons.arrow_back_rounded),
      onPressed: () {
        final router = GoRouter.of(context);
        if (router.canPop()) {
          router.pop();
          return;
        }
        context.go(fallbackRoute);
      },
    );
  }
}
