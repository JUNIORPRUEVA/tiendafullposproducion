import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/auth/auth_provider.dart';
import '../../core/widgets/custom_app_bar.dart';
import '../../core/widgets/app_drawer.dart';
import '../../core/models/user_model.dart';
import '../../core/utils/string_utils.dart';

// Este es un placeholder - en producción conectarías con la API
final usersListProvider = StateNotifierProvider<UsersListNotifier, List<UserModel>>((ref) {
  return UsersListNotifier();
});

class UsersListNotifier extends StateNotifier<List<UserModel>> {
  UsersListNotifier()
      : super([
          // Datos de ejemplo
          UserModel(
            id: '1',
            email: 'admin@fulltech.local',
            nombreCompleto: 'Administrador del Sistema',
            telefono: '1234567890',
            cedula: '12345678',
            experienciaLaboral: '5 años',
            role: 'ADMIN',
            blocked: false,
            createdAt: DateTime.now().subtract(const Duration(days: 30)),
          ),
          UserModel(
            id: '2',
            email: 'vendedor@fulltech.local',
            nombreCompleto: 'Juan Vendedor',
            telefono: '0987654321',
            cedula: '87654321',
            experienciaLaboral: '2 años',
            role: 'VENDEDOR',
            blocked: false,
            createdAt: DateTime.now().subtract(const Duration(days: 15)),
          ),
        ]);

  void addUser(UserModel user) {
    state = [...state, user];
  }

  void updateUser(String id, UserModel user) {
    state = [
      for (final u in state)
        if (u.id == id) user else u,
    ];
  }

  void deleteUser(String id) {
    state = state.where((u) => u.id != id).toList();
  }

  void toggleBlock(String id) {
    state = [
      for (final u in state)
        if (u.id == id)
          UserModel(
            id: u.id,
            email: u.email,
            nombreCompleto: u.nombreCompleto,
            telefono: u.telefono,
            cedula: u.cedula,
            experienciaLaboral: u.experienciaLaboral,
            role: u.role,
            blocked: !u.blocked,
            createdAt: u.createdAt,
          )
        else
          u,
    ];
  }
}

class UsersScreen extends ConsumerWidget {
  const UsersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final users = ref.watch(usersListProvider);
    final currentUser = ref.watch(authStateProvider).user;

