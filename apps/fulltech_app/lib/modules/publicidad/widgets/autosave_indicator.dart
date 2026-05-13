import 'package:flutter/material.dart';

import '../providers/campaign_autosave_provider.dart';

/// Autosave status indicator - Notion style
class AutosaveStatusIndicator extends StatefulWidget {
  final AutosaveState state;
  final VoidCallback? onRetry;

  const AutosaveStatusIndicator({
    required this.state,
    this.onRetry,
    super.key,
  });

  @override
  State<AutosaveStatusIndicator> createState() =>
      _AutosaveStatusIndicatorState();
}

class _AutosaveStatusIndicatorState extends State<AutosaveStatusIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOutCubic),
    );
    _controller.forward();
  }

  @override
  void didUpdateWidget(AutosaveStatusIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state.isLoading != widget.state.isLoading ||
        oldWidget.state.error != widget.state.error) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _getStatusText() {
    if (widget.state.error != null) {
      return 'Error al guardar';
    }
    if (widget.state.isLoading) {
      return 'Guardando...';
    }
    if (widget.state.hasUnsavedChanges) {
      return 'Cambios sin guardar';
    }
    return 'Guardado';
  }

  Color _getStatusColor(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (widget.state.error != null) {
      return scheme.error;
    }
    if (widget.state.isLoading) {
      return scheme.primary;
    }
    if (widget.state.hasUnsavedChanges) {
      return scheme.tertiary;
    }
    return scheme.tertiary;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final statusColor = _getStatusColor(context);
    final statusText = _getStatusText();

    return FadeTransition(
      opacity: _fadeAnimation,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: statusColor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: statusColor.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.state.isLoading)
              SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  valueColor: AlwaysStoppedAnimation(statusColor),
                ),
              )
            else if (widget.state.error != null)
              Icon(Icons.error_rounded, size: 12, color: statusColor)
            else if (widget.state.hasUnsavedChanges)
              Icon(Icons.circle_outlined, size: 12, color: statusColor)
            else
              Icon(Icons.check_circle_rounded, size: 12, color: statusColor),
            const SizedBox(width: 6),
            Text(
              statusText,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: statusColor,
                    fontWeight: FontWeight.w500,
                  ),
            ),
            if (widget.state.error != null && widget.onRetry != null)
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: GestureDetector(
                  onTap: widget.onRetry,
                  child: Text(
                    'Reintentar',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: scheme.primary,
                          fontWeight: FontWeight.w600,
                          decoration: TextDecoration.underline,
                        ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Floating autosave indicator - appears bottom right
class FloatingAutosaveIndicator extends StatelessWidget {
  final AutosaveState state;
  final VoidCallback? onRetry;

  const FloatingAutosaveIndicator({
    required this.state,
    this.onRetry,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    // Don't show if saved and no unsaved changes
    if (!state.isLoading &&
        state.error == null &&
        !state.hasUnsavedChanges) {
      return const SizedBox.shrink();
    }

    return Positioned(
      bottom: 16,
      right: 16,
      child: Material(
        color: Colors.transparent,
        child: AutosaveStatusIndicator(
          state: state,
          onRetry: onRetry,
        ),
      ),
    );
  }
}
