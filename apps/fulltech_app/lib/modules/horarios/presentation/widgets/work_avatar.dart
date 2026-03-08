import 'package:flutter/material.dart';

String _initials(String value) {
  final v = value.trim();
  if (v.isEmpty) return 'U';
  final parts = v.split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
  if (parts.isEmpty) return 'U';
  final first = parts.first;
  final second = parts.length > 1 ? parts[1] : '';
  final a = first.isNotEmpty ? first[0] : '';
  final b = second.isNotEmpty ? second[0] : '';
  final out = (a + b).toUpperCase();
  return out.isEmpty ? 'U' : out;
}

class WorkAvatar extends StatelessWidget {
  final String name;
  final String? photoUrl;
  final double size;

  const WorkAvatar({
    super.key,
    required this.name,
    this.photoUrl,
    this.size = 36,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final initials = _initials(name);
    final url = photoUrl?.trim() ?? '';

    if (url.isNotEmpty) {
      return ClipOval(
        child: Image.network(
          url,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => _fallback(scheme, initials),
        ),
      );
    }

    return _fallback(scheme, initials);
  }

  Widget _fallback(ColorScheme scheme, String initials) {
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: scheme.primaryContainer.withValues(alpha: 0.65),
      child: Text(
        initials,
        style: TextStyle(
          color: scheme.primary,
          fontWeight: FontWeight.w900,
          fontSize: size <= 32 ? 12 : 13,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}