    // Verificar si es admin
    if (currentUser?.role != 'ADMIN') {
      return Scaffold(
        appBar: CustomAppBar(title: 'FullTech', showLogo: true),
        drawer: AppDrawer(currentUser: currentUser),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.lock,
                size: 64,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: 16),
              Text(
                'No Autorizado',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              const Text('Solo administradores pueden gestionar usuarios'),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: CustomAppBar(
        title: 'Gestión de Usuarios',
        showLogo: false,
      ),
      drawer: AppDrawer(currentUser: currentUser),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showUserDialog(context, ref),
        child: const Icon(Icons.add),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Search bar
          TextField(
            decoration: InputDecoration(
              hintText: 'Buscar usuarios...',
              prefixIcon: const Icon(Icons.search),
              filled: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onChanged: (value) {
              // Implementar búsqueda
            },
          ),
          const SizedBox(height: 16),

          // Users list
          if (users.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 32),
                child: Column(
                  children: [
                    Icon(
                      Icons.people_outline,
                      size: 64,
                      color: Theme.of(context).colorScheme.outline,
                    ),
                    const SizedBox(height: 16),
                    const Text('No hay usuarios registrados'),
                  ],
                ),
              ),
            )
          else
            ...users.map((user) => _UserCard(
              user: user,
              onEdit: () => _showUserDialog(context, ref, user),
              onDelete: () => _showDeleteDialog(context, ref, user),
              onToggleBlock: () {
                ref.read(usersListProvider.notifier).toggleBlock(user.id);
              },
            )),
        ],
      ),
    );
  }

  void _showUserDialog(BuildContext context, WidgetRef ref, [UserModel? user]) {
    final nameCtrl = TextEditingController(text: user?.nombreCompleto ?? '');
    final emailCtrl = TextEditingController(text: user?.email ?? '');
    final phoneCtrl = TextEditingController(text: user?.telefono ?? '');
    final cedulaCtrl = TextEditingController(text: user?.cedula ?? '');
    final expCtrl = TextEditingController(text: user?.experienciaLaboral ?? '');
    String selectedRole = user?.role ?? 'ASISTENTE';

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(user == null ? 'Nuevo Usuario' : 'Editar Usuario'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Nombre Completo',
                  hintText: 'Ej: Juan Pérez',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: emailCtrl,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  hintText: 'Ej: usuario@empresa.com',
                ),
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: phoneCtrl,
                decoration: const InputDecoration(
                  labelText: 'Teléfono',
                  hintText: 'Ej: 1234567890',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: cedulaCtrl,
                decoration: const InputDecoration(
                  labelText: 'Cédula',
                  hintText: 'Ej: 12345678',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: expCtrl,
                decoration: const InputDecoration(
                  labelText: 'Experiencia Laboral',
                  hintText: 'Ej: 2 años',
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: selectedRole,
                decoration: const InputDecoration(labelText: 'Rol'),
                items: const [
                  DropdownMenuItem(value: 'ADMIN', child: Text('Administrador')),
                  DropdownMenuItem(value: 'ASISTENTE', child: Text('Asistente')),
                  DropdownMenuItem(value: 'VENDEDOR', child: Text('Vendedor')),
                  DropdownMenuItem(value: 'MARKETING', child: Text('Marketing')),
                  DropdownMenuItem(value: 'TECNICO', child: Text('Técnico')),
                ],
                onChanged: (value) => selectedRole = value ?? 'ASISTENTE',
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
            onPressed: () {
              final newUser = UserModel(
                id: user?.id ?? DateTime.now().toString(),
                email: emailCtrl.text,
                nombreCompleto: nameCtrl.text,
                telefono: phoneCtrl.text,
                cedula: cedulaCtrl.text,
                experienciaLaboral: expCtrl.text,
                role: selectedRole,
                blocked: user?.blocked ?? false,
                createdAt: user?.createdAt ?? DateTime.now(),
              );

              if (user == null) {
                ref.read(usersListProvider.notifier).addUser(newUser);
              } else {
                ref.read(usersListProvider.notifier).updateUser(user.id, newUser);
              }
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    user == null
                        ? 'Usuario creado exitosamente'
                        : 'Usuario actualizado',
                  ),
                ),
              );
            },
            child: Text(user == null ? 'Crear' : 'Guardar'),
          ),
        ],
      ),
    );
  }

  void _showDeleteDialog(BuildContext context, WidgetRef ref, UserModel user) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar Usuario'),
        content: Text(
          '¿Estás seguro de que deseas eliminar a ${user.nombreCompleto}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              ref.read(usersListProvider.notifier).deleteUser(user.id);
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Usuario eliminado')),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
  }
}

class _UserCard extends StatelessWidget {
  final UserModel user;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onToggleBlock;

  const _UserCard({
    required this.user,
    required this.onEdit,
    required this.onDelete,
    required this.onToggleBlock,
  });

  @override
  Widget build(BuildContext context) {
    Color roleColor = _getRoleColor(user.role);

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
                          fontSize: 12,
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
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  backgroundColor: roleColor,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Divider(color: Theme.of(context).dividerColor),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Teléfono: ${user.telefono}',
                        style: const TextStyle(fontSize: 12),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Cédula: ${user.cedula ?? '—'}',
                        style: const TextStyle(fontSize: 12),
                      ),
                      const SizedBox(height: 4),
                      if (user.createdAt != null)
                        Text(
                          'Desde: ${DateFormat('dd/MM/yyyy').format(user.createdAt!)}',
                          style: const TextStyle(fontSize: 12),
                        ),
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
                  onPressed: onToggleBlock,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: user.blocked ? Colors.orange : Colors.red,
                  ),
                ),
                ElevatedButton.icon(
                  icon: const Icon(Icons.delete, size: 16),
                  label: const Text('Eliminar'),
                  onPressed: onDelete,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.error,
                  ),
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
