import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/routing/routes.dart';

class HomeShell extends StatefulWidget {
  final Widget child;
  const HomeShell({super.key, required this.child});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _indexFromLocation(String location) {
    if (location.startsWith(Routes.operaciones)) return 0;
    if (location.startsWith(Routes.ponche)) return 1;
    if (location.startsWith(Routes.catalogo)) return 2;
    return 0;
  }

  void _onTap(int index) {
    switch (index) {
      case 0:
        context.go(Routes.operaciones);
        break;
      case 1:
        context.go(Routes.ponche);
        break;
      case 2:
        context.go(Routes.catalogo);
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;
    final currentIndex = _indexFromLocation(location);

    return Scaffold(
      body: widget.child,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: currentIndex,
        onTap: _onTap,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.build),
            label: 'Operaciones',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.access_time),
            label: 'Ponche',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.storefront),
            label: 'Catálogo',
          ),
        ],
      ),
    );
  }
}
