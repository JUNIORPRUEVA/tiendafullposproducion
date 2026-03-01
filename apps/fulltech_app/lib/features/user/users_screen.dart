import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';

import '../../core/api/env.dart';
import '../../core/auth/auth_provider.dart';
import '../../core/company/company_settings_repository.dart';
import '../../core/models/user_model.dart';
import '../../core/utils/string_utils.dart';
import '../../core/widgets/app_drawer.dart';
import '../../core/widgets/custom_app_bar.dart';
import '../user/application/users_controller.dart';
import './profile_screen.dart';
import 'utils/work_contract_pdf_service.dart';

String? _resolveUserDocUrl(String? url) {
  if (url == null || url.isEmpty) return null;
  if (url.startsWith('http://') || url.startsWith('https://')) return url;
  final base = Env.apiBaseUrl;
  if (base.isEmpty) return url;
  final trimmedBase = base.endsWith('/')
      ? base.substring(0, base.length - 1)
      : base;
  final normalizedPath = url.startsWith('/') ? url : '/$url';
  return '$trimmedBase$normalizedPath';
}

class UsersScreen extends ConsumerWidget {
  const UsersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const _UsersScreenBody();
  }
}

enum _UserStatusFilter { todos, activos, bloqueados }

class _UsersScreenBody extends ConsumerStatefulWidget {
  const _UsersScreenBody();

  @override
  ConsumerState<_UsersScreenBody> createState() => _UsersScreenState();
}

