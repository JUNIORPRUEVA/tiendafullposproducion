import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

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
    final url = (imageUrl ?? '').trim();

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
}
