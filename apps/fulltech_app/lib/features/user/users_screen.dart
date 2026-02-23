import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';

import '../../core/auth/auth_provider.dart';
import '../../core/models/user_model.dart';
import '../../core/utils/string_utils.dart';
import '../../core/widgets/app_drawer.dart';
import '../../core/widgets/custom_app_bar.dart';
import '../user/application/users_controller.dart';
import './profile_screen.dart';

class UsersScreen extends ConsumerWidget {
  const UsersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authStateProvider);
    final currentUser = auth.user;

    if (currentUser?.role != 'ADMIN') {
      return Scaffold(
        appBar: CustomAppBar(title: 'FullTech', showLogo: true),
        drawer: AppDrawer(currentUser: currentUser),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.lock,
                  size: 64,
                  color: Theme.of(context).colorScheme.error,
                ),
                const SizedBox(height: 16),
                const Text('Solo administradores pueden gestionar usuarios'),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  icon: const Icon(Icons.person),
                  label: const Text('Ir a mi perfil'),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const ProfileScreen()),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final usersState = ref.watch(usersControllerProvider);

    return Scaffold(
      appBar: CustomAppBar(title: 'Gestión de Usuarios', showLogo: false),
      drawer: AppDrawer(currentUser: currentUser),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showUserDialog(context, ref),
        child: const Icon(Icons.add),
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(usersControllerProvider.notifier).refresh(),
        child: usersState.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text('Error al cargar usuarios: $e'),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: () =>
                    ref.read(usersControllerProvider.notifier).refresh(),
                child: const Text('Reintentar'),
              ),
            ],
          ),
          data: (users) {
            if (users.isEmpty) {
              return ListView(
                padding: const EdgeInsets.all(24),
                children: const [
                  Center(child: Text('No hay usuarios registrados')),
                ],
              );
            }
            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: users.length,
              itemBuilder: (context, index) {
                final user = users[index];
                return _UserCard(
                  user: user,
                  onEdit: () => _showUserDialog(context, ref, user),
                  onDelete: () => _showDeleteDialog(context, ref, user),
                  onToggleBlock: () => _toggleBlock(context, ref, user),
                );
              },
            );
          },
        ),
      ),
    );
  }

  Future<void> _toggleBlock(
    BuildContext context,
    WidgetRef ref,
    UserModel user,
  ) async {
    try {
      await ref
          .read(usersControllerProvider.notifier)
          .toggleBlock(user.id, !user.blocked);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              user.blocked ? 'Usuario desbloqueado' : 'Usuario bloqueado',
            ),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('No se pudo actualizar: $e')));
      }
    }
  }

  Future<String?> _pickAndUploadImage(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp'],
      withData: true,
    );

    if (result == null || result.files.isEmpty) return null;
    final file = result.files.first;
    final bytes = file.bytes;

    if (bytes == null || bytes.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No se pudo leer el archivo seleccionado'),
          ),
        );
      }
      return null;
    }

    try {
      return await ref
          .read(usersControllerProvider.notifier)
          .uploadDocument(bytes: bytes, fileName: file.name);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo subir la imagen: $e')),
        );
      }
      return null;
    }
  }

  void _showUserDialog(BuildContext context, WidgetRef ref, [UserModel? user]) {
    final nameCtrl = TextEditingController(text: user?.nombreCompleto ?? '');
    final emailCtrl = TextEditingController(text: user?.email ?? '');
    final phoneCtrl = TextEditingController(text: user?.telefono ?? '');
    final cedulaCtrl = TextEditingController(text: user?.cedula ?? '');
    final familiarPhoneCtrl = TextEditingController(
      text: user?.telefonoFamiliar ?? '',
    );
    final edadCtrl = TextEditingController(text: user?.edad?.toString() ?? '');
    final passwordCtrl = TextEditingController();
    String selectedRole = user?.role ?? 'ASISTENTE';
    bool blocked = user?.blocked ?? false;
    String? fotoCedulaUrl = user?.fotoCedulaUrl;
    String? fotoLicenciaUrl = user?.fotoLicenciaUrl;
    String? fotoPersonalUrl = user?.fotoPersonalUrl;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => AlertDialog(
          title: Text(user == null ? 'Nuevo Usuario' : 'Editar Usuario'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Nombre Completo',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: emailCtrl,
                  decoration: const InputDecoration(labelText: 'Email'),
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: phoneCtrl,
                  decoration: const InputDecoration(labelText: 'Teléfono'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: familiarPhoneCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Teléfono de familiar',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: cedulaCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Número de cédula',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: edadCtrl,
                  decoration: const InputDecoration(labelText: 'Edad'),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: passwordCtrl,
                  decoration: InputDecoration(
                    labelText: user == null
                        ? 'Contraseña'
                        : 'Contraseña (opcional)',
                  ),
                  obscureText: true,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: selectedRole,
                  decoration: const InputDecoration(labelText: 'Rol'),
                  items: const [
                    DropdownMenuItem(
                      value: 'ADMIN',
                      child: Text('Administrador'),
                    ),
                    DropdownMenuItem(
                      value: 'ASISTENTE',
                      child: Text('Asistente'),
                    ),
                    DropdownMenuItem(
                      value: 'VENDEDOR',
                      child: Text('Vendedor'),
                    ),
                    DropdownMenuItem(
                      value: 'MARKETING',
                      child: Text('Marketing'),
                    ),
                    DropdownMenuItem(value: 'TECNICO', child: Text('Técnico')),
                  ],
                  onChanged: (val) => selectedRole = val ?? 'ASISTENTE',
                ),
                const SizedBox(height: 12),
                _UploadTile(
                  title: 'Foto de cédula *',
                  isUploaded:
                      fotoCedulaUrl != null && fotoCedulaUrl!.isNotEmpty,
                  onTap: () async {
                    final uploaded = await _pickAndUploadImage(context, ref);
                    if (uploaded != null) {
                      setModalState(() => fotoCedulaUrl = uploaded);
                    }
                  },
                ),
                const SizedBox(height: 8),
                _UploadTile(
                  title: 'Foto de licencia (opcional)',
                  isUploaded:
                      fotoLicenciaUrl != null && fotoLicenciaUrl!.isNotEmpty,
                  onTap: () async {
                    final uploaded = await _pickAndUploadImage(context, ref);
                    if (uploaded != null) {
                      setModalState(() => fotoLicenciaUrl = uploaded);
                    }
                  },
                ),
                const SizedBox(height: 8),
                _UploadTile(
                  title: 'Foto personal (opcional)',
                  isUploaded:
                      fotoPersonalUrl != null && fotoPersonalUrl!.isNotEmpty,
                  onTap: () async {
                    final uploaded = await _pickAndUploadImage(context, ref);
                    if (uploaded != null) {
                      setModalState(() => fotoPersonalUrl = uploaded);
                    }
                  },
                ),
                if (user != null)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Bloqueado'),
                    value: blocked,
                    onChanged: (v) => setModalState(() => blocked = v),
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
                final edad = int.tryParse(edadCtrl.text.trim());
                if (edad == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Edad inválida')),
                  );
                  return;
                }

                final payload = <String, dynamic>{
                  'email': emailCtrl.text.trim(),
                  'password': passwordCtrl.text.isEmpty
                      ? null
                      : passwordCtrl.text,
                  'nombreCompleto': nameCtrl.text.trim(),
                  'telefono': phoneCtrl.text.trim(),
                  'telefonoFamiliar': familiarPhoneCtrl.text.trim(),
                  'cedula': cedulaCtrl.text.trim(),
                  'fotoCedulaUrl': fotoCedulaUrl,
                  'fotoLicenciaUrl': fotoLicenciaUrl,
                  'fotoPersonalUrl': fotoPersonalUrl,
                  'edad': edad,
                  'role': selectedRole,
                  'blocked': blocked,
                };
                payload.removeWhere(
                  (key, value) =>
                      value == null || (value is String && value.isEmpty),
                );

                if (user == null && !payload.containsKey('password')) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('La contraseña es obligatoria al crear'),
                    ),
                  );
                  return;
                }

                if (!payload.containsKey('cedula')) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('La cédula es obligatoria')),
                  );
                  return;
                }

                if (!payload.containsKey('telefonoFamiliar')) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('El teléfono de familiar es obligatorio'),
                    ),
                  );
                  return;
                }

                if (user == null && !payload.containsKey('fotoCedulaUrl')) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Debes subir la foto de la cédula'),
                    ),
                  );
                  return;
                }

                try {
                  if (user == null) {
                    await ref
                        .read(usersControllerProvider.notifier)
                        .create(payload);
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Usuario creado')),
                    );
                  } else {
                    await ref
                        .read(usersControllerProvider.notifier)
                        .update(user.id, payload);
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Usuario actualizado')),
                    );
                  }
                  if (!context.mounted) return;
                  Navigator.pop(context);
                } catch (e) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text('Error: $e')));
                }
              },
              child: Text(user == null ? 'Crear' : 'Guardar'),
            ),
          ],
        ),
      ),
    );
  }

  void _showDeleteDialog(BuildContext context, WidgetRef ref, UserModel user) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar Usuario'),
        content: Text('¿Eliminar a ${user.nombreCompleto}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () async {
              try {
                await ref
                    .read(usersControllerProvider.notifier)
                    .delete(user.id);
                if (!context.mounted) return;
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Usuario eliminado')),
                );
              } catch (e) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('No se pudo eliminar: $e')),
                );
              }
            },
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
  }
}

