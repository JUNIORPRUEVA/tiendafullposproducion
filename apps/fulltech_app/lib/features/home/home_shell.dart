import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/location/location_tracker_provider.dart';

/// ShellRoute wrapper.
///
/// Mantiene el UX de cada pantalla (cada módulo maneja su propio Scaffold)
/// y evita romper navegación cuando el shell cambia.
class HomeShell extends ConsumerStatefulWidget {
  final Widget child;

  const HomeShell({super.key, required this.child});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  @override
  Widget build(BuildContext context) {
    ref.watch(locationTrackingBootstrapProvider);
    return widget.child;
  }
}
