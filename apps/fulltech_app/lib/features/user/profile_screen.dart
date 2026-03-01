import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/auth/auth_provider.dart';
import '../../core/widgets/custom_app_bar.dart';
import '../../core/widgets/app_drawer.dart';
import '../../core/utils/string_utils.dart';
import '../../core/models/user_model.dart';
import '../user/data/users_repository.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(authStateProvider);
    final user = state.user;

    return Scaffold(
      appBar: CustomAppBar(
        title: 'Mi Perfil',
        showLogo: false,
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
                    backgroundImage: (user?.fotoPersonalUrl != null &&
                            user!.fotoPersonalUrl!.isNotEmpty)
                        ? NetworkImage(user.fotoPersonalUrl!)
                        : null,
                    child: (user?.fotoPersonalUrl == null ||
                            user!.fotoPersonalUrl!.isEmpty)
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
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.photo_camera_outlined),
                    label: const Text('Cambiar foto'),
                    onPressed: user == null
                        ? null
                        : () => _pickAndUploadProfilePhoto(context, ref),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    user?.nombreCompleto ?? 'Usuario',
                    style: Theme.of(context).textTheme.displayMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 4),
                  Chip(
                    label: Text(
                      user?.role ?? 'Sin rol',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    backgroundColor: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ElevatedButton.icon(
                        icon: const Icon(Icons.edit),
                        label: const Text('Editar información'),
                        onPressed: user == null
                            ? null
                            : () => _showEditDialog(context, ref, user),
                      ),
                      const SizedBox(width: 10),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.lock_outline_rounded),
                        label: const Text('Contraseña'),
                        onPressed: user == null
                            ? null
                            : () => _showPasswordDialog(context, ref),
                      ),
                    ],
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
                child: Column(
                  children: [
                    _InfoRow('Nombre Completo', user?.nombreCompleto ?? '—'),
                    _Divider(),
                    _InfoRow('Email', user?.email ?? '—'),
                    _Divider(),
                    _InfoRow('Teléfono', user?.telefono ?? '—'),
                    _Divider(),
                    _InfoRow('Cédula', user?.cedula ?? '—'),
                    _Divider(),
                    _InfoRow('Experiencia Laboral', user?.experienciaLaboral ?? '—'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

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
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Estado',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.outline,
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
                                ? Theme.of(context)
                                    .colorScheme
                                    .error
                                    .withValues(alpha: 0.1)
                                : Colors.green.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            user?.blocked == true ? 'Bloqueado' : 'Activo',
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
                        DateFormat('dd/MM/yyyy').format(user!.createdAt!),
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
    );
  }

  void _showEditDialog(BuildContext context, WidgetRef ref, UserModel user) {
    final nameCtrl = TextEditingController(text: user.nombreCompleto);
    final emailCtrl = TextEditingController(text: user.email);
    final passwordCtrl = TextEditingController();
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
              const SizedBox(height: 12),
              TextField(
                controller: passwordCtrl,
                decoration: const InputDecoration(labelText: 'Nueva contraseña (opcional)'),
                obscureText: true,
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
                'email': emailCtrl.text.trim(),
                'telefono': phoneCtrl.text.trim(),
                'password': passwordCtrl.text.isEmpty ? null : passwordCtrl.text,
              };
              payload.removeWhere((key, value) => value == null || (value is String && value.isEmpty));

              try {
                final repo = ref.read(usersRepositoryProvider);
                final updated = await repo.updateMe(
                  email: payload['email'] as String?,
                  nombreCompleto: payload['nombreCompleto'] as String?,
                  telefono: payload['telefono'] as String?,
                  password: payload['password'] as String?,
                );
                ref.read(authStateProvider.notifier).setUser(updated);
                if (!context.mounted) return;
                Navigator.pop(context);
                ScaffoldMessenger.of(context)
                    .showSnackBar(const SnackBar(content: Text('Perfil actualizado')));
              } catch (e) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context)
                    .showSnackBar(SnackBar(content: Text('No se pudo actualizar: $e')));
              }
            },
            child: const Text('Guardar cambios'),
          ),
        ],
      ),
    );
  }

  Future<void> _pickAndUploadProfilePhoto(BuildContext context, WidgetRef ref) async {
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
          const SnackBar(content: Text('No se pudo leer la imagen seleccionada')),
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
                  const SnackBar(content: Text('Ingresa una contraseña válida')),
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
                  SnackBar(content: Text('No se pudo actualizar la contraseña: $e')),
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
          Text(
            value,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
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
