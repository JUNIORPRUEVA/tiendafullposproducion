import 'dart:ui';

import 'package:flutter/material.dart';

class FulltechGlobalBackground extends StatelessWidget {
  const FulltechGlobalBackground({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    Color blendOnWhite(Color color, double amount) {
      return Color.lerp(Colors.white, color, amount) ?? Colors.white;
    }

    final top = blendOnWhite(cs.primary, 0.08);
    final mid = blendOnWhite(Color.alphaBlend(cs.secondary.withValues(alpha: 0.20), cs.primary), 0.06);
    final bottom = blendOnWhite(cs.primary, 0.03);

    final blobA = blendOnWhite(cs.primary, 0.18).withValues(alpha: 0.10);
    final blobB = blendOnWhite(cs.secondary, 0.20).withValues(alpha: 0.08);
    final blobC = blendOnWhite(cs.tertiary, 0.12).withValues(alpha: 0.06);

    return Positioned.fill(
      child: IgnorePointer(
        child: Stack(
          fit: StackFit.expand,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [top, mid, bottom],
                ),
              ),
            ),
            _BlurredCircle(
              alignment: const Alignment(-1.15, -1.10),
              diameter: 520,
              color: blobA,
              blurSigma: 120,
            ),
            _BlurredCircle(
              alignment: const Alignment(1.15, -0.70),
              diameter: 420,
              color: blobB,
              blurSigma: 120,
            ),
            _BlurredCircle(
              alignment: const Alignment(0.85, 1.10),
              diameter: 560,
              color: blobC,
              blurSigma: 140,
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0.0, -0.7),
                  radius: 1.25,
                  colors: [
                    cs.surface.withValues(alpha: 0.00),
                    cs.surface.withValues(alpha: 0.06),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BlurredCircle extends StatelessWidget {
  const _BlurredCircle({
    required this.alignment,
    required this.diameter,
    required this.color,
    required this.blurSigma,
  });

  final Alignment alignment;
  final double diameter;
  final Color color;
  final double blurSigma;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: ClipRect(
        child: ImageFiltered(
          imageFilter: ImageFilter.blur(
            sigmaX: blurSigma,
            sigmaY: blurSigma,
          ),
          child: Container(
            width: diameter,
            height: diameter,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
            ),
          ),
        ),
      ),
    );
  }
}
