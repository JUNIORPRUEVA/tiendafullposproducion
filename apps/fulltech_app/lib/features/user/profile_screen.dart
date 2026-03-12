import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../core/auth/auth_provider.dart';
import '../../core/widgets/custom_app_bar.dart';
import '../../core/widgets/app_drawer.dart';
import '../../core/routing/routes.dart';
import '../../core/utils/string_utils.dart';
import '../../core/models/user_model.dart';
import '../user/data/users_repository.dart';
import 'work_contract_screen.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(authStateProvider);
    final user = state.user;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: CustomAppBar(title: 'Mi Perfil', showLogo: false),
      drawer: buildAdaptiveDrawer(context, currentUser: user),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1000),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _ProfileHeaderCard(
                  user: user,
                  onPhotoTap: user == null
                      ? null
                      : () => _showPhotoActionsSheet(context, ref),
                  onEdit: user == null
                      ? null
                      : () => _showEditDialog(context, ref, user),
                ),
                const SizedBox(height: 16),
                if (user == null)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        'No hay información del usuario disponible.',
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                  )
                else
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final width = constraints.maxWidth;
                      final isWide = width >= 860;

                      final cards = <Widget>[
                        _SectionCard(
                          title: 'Datos personales',
                          icon: Icons.badge_outlined,
                          child: _InfoList(
                            children: [
                              if ((user.cedula ?? '').trim().isNotEmpty)
                                _InfoRow('Cédula', user.cedula!.trim()),
                              if (user.edad != null)
                                _InfoRow('Edad', '${user.edad}'),
                              if (user.fechaNacimiento != null)
                                _InfoRow(
                                  'Fecha de nacimiento',
                                  DateFormat(
                                    'dd/MM/yyyy',
                                  ).format(user.fechaNacimiento!),
                                ),
                              _InfoRow(
                                'Estado civil',
                                user.estaCasado == true ? 'Casado' : 'Soltero',
                              ),
                              _InfoRow(
                                'Hijos',
                                user.tieneHijos == true ? 'Sí' : 'No',
                              ),
                            ],
                          ),
                        ),
                        _SectionCard(
                          title: 'Contacto',
                          icon: Icons.contact_phone_outlined,
                          child: _InfoList(
                            children: [
                              if (user.telefono.trim().isNotEmpty)
                                _InfoRow('Teléfono', user.telefono.trim()),
                              if ((user.telefonoFamiliar ?? '')
                                  .trim()
                                  .isNotEmpty)
                                _InfoRow(
                                  'Teléfono familiar',
                                  user.telefonoFamiliar!.trim(),
                                ),
                              if (user.email.trim().isNotEmpty)
                                _InfoRow('Email', user.email.trim()),
                            ],
                          ),
                        ),
                        _SectionCard(
                          title: 'RRHH',
                          icon: Icons.work_outline_rounded,
                          child: _InfoList(
                            children: [
                              if (user.fechaIngreso != null)
                                _InfoRow(
                                  'Fecha de ingreso',
                                  DateFormat(
                                    'dd/MM/yyyy',
                                  ).format(user.fechaIngreso!),
                                ),
                              if (user.fechaIngreso != null)
                                _InfoRow(
                                  'Días en la empresa',
                                  (user.diasEnEmpresa ?? 0).toString(),
                                ),
                              _InfoRow(
                                'Licencia de conducir',
                                user.licenciaConducir == true ? 'Sí' : 'No',
                              ),
                              _InfoRow(
                                'Vehículo',
                                user.vehiculo == true ? 'Sí' : 'No',
                              ),
                              _InfoRow(
                                'Casa propia',
                                user.casaPropia == true ? 'Sí' : 'No',
                              ),
                            ],
                          ),
                        ),
                        if ((user.role ?? '').toUpperCase() == 'TECNICO')
                          _SectionCard(
                            title: 'Salidas técnicas',
                            icon: Icons.route_outlined,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                  'Administra tus vehículos propios, inicia salidas de campo y registra llegada/finalización para calcular combustible.',
                                  style: theme.textTheme.bodyMedium,
                                ),
                                const SizedBox(height: 14),
                                FilledButton.icon(
                                  onPressed: () =>
                                      context.go(Routes.salidasTecnicas),
                                  icon: const Icon(
                                    Icons.directions_car_outlined,
                                  ),
                                  label: const Text(
                                    'Gestionar vehículos y salidas',
                                  ),
                                ),
                              ],
                            ),
                          ),
                        if ((user.cuentaNominaPreferencial ?? '')
                            .trim()
                            .isNotEmpty)
                          _SectionCard(
                            title: 'Nómina',
                            icon: Icons.payments_outlined,
                            child: _InfoList(
                              children: [
                                _InfoRow(
                                  'Cuenta preferencial',
                                  user.cuentaNominaPreferencial!.trim(),
                                ),
                              ],
                            ),
                          ),
                        if (user.habilidades.isNotEmpty)
                          _SectionCard(
                            title: 'Habilidades',
                            icon: Icons.star_border_rounded,
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
                        _SectionCard(
                          title: 'Cuenta',
                          icon: Icons.manage_accounts_outlined,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _InfoRow('Rol', (user.role ?? 'Sin rol').trim()),
                              const SizedBox(height: 12),
                              _StatusPill(blocked: user.blocked),
                              if (user.createdAt != null) ...[
                                const SizedBox(height: 12),
                                _InfoRow(
                                  'Miembro desde',
                                  DateFormat(
                                    'dd/MM/yyyy',
                                  ).format(user.createdAt!),
                                ),
                              ],
                              const SizedBox(height: 16),
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: () =>
                                          _showPasswordDialog(context, ref),
                                      icon: const Icon(
                                        Icons.lock_outline_rounded,
                                      ),
                                      label: const Text('Contraseña'),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: () => _openContract(context),
                                      icon: const Icon(
                                        Icons.description_outlined,
                                      ),
                                      label: const Text('Contrato'),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ];

                      if (!isWide) {
                        return Column(
                          children: [
                            for (final c in cards) ...[
                              c,
                              const SizedBox(height: 16),
                            ],
                          ],
                        );
                      }

                      const cardMinWidth = 440.0;
                      return Wrap(
                        spacing: 16,
                        runSpacing: 16,
                        children: [
                          for (final c in cards)
                            SizedBox(
                              width: width >= (cardMinWidth * 2 + 16)
                                  ? (width - 16) / 2
                                  : width,
                              child: c,
                            ),
                        ],
                      );
                    },
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showPhotoActionsSheet(
    BuildContext context,
    WidgetRef ref,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.photo_camera_outlined),
                  title: const Text('Cambiar imagen'),
                  onTap: () {
                    Navigator.of(context).pop();
                    _pickAndUploadProfilePhoto(context, ref);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.close_rounded),
                  title: const Text('Cancelar'),
                  onTap: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _openContract(BuildContext context) async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const WorkContractScreen()));
  }

  void _showEditDialog(BuildContext context, WidgetRef ref, UserModel user) {
    final nameCtrl = TextEditingController(text: user.nombreCompleto);
    final emailCtrl = TextEditingController(text: user.email);
    final phoneCtrl = TextEditingController(text: user.telefono);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Editar mis datos'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Nombre completo'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: emailCtrl,
                decoration: const InputDecoration(labelText: 'Correo'),
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: phoneCtrl,
                decoration: const InputDecoration(labelText: 'Teléfono'),
                keyboardType: TextInputType.phone,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () async {
              final newName = nameCtrl.text.trim();
              if (newName.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('El nombre no puede estar vacío'),
                  ),
                );
                return;
              }

              final originalEmail = user.email.trim();
              final newEmail = emailCtrl.text.trim();
              final originalPhone = user.telefono.trim();
              final newPhone = phoneCtrl.text.trim();

              final changedEmail =
                  newEmail.isNotEmpty && newEmail != originalEmail;
              final changedName = newName != user.nombreCompleto.trim();
              final changedPhone = newPhone != originalPhone;

              if (!changedEmail && !changedName && !changedPhone) {
                Navigator.pop(context);
                return;
              }

              try {
                final repo = ref.read(usersRepositoryProvider);
                UserModel updated;
                try {
                  updated = await repo.updateMe(
                    email: changedEmail ? newEmail : null,
                    nombreCompleto: changedName ? newName : null,
                    telefono: changedPhone ? newPhone : null,
                  );
                } catch (e) {
                  if (changedEmail) {
                    updated = await repo.updateMe(
                      nombreCompleto: changedName ? newName : null,
                      telefono: changedPhone ? newPhone : null,
                    );
                    ref.read(authStateProvider.notifier).setUser(updated);
                    if (!context.mounted) return;
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Perfil actualizado (el correo no se pudo cambiar)',
                        ),
                      ),
                    );
                    return;
                  }
                  rethrow;
                }

                ref.read(authStateProvider.notifier).setUser(updated);
                if (!context.mounted) return;
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Perfil actualizado')),
                );
              } catch (e) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('No se pudo actualizar: $e')),
                );
              }
            },
            child: const Text('Guardar cambios'),
          ),
        ],
      ),
    );
  }

  Future<void> _pickAndUploadProfilePhoto(
    BuildContext context,
    WidgetRef ref,
  ) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;

      final picked = result.files.first;
      final bytes = picked.bytes;
      if (bytes == null || bytes.isEmpty) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No se pudo leer la imagen seleccionada'),
          ),
        );
        return;
      }

      final repo = ref.read(usersRepositoryProvider);
      final uploadedUrl = await repo.uploadUserDocument(
        bytes: bytes,
        fileName: picked.name,
      );
      final updated = await repo.updateMe(fotoPersonalUrl: uploadedUrl);
      ref.read(authStateProvider.notifier).setUser(updated);

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Foto de perfil actualizada')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo actualizar la foto: $e')),
      );
    }
  }

  Future<void> _showPasswordDialog(BuildContext context, WidgetRef ref) async {
    final passwordCtrl = TextEditingController();

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cambiar contraseña'),
        content: TextField(
          controller: passwordCtrl,
          decoration: const InputDecoration(labelText: 'Nueva contraseña'),
          obscureText: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () async {
              final password = passwordCtrl.text.trim();
              if (password.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Ingresa una contraseña válida'),
                  ),
                );
                return;
              }

              try {
                final repo = ref.read(usersRepositoryProvider);
                final updated = await repo.updateMe(password: password);
                ref.read(authStateProvider.notifier).setUser(updated);
                if (!context.mounted) return;
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Contraseña actualizada')),
                );
              } catch (e) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('No se pudo actualizar la contraseña: $e'),
                  ),
                );
              }
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              color: theme.colorScheme.outline,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileHeaderCard extends StatelessWidget {
  final UserModel? user;
  final VoidCallback? onPhotoTap;
  final VoidCallback? onEdit;

  const _ProfileHeaderCard({
    required this.user,
    required this.onPhotoTap,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final name = (user?.nombreCompleto ?? 'Usuario').trim();
    final email = (user?.email ?? '').trim();
    final role = (user?.role ?? 'Sin rol').trim();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ProfileAvatar(
              user: user,
              color: scheme.primary,
              onTap: onPhotoTap,
              radius: 42,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name.isEmpty ? 'Usuario' : name,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (email.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      email,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.outline,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _RolePill(role: role),
                      if (user != null) _StatusPill(blocked: user!.blocked),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: 200,
                    child: ElevatedButton.icon(
                      onPressed: onEdit,
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('Editar perfil'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;

  const _SectionCard({
    required this.title,
    required this.icon,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: scheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _RolePill extends StatelessWidget {
  final String role;

  const _RolePill({required this.role});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Text(
          role.isEmpty ? 'Sin rol' : role,
          style: TextStyle(
            color: scheme.onPrimaryContainer,
            fontWeight: FontWeight.w800,
            fontSize: 12,
            letterSpacing: 0.2,
          ),
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final bool blocked;

  const _StatusPill({required this.blocked});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = blocked ? scheme.errorContainer : scheme.secondaryContainer;
    final fg = blocked ? scheme.onErrorContainer : scheme.onSecondaryContainer;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Text(
          blocked ? 'Bloqueado' : 'Activo',
          style: TextStyle(
            color: fg,
            fontWeight: FontWeight.w800,
            fontSize: 12,
            letterSpacing: 0.2,
          ),
        ),
      ),
    );
  }
}

class _ProfileAvatar extends StatelessWidget {
  final UserModel? user;
  final Color color;
  final VoidCallback? onTap;
  final double radius;

  const _ProfileAvatar({
    required this.user,
    required this.color,
    required this.onTap,
    this.radius = 52,
  });

  @override
  Widget build(BuildContext context) {
    final hasPhoto = (user?.fotoPersonalUrl ?? '').trim().isNotEmpty;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: CircleAvatar(
          radius: radius,
          backgroundColor: color,
          backgroundImage: hasPhoto
              ? NetworkImage(user!.fotoPersonalUrl!)
              : null,
          child: !hasPhoto
              ? Text(
                  getInitials(user?.nombreCompleto ?? 'U'),
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: radius >= 50 ? 28 : 20,
                    fontWeight: FontWeight.bold,
                  ),
                )
              : null,
        ),
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
          if (i > 0) const SizedBox(height: 10),
          visible[i],
        ],
      ],
    );
  }
}
