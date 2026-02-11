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
    if (location.startsWith(Routes.user)) return 0;
    if (location.startsWith(Routes.ponche)) return 1;
    if (location.startsWith(Routes.operaciones)) return 2;
    if (location.startsWith(Routes.ventas)) return 3;
    if (location.startsWith(Routes.contabilidad)) return 4;
    return 0;
  }

  void _onTap(int index) {
    switch (index) {
      case 0:
        context.go(Routes.user);
        break;
      case 1:
        context.go(Routes.ponche);
        break;
      case 2:
        context.go(Routes.operaciones);
        break;
      case 3:
        context.go(Routes.ventas);
        break;
      case 4:
        context.go(Routes.contabilidad);
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentIndex = _indexFromLocation(GoRouterState.of(context).uri.toString());
    return Scaffold(
      body: widget.child,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: currentIndex,
        onTap: _onTap,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.person_outline), label: 'Usuario'),
          BottomNavigationBarItem(icon: Icon(Icons.access_time), label: 'Ponche'),
          BottomNavigationBarItem(icon: Icon(Icons.build), label: 'Operaciones'),
          BottomNavigationBarItem(icon: Icon(Icons.point_of_sale), label: 'Ventas'),
          BottomNavigationBarItem(icon: Icon(Icons.account_balance), label: 'Contab.'),
        ],
      ),
    );
  }
}
