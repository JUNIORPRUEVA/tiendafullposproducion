import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/auth/auth_provider.dart';
import '../../core/widgets/custom_app_bar.dart';
import '../../core/widgets/app_drawer.dart';
import '../../core/utils/string_utils.dart';
import '../../core/models/user_model.dart';
import '../../core/company/company_settings_repository.dart';
import '../user/data/users_repository.dart';
import 'utils/work_contract_preview_screen.dart';
import 'utils/work_contract_pdf_service.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(authStateProvider);
    final user = state.user;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: CustomAppBar(title: 'Mi Perfil', showLogo: false),
      drawer: AppDrawer(currentUser: user),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header con avatar
                    Center(
                      child: Column(
                        children: [
                          _ProfileAvatar(
                            user: user,
                            color: theme.colorScheme.primary,
                            onTap: user == null
                                ? null
                                : () => _showPhotoActionsSheet(context, ref),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            user?.nombreCompleto ?? 'Usuario',
                            style: theme.textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          if ((user?.email ?? '').trim().isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              user!.email!.trim(),
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.outline,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                          const SizedBox(height: 10),
                          Chip(
                            label: Text(
                              user?.role ?? 'Sin rol',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            backgroundColor: theme.colorScheme.primary,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 28),

                    Text(
                      'Datos Personales',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: _InfoList(
                          children: [
                            if ((user?.cedula ?? '').trim().isNotEmpty)
                              _InfoRow('Cédula', user!.cedula!.trim()),
                            if (user?.edad != null)
                              _InfoRow('Edad', '${user!.edad}'),
                            if (user?.fechaNacimiento != null)
                              _InfoRow(
                                'Fecha de nacimiento',
                                DateFormat(
                                  'dd/MM/yyyy',
                                ).format(user!.fechaNacimiento!),
                              ),
                            if (user != null)
                              _InfoRow(
                                'Estado civil',
                                user.estaCasado == true ? 'Casado' : 'Soltero',
                              ),
                            if (user != null)
                              _InfoRow(
                                'Hijos',
                                user.tieneHijos == true ? 'Sí' : 'No',
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    Text(
                      'Contacto',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: _InfoList(
                          children: [
                            if ((user?.telefono ?? '').trim().isNotEmpty)
                              _InfoRow('Teléfono', user!.telefono!.trim()),
                            if ((user?.telefonoFamiliar ?? '')
                                .trim()
                                .isNotEmpty)
                              _InfoRow(
                                'Teléfono familiar',
                                user!.telefonoFamiliar!.trim(),
                              ),
                            if ((user?.email ?? '').trim().isNotEmpty)
                              _InfoRow('Email', user!.email!.trim()),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    Text(
                      'RRHH',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: _InfoList(
                          children: [
                            if (user?.fechaIngreso != null) ...[
                              _InfoRow(
                                'Fecha de ingreso',
                                DateFormat(
                                  'dd/MM/yyyy',
                                ).format(user!.fechaIngreso!),
                              ),
                              _InfoRow(
                                'Días en la empresa',
                                (user.diasEnEmpresa ?? 0).toString(),
                              ),
                            ],
                            if (user != null)
                              _InfoRow(
                                'Licencia de conducir',
                                user.licenciaConducir == true ? 'Sí' : 'No',
                              ),
                            if (user != null)
                              _InfoRow(
                                'Vehículo',
                                user.vehiculo == true ? 'Sí' : 'No',
                              ),
                            if (user != null)
                              _InfoRow(
                                'Casa propia',
                                user.casaPropia == true ? 'Sí' : 'No',
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Nómina
                    if ((user?.cuentaNominaPreferencial ?? '')
                        .trim()
                        .isNotEmpty) ...[
                      Text(
                        'Nómina',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
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
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
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
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Estado',
                                  style: TextStyle(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.outline,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: user?.blocked == true
                                        ? Theme.of(context).colorScheme.error
                                              .withValues(alpha: 0.1)
                                        : Colors.green.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    user?.blocked == true
                                        ? 'Bloqueado'
                                        : 'Activo',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: user?.blocked == true
                                          ? Theme.of(context).colorScheme.error
                                          : Colors.green,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            if (user?.createdAt != null) ...[
                              _Divider(),
                              _InfoRow(
                                'Miembro desde',
                                DateFormat(
                                  'dd/MM/yyyy',
                                ).format(user!.createdAt!),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
          ),
          if (user != null)
            SafeArea(
              child: Align(
                alignment: Alignment.centerRight,
                child: Transform.translate(
                  offset: const Offset(18, 0),
                  child: _SideFloatingActions(
                    onEdit: () => _showEditDialog(context, ref, user),
                    onPassword: () => _showPasswordDialog(context, ref),
                    onContract: () => _openContractPdf(context, ref, user),
                  ),
                ),
              ),
            ),
        ],
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

  Future<void> _openContractPdf(
    BuildContext context,
    WidgetRef ref,
    UserModel user,
  ) async {
    try {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Generando contrato...')));

      final settingsRepo = ref.read(companySettingsRepositoryProvider);
      final company = await settingsRepo.getSettings();
      final bytes = await buildWorkContractPdf(
        employee: user,
        company: company,
      );
      final safeName = user.nombreCompleto.trim().isEmpty
          ? 'empleado'
          : user.nombreCompleto.trim().replaceAll(RegExp(r'\s+'), '_');
      final dateFmt = DateFormat('yyyyMMdd');
      final fileName =
          'contrato_${safeName}_${dateFmt.format(DateTime.now())}.pdf';

      if (!context.mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) =>
              WorkContractPreviewScreen(bytes: bytes, fileName: fileName),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo generar el contrato: $e')),
      );
    }
  }

  void _showEditDialog(BuildContext context, WidgetRef ref, UserModel user) {
    final isAdmin = (user.role ?? '').trim().toUpperCase() == 'ADMIN';
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
              if (isAdmin) ...[
                TextField(
                  controller: emailCtrl,
                  decoration: const InputDecoration(labelText: 'Correo'),
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 12),
              ],
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
              final payload = <String, dynamic>{
                'nombreCompleto': nameCtrl.text.trim(),
                if (isAdmin) 'email': emailCtrl.text.trim(),
                'telefono': phoneCtrl.text.trim(),
              };
              payload.removeWhere(
                (key, value) =>
                    value == null || (value is String && value.isEmpty),
              );

              try {
                final repo = ref.read(usersRepositoryProvider);
                final updated = await repo.updateMe(
                  email: isAdmin ? payload['email'] as String? : null,
                  nombreCompleto: payload['nombreCompleto'] as String?,
                  telefono: payload['telefono'] as String?,
                );
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
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              color: theme.colorScheme.outline,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
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

class _ProfileAvatar extends StatelessWidget {
  final UserModel? user;
  final Color color;
  final VoidCallback? onTap;

  const _ProfileAvatar({
    required this.user,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final hasPhoto = (user?.fotoPersonalUrl ?? '').trim().isNotEmpty;

    return GestureDetector(
      onTap: onTap,
      child: CircleAvatar(
        radius: 52,
        backgroundColor: color,
        backgroundImage: hasPhoto ? NetworkImage(user!.fotoPersonalUrl!) : null,
        child: !hasPhoto
            ? Text(
                getInitials(user?.nombreCompleto ?? 'U'),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              )
            : null,
      ),
    );
  }
}

class _SideFloatingActions extends StatelessWidget {
  final VoidCallback onEdit;
  final VoidCallback onPassword;
  final VoidCallback onContract;

  const _SideFloatingActions({
    required this.onEdit,
    required this.onPassword,
    required this.onContract,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(999),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Editar',
              onPressed: onEdit,
              icon: const Icon(Icons.edit_outlined),
            ),
            IconButton(
              tooltip: 'Contraseña',
              onPressed: onPassword,
              icon: const Icon(Icons.lock_outline_rounded),
            ),
            IconButton(
              tooltip: 'Contrato (PDF)',
              onPressed: onContract,
              icon: const Icon(Icons.picture_as_pdf_outlined),
            ),
          ],
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
          if (i > 0) const _Divider(),
          visible[i],
        ],
      ],
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Divider(color: Theme.of(context).dividerColor, height: 16),
    );
  }
}
