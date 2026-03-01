import 'package:flutter/material.dart';

class CustomAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final Widget? titleWidget;
  final VoidCallback? onMenuPressed;
  final List<Widget>? actions;
  final bool showLogo;

  const CustomAppBar({
    super.key,
    required this.title,
    this.titleWidget,
    this.onMenuPressed,
    this.actions,
    this.showLogo = true,
  });

  @override
  Widget build(BuildContext context) {
    final scaffold = Scaffold.maybeOf(context);
    final canPop = Navigator.of(context).canPop();
    final hasDrawer = scaffold?.hasDrawer ?? false;

    return AppBar(
      leading: canPop
          ? null
          : (onMenuPressed != null || hasDrawer)
              ? IconButton(
                  tooltip: 'Menú',
                  onPressed:
                      onMenuPressed ??
                      () {
                        scaffold?.openDrawer();
                      },
                  icon: const Icon(Icons.menu_rounded),
                )
              : null,
      title:
          titleWidget ??
          Row(
            children: [
              if (showLogo)
                Image.asset(
                  'assets/logoprincipal.png',
                  height: 32,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Icon(Icons.business, color: Colors.white),
                    );
                  },
                ),
              if (showLogo) const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
      actions: actions,
      elevation: 0,
      backgroundColor: Theme.of(context).colorScheme.primary,
      foregroundColor: Colors.white,
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}
