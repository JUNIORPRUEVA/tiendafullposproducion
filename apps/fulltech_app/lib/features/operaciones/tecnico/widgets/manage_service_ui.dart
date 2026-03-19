import 'dart:math' as math;

import 'package:flutter/material.dart';

class CompactAppBar extends StatelessWidget implements PreferredSizeWidget {
  final VoidCallback onBack;
  final String clientName;
  final String phaseLabel;
  final String statusLabel;
  final Color statusColor;
  final double toolbarHeight;

  const CompactAppBar({
    super.key,
    required this.onBack,
    required this.clientName,
    required this.phaseLabel,
    required this.statusLabel,
    required this.statusColor,
    this.toolbarHeight = 56,
  });

  @override
  Size get preferredSize => Size.fromHeight(toolbarHeight);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final width = MediaQuery.sizeOf(context).width;
    final tight = width < 390;

    return Material(
      color: Colors.transparent,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFF8FBFF), Color(0xFFF2F7FF), Color(0xFFFFFFFF)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border(
            bottom: BorderSide(
              color: const Color(0xFFCBD5E1).withValues(alpha: 0.55),
            ),
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x120F172A),
              blurRadius: 18,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: SafeArea(
          bottom: false,
          child: SizedBox(
            height: toolbarHeight,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                children: [
                  _CompactIconButton(
                    onTap: onBack,
                    icon: Icons.arrow_back_rounded,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Row(
                      children: [
                        Flexible(
                          flex: 11,
                          child: Text(
                            clientName.trim().isEmpty
                                ? 'CLIENTE'
                                : clientName.trim().toUpperCase(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontSize: tight ? 13 : 14,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.18,
                              color: const Color(0xFF0F172A),
                            ),
                          ),
                        ),
                        const _HeaderDivider(),
                        Flexible(
                          flex: 10,
                          child: _PhaseBadge(label: phaseLabel, compact: tight),
                        ),
                        const _HeaderDivider(),
                        Flexible(
                          flex: 10,
                          child: _StatusBadge(
                            label: statusLabel,
                            color: statusColor,
                            compact: tight,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class ActionButtonItem {
  final GlobalKey anchorKey;
  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final Color accentColor;
  final String? caption;

  const ActionButtonItem({
    required this.anchorKey,
    required this.label,
    required this.icon,
    required this.onTap,
    required this.accentColor,
    this.caption,
  });
}

class ActionButtonGrid extends StatelessWidget {
  final List<ActionButtonItem> items;

  const ActionButtonGrid({super.key, required this.items});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = width >= 560 ? 4 : 2;
        final spacing = 10.0;
        final itemWidth = (width - (spacing * (columns - 1))) / columns;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final item in items)
              SizedBox(
                width: itemWidth,
                child: _ActionButtonCard(item: item, key: item.anchorKey),
              ),
          ],
        );
      },
    );
  }
}

Future<T?> showActionDialog<T>(
  BuildContext context, {
  required GlobalKey anchorKey,
  required WidgetBuilder builder,
}) {
  final media = MediaQuery.of(context);
  final screenSize = media.size;
  final bottomInset = media.viewInsets.bottom;
  final maxWidth = math.min(screenSize.width - 24, 360.0).toDouble();
  final renderBox = anchorKey.currentContext?.findRenderObject() as RenderBox?;
  final anchorRect = renderBox == null
      ? null
      : renderBox.localToGlobal(Offset.zero) & renderBox.size;

  final left =
      (anchorRect == null
              ? (screenSize.width - maxWidth) / 2
              : (anchorRect.center.dx - (maxWidth / 2)).clamp(
                  12.0,
                  math.max(12.0, screenSize.width - maxWidth - 12.0),
                ))
          .toDouble();
  final topBase = anchorRect == null
      ? screenSize.height * 0.22
      : anchorRect.bottom + 10;
  final maxTop = math.max(24.0, screenSize.height - bottomInset - 320);
  final top = math.min(topBase, maxTop).toDouble();

  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.black.withValues(alpha: 0.12),
    transitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (dialogContext, animation, secondaryAnimation) {
      return Material(
        color: Colors.transparent,
        child: Stack(
          children: [
            Positioned(
              left: left,
              top: top,
              width: maxWidth,
              child: builder(dialogContext),
            ),
          ],
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
          scale: Tween<double>(begin: 0.94, end: 1).animate(curved),
          alignment: Alignment.topCenter,
          child: child,
        ),
      );
    },
  );
}

class ActionDialog extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget body;
  final List<Widget> actions;

  const ActionDialog({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    this.subtitle,
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1A0F172A),
            blurRadius: 26,
            offset: Offset(0, 14),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: cs.primaryContainer.withValues(alpha: 0.72),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, size: 18, color: cs.onPrimaryContainer),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                          color: const Color(0xFF0F172A),
                        ),
                      ),
                      if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle!.trim(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: const Color(0xFF64748B),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Cerrar',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded, size: 20),
                ),
              ],
            ),
            const SizedBox(height: 12),
            body,
            if (actions.isNotEmpty) ...[
              const SizedBox(height: 14),
              Row(
                children: [
                  for (var i = 0; i < actions.length; i++) ...[
                    if (i > 0) const SizedBox(width: 10),
                    Expanded(child: actions[i]),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class InfoRowWidget extends StatelessWidget {
  final String label;
  final String? value;
  final bool multiline;

  const InfoRowWidget({
    super.key,
    required this.label,
    required this.value,
    this.multiline = false,
  });

  @override
  Widget build(BuildContext context) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: multiline
            ? CrossAxisAlignment.start
            : CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 92,
            child: Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: const Color(0xFF64748B),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              trimmed,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: const Color(0xFF0F172A),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CompactIconButton extends StatelessWidget {
  final VoidCallback onTap;
  final IconData icon;

  const _CompactIconButton({required this.onTap, required this.icon});

  @override
  Widget build(BuildContext context) {
    return InkResponse(
      onTap: onTap,
      radius: 20,
      containedInkWell: true,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE2E8F0)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x120F172A),
              blurRadius: 10,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Icon(icon, size: 19, color: const Color(0xFF0F172A)),
      ),
    );
  }
}

class _HeaderDivider extends StatelessWidget {
  const _HeaderDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 18,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      color: const Color(0xFFCBD5E1),
    );
  }
}

