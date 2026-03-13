import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/env.dart';
import '../../core/auth/app_role.dart';
import '../../core/auth/auth_provider.dart';
import '../../core/models/user_model.dart';
import '../../core/routing/routes.dart';
import '../../core/utils/string_utils.dart';
import '../../core/widgets/app_drawer.dart';
import '../../core/widgets/custom_app_bar.dart';
import '../user/application/users_controller.dart';
import 'utils/cedula_ocr_service.dart';
import 'utils/work_contract_preview_screen.dart';

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

enum _UserRoleFilter {
  todos,
  administradores,
  tecnicos,
  vendedores,
  asistentes,
  marketing,
}

enum _UserSortOption { nombre, fechaCreacion, rol, estado }

class _UsersScreenBody extends ConsumerStatefulWidget {
  const _UsersScreenBody();

  @override
  ConsumerState<_UsersScreenBody> createState() => _UsersScreenState();
}

class _UsersScreenState extends ConsumerState<_UsersScreenBody> {
  static const double _desktopBreakpoint = 1000;

  final TextEditingController _searchCtrl = TextEditingController();
  bool _searching = false;
  String _searchQuery = '';
  _UserStatusFilter _statusFilter = _UserStatusFilter.todos;
  _UserRoleFilter _roleFilter = _UserRoleFilter.todos;
  _UserSortOption _sortOption = _UserSortOption.nombre;
  String? _selectedDesktopUserId;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  bool _isDesktop(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= _desktopBreakpoint;

  List<UserModel> _filterUsers(List<UserModel> users, {required bool desktop}) {
    final filtered = users
        .where((user) {
          final matchesStatus = switch (_statusFilter) {
            _UserStatusFilter.todos => true,
            _UserStatusFilter.activos => !user.blocked,
            _UserStatusFilter.bloqueados => user.blocked,
          };

          final matchesRole = !desktop
              ? true
              : switch (_roleFilter) {
                  _UserRoleFilter.todos => true,
                  _UserRoleFilter.administradores =>
                    user.appRole == AppRole.admin,
                  _UserRoleFilter.tecnicos => user.appRole == AppRole.tecnico,
                  _UserRoleFilter.vendedores =>
                    user.appRole == AppRole.vendedor,
                  _UserRoleFilter.asistentes =>
                    user.appRole == AppRole.asistente,
                  _UserRoleFilter.marketing =>
                    user.appRole == AppRole.marketing,
                };

          final q = _searchQuery.trim().toLowerCase();
          final matchesSearch = q.isEmpty
              ? true
              : ('${user.nombreCompleto} '
                        '${user.email} '
                        '${user.telefono} '
                        '${user.cedula ?? ''} '
                        '${user.role ?? ''} '
                        '${user.appRole.label}')
                    .toLowerCase()
                    .contains(q);

          return matchesStatus && matchesRole && matchesSearch;
        })
        .toList(growable: false);

    if (!desktop) return filtered;

    final sorted = [...filtered];
    sorted.sort((left, right) {
      switch (_sortOption) {
        case _UserSortOption.nombre:
          return left.nombreCompleto.toLowerCase().compareTo(
            right.nombreCompleto.toLowerCase(),
          );
        case _UserSortOption.fechaCreacion:
          final leftDate =
              left.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          final rightDate =
              right.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          return rightDate.compareTo(leftDate);
        case _UserSortOption.rol:
          return left.appRole.label.compareTo(right.appRole.label);
        case _UserSortOption.estado:
          if (left.blocked == right.blocked) {
            return left.nombreCompleto.toLowerCase().compareTo(
              right.nombreCompleto.toLowerCase(),
            );
          }
          return left.blocked ? 1 : -1;
      }
    });
    return sorted;
  }

  UserModel? _resolveSelectedDesktopUser(List<UserModel> users) {
    if (users.isEmpty) {
      if (_selectedDesktopUserId != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          setState(() => _selectedDesktopUserId = null);
        });
      }
      return null;
    }

    for (final user in users) {
      if (user.id == _selectedDesktopUserId) return user;
    }