class _UserCard extends StatelessWidget {
  const _UserCard({
    required this.user,
    required this.onEdit,
    required this.onDelete,
    required this.onToggleBlock,
  });

  final UserModel user;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onToggleBlock;

  @override
  Widget build(BuildContext context) {
    final roleColor = _getRoleColor(user.role);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: roleColor,
                  child: Text(
                    getInitials(user.nombreCompleto),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user.nombreCompleto,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        user.email,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.outline,
                        ),
                      ),
                    ],
                  ),
                ),
                Chip(
                  label: Text(
                    user.role ?? 'Sin rol',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  backgroundColor: roleColor,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Teléfono: ${user.telefono}'),
                      Text('Tel. familiar: ${user.telefonoFamiliar ?? '—'}'),
                      Text('Cédula: ${user.cedula ?? '—'}'),
                      if (user.createdAt != null)
                        Text(
                          'Desde: ${DateFormat('dd/MM/yyyy').format(user.createdAt!)}',
                        ),
                      Text('Estado: ${user.blocked ? 'Bloqueado' : 'Activo'}'),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ElevatedButton.icon(
                  icon: const Icon(Icons.edit, size: 16),
                  label: const Text('Editar'),
                  onPressed: onEdit,
                ),
                ElevatedButton.icon(
                  icon: Icon(
                    user.blocked ? Icons.lock_open : Icons.lock,
                    size: 16,
                  ),
                  label: Text(user.blocked ? 'Desbloquear' : 'Bloquear'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: user.blocked ? Colors.orange : Colors.red,
                  ),
                  onPressed: onToggleBlock,
                ),
                ElevatedButton.icon(
                  icon: const Icon(Icons.delete, size: 16),
                  label: const Text('Eliminar'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.error,
                  ),
                  onPressed: onDelete,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Color _getRoleColor(String? role) {
    switch (role) {
      case 'ADMIN':
        return Colors.red;
      case 'VENDEDOR':
        return Colors.blue;
      case 'ASISTENTE':
        return Colors.green;
      case 'MARKETING':
        return Colors.purple;
      case 'TECNICO':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }
}

class _UploadTile extends StatelessWidget {
  const _UploadTile({
    required this.title,
    required this.isUploaded,
    required this.onTap,
  });

  final String title;
  final bool isUploaded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(
              isUploaded ? Icons.check_circle : Icons.upload_file,
              size: 18,
              color: isUploaded
                  ? Colors.green
                  : Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                isUploaded ? '$title (subida)' : title,
                style: const TextStyle(fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
