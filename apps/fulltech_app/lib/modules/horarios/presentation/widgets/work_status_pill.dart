import 'package:flutter/material.dart';

import 'work_status_style.dart';

class WorkStatusPill extends StatelessWidget {
  final WorkStatusStyle style;
  final bool compact;

  const WorkStatusPill({
    super.key,
    required this.style,
    this.compact = true,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final pad = compact
        ? const EdgeInsets.symmetric(horizontal: 10, vertical: 6)
        : const EdgeInsets.symmetric(horizontal: 12, vertical: 8);

    return Container(
      padding: pad,
      decoration: BoxDecoration(
        color: style.bg(scheme),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: style.border(scheme)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(style.icon, size: compact ? 16 : 18, color: style.color),
          const SizedBox(width: 6),
          Text(
            style.label,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: style.color,
              fontSize: compact ? 12 : 13,
            ),
          ),
        ],
      ),
    );
  }
}
