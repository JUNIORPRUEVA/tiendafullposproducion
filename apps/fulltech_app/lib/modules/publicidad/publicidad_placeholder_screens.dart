import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

import '../../core/auth/app_permissions.dart';
import '../../core/auth/auth_provider.dart';
import '../../core/utils/safe_url_launcher.dart';
import '../../core/widgets/app_drawer.dart';
import '../../core/widgets/custom_app_bar.dart';
import 'marketing_api.dart';
import 'marketing_social_accounts_models.dart';

class PublicidadMarketplaceScreen extends ConsumerStatefulWidget {
  const PublicidadMarketplaceScreen({super.key});

  @override
  ConsumerState<PublicidadMarketplaceScreen> createState() =>
      _PublicidadMarketplaceScreenState();
}

class _PublicidadMarketplaceScreenState
    extends ConsumerState<PublicidadMarketplaceScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final TextEditingController _searchCtrl = TextEditingController();
  final Set<String> _visiblePasswords = <String>{};
  List<MarketingSocialAccount> _accounts = const [];
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() {});
      }
    });
    _loadAccounts();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  MarketingSocialAccountType get _selectedType {
    switch (_tabController.index) {
      case 1:
        return MarketingSocialAccountType.instagram;
      case 2:
        return MarketingSocialAccountType.whatsapp;
      case 0:
      default:
        return MarketingSocialAccountType.facebook;
    }
  }

  Future<void> _loadAccounts() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await ref.read(marketingApiProvider).loadSocialAccounts();
      if (!mounted) return;
      setState(() => _accounts = rows);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _openCreateDialog() async {
    final result = await showDialog<_SocialAccountEditResult>(
      context: context,
      builder: (context) => _SocialAccountEditorDialog(type: _selectedType),
    );
    if (result == null) return;
    try {
      await ref.read(marketingApiProvider).createSocialAccount(
            type: result.type,
            accountName: result.accountName,
            username: result.username,
            password: result.password,
            profileLink: result.profileLink,
            whatsappNumber: result.whatsappNumber,
            observations: result.observations,
            avatarUrl: result.avatarUrl,
            isActive: result.isActive,
          );
      if (!mounted) return;
      _showMessage('Cuenta creada correctamente.');
      await _loadAccounts();
    } catch (e) {
      if (!mounted) return;
      _showMessage('No se pudo crear la cuenta: $e');
    }
  }

  Future<void> _openEditDialog(MarketingSocialAccount account) async {
    final result = await showDialog<_SocialAccountEditResult>(
      context: context,
      builder: (context) => _SocialAccountEditorDialog(
        type: account.type,
        initial: account,
      ),
    );
    if (result == null) return;
    try {
      await ref.read(marketingApiProvider).updateSocialAccount(
            account.id,
            type: result.type,
            accountName: result.accountName,
            username: result.username,
            password: result.password,
            profileLink: result.profileLink,
            whatsappNumber: result.whatsappNumber,
            observations: result.observations,
            avatarUrl: result.avatarUrl,
            isActive: result.isActive,
          );
      if (!mounted) return;
      _showMessage('Cuenta actualizada correctamente.');
      await _loadAccounts();
    } catch (e) {
      if (!mounted) return;
      _showMessage('No se pudo actualizar: $e');
    }
  }

  Future<void> _deleteAccount(MarketingSocialAccount account) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar cuenta empresarial'),
        content: Text(
          'Se eliminará ${account.accountName}. Esta acción no se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      await ref.read(marketingApiProvider).deleteSocialAccount(account.id);
      if (!mounted) return;
      _showMessage('Cuenta eliminada correctamente.');
      await _loadAccounts();
    } catch (e) {
      if (!mounted) return;
      _showMessage('No se pudo eliminar: $e');
    }
  }

  Future<void> _copyField(String label, String value) async {
    if (value.trim().isEmpty) {
      _showMessage('No hay valor para copiar en $label.');
      return;
    }
    await Clipboard.setData(ClipboardData(text: value.trim()));
    if (!mounted) return;
    _showMessage('$label copiado.');
  }

  Future<void> _copyAll(MarketingSocialAccount account) async {
    final payload = [
      'Tipo: ${_tabLabel(account.type)}',
      'Nombre: ${account.accountName}',
      if ((account.username ?? '').trim().isNotEmpty)
        'Usuario: ${account.username!.trim()}',
      if ((account.password ?? '').trim().isNotEmpty)
        'Contrasena: ${account.password!.trim()}',
      if ((account.whatsappNumber ?? '').trim().isNotEmpty)
        'Whatsapp: ${account.whatsappNumber!.trim()}',
      if ((account.profileLink ?? '').trim().isNotEmpty)
        'Perfil: ${account.profileLink!.trim()}',
      if ((account.whatsappWaLink ?? '').trim().isNotEmpty)
        'wa.me: ${account.whatsappWaLink!.trim()}',
      if ((account.observations ?? '').trim().isNotEmpty)
        'Observaciones: ${account.observations!.trim()}',
    ].join('\n');
    await Clipboard.setData(ClipboardData(text: payload));
    if (!mounted) return;
    _showMessage('Datos de la cuenta copiados.');
  }

  Future<void> _openProfile(MarketingSocialAccount account) async {
    final candidate = account.type == MarketingSocialAccountType.whatsapp
        ? (account.whatsappWaLink ?? account.profileLink ?? '')
        : (account.profileLink ?? '');
    final link = candidate.trim();
    if (link.isEmpty) {
      _showMessage('Esta cuenta no tiene link de perfil.');
      return;
    }
    final uri = Uri.tryParse(link);
    if (uri == null) {
      _showMessage('El link de perfil no es válido.');
      return;
    }

    if (account.type == MarketingSocialAccountType.whatsapp) {
      await safeOpenWhatsApp(
        context,
        uri,
        copiedMessage: 'No se pudo abrir WhatsApp. Link copiado.',
      );
      return;
    }

    await safeOpenUrl(
      context,
      uri,
      copiedMessage: 'No se pudo abrir el perfil. Link copiado.',
    );
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  String _tabLabel(MarketingSocialAccountType type) {
    switch (type) {
      case MarketingSocialAccountType.facebook:
        return 'Facebook';
      case MarketingSocialAccountType.instagram:
        return 'Instagram';
      case MarketingSocialAccountType.whatsapp:
        return 'WhatsApp';
    }
  }

  IconData _tabIcon(MarketingSocialAccountType type) {
    switch (type) {
      case MarketingSocialAccountType.facebook:
        return Icons.facebook_rounded;
      case MarketingSocialAccountType.instagram:
        return Icons.photo_camera_back_rounded;
      case MarketingSocialAccountType.whatsapp:
        return Icons.chat_bubble_rounded;
    }
  }

  String _formatDate(DateTime? value) {
    if (value == null) return '-';
    final day = value.day.toString().padLeft(2, '0');
    final month = value.month.toString().padLeft(2, '0');
    final year = value.year;
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '$day/$month/$year $hour:$minute';
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authStateProvider);
    final user = auth.user;
    final isAdmin =
        user != null && hasPermission(user.appRole, AppPermission.viewPublicidad);
    final scheme = Theme.of(context).colorScheme;

    if (!isAdmin) {
      return Scaffold(
        appBar: const CustomAppBar(title: 'Publicidad', showLogo: false),
        body: const Center(
          child: Text('Acceso denegado. Solo ADMIN puede usar Publicidad.'),
        ),
      );
    }

    final selectedType = _selectedType;
    final query = _searchCtrl.text.trim().toLowerCase();
    final filtered = _accounts.where((item) {
      if (item.type != selectedType) return false;
      if (query.isEmpty) return true;
      final haystack = [
        item.accountName,
        item.username ?? '',
        item.whatsappNumber ?? '',
        item.profileLink ?? '',
        item.observations ?? '',
      ].join(' ').toLowerCase();
      return haystack.contains(query);
    }).toList(growable: false);

    return Scaffold(
      drawer: buildAdaptiveDrawer(context, currentUser: user),
      appBar: const CustomAppBar(title: 'Publicidad / Marketplace / Cuentas Empresariales'),
      backgroundColor: scheme.surfaceContainerLowest,
      body: RefreshIndicator(
        onRefresh: _loadAccounts,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 18),
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              decoration: BoxDecoration(
                color: scheme.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.35)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        'Boveda de Cuentas Empresariales',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                        decoration: BoxDecoration(
                          color: scheme.primaryContainer.withValues(alpha: 0.75),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          '${_accounts.length} cuentas',
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _searchCtrl,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      isDense: true,
                      prefixIcon: const Icon(Icons.search_rounded),
                      hintText: 'Buscar por nombre, usuario, numero o link',
                      suffixIcon: _searchCtrl.text.isEmpty
                          ? null
                          : IconButton(
                              onPressed: () {
                                _searchCtrl.clear();
                                setState(() {});
                              },
                              icon: const Icon(Icons.close_rounded),
                            ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TabBar(
                    controller: _tabController,
                    isScrollable: true,
                    tabAlignment: TabAlignment.start,
                    tabs: const [
                      Tab(icon: Icon(Icons.facebook_rounded), text: 'Facebook'),
                      Tab(icon: Icon(Icons.photo_camera_back_rounded), text: 'Instagram'),
                      Tab(icon: Icon(Icons.chat_bubble_rounded), text: 'WhatsApp'),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                FilledButton.icon(
                  onPressed: _openCreateDialog,
                  icon: const Icon(Icons.add_rounded),
                  label: Text('Agregar ${_tabLabel(selectedType)}'),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: _loadAccounts,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Recargar'),
                ),
              ],
            ),
            if (_loading) ...[
              const SizedBox(height: 14),
              const LinearProgressIndicator(),
            ],
            if (_error != null) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFFECACA)),
                ),
                child: Text(
                  _error!,
                  style: const TextStyle(color: Color(0xFF991B1B)),
                ),
              ),
            ],
            const SizedBox(height: 10),
            if (!_loading && filtered.isEmpty)
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: scheme.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.35)),
                ),
                child: Text(
                  'No hay cuentas para ${_tabLabel(selectedType)} con el filtro actual.',
                ),
              )
            else
              ...filtered.map((account) {
                final showPassword = _visiblePasswords.contains(account.id);
                final password = (account.password ?? '').trim();
                final hasPassword = password.isNotEmpty;
                final link = (account.type == MarketingSocialAccountType.whatsapp
                        ? account.whatsappWaLink ?? account.profileLink ?? ''
                        : account.profileLink ?? '')
                    .trim();

                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _SocialAccountCard(
                    account: account,
                    titleLabel: _tabLabel(account.type),
                    icon: _tabIcon(account.type),
                    createdLabel: _formatDate(account.createdAt),
                    updatedLabel: _formatDate(account.updatedAt),
                    passwordText: showPassword ? password : (hasPassword ? '••••••••' : '-'),
                    onTogglePassword: hasPassword
                        ? () {
                            setState(() {
                              if (showPassword) {
                                _visiblePasswords.remove(account.id);
                              } else {
                                _visiblePasswords.add(account.id);
                              }
                            });
                          }
                        : null,
                    onCopyUser: () => _copyField(
                      account.type == MarketingSocialAccountType.whatsapp
                          ? 'Numero'
                          : 'Usuario',
                      account.type == MarketingSocialAccountType.whatsapp
                          ? (account.whatsappNumber ?? '')
                          : (account.username ?? ''),
                    ),
                    onCopyPassword: hasPassword
                        ? () => _copyField('Contrasena', password)
                        : null,
                    onCopyLink: link.isNotEmpty
                        ? () => _copyField('Link', link)
                        : null,
                    onOpenProfile: () => _openProfile(account),
                    onCopyAll: () => _copyAll(account),
                    onEdit: () => _openEditDialog(account),
                    onDelete: () => _deleteAccount(account),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}

class _SocialAccountCard extends StatefulWidget {
  const _SocialAccountCard({
    required this.account,
    required this.titleLabel,
    required this.icon,
    required this.createdLabel,
    required this.updatedLabel,
    required this.passwordText,
    required this.onTogglePassword,
    required this.onCopyUser,
    required this.onCopyPassword,
    required this.onCopyLink,
    required this.onOpenProfile,
    required this.onCopyAll,
    required this.onEdit,
    required this.onDelete,
  });

  final MarketingSocialAccount account;
  final String titleLabel;
  final IconData icon;
  final String createdLabel;
  final String updatedLabel;
  final String passwordText;
  final VoidCallback? onTogglePassword;
  final VoidCallback onCopyUser;
  final VoidCallback? onCopyPassword;
  final VoidCallback? onCopyLink;
  final VoidCallback onOpenProfile;
  final VoidCallback onCopyAll;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  State<_SocialAccountCard> createState() => _SocialAccountCardState();
}

class _SocialAccountCardState extends State<_SocialAccountCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          color: _hovered ? scheme.surfaceContainerLow : scheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: _hovered
                ? scheme.primary.withValues(alpha: 0.35)
                : scheme.outlineVariant.withValues(alpha: 0.35),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: _hovered ? 0.05 : 0.02),
              blurRadius: _hovered ? 14 : 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: scheme.primaryContainer.withValues(alpha: 0.75),
                  backgroundImage: (widget.account.avatarUrl ?? '').trim().isNotEmpty
                      ? NetworkImage(widget.account.avatarUrl!.trim())
                      : null,
                  child: (widget.account.avatarUrl ?? '').trim().isEmpty
                      ? Icon(widget.icon, size: 18, color: scheme.onPrimaryContainer)
                      : null,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.account.accountName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.titleLabel,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: widget.account.isActive
                        ? const Color(0xFFDCFCE7)
                        : const Color(0xFFF3F4F6),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    widget.account.isActive ? 'Activa' : 'Inactiva',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 11,
                      color: widget.account.isActive
                          ? const Color(0xFF166534)
                          : const Color(0xFF4B5563),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                _InfoText(
                  label: widget.account.type == MarketingSocialAccountType.whatsapp
                      ? 'Numero'
                      : 'Usuario',
                  value: widget.account.displayUserOrNumber,
                ),
                if (widget.account.type != MarketingSocialAccountType.whatsapp)
                  _InfoText(
                    label: 'Contrasena',
                    value: widget.passwordText,
                  ),
                _InfoText(
                  label: 'Creada',
                  value: widget.createdLabel,
                ),
                _InfoText(
                  label: 'Ult. modificacion',
                  value: widget.updatedLabel,
                ),
              ],
            ),
            if ((widget.account.observations ?? '').trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                widget.account.observations!.trim(),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: widget.onCopyUser,
                  icon: const Icon(Icons.copy_rounded, size: 16),
                  label: Text(
                    widget.account.type == MarketingSocialAccountType.whatsapp
                        ? 'Copiar numero'
                        : 'Copiar usuario',
                  ),
                ),
                if (widget.account.type != MarketingSocialAccountType.whatsapp)
                  OutlinedButton.icon(
                    onPressed: widget.onCopyPassword,
                    icon: const Icon(Icons.key_rounded, size: 16),
                    label: const Text('Copiar contrasena'),
                  ),
                if (widget.account.type != MarketingSocialAccountType.whatsapp)
                  OutlinedButton.icon(
                    onPressed: widget.onTogglePassword,
                    icon: const Icon(Icons.remove_red_eye_outlined, size: 16),
                    label: const Text('Mostrar/Ocultar'),
                  ),
                OutlinedButton.icon(
                  onPressed: widget.onCopyLink,
                  icon: const Icon(Icons.link_rounded, size: 16),
                  label: const Text('Copiar link'),
                ),
                FilledButton.icon(
                  onPressed: widget.onOpenProfile,
                  icon: const Icon(Icons.open_in_new_rounded, size: 16),
                  label: const Text('Abrir perfil'),
                ),
                OutlinedButton.icon(
                  onPressed: widget.onCopyAll,
                  icon: const Icon(Icons.content_copy_rounded, size: 16),
                  label: const Text('Copiar todo'),
                ),
                OutlinedButton.icon(
                  onPressed: widget.onEdit,
                  icon: const Icon(Icons.edit_rounded, size: 16),
                  label: const Text('Editar'),
                ),
                OutlinedButton.icon(
                  onPressed: widget.onDelete,
                  icon: const Icon(Icons.delete_outline_rounded, size: 16),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFB91C1C),
                  ),
                  label: const Text('Eliminar'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoText extends StatelessWidget {
  const _InfoText({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return RichText(
      text: TextSpan(
        style: Theme.of(context).textTheme.bodySmall,
        children: [
          TextSpan(
            text: '$label: ',
            style: TextStyle(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          TextSpan(
            text: value,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _SocialAccountEditResult {
  const _SocialAccountEditResult({
    required this.type,
    required this.accountName,
    required this.username,
    required this.password,
    required this.profileLink,
    required this.whatsappNumber,
    required this.observations,
    required this.avatarUrl,
    required this.isActive,
  });

  final MarketingSocialAccountType type;
  final String accountName;
  final String? username;
  final String? password;
  final String? profileLink;
  final String? whatsappNumber;
  final String? observations;
  final String? avatarUrl;
  final bool isActive;
}

class _SocialAccountEditorDialog extends StatefulWidget {
  const _SocialAccountEditorDialog({required this.type, this.initial});

  final MarketingSocialAccountType type;
  final MarketingSocialAccount? initial;

  @override
  State<_SocialAccountEditorDialog> createState() =>
      _SocialAccountEditorDialogState();
}

class _SocialAccountEditorDialogState extends State<_SocialAccountEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  late MarketingSocialAccountType _type;
  late TextEditingController _nameCtrl;
  late TextEditingController _userCtrl;
  late TextEditingController _passCtrl;
  late TextEditingController _linkCtrl;
  late TextEditingController _phoneCtrl;
  late TextEditingController _obsCtrl;
  late TextEditingController _avatarCtrl;
  bool _isActive = true;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _type = initial?.type ?? widget.type;
    _nameCtrl = TextEditingController(text: initial?.accountName ?? '');
    _userCtrl = TextEditingController(text: initial?.username ?? '');
    _passCtrl = TextEditingController(text: initial?.password ?? '');
    _linkCtrl = TextEditingController(
      text: initial?.profileLink ?? initial?.whatsappWaLink ?? '',
    );
    _phoneCtrl = TextEditingController(text: initial?.whatsappNumber ?? '');
    _obsCtrl = TextEditingController(text: initial?.observations ?? '');
    _avatarCtrl = TextEditingController(text: initial?.avatarUrl ?? '');
    _isActive = initial?.isActive ?? true;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    _linkCtrl.dispose();
    _phoneCtrl.dispose();
    _obsCtrl.dispose();
    _avatarCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isWhatsapp = _type == MarketingSocialAccountType.whatsapp;

    return AlertDialog(
      title: Text(widget.initial == null ? 'Agregar cuenta' : 'Editar cuenta'),
      content: SizedBox(
        width: 560,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<MarketingSocialAccountType>(
                  value: _type,
                  decoration: const InputDecoration(labelText: 'Tipo de cuenta'),
                  items: const [
                    DropdownMenuItem(
                      value: MarketingSocialAccountType.facebook,
                      child: Text('Facebook'),
                    ),
                    DropdownMenuItem(
                      value: MarketingSocialAccountType.instagram,
                      child: Text('Instagram'),
                    ),
                    DropdownMenuItem(
                      value: MarketingSocialAccountType.whatsapp,
                      child: Text('WhatsApp'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => _type = value);
                  },
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _nameCtrl,
                  decoration: InputDecoration(
                    labelText: isWhatsapp ? 'Nombre' : 'Nombre de la cuenta',
                  ),
                  validator: (value) => (value ?? '').trim().isEmpty
                      ? 'Este campo es obligatorio'
                      : null,
                ),
                const SizedBox(height: 10),
                if (!isWhatsapp)
                  TextFormField(
                    controller: _userCtrl,
                    decoration: const InputDecoration(labelText: 'Usuario o correo'),
                    validator: (value) => (value ?? '').trim().isEmpty
                        ? 'Debes indicar usuario o correo'
                        : null,
                  )
                else
                  TextFormField(
                    controller: _phoneCtrl,
                    decoration: const InputDecoration(labelText: 'Numero WhatsApp'),
                    validator: (value) => (value ?? '').trim().isEmpty
                        ? 'Debes indicar el numero de WhatsApp'
                        : null,
                  ),
                const SizedBox(height: 10),
                if (!isWhatsapp)
                  TextFormField(
                    controller: _passCtrl,
                    decoration: const InputDecoration(labelText: 'Contrasena'),
                  ),
                if (!isWhatsapp) const SizedBox(height: 10),
                TextFormField(
                  controller: _linkCtrl,
                  decoration: InputDecoration(
                    labelText: isWhatsapp ? 'Link wa.me o perfil' : 'Link perfil/pagina',
                  ),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _avatarCtrl,
                  decoration: const InputDecoration(labelText: 'Foto/avatar (URL opcional)'),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _obsCtrl,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'Observaciones'),
                ),
                const SizedBox(height: 10),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _isActive,
                  onChanged: (value) => setState(() => _isActive = value),
                  title: const Text('Cuenta activa'),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            final result = _SocialAccountEditResult(
              type: _type,
              accountName: _nameCtrl.text.trim(),
              username: _userCtrl.text.trim().isEmpty ? null : _userCtrl.text.trim(),
              password: _passCtrl.text.trim().isEmpty ? null : _passCtrl.text.trim(),
              profileLink: _linkCtrl.text.trim().isEmpty ? null : _linkCtrl.text.trim(),
              whatsappNumber: _phoneCtrl.text.trim().isEmpty
                  ? null
                  : _phoneCtrl.text.trim(),
              observations: _obsCtrl.text.trim().isEmpty ? null : _obsCtrl.text.trim(),
              avatarUrl: _avatarCtrl.text.trim().isEmpty ? null : _avatarCtrl.text.trim(),
              isActive: _isActive,
            );
            Navigator.pop(context, result);
          },
          child: const Text('Guardar'),
        ),
      ],
    );
              ),
            ),
          ),
        ),
      ),
    );
  }
}