class _UsersScreenState extends ConsumerState<_UsersScreenBody> {
  final TextEditingController _searchCtrl = TextEditingController();
  bool _searching = false;
  String _searchQuery = '';
  _UserStatusFilter _statusFilter = _UserStatusFilter.todos;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
      appBar: CustomAppBar(
        title: 'Gestión de Usuarios',
        showLogo: false,
        titleWidget: _searching
            ? TextField(
                controller: _searchCtrl,
                autofocus: true,
                onChanged: (value) => setState(() => _searchQuery = value),
                style: const TextStyle(color: Colors.white, fontSize: 15),
                decoration: InputDecoration(
                  hintText: 'Buscar usuario...',
                  hintStyle: const TextStyle(color: Colors.white70),
                  border: InputBorder.none,
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () {
                      setState(() {
                        _searching = false;
                        _searchQuery = '';
                        _searchCtrl.clear();
                      });
                    },
                  ),
                ),
              )
            : null,
        actions: [
          IconButton(
            tooltip: 'Buscar',
            onPressed: () => setState(() => _searching = true),
            icon: const Icon(Icons.search),
          ),
          PopupMenuButton<_UserStatusFilter>(
            tooltip: 'Filtrar',
            initialValue: _statusFilter,
            onSelected: (value) => setState(() => _statusFilter = value),
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: _UserStatusFilter.todos,
                child: Text('Todos'),
              ),
              PopupMenuItem(
                value: _UserStatusFilter.activos,
                child: Text('Solo activos'),
              ),
              PopupMenuItem(
                value: _UserStatusFilter.bloqueados,
                child: Text('Solo bloqueados'),
              ),
            ],
            icon: const Icon(Icons.filter_list),
          ),
        ],
      ),
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
            final filteredUsers = users.where((user) {
              final matchesStatus = switch (_statusFilter) {
                _UserStatusFilter.todos => true,
                _UserStatusFilter.activos => !user.blocked,
                _UserStatusFilter.bloqueados => user.blocked,
              };

              final q = _searchQuery.trim().toLowerCase();
              final matchesSearch = q.isEmpty
                  ? true
                  : ('${user.nombreCompleto} ${user.email} ${user.telefono} ${user.cedula ?? ''}'
                        .toLowerCase()
                        .contains(q));

              return matchesStatus && matchesSearch;
            }).toList();

            if (filteredUsers.isEmpty) {
              return ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  Center(
                    child: Text(
                      users.isEmpty
                          ? 'No hay usuarios registrados'
                          : 'No hay resultados con ese filtro',
                    ),
                  ),
                ],
              );
            }
            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: filteredUsers.length,
              itemBuilder: (context, index) {
                final user = filteredUsers[index];
                return _UserCard(
                  user: user,
                  onView: () => _showUserDetailsSheet(context, user),
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
    final cuentaNominaCtrl = TextEditingController(
      text: user?.cuentaNominaPreferencial ?? '',
    );
    final passwordCtrl = TextEditingController();
    final habilidadCtrl = TextEditingController();
    String selectedRole = user?.role ?? 'ASISTENTE';
    bool blocked = user?.blocked ?? false;
    bool tieneHijos = user?.tieneHijos ?? false;
    bool estaCasado = user?.estaCasado ?? false;
    bool casaPropia = user?.casaPropia ?? false;
    bool vehiculo = user?.vehiculo ?? false;
    bool licenciaConducir = user?.licenciaConducir ?? false;
    DateTime? fechaIngreso = user?.fechaIngreso;
    DateTime? fechaNacimiento = user?.fechaNacimiento;
    final habilidades = [...user?.habilidades ?? const <String>[]];
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
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Fecha de ingreso (opcional)'),
                  subtitle: Text(
                    fechaIngreso == null
                        ? 'Seleccionar fecha'
                        : DateFormat('dd/MM/yyyy').format(fechaIngreso!),
                  ),
                  trailing: const Icon(Icons.calendar_today_outlined),
                  onTap: () async {
                    final now = DateTime.now();
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: fechaIngreso ?? now,
                      firstDate: DateTime(1990),
                      lastDate: DateTime(now.year + 5),
                    );
                    if (picked != null) {
                      setModalState(() => fechaIngreso = picked);
                    }
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Fecha de nacimiento (opcional)'),
                  subtitle: Text(
                    fechaNacimiento == null
                        ? 'Seleccionar fecha'
                        : DateFormat('dd/MM/yyyy').format(fechaNacimiento!),
                  ),
                  trailing: const Icon(Icons.cake_outlined),
                  onTap: () async {
                    final now = DateTime.now();
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: fechaNacimiento ?? DateTime(now.year - 18),
                      firstDate: DateTime(1940),
                      lastDate: now,
                    );
                    if (picked != null) {
                      setModalState(() => fechaNacimiento = picked);
                    }
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: cuentaNominaCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Cuenta preferencial para nómina (opcional)',
                    hintText: 'Ej: Banco, tipo, # cuenta o # IBAN',
                  ),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Habilidades (opcional)',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                const SizedBox(height: 8),
                if (habilidades.isNotEmpty)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: habilidades
                          .map(
                            (h) => Chip(
                              label: Text(h),
                              onDeleted: () => setModalState(
                                () => habilidades.remove(h),
                              ),
                            ),
                          )
                          .toList(growable: false),
                    ),
                  ),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: habilidadCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Agregar habilidad',
                        ),
                        textInputAction: TextInputAction.done,
                        onSubmitted: (value) {
                          final skill = value.trim();
                          if (skill.isEmpty) return;
                          if (habilidades.contains(skill)) {
                            habilidadCtrl.clear();
                            return;
                          }
                          setModalState(() {
                            habilidades.add(skill);
                            habilidadCtrl.clear();
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: () {
                        final skill = habilidadCtrl.text.trim();
                        if (skill.isEmpty) return;
                        if (habilidades.contains(skill)) {
                          habilidadCtrl.clear();
                          return;
                        }
                        setModalState(() {
                          habilidades.add(skill);
                          habilidadCtrl.clear();
                        });
                      },
                      icon: const Icon(Icons.add_circle_outline),
                      tooltip: 'Agregar',
                    ),
                  ],
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
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Tiene hijos'),
                  value: tieneHijos,
                  onChanged: (v) => setModalState(() => tieneHijos = v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Está casado/a'),
                  value: estaCasado,
                  onChanged: (v) => setModalState(() => estaCasado = v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Casa propia'),
                  value: casaPropia,
                  onChanged: (v) => setModalState(() => casaPropia = v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Posee vehículo'),
                  value: vehiculo,
                  onChanged: (v) => setModalState(() => vehiculo = v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Licencia de conducir'),
                  value: licenciaConducir,
                  onChanged: (v) => setModalState(() => licenciaConducir = v),
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
                  'fechaIngreso': fechaIngreso?.toIso8601String(),
                  'fechaNacimiento': fechaNacimiento?.toIso8601String(),
                  'cuentaNominaPreferencial': cuentaNominaCtrl.text.trim(),
                  'habilidades': habilidades,
                  'tieneHijos': tieneHijos,
                  'estaCasado': estaCasado,
                  'casaPropia': casaPropia,
                  'vehiculo': vehiculo,
                  'licenciaConducir': licenciaConducir,
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

  void _showUserDetailsSheet(BuildContext context, UserModel user) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        final theme = Theme.of(context);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Detalle de usuario', style: theme.textTheme.titleLarge),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerRight,
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.picture_as_pdf_outlined),
                      label: const Text('Contrato (PDF)'),
                      onPressed: () async {
                        try {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Generando contrato...')),
                          );
                          final settingsRepo =
                              ref.read(companySettingsRepositoryProvider);
                          final company = await settingsRepo.getSettings();
                          final bytes = await buildWorkContractPdf(
                            employee: user,
                            company: company,
                          );
                          await shareWorkContractPdf(bytes: bytes, employee: user);
                        } catch (e) {
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('No se pudo generar: $e')),
                          );
                        }
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        children: [
                          _DetailRow('Nombre', user.nombreCompleto),
                          _DetailRow('Email', user.email),
                          _DetailRow('Rol', user.role ?? '—'),
                          _DetailRow(
                            'Estado',
                            user.blocked ? 'Bloqueado' : 'Activo',
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        children: [
                          _DetailRow('Teléfono', user.telefono),
                          _DetailRow(
                            'Teléfono familiar',
                            user.telefonoFamiliar ?? '—',
                          ),
                          _DetailRow('Cédula', user.cedula ?? '—'),
                          _DetailRow('Edad', user.edad?.toString() ?? '—'),
                          _DetailRow(
                            'Tiene hijos',
                            user.tieneHijos ? 'Sí' : 'No',
                          ),
                          _DetailRow(
                            'Estado civil',
                            user.estaCasado ? 'Casado/a' : 'Soltero/a',
                          ),
                          _DetailRow(
                            'Casa propia',
                            user.casaPropia ? 'Sí' : 'No',
                          ),
                          _DetailRow('Vehículo', user.vehiculo ? 'Sí' : 'No'),
                          _DetailRow(
                            'Licencia',
                            user.licenciaConducir ? 'Sí' : 'No',
                          ),
                          _DetailRow(
                            'Fecha de ingreso',
                            user.fechaIngreso != null
                                ? DateFormat('dd/MM/yyyy').format(user.fechaIngreso!)
                                : '—',
                          ),
                          _DetailRow(
                            'Días en la empresa',
                            user.diasEnEmpresa?.toString() ?? '—',
                          ),
                          _DetailRow(
                            'Cuenta nómina preferencial',
                            (user.cuentaNominaPreferencial ?? '').trim().isEmpty
                                ? '—'
                                : user.cuentaNominaPreferencial!.trim(),
                          ),
                          _DetailRow(
                            'Habilidades',
                            user.habilidades.isEmpty
                                ? '—'
                                : user.habilidades.join(', '),
                          ),
                          _DetailRow(
                            'Creado',
                            user.createdAt != null
                                ? DateFormat(
                                    'dd/MM/yyyy',
                                  ).format(user.createdAt!)
                                : '—',
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.photo_library_outlined,
                                color: theme.colorScheme.primary,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Documentos subidos',
                                style: theme.textTheme.titleMedium,
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          _UserDocumentPreviewCard(
                            title: 'Foto de cédula',
                            imageUrl: _resolveUserDocUrl(user.fotoCedulaUrl),
                          ),
                          const SizedBox(height: 10),
                          _UserDocumentPreviewCard(
                            title: 'Foto de licencia',
                            imageUrl: _resolveUserDocUrl(user.fotoLicenciaUrl),
                          ),
                          const SizedBox(height: 10),
                          _UserDocumentPreviewCard(
                            title: 'Foto personal',
                            imageUrl: _resolveUserDocUrl(user.fotoPersonalUrl),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

enum _UserMenuAction { editar, bloquear, eliminar }

class _UserCard extends StatelessWidget {
  const _UserCard({
    required this.user,
    required this.onView,
    required this.onEdit,
    required this.onDelete,
    required this.onToggleBlock,
  });

  final UserModel user;
  final VoidCallback onView;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onToggleBlock;

  @override
  Widget build(BuildContext context) {
    final statusText = user.blocked ? 'Bloqueado' : 'Activo';
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        onTap: onView,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        leading: CircleAvatar(
          backgroundColor: _getRoleColor(user.role),
          child: Text(
            getInitials(user.nombreCompleto),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        title: Text(
          '${user.nombreCompleto} • ${user.role ?? 'Sin rol'} • $statusText',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
        subtitle: Text(
          user.telefono,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: Theme.of(context).colorScheme.outline),
        ),
        trailing: PopupMenuButton<_UserMenuAction>(
          icon: const Icon(Icons.more_vert),
          onSelected: (action) {
            switch (action) {
              case _UserMenuAction.editar:
                onEdit();
                break;
              case _UserMenuAction.bloquear:
                onToggleBlock();
                break;
              case _UserMenuAction.eliminar:
                onDelete();
                break;
            }
          },
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: _UserMenuAction.editar,
              child: Text('Editar'),
            ),
            PopupMenuItem(
              value: _UserMenuAction.bloquear,
              child: Text(user.blocked ? 'Desbloquear' : 'Bloquear'),
            ),
            const PopupMenuItem(
              value: _UserMenuAction.eliminar,
              child: Text('Eliminar'),
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

class _DetailRow extends StatelessWidget {
  const _DetailRow(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
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

class _UserDocumentPreviewCard extends StatelessWidget {
  const _UserDocumentPreviewCard({required this.title, required this.imageUrl});

  final String title;
  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    final hasImage = imageUrl != null && imageUrl!.isNotEmpty;
    final outline = Theme.of(context).colorScheme.outlineVariant;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Container(
              height: 150,
              width: double.infinity,
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: hasImage
                  ? Image.network(
                      imageUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _DocumentImageFallback(
                        text: 'No se pudo cargar la imagen',
                      ),
                    )
                  : const _DocumentImageFallback(text: 'Sin imagen'),
            ),
          ),
        ],
      ),
    );
  }
}

class _DocumentImageFallback extends StatelessWidget {
  const _DocumentImageFallback({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.image_not_supported_outlined,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 6),
          Text(
            text,
            style: TextStyle(
              color: Theme.of(context).colorScheme.outline,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
