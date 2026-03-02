import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'external_launcher.dart';

LaunchMode _preferredLaunchMode() {
  if (kIsWeb) return LaunchMode.platformDefault;

  final platform = defaultTargetPlatform;
  final isDesktop =
      platform == TargetPlatform.windows ||
      platform == TargetPlatform.linux ||
      platform == TargetPlatform.macOS;

  return isDesktop
      ? LaunchMode.externalApplication
      : LaunchMode.platformDefault;
}

Future<void> safeOpenUrl(
  BuildContext context,
  Uri uri, {
  String copiedMessage = 'Link copiado',
}) async {
  var opened = false;

  try {
    final can = await canLaunchUrl(uri);
    if (can) {
      opened = await launchUrl(uri, mode: _preferredLaunchMode());
    }
  } catch (_) {
    // Fall through.
  }

  if (!opened) {
    try {
      opened = await openUrlWithOs(uri);
    } catch (_) {
      // ignore
    }
  }

  if (opened) return;

  try {
    await Clipboard.setData(ClipboardData(text: uri.toString()));
  } catch (_) {
    // ignore
  }

  if (!context.mounted) return;
  ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(copiedMessage)));
}
