import 'package:flutter/material.dart';

class AiAssistantDockButton extends StatelessWidget {
  const AiAssistantDockButton({
    super.key,
    required this.onPressed,
    this.isActive = false,
    this.compact = false,
  });

  final VoidCallback onPressed;
  final bool isActive;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.sizeOf(context).width >= 900;
    final borderRadius = BorderRadius.only(
      topLeft: const Radius.circular(24),
      bottomLeft: const Radius.circular(24),
      topRight: Radius.circular((isDesktop && !compact) ? 0 : 24),
      bottomRight: Radius.circular((isDesktop && !compact) ? 0 : 24),
    );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: borderRadius,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: borderRadius,
            gradient: LinearGradient(
              colors: isActive
                  ? const [
                      Color(0xFF0E2A6F),
                      Color(0xFF173DA8),
                      Color(0xFF13B8C8),
                    ]
                  : const [
                      Color(0xFF173DA8),
                      Color(0xFF2457D6),
                      Color(0xFF13B8C8),
                    ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF173DA8).withValues(alpha: 0.26),
                blurRadius: 28,
                offset: const Offset(0, 14),
              ),
            ],
          ),
          child: SizedBox(
            height: compact ? 40 : 64,
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: compact ? 14 : (isDesktop ? 18 : 16),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.auto_awesome_rounded, color: Colors.white),
                  if (isDesktop && !compact) ...[
                    const SizedBox(width: 10),
                    const Text(
                      'IA',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