    final fallback = users.first;
    if (_selectedDesktopUserId != fallback.id) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() => _selectedDesktopUserId = fallback.id);
      });
    }
    return fallback;
  }

  Future<void> _openWorkContractPreview(
    BuildContext context,
    UserModel user,
  ) async {
    try {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Abriendo contrato...')));
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => WorkContractPreviewScreen(employee: user),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('No se pudo generar: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authStateProvider);
    final currentUser = auth.user;

    if (currentUser?.role != 'ADMIN') {
      return Scaffold(
        appBar: CustomAppBar(
          title: 'FullTech',
          showLogo: true,
          trailing: currentUser == null
              ? null
              : Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(999),
                    onTap: () => context.push(Routes.profile),
                    child: CircleAvatar(
                      radius: 16,
                      backgroundColor: Colors.white24,
                      backgroundImage:
                          (currentUser.fotoPersonalUrl ?? '').trim().isEmpty
                          ? null
                          : NetworkImage(currentUser.fotoPersonalUrl!),
                      child: (currentUser.fotoPersonalUrl ?? '').trim().isEmpty
                          ? Text(
                              getInitials(currentUser.nombreCompleto),
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
        drawer: buildAdaptiveDrawer(context, currentUser: currentUser),
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
                  onPressed: () => context.push(Routes.profile),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final usersState = ref.watch(usersControllerProvider);

    if (_isDesktop(context)) {
      return _buildDesktopScaffold(context, ref, currentUser, usersState);
    }

    return _buildMobileScaffold(context, ref, currentUser, usersState);
  }

  Widget _buildMobileScaffold(
    BuildContext context,
    WidgetRef ref,
    UserModel? currentUser,
    AsyncValue<List<UserModel>> usersState,
  ) {
    return Scaffold(
      appBar: CustomAppBar(
        title: 'Gestión de Usuarios',
        showLogo: false,
        trailing: currentUser == null
            ? null
            : Padding(
                padding: const EdgeInsets.only(right: 12),
                child: InkWell(
                  borderRadius: BorderRadius.circular(999),
                  onTap: () => context.push(Routes.profile),
                  child: CircleAvatar(
                    radius: 16,
                    backgroundColor: Colors.white24,
                    backgroundImage:
                        (currentUser.fotoPersonalUrl ?? '').trim().isEmpty
                        ? null
                        : NetworkImage(currentUser.fotoPersonalUrl!),
                    child: (currentUser.fotoPersonalUrl ?? '').trim().isEmpty
                        ? Text(
                            getInitials(currentUser.nombreCompleto),
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
      drawer: buildAdaptiveDrawer(context, currentUser: currentUser),
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
            final filteredUsers = _filterUsers(users, desktop: false);

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

  Widget _buildDesktopScaffold(
    BuildContext context,
    WidgetRef ref,
    UserModel? currentUser,
    AsyncValue<List<UserModel>> usersState,
  ) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: CustomAppBar(
        title: 'Gestión de Usuarios',
        showLogo: false,
        trailing: currentUser == null
            ? null
            : Padding(
                padding: const EdgeInsets.only(right: 12),
                child: InkWell(
                  borderRadius: BorderRadius.circular(999),
                  onTap: () => context.push(Routes.profile),
                  child: CircleAvatar(
                    radius: 16,
                    backgroundColor: Colors.white24,
                    backgroundImage:
                        (currentUser.fotoPersonalUrl ?? '').trim().isEmpty
                        ? null
                        : NetworkImage(currentUser.fotoPersonalUrl!),
                    child: (currentUser.fotoPersonalUrl ?? '').trim().isEmpty
                        ? Text(
                            getInitials(currentUser.nombreCompleto),
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
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            onPressed: () =>
                ref.read(usersControllerProvider.notifier).refresh(),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      drawer: buildAdaptiveDrawer(context, currentUser: currentUser),
      body: Container(
        color: theme.colorScheme.surfaceContainerLowest,
        child: usersState.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: _DesktopUsersEmptyState(
                  icon: Icons.error_outline,
                  title: 'No se pudieron cargar los usuarios',
                  message: 'Error al cargar usuarios: $e',
                  actionLabel: 'Reintentar',
                  onAction: () =>
                      ref.read(usersControllerProvider.notifier).refresh(),
                ),
              ),
            ),
          ),
          data: (users) {
            final filteredUsers = _filterUsers(users, desktop: true);
            final selectedUser = _resolveSelectedDesktopUser(filteredUsers);
            final activeUsers = users.where((user) => !user.blocked).length;
            final blockedUsers = users.where((user) => user.blocked).length;
            final techUsers = users
                .where((user) => user.appRole == AppRole.tecnico)
                .length;
            final adminUsers = users
                .where((user) => user.appRole == AppRole.admin)
                .length;
            final vendorUsers = users
                .where((user) => user.appRole == AppRole.vendedor)
                .length;
            final currentSelection = selectedUser;

            return Padding(
              padding: const EdgeInsets.fromLTRB(28, 24, 28, 28),
              child: Column(
                children: [
                  _UsersHeaderSection(
                    searchController: _searchCtrl,
                    searchQuery: _searchQuery,
                    statusFilter: _statusFilter,
                    roleFilter: _roleFilter,
                    sortOption: _sortOption,
                    totalUsers: users.length,
                    activeUsers: activeUsers,
                    blockedUsers: blockedUsers,
                    onSearchChanged: (value) =>
                        setState(() => _searchQuery = value),
                    onStatusFilterChanged: (value) =>
                        setState(() => _statusFilter = value),
                    onRoleFilterChanged: (value) =>
                        setState(() => _roleFilter = value),
                    onSortChanged: (value) =>
                        setState(() => _sortOption = value),
                    onAddUser: () => _showUserDialog(context, ref),
                    onClearFilters: () {
                      setState(() {
                        _searchQuery = '';
                        _searchCtrl.clear();
                        _statusFilter = _UserStatusFilter.todos;
                        _roleFilter = _UserRoleFilter.todos;
                        _sortOption = _UserSortOption.nombre;
                      });
                    },
                  ),
                  const SizedBox(height: 18),
                  _UsersStatsRow(
                    items: [
                      _UsersStatData(
                        label: 'Total de usuarios',
                        value: users.length.toString(),
                        icon: Icons.groups_2_outlined,
                        accent: const Color(0xFF0F766E),
                      ),
                      _UsersStatData(
                        label: 'Usuarios activos',
                        value: activeUsers.toString(),
                        icon: Icons.verified_user_outlined,
                        accent: const Color(0xFF15803D),
                      ),
                      _UsersStatData(
                        label: 'Usuarios bloqueados',
                        value: blockedUsers.toString(),
                        icon: Icons.lock_person_outlined,
                        accent: const Color(0xFFB45309),
                      ),
                      _UsersStatData(
                        label: 'Tecnicos',
                        value: techUsers.toString(),
                        icon: Icons.build_circle_outlined,
                        accent: const Color(0xFF2563EB),
                      ),
                      _UsersStatData(
                        label: 'Administradores',
                        value: adminUsers.toString(),
                        icon: Icons.admin_panel_settings_outlined,
                        accent: const Color(0xFF7C3AED),
                      ),
                      _UsersStatData(
                        label: 'Vendedores',
                        value: vendorUsers.toString(),
                        icon: Icons.point_of_sale_outlined,
                        accent: const Color(0xFFEA580C),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          flex: 9,
                          child: _UsersTable(
                            users: filteredUsers,
                            selectedUserId: currentSelection?.id,
                            onSelectUser: (user) => setState(
                              () => _selectedDesktopUserId = user.id,
                            ),
                            onViewUser: (user) => setState(
                              () => _selectedDesktopUserId = user.id,
                            ),
                            onEditUser: (user) =>
                                _showUserDialog(context, ref, user),
                            onDeleteUser: (user) =>
                                _showDeleteDialog(context, ref, user),
                            onToggleBlock: (user) =>
                                _toggleBlock(context, ref, user),
                            onOpenContract: (user) =>
                                _openWorkContractPreview(context, user),
                          ),
                        ),
                        const SizedBox(width: 18),
                        SizedBox(
                          width: 360,
                          child: _UserDetailPanel(
                            user: currentSelection,
                            onEdit: currentSelection == null
                                ? null
                                : () => _showUserDialog(
                                    context,
                                    ref,
                                    currentSelection,
                                  ),
                            onDelete: currentSelection == null
                                ? null
                                : () => _showDeleteDialog(
                                    context,
                                    ref,
                                    currentSelection,
                                  ),
                            onToggleBlock: currentSelection == null
                                ? null
                                : () => _toggleBlock(
                                    context,
                                    ref,
                                    currentSelection,
                                  ),
                            onOpenContract: currentSelection == null
                                ? null
                                : () => _openWorkContractPreview(
                                    context,
                                    currentSelection,
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
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
    final scaffoldContext = context;

    void showSnack(SnackBar snackBar) {
      if (!scaffoldContext.mounted) return;
      final messenger = ScaffoldMessenger.maybeOf(scaffoldContext);
      if (messenger == null) return;
      messenger.showSnackBar(snackBar);
    }

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
    final contractJobTitleCtrl = TextEditingController(
      text: user?.workContractJobTitle ?? '',
    );
    final contractSalaryCtrl = TextEditingController(
      text: user?.workContractSalary ?? '',
    );
    final contractPaymentFrequencyCtrl = TextEditingController(
      text: user?.workContractPaymentFrequency ?? '',
    );
    final contractPaymentMethodCtrl = TextEditingController(
      text: user?.workContractPaymentMethod ?? '',
    );
    final contractWorkScheduleCtrl = TextEditingController(
      text: user?.workContractWorkSchedule ?? '',
    );
    final contractWorkLocationCtrl = TextEditingController(
      text: user?.workContractWorkLocation ?? '',
    );
    final contractCustomClausesCtrl = TextEditingController(
      text: user?.workContractCustomClauses ?? '',
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
    DateTime? workContractStartDate = user?.workContractStartDate;
    final habilidades = [...user?.habilidades ?? const <String>[]];
    String? fotoCedulaUrl = user?.fotoCedulaUrl;
    String? fotoLicenciaUrl = user?.fotoLicenciaUrl;
    String? fotoPersonalUrl = user?.fotoPersonalUrl;
    bool scanningCedula = false;

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
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.document_scanner_outlined),
                    label: Text(
                      scanningCedula
                          ? 'Escaneando cédula...'
                          : 'Escanear cédula (IA)',
                    ),
                    onPressed: scanningCedula
                        ? null
                        : () async {
                            final result = await FilePicker.platform.pickFiles(
                              type: FileType.custom,
                              allowedExtensions: const [
                                'jpg',
                                'jpeg',
                                'png',
                                'webp',
                              ],
                              withData: true,
                            );

                            if (result == null || result.files.isEmpty) return;
                            final file = result.files.first;
                            final bytes = file.bytes;
                            if (bytes == null || bytes.isEmpty) {
                              if (!context.mounted) return;
                              showSnack(
                                const SnackBar(
                                  content: Text(
                                    'No se pudo leer la imagen seleccionada',
                                  ),
                                ),
                              );
                              return;
                            }

                            setModalState(() => scanningCedula = true);
                            try {
                              // 1) Subir imagen automáticamente
                              final uploadedUrl = await ref
                                  .read(usersControllerProvider.notifier)
                                  .uploadDocument(
                                    bytes: bytes,
                                    fileName: file.name,
                                  );
                              setModalState(() => fotoCedulaUrl = uploadedUrl);

                              // 2) OCR para autollenar campos
                              final ocr = ref.read(cedulaOcrServiceProvider);
                              final ocrResult = await ocr.scan(
                                bytes: bytes,
                                fileName: file.name,
                              );

                              final cedula = (ocrResult.cedula ?? '').trim();
                              if (cedula.isNotEmpty &&
                                  cedulaCtrl.text.trim().isEmpty) {
                                cedulaCtrl.text = cedula;
                              }

                              final nombre = (ocrResult.nombreCompleto ?? '')
                                  .trim();
                              if (nombre.isNotEmpty &&
                                  nameCtrl.text.trim().isEmpty) {
                                nameCtrl.text = nombre;
                              }

                              if (ocrResult.fechaNacimiento != null &&
                                  fechaNacimiento == null) {
                                setModalState(
                                  () => fechaNacimiento =
                                      ocrResult.fechaNacimiento,
                                );

                                // Autocalcular edad si está vacía.
                                if (edadCtrl.text.trim().isEmpty) {
                                  final now = DateTime.now();
                                  final dob = ocrResult.fechaNacimiento!;
                                  var age = now.year - dob.year;
                                  final hadBirthdayThisYear =
                                      (now.month > dob.month) ||
                                      (now.month == dob.month &&
                                          now.day >= dob.day);
                                  if (!hadBirthdayThisYear) age -= 1;
                                  if (age >= 0 && age <= 120) {
                                    edadCtrl.text = age.toString();
                                  }
                                }
                              }

                              if (!context.mounted) return;
                              showSnack(
                                const SnackBar(
                                  content: Text(
                                    'Cédula escaneada y datos autollenados',
                                  ),
                                ),
                              );
                            } catch (e) {
                              if (!context.mounted) return;
                              showSnack(
                                SnackBar(
                                  content: Text(
                                    'No se pudo escanear la cédula: $e',
                                  ),
                                ),
                              );
                            } finally {
                              if (context.mounted) {
                                setModalState(() => scanningCedula = false);
                              }
                            }
                          },
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
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Personalización del contrato',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                const SizedBox(height: 8),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Si llenas estos campos, el contrato de este usuario usará estos valores en lugar de los automáticos.',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: contractJobTitleCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Cargo contractual (opcional)',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: contractSalaryCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Salario contractual (opcional)',
                    hintText: 'Ej: RD\$ 25,000.00',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: contractPaymentFrequencyCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Periodicidad de pago (opcional)',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: contractPaymentMethodCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Método de pago (opcional)',
                  ),
                ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Fecha de inicio contractual (opcional)'),
                  subtitle: Text(
                    workContractStartDate == null
                        ? 'Usar fecha de ingreso'
                        : DateFormat(
                            'dd/MM/yyyy',
                          ).format(workContractStartDate!),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (workContractStartDate != null)
                        IconButton(
                          tooltip: 'Quitar fecha',
                          onPressed: () =>
                              setModalState(() => workContractStartDate = null),
                          icon: const Icon(Icons.delete_outline),
                        ),
                      const Icon(Icons.calendar_today_outlined),
                    ],
                  ),
                  onTap: () async {
                    final now = DateTime.now();
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: workContractStartDate ?? fechaIngreso ?? now,
                      firstDate: DateTime(1990),
                      lastDate: DateTime(now.year + 5),
                    );
                    if (picked != null) {
                      setModalState(() => workContractStartDate = picked);
                    }
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: contractWorkScheduleCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Horario contractual (opcional)',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: contractWorkLocationCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Lugar de trabajo contractual (opcional)',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: contractCustomClausesCtrl,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Cláusulas especiales (opcional)',
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
                              onDeleted: () =>
                                  setModalState(() => habilidades.remove(h)),
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
                    final uploaded = await _pickAndUploadImage(
                      scaffoldContext,
                      ref,
                    );
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
                    final uploaded = await _pickAndUploadImage(
                      scaffoldContext,
                      ref,
                    );
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
                    final uploaded = await _pickAndUploadImage(
                      scaffoldContext,
                      ref,
                    );
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
                  showSnack(const SnackBar(content: Text('Edad inválida')));
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
                  'workContractJobTitle': contractJobTitleCtrl.text.trim(),
                  'workContractSalary': contractSalaryCtrl.text.trim(),
                  'workContractPaymentFrequency': contractPaymentFrequencyCtrl
                      .text
                      .trim(),
                  'workContractPaymentMethod': contractPaymentMethodCtrl.text
                      .trim(),
                  'workContractWorkSchedule': contractWorkScheduleCtrl.text
                      .trim(),
                  'workContractWorkLocation': contractWorkLocationCtrl.text
                      .trim(),
                  'workContractCustomClauses': contractCustomClausesCtrl.text
                      .trim(),
                  'workContractStartDate': workContractStartDate
                      ?.toIso8601String(),
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
                  showSnack(
                    const SnackBar(
                      content: Text('La contraseña es obligatoria al crear'),
                    ),
                  );
                  return;
                }

                if (!payload.containsKey('cedula')) {
                  showSnack(
                    const SnackBar(content: Text('La cédula es obligatoria')),
                  );
                  return;
                }

                if (!payload.containsKey('telefonoFamiliar')) {
                  showSnack(
                    const SnackBar(
                      content: Text('El teléfono de familiar es obligatorio'),
                    ),
                  );
                  return;
                }

                if (user == null && !payload.containsKey('fotoCedulaUrl')) {
                  showSnack(
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
                    showSnack(const SnackBar(content: Text('Usuario creado')));
                  } else {
                    await ref
                        .read(usersControllerProvider.notifier)
                        .update(user.id, payload);
                    if (!context.mounted) return;
                    showSnack(
                      const SnackBar(content: Text('Usuario actualizado')),
                    );
                  }
                  if (!context.mounted) return;
                  Navigator.pop(context);
                } catch (e) {
                  if (!context.mounted) return;
                  showSnack(SnackBar(content: Text('Error: $e')));
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
    final scaffoldContext = context;

    void showSnack(SnackBar snackBar) {
      if (!scaffoldContext.mounted) return;
      final messenger = ScaffoldMessenger.maybeOf(scaffoldContext);
      if (messenger == null) return;
      messenger.showSnackBar(snackBar);
    }

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
                showSnack(const SnackBar(content: Text('Usuario eliminado')));
              } catch (e) {
                if (!context.mounted) return;
                showSnack(SnackBar(content: Text('No se pudo eliminar: $e')));
              }
            },
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
  }

  void _showUserDetailsSheet(BuildContext context, UserModel user) {
    final parentContext = context;

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
                          if (!context.mounted) return;
                          final navigator = Navigator.of(context);
                          navigator.pop();
                          await _openWorkContractPreview(parentContext, user);
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
                                ? DateFormat(
                                    'dd/MM/yyyy',
                                  ).format(user.fechaIngreso!)
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

class _UsersHeaderSection extends StatelessWidget {
  const _UsersHeaderSection({
    required this.searchController,
    required this.searchQuery,
    required this.statusFilter,
    required this.roleFilter,
    required this.sortOption,
    required this.totalUsers,
    required this.activeUsers,
    required this.blockedUsers,
    required this.onSearchChanged,
    required this.onStatusFilterChanged,
    required this.onRoleFilterChanged,
    required this.onSortChanged,
    required this.onAddUser,
    required this.onClearFilters,
  });

  final TextEditingController searchController;
  final String searchQuery;
  final _UserStatusFilter statusFilter;
  final _UserRoleFilter roleFilter;
  final _UserSortOption sortOption;
  final int totalUsers;
  final int activeUsers;
  final int blockedUsers;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<_UserStatusFilter> onStatusFilterChanged;
  final ValueChanged<_UserRoleFilter> onRoleFilterChanged;
  final ValueChanged<_UserSortOption> onSortChanged;
  final VoidCallback onAddUser;
  final VoidCallback onClearFilters;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasFilters =
        searchQuery.trim().isNotEmpty ||
        statusFilter != _UserStatusFilter.todos ||
        roleFilter != _UserRoleFilter.todos ||
        sortOption != _UserSortOption.nombre;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFF8FAFC), Color(0xFFF0F9FF)],
        ),
        border: Border.all(color: const Color(0xFFBFDBFE)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 1320;
          final searchWidth = compact ? 280.0 : 360.0;
          final showMiniStats = constraints.maxWidth >= 1180;

          return Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: const Color(0xFFDBEAFE),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(
                        Icons.manage_accounts_outlined,
                        color: Color(0xFF1D4ED8),
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Flexible(
                      child: Text(
                        'Gestión de Usuarios',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF0F172A),
                        ),
                      ),
                    ),
                    if (showMiniStats) ...[
                      const SizedBox(width: 14),
                      _CompactHeaderStat(
                        label: 'Total',
                        value: totalUsers.toString(),
                      ),
                      const SizedBox(width: 8),
                      _CompactHeaderStat(
                        label: 'Activos',
                        value: activeUsers.toString(),
                        accent: const Color(0xFF166534),
                        background: const Color(0xFFDCFCE7),
                      ),
                      const SizedBox(width: 8),
                      _CompactHeaderStat(
                        label: 'Bloq.',
                        value: blockedUsers.toString(),
                        accent: const Color(0xFFB45309),
                        background: const Color(0xFFFFEDD5),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: searchWidth,
                child: TextField(
                  controller: searchController,
                  onChanged: onSearchChanged,
                  decoration: InputDecoration(
                    hintText: 'Buscar usuario',
                    isDense: true,
                    prefixIcon: const Icon(Icons.search, size: 20),
                    suffixIcon: searchQuery.trim().isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Limpiar búsqueda',
                            onPressed: () {
                              searchController.clear();
                              onSearchChanged('');
                            },
                            icon: const Icon(Icons.close, size: 18),
                          ),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              _UsersHeaderFiltersButton(
                hasFilters: hasFilters,
                statusFilter: statusFilter,
                roleFilter: roleFilter,
                sortOption: sortOption,
                onStatusFilterChanged: onStatusFilterChanged,
                onRoleFilterChanged: onRoleFilterChanged,
                onSortChanged: onSortChanged,
                onClearFilters: onClearFilters,
              ),
              const SizedBox(width: 10),
              FilledButton.icon(
                onPressed: onAddUser,
                icon: const Icon(Icons.person_add_alt_1, size: 18),
                label: const Text('Agregar usuario'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  backgroundColor: const Color(0xFF0F172A),
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _CompactHeaderStat extends StatelessWidget {
  const _CompactHeaderStat({
    required this.label,
    required this.value,
    this.accent = const Color(0xFF0F172A),
    this.background = const Color(0xFFFFFFFF),
  });

  final String label;
  final String value;
  final Color accent;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: RichText(
        text: TextSpan(
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: accent,
            fontWeight: FontWeight.w700,
          ),
          children: [
            TextSpan(text: '$label '),
            TextSpan(
              text: value,
              style: TextStyle(color: accent, fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
    );
  }
}

class _UsersHeaderFiltersButton extends StatelessWidget {
  const _UsersHeaderFiltersButton({
    required this.hasFilters,
    required this.statusFilter,
    required this.roleFilter,
    required this.sortOption,
    required this.onStatusFilterChanged,
    required this.onRoleFilterChanged,
    required this.onSortChanged,
    required this.onClearFilters,
  });

  final bool hasFilters;
  final _UserStatusFilter statusFilter;
  final _UserRoleFilter roleFilter;
  final _UserSortOption sortOption;
  final ValueChanged<_UserStatusFilter> onStatusFilterChanged;
  final ValueChanged<_UserRoleFilter> onRoleFilterChanged;
  final ValueChanged<_UserSortOption> onSortChanged;
  final VoidCallback onClearFilters;

  @override
  Widget build(BuildContext context) {
    return Badge(
      isLabelVisible: hasFilters,
      backgroundColor: const Color(0xFF1D4ED8),
      smallSize: 8,
      child: OutlinedButton(
        onPressed: () => showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 24,
              vertical: 24,
            ),
            titlePadding: const EdgeInsets.fromLTRB(20, 18, 12, 8),
            contentPadding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            title: Row(
              children: [
                const Expanded(child: Text('Filtros de usuarios')),
                IconButton(
                  tooltip: 'Cerrar',
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            content: SizedBox(
              width: 320,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<_UserStatusFilter>(
                    initialValue: statusFilter,
                    decoration: const InputDecoration(labelText: 'Estado'),
                    items: const [
                      DropdownMenuItem(
                        value: _UserStatusFilter.todos,
                        child: Text('Todos'),
                      ),
                      DropdownMenuItem(
                        value: _UserStatusFilter.activos,
                        child: Text('Activos'),
                      ),
                      DropdownMenuItem(
                        value: _UserStatusFilter.bloqueados,
                        child: Text('Bloqueados'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) onStatusFilterChanged(value);
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<_UserRoleFilter>(
                    initialValue: roleFilter,
                    decoration: const InputDecoration(labelText: 'Rol'),
                    items: const [
                      DropdownMenuItem(
                        value: _UserRoleFilter.todos,
                        child: Text('Todos los roles'),
                      ),
                      DropdownMenuItem(
                        value: _UserRoleFilter.administradores,
                        child: Text('Administradores'),
                      ),
                      DropdownMenuItem(
                        value: _UserRoleFilter.tecnicos,
                        child: Text('Tecnicos'),
                      ),
                      DropdownMenuItem(
                        value: _UserRoleFilter.vendedores,
                        child: Text('Vendedores'),
                      ),
                      DropdownMenuItem(
                        value: _UserRoleFilter.asistentes,
                        child: Text('Asistentes'),
                      ),
                      DropdownMenuItem(
                        value: _UserRoleFilter.marketing,
                        child: Text('Marketing'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) onRoleFilterChanged(value);
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<_UserSortOption>(
                    initialValue: sortOption,
                    decoration: const InputDecoration(labelText: 'Ordenar por'),
                    items: const [
                      DropdownMenuItem(
                        value: _UserSortOption.nombre,
                        child: Text('Nombre'),
                      ),
                      DropdownMenuItem(
                        value: _UserSortOption.fechaCreacion,
                        child: Text('Fecha de creacion'),
                      ),
                      DropdownMenuItem(
                        value: _UserSortOption.rol,
                        child: Text('Rol'),
                      ),
                      DropdownMenuItem(
                        value: _UserSortOption.estado,
                        child: Text('Estado'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) onSortChanged(value);
                    },
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: hasFilters ? onClearFilters : null,
                          icon: const Icon(Icons.filter_alt_off_outlined),
                          label: const Text('Limpiar'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () => Navigator.of(dialogContext).pop(),
                          icon: const Icon(Icons.check),
                          label: const Text('Aplicar'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(46, 46),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          backgroundColor: Colors.white,
          side: BorderSide(
            color: hasFilters
                ? const Color(0xFF93C5FD)
                : const Color(0xFFCBD5E1),
          ),
        ),
        child: Icon(
          hasFilters ? Icons.tune : Icons.filter_alt_outlined,
          size: 20,
        ),
      ),
    );
  }
}

class _UsersStatData {
  const _UsersStatData({
    required this.label,
    required this.value,
    required this.icon,
    required this.accent,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color accent;
}

class _UsersStatsRow extends StatelessWidget {
  const _UsersStatsRow({required this.items});

  final List<_UsersStatData> items;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1500
            ? 6
            : constraints.maxWidth >= 1150
            ? 3
            : 2;
        final spacing = 14.0;
        final width =
            (constraints.maxWidth - (spacing * (columns - 1))) / columns;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: items
              .map(
                (item) => SizedBox(
                  width: width.clamp(180.0, 320.0),
                  child: _UsersStatCard(item: item),
                ),
              )
              .toList(growable: false),
        );
      },
    );
  }
}

class _UsersStatCard extends StatelessWidget {
  const _UsersStatCard({required this.item});

  final _UsersStatData item;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: item.accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(item.icon, color: item.accent),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 6),
                Text(
                  item.value,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF0F172A),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _UsersTable extends StatelessWidget {
  const _UsersTable({
    required this.users,
    required this.selectedUserId,
    required this.onSelectUser,
    required this.onViewUser,
    required this.onEditUser,
    required this.onDeleteUser,
    required this.onToggleBlock,
    required this.onOpenContract,
  });

  final List<UserModel> users;
  final String? selectedUserId;
  final ValueChanged<UserModel> onSelectUser;
  final ValueChanged<UserModel> onViewUser;
  final ValueChanged<UserModel> onEditUser;
  final ValueChanged<UserModel> onDeleteUser;
  final ValueChanged<UserModel> onToggleBlock;
  final ValueChanged<UserModel> onOpenContract;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 20,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(22, 20, 22, 16),
            decoration: const BoxDecoration(
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              color: Color(0xFFF8FAFC),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Directorio de usuarios',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                Text(
                  users.isEmpty
                      ? 'No hay usuarios para mostrar con los filtros actuales.'
                      : '${users.length} usuario${users.length == 1 ? '' : 's'} visible${users.length == 1 ? '' : 's'} en escritorio.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF64748B),
                  ),
                ),
                const SizedBox(height: 18),
                const _UsersTableHeader(),
              ],
            ),
          ),
          Expanded(
            child: users.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: _DesktopUsersEmptyState(
                        icon: Icons.group_off_outlined,
                        title: 'Sin resultados',
                        message:
                            'Prueba otro término de búsqueda o ajusta los filtros para encontrar usuarios.',
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(14),
                    itemCount: users.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final user = users[index];
                      return _UserRowCard(
                        user: user,
                        selected: user.id == selectedUserId,
                        onSelect: () => onSelectUser(user),
                        onView: () => onViewUser(user),
                        onEdit: () => onEditUser(user),
                        onDelete: () => onDeleteUser(user),
                        onToggleBlock: () => onToggleBlock(user),
                        onOpenContract: () => onOpenContract(user),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _UsersTableHeader extends StatelessWidget {
  const _UsersTableHeader();

  @override
  Widget build(BuildContext context) {
    return DefaultTextStyle(
      style: Theme.of(context).textTheme.labelLarge!.copyWith(
        color: const Color(0xFF64748B),
        fontWeight: FontWeight.w700,
      ),
      child: const Row(
        children: [
          Expanded(flex: 33, child: Text('Usuario')),
          Expanded(flex: 16, child: Text('Telefono')),
          Expanded(flex: 14, child: Text('Rol')),
          Expanded(flex: 14, child: Text('Estado')),
          Expanded(flex: 11, child: Text('Creado')),
          Expanded(flex: 12, child: Text('Ultima actividad')),
          SizedBox(width: 172, child: Text('Acciones')),
        ],
      ),
    );
  }
}

class _UserRowCard extends StatefulWidget {
  const _UserRowCard({
    required this.user,
    required this.selected,
    required this.onSelect,
    required this.onView,
    required this.onEdit,
    required this.onDelete,
    required this.onToggleBlock,
    required this.onOpenContract,
  });

  final UserModel user;
  final bool selected;
  final VoidCallback onSelect;
  final VoidCallback onView;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onToggleBlock;
  final VoidCallback onOpenContract;

  @override
  State<_UserRowCard> createState() => _UserRowCardState();
}

class _UserRowCardState extends State<_UserRowCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final surfaceColor = widget.selected
        ? const Color(0xFFEFF6FF)
        : _hovered
        ? const Color(0xFFF8FAFC)
        : theme.colorScheme.surface;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Material(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(22),
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: widget.onSelect,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: widget.selected
                    ? const Color(0xFF93C5FD)
                    : theme.colorScheme.outlineVariant,
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  flex: 33,
                  child: Row(
                    children: [
                      _UserAvatar(user: widget.user, radius: 24),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.user.nombreCompleto,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              widget.user.email,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: const Color(0xFF64748B),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  flex: 16,
                  child: Text(
                    widget.user.telefono,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Expanded(
                  flex: 14,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: _UserRoleBadge(role: widget.user.appRole),
                  ),
                ),
                Expanded(
                  flex: 14,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: _UserStatusBadge(blocked: widget.user.blocked),
                  ),
                ),
                Expanded(
                  flex: 11,
                  child: Text(_formatOptionalDate(widget.user.createdAt)),
                ),
                const Expanded(flex: 12, child: Text('Sin datos')),
                SizedBox(
                  width: 172,
                  child: Row(
                    children: [
                      _RowActionButton(
                        tooltip: 'Ver detalle',
                        icon: Icons.visibility_outlined,
                        onPressed: widget.onView,
                      ),
                      const SizedBox(width: 4),
                      _RowActionButton(
                        tooltip: 'Editar usuario',
                        icon: Icons.edit_outlined,
                        onPressed: widget.onEdit,
                      ),
                      const SizedBox(width: 4),
                      _RowActionButton(
                        tooltip: widget.user.blocked
                            ? 'Desbloquear usuario'
                            : 'Bloquear usuario',
                        icon: widget.user.blocked
                            ? Icons.lock_open_outlined
                            : Icons.lock_outline,
                        onPressed: widget.onToggleBlock,
                      ),
                      const SizedBox(width: 4),
                      _UserActionsMenu(
                        user: widget.user,
                        onView: widget.onView,
                        onEdit: widget.onEdit,
                        onDelete: widget.onDelete,
                        onToggleBlock: widget.onToggleBlock,
                        onOpenContract: widget.onOpenContract,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RowActionButton extends StatelessWidget {
  const _RowActionButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
          ),
          child: Icon(icon, size: 18),
        ),
      ),
    );
  }
}

enum _DesktopUserMenuAction {
  ver,
  editar,
  bloquear,
  contrato,
  cambiarRol,
  resetearAcceso,
  eliminar,
}

class _UserActionsMenu extends StatelessWidget {
  const _UserActionsMenu({
    required this.user,
    required this.onView,
    required this.onEdit,
    required this.onDelete,
    required this.onToggleBlock,
    required this.onOpenContract,
  });

  final UserModel user;
  final VoidCallback onView;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onToggleBlock;
  final VoidCallback onOpenContract;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_DesktopUserMenuAction>(
      tooltip: 'Mas acciones',
      icon: const Icon(Icons.more_horiz),
      onSelected: (value) {
        switch (value) {
          case _DesktopUserMenuAction.ver:
            onView();
            break;
          case _DesktopUserMenuAction.editar:
            onEdit();
            break;
          case _DesktopUserMenuAction.bloquear:
            onToggleBlock();
            break;
          case _DesktopUserMenuAction.contrato:
            onOpenContract();
            break;
          case _DesktopUserMenuAction.cambiarRol:
            onEdit();
            break;
          case _DesktopUserMenuAction.resetearAcceso:
            onEdit();
            break;
          case _DesktopUserMenuAction.eliminar:
            onDelete();
            break;
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: _DesktopUserMenuAction.ver,
          child: Text('Ver detalle'),
        ),
        const PopupMenuItem(
          value: _DesktopUserMenuAction.editar,
          child: Text('Editar usuario'),
        ),
        PopupMenuItem(
          value: _DesktopUserMenuAction.bloquear,
          child: Text(user.blocked ? 'Desbloquear' : 'Bloquear'),
        ),
        const PopupMenuItem(
          value: _DesktopUserMenuAction.contrato,
          child: Text('Abrir contrato'),
        ),
        const PopupMenuItem(
          value: _DesktopUserMenuAction.cambiarRol,
          child: Text('Cambiar rol'),
        ),
        const PopupMenuItem(
          value: _DesktopUserMenuAction.resetearAcceso,
          child: Text('Resetear acceso'),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: _DesktopUserMenuAction.eliminar,
          child: Text('Eliminar'),
        ),
      ],
    );
  }
}

class _UserStatusBadge extends StatelessWidget {
  const _UserStatusBadge({required this.blocked});

  final bool blocked;

  @override
  Widget build(BuildContext context) {
    final background = blocked
        ? const Color(0xFFFFEDD5)
        : const Color(0xFFDCFCE7);
    final foreground = blocked
        ? const Color(0xFFB45309)
        : const Color(0xFF166534);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        blocked ? 'Bloqueado' : 'Activo',
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: foreground,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _UserRoleBadge extends StatelessWidget {
  const _UserRoleBadge({required this.role});

  final AppRole role;

  @override
  Widget build(BuildContext context) {
    final colors = switch (role) {
      AppRole.admin => (const Color(0xFFFCE7F3), const Color(0xFF9D174D)),
      AppRole.asistente => (const Color(0xFFECFDF5), const Color(0xFF047857)),
      AppRole.vendedor => (const Color(0xFFEFF6FF), const Color(0xFF1D4ED8)),
      AppRole.marketing => (const Color(0xFFF5F3FF), const Color(0xFF6D28D9)),
      AppRole.tecnico => (const Color(0xFFFFF7ED), const Color(0xFFC2410C)),
      AppRole.unknown => (const Color(0xFFF1F5F9), const Color(0xFF475569)),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colors.$1,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        role.label.isEmpty ? 'Sin rol' : role.label,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: colors.$2,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _UserDetailPanel extends StatelessWidget {
  const _UserDetailPanel({
    required this.user,
    required this.onEdit,
    required this.onDelete,
    required this.onToggleBlock,
    required this.onOpenContract,
  });

  final UserModel? user;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onToggleBlock;
  final VoidCallback? onOpenContract;

  @override
  Widget build(BuildContext context) {
    if (user == null) {
      return const _DesktopUsersEmptyState(
        icon: Icons.person_search_outlined,
        title: 'Selecciona un usuario',
        message:
            'Haz clic en una fila para revisar su perfil, estado, documentos y acciones disponibles.',
      );
    }

    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: theme.colorScheme.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 20,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _UserAvatar(user: user!, radius: 30),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user!.nombreCompleto,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        user!.email,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: const Color(0xFF64748B),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _UserRoleBadge(role: user!.appRole),
                          _UserStatusBadge(blocked: user!.blocked),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Editar'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onToggleBlock,
                    icon: Icon(
                      user!.blocked
                          ? Icons.lock_open_outlined
                          : Icons.lock_outline,
                    ),
                    label: Text(user!.blocked ? 'Desbloquear' : 'Bloquear'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onOpenContract,
                    icon: const Icon(Icons.picture_as_pdf_outlined),
                    label: const Text('Contrato'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Eliminar'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: theme.colorScheme.error,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Text(
              'Cambio de rol y reseteo de acceso se gestionan desde Editar usuario para mantener la lógica existente.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: const Color(0xFF64748B),
                height: 1.4,
              ),
            ),
            const SizedBox(height: 20),
            _DetailSection(
              title: 'Resumen',
              children: [
                _DetailLine(label: 'Telefono', value: user!.telefono),
                _DetailLine(
                  label: 'Telefono familiar',
                  value: _fallbackText(user!.telefonoFamiliar),
                ),
                _DetailLine(
                  label: 'Cedula',
                  value: _fallbackText(user!.cedula),
                ),
                _DetailLine(
                  label: 'Fecha de registro',
                  value: _formatOptionalDate(user!.createdAt),
                ),
                const _DetailLine(
                  label: 'Ultima actividad',
                  value: 'Sin datos',
                ),
              ],
            ),
            const SizedBox(height: 14),
            _DetailSection(
              title: 'Contexto laboral',
              children: [
                _DetailLine(
                  label: 'Fecha de ingreso',
                  value: _formatOptionalDate(user!.fechaIngreso),
                ),
                _DetailLine(
                  label: 'Dias en empresa',
                  value: user!.diasEnEmpresa?.toString() ?? 'Sin datos',
                ),
                _DetailLine(
                  label: 'Cuenta nomina',
                  value: _fallbackText(user!.cuentaNominaPreferencial),
                ),
                _DetailLine(
                  label: 'Permisos / habilidades',
                  value: user!.habilidades.isEmpty
                      ? 'Sin datos'
                      : user!.habilidades.join(', '),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _DetailSection(
              title: 'Documentos',
              children: [
                _UserDocumentPreviewCard(
                  title: 'Foto de cédula',
                  imageUrl: _resolveUserDocUrl(user!.fotoCedulaUrl),
                ),
                const SizedBox(height: 10),
                _UserDocumentPreviewCard(
                  title: 'Foto de licencia',
                  imageUrl: _resolveUserDocUrl(user!.fotoLicenciaUrl),
                ),
                const SizedBox(height: 10),
                _UserDocumentPreviewCard(
                  title: 'Foto personal',
                  imageUrl: _resolveUserDocUrl(user!.fotoPersonalUrl),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailSection extends StatelessWidget {
  const _DetailSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }
}

class _DetailLine extends StatelessWidget {
  const _DetailLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.labelLarge?.copyWith(color: const Color(0xFF64748B)),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _UserAvatar extends StatelessWidget {
  const _UserAvatar({required this.user, required this.radius});

  final UserModel user;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final role = user.appRole;
    final background = switch (role) {
      AppRole.admin => const Color(0xFF9D174D),
      AppRole.asistente => const Color(0xFF047857),
      AppRole.vendedor => const Color(0xFF1D4ED8),
      AppRole.marketing => const Color(0xFF6D28D9),
      AppRole.tecnico => const Color(0xFFC2410C),
      AppRole.unknown => const Color(0xFF475569),
    };

    final imageUrl = (user.fotoPersonalUrl ?? '').trim();
    return CircleAvatar(
      radius: radius,
      backgroundColor: background,
      backgroundImage: imageUrl.isEmpty ? null : NetworkImage(imageUrl),
      child: imageUrl.isEmpty
          ? Text(
              getInitials(user.nombreCompleto),
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: radius * 0.72,
              ),
            )
          : null,
    );
  }
}

class _DesktopUsersEmptyState extends StatelessWidget {
  const _DesktopUsersEmptyState({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: const Color(0xFFE0F2FE),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(icon, size: 30, color: const Color(0xFF0284C7)),
          ),
          const SizedBox(height: 14),
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: const Color(0xFF64748B),
              height: 1.45,
            ),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 16),
            FilledButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ],
      ),
    );
  }
}

String _formatOptionalDate(DateTime? date) {
  if (date == null) return 'Sin datos';
  return DateFormat('dd/MM/yyyy').format(date);
}

String _fallbackText(String? value) {
  final text = value?.trim() ?? '';
  return text.isEmpty ? 'Sin datos' : text;
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
