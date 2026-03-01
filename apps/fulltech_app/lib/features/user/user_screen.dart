import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../core/auth/auth_provider.dart';
import '../../core/routing/routes.dart';
import '../../core/widgets/custom_app_bar.dart';
import '../../core/widgets/app_drawer.dart';

String _getInitials(String name) {
  final initials = name
      .split(' ')
      .map((e) => e.isNotEmpty ? e[0].toUpperCase() : '')
      .join('')
      .replaceAll(' ', '');

  if (initials.isEmpty) return 'U';
  if (initials.length >= 2) return initials.substring(0, 2);
  return initials.padRight(2, initials[0]);
}

class UserScreen extends ConsumerWidget {
  const UserScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(authStateProvider);
    final user = state.user;

    return Scaffold(
      appBar: CustomAppBar(
        title: 'FullTech',
        showLogo: true,
        trailing: user == null
            ? null
            : Padding(
                padding: const EdgeInsets.only(right: 12),
                child: InkWell(
                  borderRadius: BorderRadius.circular(999),
                  onTap: () => context.push(Routes.profile),
                  child: CircleAvatar(
                    radius: 16,
                    backgroundColor: Colors.white24,
                    backgroundImage: (user.fotoPersonalUrl ?? '').trim().isEmpty
                        ? null
                        : NetworkImage(user.fotoPersonalUrl!),
                    child: (user.fotoPersonalUrl ?? '').trim().isEmpty
                        ? Text(
                            _getInitials(user.nombreCompleto ?? 'U'),
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          )
                        : null,
                  ),
                ),
              ),
      ),
      drawer: AppDrawer(currentUser: user),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header con avatar
            Center(
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 50,
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    backgroundImage:
                        (user?.fotoPersonalUrl ?? '').trim().isEmpty
                            ? null
                            : NetworkImage(user!.fotoPersonalUrl!),
                    child: (user?.fotoPersonalUrl ?? '').trim().isEmpty
                        ? Text(
                            _getInitials(user?.nombreCompleto ?? 'U'),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    user?.nombreCompleto ?? 'Usuario',
                    style: Theme.of(context).textTheme.displayMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    user?.email ?? 'Sin email',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.outline,
                      fontSize: 14,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),

            // Información personal
            Text(
              'Información Personal',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: _InfoList(
                  children: [
                    if ((user?.nombreCompleto ?? '').trim().isNotEmpty)
                      _InfoRow('Nombre Completo', user!.nombreCompleto!.trim()),
                    if ((user?.email ?? '').trim().isNotEmpty)
                      _InfoRow('Email', user!.email!.trim()),
                    if ((user?.telefono ?? '').trim().isNotEmpty)
                      _InfoRow('Teléfono', user!.telefono!.trim()),
                    if ((user?.cedula ?? '').trim().isNotEmpty)
                      _InfoRow('Cédula', user!.cedula!.trim()),
                    if ((user?.experienciaLaboral ?? '').trim().isNotEmpty)
                      _InfoRow(
                        'Experiencia Laboral',
                        user!.experienciaLaboral!.trim(),
                      ),
                    if (user?.fechaIngreso != null) ...[
                      _InfoRow(
                        'Fecha de ingreso',
                        DateFormat('dd/MM/yyyy').format(user!.fechaIngreso!),
                      ),
                      _InfoRow(
                        'Días en la empresa',
                        (user.diasEnEmpresa ?? 0).toString(),
                      ),
                    ],
                    if (user?.fechaNacimiento != null)
                      _InfoRow(
                        'Fecha de nacimiento',
                        DateFormat('dd/MM/yyyy').format(user!.fechaNacimiento!),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Nómina
            if ((user?.cuentaNominaPreferencial ?? '').trim().isNotEmpty) ...[
              Text(
                'Nómina',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: _InfoList(
                    children: [
                      _InfoRow(
                        'Cuenta preferencial',
                        user!.cuentaNominaPreferencial!.trim(),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],

            // Habilidades
            if (user != null && user.habilidades.isNotEmpty) ...[
              Text(
                'Habilidades',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: user.habilidades
                          .map((h) => Chip(label: Text(h)))
                          .toList(growable: false),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],

            // Información de cuenta
            Text(
              'Información de Cuenta',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    _InfoRow('Rol', user?.role ?? '—'),
                    _InfoRow(
                      'Estado',
                      user?.blocked == true ? 'Bloqueado' : 'Activo',
                      statusColor: user?.blocked == true
                          ? Theme.of(context).colorScheme.error
                          : Colors.green,
                    ),
                    if (user?.createdAt != null)
                      _InfoRow(
                        'Miembro desde',
                        DateFormat('dd/MM/yyyy').format(user!.createdAt!),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 32),

            // Botones de acción
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.edit),
                label: const Text('Editar Perfil'),
                onPressed: () {
                  context.push(Routes.profile);
                },
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.logout),
                label: const Text('Cerrar Sesión'),
                onPressed: () async {
                  await ref.read(authStateProvider.notifier).logout();
                  if (context.mounted) {
                    context.go(Routes.login);
                  }
                },
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? statusColor;

  const _InfoRow(this.label, this.value, {this.statusColor});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Theme.of(context).colorScheme.outline,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          Row(
            children: [
              if (statusColor != null)
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: statusColor,
                    shape: BoxShape.circle,
                  ),
                  margin: const EdgeInsets.only(right: 8),
                ),
              Text(
                value,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Divider(
        color: Theme.of(context).dividerColor,
        height: 16,
      ),
    );
  }
}

class _InfoList extends StatelessWidget {
  final List<Widget> children;

  const _InfoList({required this.children});

  @override
  Widget build(BuildContext context) {
    final visible = children.whereType<Widget>().toList(growable: false);
    if (visible.isEmpty) return const SizedBox.shrink();

    return Column(
      children: [
        for (var i = 0; i < visible.length; i++) ...[
          if (i > 0) const _Divider(),
          visible[i],
        ],
      ],
    );
  }
}
