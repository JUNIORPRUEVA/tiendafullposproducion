import 'dart:math' as math;

import 'package:flutter/material.dart';

Future<T?> showAnchoredCompactPanel<T>(
  BuildContext context, {
  required GlobalKey anchorKey,
  required WidgetBuilder builder,
  double maxWidth = 440,
  double maxHeightFactor = 0.5,
  EdgeInsets margin = const EdgeInsets.all(12),
}) {
  final media = MediaQuery.of(context);
  final screenSize = media.size;
  final viewInsets = media.viewInsets;

  final renderBox = anchorKey.currentContext?.findRenderObject() as RenderBox?;
  final anchorRect = renderBox == null
      ? null
      : renderBox.localToGlobal(Offset.zero) & renderBox.size;

  final availableWidth = math.max(280.0, screenSize.width - margin.horizontal);
  final panelWidth = math.min(maxWidth, availableWidth).toDouble();
  final availableHeight = math.max(
    260.0,
    screenSize.height - margin.vertical - viewInsets.bottom,
  );
  final panelMaxHeight = (availableHeight * maxHeightFactor)
      .clamp(260.0, 520.0)
      .toDouble();

  final rawLeft = anchorRect == null
      ? (screenSize.width - panelWidth) / 2
      : anchorRect.right - panelWidth;
  final left = rawLeft.clamp(
    margin.left,
    math.max(margin.left, screenSize.width - panelWidth - margin.right),
  );

  final belowTop = anchorRect == null
      ? screenSize.height * 0.16
      : anchorRect.bottom + 10;
  final aboveTop = anchorRect == null
      ? belowTop
      : anchorRect.top - panelMaxHeight - 10;
  final canOpenBelow =
      belowTop + panelMaxHeight <=
      screenSize.height - viewInsets.bottom - margin.bottom;
  final top = (canOpenBelow ? belowTop : aboveTop)
      .clamp(
        margin.top,
        math.max(
          margin.top,
          screenSize.height -
              panelMaxHeight -
              margin.bottom -
              viewInsets.bottom,
        ),
      )
      .toDouble();

  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.black.withValues(alpha: 0.16),
    transitionDuration: const Duration(milliseconds: 190),
    pageBuilder: (dialogContext, animation, secondaryAnimation) {
      return Material(
        color: Colors.transparent,
        child: SafeArea(
          child: Stack(
            children: [
              Positioned(
                left: left.toDouble(),
                top: top,
                width: panelWidth,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: panelMaxHeight),
                  child: builder(dialogContext),
                ),
              ),
            ],
          ),
        ),
      );
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );

      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.92, end: 1).animate(curved),
          alignment: Alignment.topRight,
          child: child,
        ),
      );
    },
  );
}

class CompactFilterPanelFrame extends StatelessWidget {
  final String title;
  final Widget child;
  final VoidCallback onClose;
  final VoidCallback onApply;
  final VoidCallback? onClear;
  final bool canClear;

  const CompactFilterPanelFrame({
    super.key,
    required this.title,
    required this.child,
    required this.onClose,
    required this.onApply,
    this.onClear,
    this.canClear = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white,
            scheme.primary.withValues(alpha: 0.03),
            scheme.surface,
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFD9E3EE)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.14),
            blurRadius: 30,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Material(
          color: Colors.transparent,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 8, 6),
                child: Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: scheme.primary.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: Icon(
                        Icons.tune_rounded,
                        size: 18,
                        color: scheme.primary,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                          color: const Color(0xFF10233F),
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Cerrar',
                      onPressed: onClose,
                      icon: const Icon(Icons.close_rounded, size: 18),
                      visualDensity: VisualDensity.compact,
                      style: IconButton.styleFrom(
                        foregroundColor: const Color(0xFF526277),
                        backgroundColor: const Color(0xFFF3F6F9),
                      ),
                    ),
                  ],
                ),
              ),
              Flexible(child: child),
              Container(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.92),
                  border: Border(
                    top: BorderSide(
                      color: scheme.outlineVariant.withValues(alpha: 0.36),
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: canClear ? onClear : null,
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(40),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: const Text('Limpiar'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton(
                        onPressed: onApply,
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(40),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: const Text('Aplicar'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class CompactFilterSection extends StatelessWidget {
  final String title;
  final Widget child;

  const CompactFilterSection({
    super.key,
    required this.title,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFCFDFE),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2EAF2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w900,
              color: const Color(0xFF1D344F),
            ),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class CompactFilterSelectorTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onTap;

  const CompactFilterSelectorTile({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Material(
      color: const Color(0xFFF5F8FB),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 18, color: scheme.primary),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: const Color(0xFF64758B),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFF10233F),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: Color(0xFF64758B),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class CompactFilterChoiceGroup<T> extends StatelessWidget {
  final T value;
  final List<(T, String)> items;
  final ValueChanged<T> onChanged;

  const CompactFilterChoiceGroup({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        final columns = maxWidth >= 360 ? 3 : (maxWidth >= 240 ? 2 : 1);
        final spacing = 8.0;
        final itemWidth = columns == 1
            ? maxWidth
            : (maxWidth - (spacing * (columns - 1))) / columns;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final item in items)
              SizedBox(
                width: itemWidth,
                child: _CompactChoiceTile<T>(
                  label: item.$2,
                  selected: value == item.$1,
                  onTap: () => onChanged(item.$1),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _CompactChoiceTile<T> extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _CompactChoiceTile({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Material(
      color: selected
          ? scheme.primary.withValues(alpha: 0.11)
          : const Color(0xFFF7FAFD),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected
                  ? scheme.primary.withValues(alpha: 0.28)
                  : const Color(0xFFDCE5EF),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: selected ? scheme.primary : const Color(0xFF29415D),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (selected) ...[
                const SizedBox(width: 6),
                Icon(
                  Icons.check_circle_rounded,
                  size: 16,
                  color: scheme.primary,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
