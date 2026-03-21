import 'package:flutter/material.dart';

import '../../../core/routing/app_navigator.dart';

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
    return AppNavigator.maybeBackButton(
          context,
          fallbackRoute: fallbackRoute,
          tooltip: tooltip,
        ) ??
        const SizedBox.shrink();
  }
}