class _PhaseBadge extends StatelessWidget {
  final String label;
  final bool compact;

  const _PhaseBadge({required this.label, required this.compact});

  @override
  Widget build(BuildContext context) {
    final text = label.trim().isEmpty ? 'FASE' : label.trim().toUpperCase();

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 5 : 6,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFFE0F2FE),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFBAE6FD)),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          fontSize: compact ? 10.5 : 11.2,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.18,
          color: const Color(0xFF0C4A6E),
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String label;
  final Color color;
  final bool compact;

  const _StatusBadge({
    required this.label,
    required this.color,
    required this.compact,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: compact ? 7 : 8,
          height: compact ? 7 : 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            label.trim().isEmpty ? 'Sin estado' : label.trim(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              fontSize: compact ? 11.5 : 12.2,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ),
      ],
    );
  }
}

class _ActionButtonCard extends StatefulWidget {
  final ActionButtonItem item;

  const _ActionButtonCard({super.key, required this.item});

  @override
  State<_ActionButtonCard> createState() => _ActionButtonCardState();
}

class _ActionButtonCardState extends State<_ActionButtonCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final enabled = item.onTap != null;

    return AnimatedScale(
      duration: const Duration(milliseconds: 110),
      scale: _pressed && enabled ? 0.97 : 1,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 110),
        opacity: enabled ? 1 : 0.56,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: item.onTap,
            onHighlightChanged: (value) => setState(() => _pressed = value),
            borderRadius: BorderRadius.circular(18),
            child: Ink(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.white,
                    item.accentColor.withValues(alpha: 0.07),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: item.accentColor.withValues(alpha: 0.18),
                ),
                boxShadow: [
                  BoxShadow(
                    color: item.accentColor.withValues(alpha: 0.10),
                    blurRadius: 16,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: item.accentColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(item.icon, size: 18, color: item.accentColor),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      item.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: const Color(0xFF0F172A),
                      ),
                    ),
                    if (item.caption != null &&
                        item.caption!.trim().isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        item.caption!.trim(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: const Color(0xFF64748B),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
