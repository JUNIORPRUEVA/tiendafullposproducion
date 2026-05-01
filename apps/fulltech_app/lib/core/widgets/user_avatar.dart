import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../api/env.dart';

/// A CircleAvatar replacement that loads [imageUrl] via [CachedNetworkImage]
/// and falls back to [child] on error or when the URL is empty.
/// This prevents the unhandled [SocketException] that a plain [CircleAvatar]
/// with [NetworkImage] throws when DNS resolution fails.
class UserAvatar extends StatelessWidget {
  final String? imageUrl;
  final double radius;
  final Color? backgroundColor;
  final Widget? child;

  const UserAvatar({
    super.key,
    this.imageUrl,
    required this.radius,
    this.backgroundColor,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    final url = _resolveAvatarUrl(imageUrl);

    if (url.isEmpty) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: backgroundColor,
        child: child,
      );
    }

    return CachedNetworkImage(
      imageUrl: url,
      imageBuilder: (context, imageProvider) => CircleAvatar(
        radius: radius,
        backgroundColor: backgroundColor,
        backgroundImage: imageProvider,
      ),
      placeholder: (context, _) => CircleAvatar(
        radius: radius,
        backgroundColor: backgroundColor,
        child: child,
      ),
      errorWidget: (context, _, __) => CircleAvatar(
        radius: radius,
        backgroundColor: backgroundColor,
        child: child,
      ),
    );
  }

  String _resolveAvatarUrl(String? rawUrl) {
    final value = (rawUrl ?? '').trim();
    if (value.isEmpty) return '';
    if (value.startsWith('http://') || value.startsWith('https://')) {
      return value;
    }

    final base = Env.apiBaseUrl.trim();
    if (base.isEmpty) return value;

    final normalizedBase = base.endsWith('/')
        ? base.substring(0, base.length - 1)
        : base;
    final normalizedPath = value.startsWith('/')
        ? value
        : (value.startsWith('uploads/') ? '/$value' : '/uploads/$value');
    return '$normalizedBase$normalizedPath';
  }
}
