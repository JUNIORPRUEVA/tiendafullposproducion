import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/auth/auth_provider.dart';
import '../../core/auth/app_role.dart';
import '../../core/realtime/operations_realtime_service.dart';
import '../../core/routing/route_access.dart';
import '../../core/widgets/app_drawer.dart';
import '../../core/widgets/custom_app_bar.dart';
import '../whatsapp_crm/application/wa_crm_controller.dart';
import '../whatsapp_crm/models/wa_crm_conversation.dart';
import '../whatsapp_crm/models/wa_crm_message.dart';

// ─── Breakpoints ─────────────────────────────────────────────────────────────

const double _kMobileBreak = 600;
const double _kTabletBreak = 960;

class WhatsappCrmScreen extends ConsumerStatefulWidget {
  const WhatsappCrmScreen({super.key});

  @override
  ConsumerState<WhatsappCrmScreen> createState() => _WhatsappCrmScreenState();
}

class _WhatsappCrmScreenState extends ConsumerState<WhatsappCrmScreen> {
  final _msgController = TextEditingController();
  final _scrollController = ScrollController();
  StreamSubscription<Map<String, dynamic>>? _whatsappSub;
  bool _showActionPanel = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final user = ref.read(authStateProvider).user;
      if (user?.appRole != AppRole.admin) {
        context.go(RouteAccess.defaultHomeForRole(user?.appRole ?? AppRole.unknown));
        return;
      }
      ref.read(waCrmControllerProvider.notifier).loadUsers();
      _listenRealtime();
    });
  }

  void _listenRealtime() {
    final realtimeSvc = ref.read(operationsRealtimeServiceProvider);
    _whatsappSub = realtimeSvc.whatsappStream.listen((data) {
      if (!mounted) return;
      ref.read(waCrmControllerProvider.notifier).handleRealtimeMessage(data);
      _scrollToBottom();
    });
  }

  @override
  void dispose() {
    _whatsappSub?.cancel();
    _msgController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authStateProvider).user;
    final state = ref.watch(waCrmControllerProvider);
    final theme = Theme.of(context);
    final size = MediaQuery.of(context).size;
    final isMobile = size.width < _kMobileBreak;
    final isTablet = size.width >= _kMobileBreak && size.width < _kTabletBreak;

    // ── Listen for new messages to scroll ──────────────────────────────────
    ref.listen<WaCrmState>(waCrmControllerProvider, (prev, next) {
      if ((prev?.messages.length ?? 0) < next.messages.length) {
        _scrollToBottom();
      }
    });

    Widget body;
    if (isMobile) {
      body = _buildMobileLayout(context, state, theme);
    } else if (isTablet) {
      body = _buildTwoColumnLayout(context, state, theme);
    } else {
      body = _buildThreeColumnLayout(context, state, theme);
    }

    return Scaffold(
      appBar: CustomAppBar(
        title: 'CRM WhatsApp',
        showLogo: false,
        showDepartmentLabel: false,
        actions: [
          if (!isMobile)
            IconButton(
              icon: Icon(
                _showActionPanel
                    ? Icons.view_sidebar_outlined
                    : Icons.view_sidebar,
              ),
              tooltip: _showActionPanel ? 'Ocultar panel' : 'Mostrar panel',
              onPressed: () =>
                  setState(() => _showActionPanel = !_showActionPanel),
            ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Actualizar',
            onPressed: () {
              ref.read(waCrmControllerProvider.notifier).loadUsers();
            },
          ),
        ],
      ),
      drawer: buildAdaptiveDrawer(context, currentUser: user),
      body: SafeArea(child: body),
    );
  }

  // ─── Three-column layout (desktop) ───────────────────────────────────────

  Widget _buildThreeColumnLayout(
    BuildContext context,
    WaCrmState state,
    ThemeData theme,
  ) {
    return Row(
      children: [
        // Column 1: User + Conversations
        SizedBox(
          width: 280,
          child: _ConversationsPanel(
            state: state,
            onSelectConversation: (conv) {
              ref.read(waCrmControllerProvider.notifier).selectConversation(conv);
            },
            onSelectUser: (u) {
              ref.read(waCrmControllerProvider.notifier).selectUser(u);
            },
          ),
        ),
        const VerticalDivider(width: 1),
        // Column 2: Chat view
        Expanded(
          child: _ChatPanel(
            state: state,
            msgController: _msgController,
            scrollController: _scrollController,
            onSend: () => _sendReply(),
          ),
        ),
        if (_showActionPanel) ...[
          const VerticalDivider(width: 1),
          // Column 3: Actions
          SizedBox(
            width: 260,
            child: _ActionsPanel(state: state),
          ),
        ],
      ],
    );
  }

  // ─── Two-column layout (tablet) ───────────────────────────────────────────

  Widget _buildTwoColumnLayout(
    BuildContext context,
    WaCrmState state,
    ThemeData theme,
  ) {
    return Row(
      children: [
        SizedBox(
          width: 240,
          child: _ConversationsPanel(
            state: state,
            onSelectConversation: (conv) {
              ref.read(waCrmControllerProvider.notifier).selectConversation(conv);
            },
            onSelectUser: (u) {
              ref.read(waCrmControllerProvider.notifier).selectUser(u);
            },
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(
          child: _ChatPanel(
            state: state,
            msgController: _msgController,
            scrollController: _scrollController,
            onSend: () => _sendReply(),
          ),
        ),
      ],
    );
  }

  // ─── Mobile layout (stack navigation) ────────────────────────────────────

  Widget _buildMobileLayout(
    BuildContext context,
    WaCrmState state,
    ThemeData theme,
  ) {
    if (state.selectedConversation != null) {
      return Column(
        children: [
          Material(
            elevation: 1,
            child: InkWell(
              onTap: () {
                ref
                    .read(waCrmControllerProvider.notifier)
                    .clearSelection();
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        state.selectedConversation!.displayName,
                        style: theme.textTheme.titleMedium,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: _ChatPanel(
              state: state,
              msgController: _msgController,
              scrollController: _scrollController,
              onSend: () => _sendReply(),
            ),
          ),
        ],
      );
    }
    return _ConversationsPanel(
      state: state,
      onSelectConversation: (conv) {
        ref.read(waCrmControllerProvider.notifier).selectConversation(conv);
      },
      onSelectUser: (u) {
        ref.read(waCrmControllerProvider.notifier).selectUser(u);
      },
    );
  }

  void _sendReply() async {
    final text = _msgController.text.trim();
    if (text.isEmpty) return;
    _msgController.clear();
    await ref.read(waCrmControllerProvider.notifier).sendReply(text);
  }
}

// ─── Conversations Panel (Column 1) ─────────────────────────────────────────

class _ConversationsPanel extends StatefulWidget {
  const _ConversationsPanel({
    required this.state,
    required this.onSelectConversation,
    required this.onSelectUser,
  });

  final WaCrmState state;
  final ValueChanged<WaCrmConversation> onSelectConversation;
  final ValueChanged<WaCrmUser> onSelectUser;

  @override
  State<_ConversationsPanel> createState() => _ConversationsPanelState();
}

class _ConversationsPanelState extends State<_ConversationsPanel> {
  bool _showInstances = true;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = widget.state;

    return Column(
      children: [
        // ── Instances section (collapsible) ──────────────────────────
        _InstancesSection(
          instances: state.allInstances,
          loading: state.loadingInstances,
          expanded: _showInstances,
          onToggleExpanded: () =>
              setState(() => _showInstances = !_showInstances),
        ),
        const Divider(height: 1),
        // ── User selector for conversations ──────────────────────────
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          color: theme.colorScheme.surfaceContainerHighest
              .withValues(alpha: 0.4),
          child: _UserSelectorDropdown(
            users: state.users,
            selected: state.selectedUser,
            loading: state.loadingUsers,
            onChanged: widget.onSelectUser,
          ),
        ),
        const Divider(height: 1),
        // ── Conversations list ────────────────────────────────────────
        Expanded(
          child: state.loadingConversations
              ? const Center(child: CircularProgressIndicator())
              : state.conversations.isEmpty
                  ? _EmptyConvState(loading: state.loadingUsers)
                  : ListView.builder(
                      itemCount: state.conversations.length,
                      itemBuilder: (context, i) {
                        final conv = state.conversations[i];
                        final isSelected =
                            state.selectedConversation?.id == conv.id;
                        return _ConversationTile(
                          conv: conv,
                          isSelected: isSelected,
                          onTap: () => widget.onSelectConversation(conv),
                        );
                      },
                    ),
        ),
      ],
    );
  }
}

// ─── Instances Section ────────────────────────────────────────────────────────

class _InstancesSection extends StatelessWidget {
  const _InstancesSection({
    required this.instances,
    required this.loading,
    required this.expanded,
    required this.onToggleExpanded,
  });

  final List<WaCrmInstanceEntry> instances;
  final bool loading;
  final bool expanded;
  final VoidCallback onToggleExpanded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Header
        InkWell(
          onTap: onToggleExpanded,
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            color: theme.colorScheme.primaryContainer
                .withValues(alpha: 0.25),
            child: Row(
              children: [
                Icon(
                  Icons.wifi_tethering_rounded,
                  size: 15,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Instancias (${instances.length})',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                if (loading)
                  const SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(strokeWidth: 1.5),
                  )
                else
                  Icon(
                    expanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    size: 16,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
              ],
            ),
          ),
        ),
        if (expanded) ...[
          if (instances.isEmpty && !loading)
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 8,
              ),
              child: Text(
                'Sin instancias configuradas',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                ),
              ),
            )
          else
            ...instances.map(
              (inst) => _InstanceRow(instance: inst),
            ),
        ],
      ],
    );
  }
}

// ─── Instance Row ──────────────────────────────────────────────────────────────

class _InstanceRow extends ConsumerWidget {
  const _InstanceRow({required this.instance});

  final WaCrmInstanceEntry instance;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          _StatusDot(status: instance.status),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    if (instance.isCompany)
                      Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: Icon(
                          Icons.business_rounded,
                          size: 11,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    Expanded(
                      child: Text(
                        instance.userName,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w500,
                          fontSize: 11.5,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                Text(
                  instance.instanceName,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 10,
                    color:
                        theme.colorScheme.onSurface.withValues(alpha: 0.45),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          // Webhook toggle icon
          Tooltip(
            message: instance.webhookEnabled
                ? 'Webhook activo'
                : 'Webhook inactivo',
            child: IconButton(
              iconSize: 18,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(
                minWidth: 28,
                minHeight: 28,
              ),
              icon: Icon(
                instance.webhookEnabled
                    ? Icons.webhook_rounded
                    : Icons.webhook_outlined,
                color: instance.webhookEnabled
                    ? Colors.green
                    : theme.colorScheme.onSurface.withValues(alpha: 0.35),
              ),
              onPressed: () =>
                  _showWebhookDialog(context, ref, instance),
            ),
          ),
        ],
      ),
    );
  }

  void _showWebhookDialog(
    BuildContext context,
    WidgetRef ref,
    WaCrmInstanceEntry inst,
  ) {
    showDialog<void>(
      context: context,
      builder: (_) => _WebhookDialog(instance: inst, ref: ref),
    );
  }
}

// ─── Webhook Dialog ────────────────────────────────────────────────────────────

class _WebhookDialog extends StatefulWidget {
  const _WebhookDialog({required this.instance, required this.ref});

  final WaCrmInstanceEntry instance;
  final WidgetRef ref;

  @override
  State<_WebhookDialog> createState() => _WebhookDialogState();
}

class _WebhookDialogState extends State<_WebhookDialog> {
  late bool _enabled;
  bool _saving = false;
  String? _error;
  String? _configuredUrl;

  @override
  void initState() {
    super.initState();
    _enabled = widget.instance.webhookEnabled;
  }

  Future<void> _toggle(bool value) async {
    setState(() {
      _enabled = value;
      _saving = true;
      _error = null;
      _configuredUrl = null;
    });
    try {
      final url = await widget.ref
          .read(waCrmControllerProvider.notifier)
          .setInstanceWebhook(
            widget.instance.instanceName,
            enabled: value,
          );
      setState(() {
        _saving = false;
        _configuredUrl = url.isNotEmpty ? url : null;
      });
    } catch (e) {
      setState(() {
        _saving = false;
        _enabled = !value; // revert
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final inst = widget.instance;

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.webhook_rounded, size: 20),
          const SizedBox(width: 8),
          const Text('Webhook'),
        ],
      ),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Instance info
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest
                    .withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (inst.isCompany)
                        const Icon(Icons.business_rounded,
                            size: 14)
                      else
                        const Icon(Icons.person_rounded, size: 14),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          inst.userName,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    inst.instanceName,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface
                          .withValues(alpha: 0.55),
                      fontFamily: 'monospace',
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      _StatusDot(status: inst.status),
                      const SizedBox(width: 6),
                      Text(
                        _statusLabel(inst.status),
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // Toggle row
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Recibir mensajes en backend',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Text(
                        'Configura el webhook en Evolution API',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.55),
                        ),
                      ),
                    ],
                  ),
                ),
                if (_saving)
                  const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  Switch(
                    value: _enabled,
                    onChanged: _toggle,
                    activeThumbColor: Colors.green,
                  ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
            if (_enabled) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: Colors.green.withValues(alpha: 0.3),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.check_circle_outline_rounded,
                          size: 14,
                          color: Colors.green,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Los mensajes de esta instancia llegarán al CRM en tiempo real.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: Colors.green.shade700,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (_configuredUrl != null) ...[
                      const SizedBox(height: 6),
                      const Divider(height: 1),
                      const SizedBox(height: 6),
                      Text(
                        'URL configurada en Evolution API:',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.green.shade800,
                          fontWeight: FontWeight.w600,
                          fontSize: 10,
                        ),
                      ),
                      const SizedBox(height: 2),
                      SelectableText(
                        _configuredUrl!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                          fontSize: 10,
                          color: Colors.green.shade900,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cerrar'),
        ),
      ],
    );
  }

  String _statusLabel(String status) {
    return switch (status.toLowerCase()) {
      'open' || 'connected' => 'Conectado',
      'close' || 'closed' => 'Desconectado',
      'connecting' => 'Conectando...',
      _ => 'Pendiente',
    };
  }
}

// ─── User Selector Dropdown ───────────────────────────────────────────────────

class _UserSelectorDropdown extends StatelessWidget {
  const _UserSelectorDropdown({
    required this.users,
    required this.selected,
    required this.loading,
    required this.onChanged,
  });

  final List<WaCrmUser> users;
  final WaCrmUser? selected;
  final bool loading;
  final ValueChanged<WaCrmUser> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (loading && users.isEmpty) {
      return const SizedBox(
        height: 40,
        child: Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    if (users.isEmpty) {
      return Text(
        'Sin usuarios con WhatsApp',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
        ),
      );
    }

    return DropdownButtonHideUnderline(
      child: DropdownButton<WaCrmUser>(
        isExpanded: true,
        value: users.contains(selected) ? selected : users.first,
        style: theme.textTheme.bodyMedium,
        borderRadius: BorderRadius.circular(12),
        items: users.map((u) {
          return DropdownMenuItem<WaCrmUser>(
            value: u,
            child: Row(
              children: [
                _StatusDot(
                  status: u.instanceStatus,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    u.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
        onChanged: (u) {
          if (u != null) onChanged(u);
        },
      ),
    );
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.status});
  final String? status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status?.toLowerCase()) {
      'open' || 'connected' => Colors.green,
      'close' || 'closed' => Colors.grey,
      'connecting' => Colors.orange,
      _ => Colors.grey,
    };
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

// ─── Conversation Tile ────────────────────────────────────────────────────────

class _ConversationTile extends StatelessWidget {
  const _ConversationTile({
    required this.conv,
    required this.isSelected,
    required this.onTap,
  });

  final WaCrmConversation conv;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final last = conv.lastMessage;
    final timeStr = conv.lastMessageAt != null
        ? _formatTime(conv.lastMessageAt!)
        : '';

    return InkWell(
      onTap: onTap,
      child: Container(
        color: isSelected
            ? theme.colorScheme.primaryContainer.withValues(alpha: 0.35)
            : null,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.15),
              child: Text(
                conv.displayName.isNotEmpty
                    ? conv.displayName[0].toUpperCase()
                    : '?',
                style: TextStyle(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          conv.displayName,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: conv.unreadCount > 0
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (timeStr.isNotEmpty)
                        Text(
                          timeStr,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.5),
                            fontSize: 11,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          last?.previewText ?? '',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.6),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (conv.unreadCount > 0)
                        Container(
                          margin: const EdgeInsets.only(left: 4),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            conv.unreadCount > 99
                                ? '99+'
                                : '${conv.unreadCount}',
                            style: TextStyle(
                              color: theme.colorScheme.onPrimary,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inDays == 0) {
      return DateFormat('HH:mm').format(dt);
    } else if (diff.inDays == 1) {
      return 'Ayer';
    } else if (diff.inDays < 7) {
      return DateFormat('EEE', 'es').format(dt);
    }
    return DateFormat('dd/MM').format(dt);
  }
}

// ─── Chat Panel (Column 2) ───────────────────────────────────────────────────

class _ChatPanel extends StatelessWidget {
  const _ChatPanel({
    required this.state,
    required this.msgController,
    required this.scrollController,
    required this.onSend,
  });

  final WaCrmState state;
  final TextEditingController msgController;
  final ScrollController scrollController;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final conv = state.selectedConversation;

    if (conv == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.chat_bubble_outline_rounded,
              size: 64,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.2),
            ),
            const SizedBox(height: 16),
            Text(
              'Selecciona una conversación',
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor:
                    theme.colorScheme.primary.withValues(alpha: 0.15),
                child: Text(
                  conv.displayName.isNotEmpty
                      ? conv.displayName[0].toUpperCase()
                      : '?',
                  style: TextStyle(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      conv.displayName,
                      style: theme.textTheme.titleSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (conv.remotePhone != null)
                      Text(
                        '+${conv.remotePhone}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color:
                              theme.colorScheme.onSurface.withValues(alpha: 0.5),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        // Messages
        Expanded(
          child: state.loadingMessages
              ? const Center(child: CircularProgressIndicator())
              : state.messages.isEmpty
                  ? Center(
                      child: Text(
                        'Sin mensajes aún',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.4),
                        ),
                      ),
                    )
                  : ListView.builder(
                      controller: scrollController,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      itemCount: state.messages.length,
                      itemBuilder: (context, i) {
                        return _MessageBubble(msg: state.messages[i]);
                      },
                    ),
        ),
        // Error banner
        if (state.error != null)
          Container(
            color: theme.colorScheme.errorContainer,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Text(
              state.error!,
              style: TextStyle(
                color: theme.colorScheme.onErrorContainer,
                fontSize: 12,
              ),
            ),
          ),
        // Input
        _ChatInput(
          controller: msgController,
          sending: state.sending,
          onSend: onSend,
        ),
      ],
    );
  }
}

// ─── Message Bubble ───────────────────────────────────────────────────────────

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.msg});

  final WaCrmMessage msg;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isOut = msg.isOutgoing;
    final align = isOut ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final bubbleColor = isOut
        ? theme.colorScheme.primary
        : theme.colorScheme.surfaceContainerHighest;
    final textColor = isOut
        ? theme.colorScheme.onPrimary
        : theme.colorScheme.onSurface;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Column(
        crossAxisAlignment: align,
        children: [
          if (!isOut && msg.senderName != null)
            Padding(
              padding: const EdgeInsets.only(left: 8, bottom: 2),
              child: Text(
                msg.senderName!,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.65,
            ),
            decoration: BoxDecoration(
              color: bubbleColor,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(16),
                topRight: const Radius.circular(16),
                bottomLeft: Radius.circular(isOut ? 16 : 4),
                bottomRight: Radius.circular(isOut ? 4 : 16),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.07),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _MessageContent(msg: msg, textColor: textColor),
                const SizedBox(height: 3),
                Text(
                  DateFormat('HH:mm').format(msg.sentAt.toLocal()),
                  style: TextStyle(
                    color: textColor.withValues(alpha: 0.55),
                    fontSize: 10,
                  ),
                  textAlign: TextAlign.right,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Message Content (handles text/image/audio) ───────────────────────────────

class _MessageContent extends StatelessWidget {
  const _MessageContent({required this.msg, required this.textColor});

  final WaCrmMessage msg;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    switch (msg.messageType) {
      case WaMessageType.image:
        return _ImageContent(msg: msg, textColor: textColor);
      case WaMessageType.audio:
        return _AudioContent(msg: msg, textColor: textColor);
      case WaMessageType.video:
        return _VideoContent(msg: msg, textColor: textColor);
      case WaMessageType.document:
        return _DocumentContent(msg: msg, textColor: textColor);
      default:
        return SelectableText(
          msg.body ?? '',
          style: TextStyle(color: textColor, fontSize: 14),
        );
    }
  }
}

class _ImageContent extends StatelessWidget {
  const _ImageContent({required this.msg, required this.textColor});
  final WaCrmMessage msg;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    final url = msg.mediaUrl;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (url != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: GestureDetector(
              onTap: () => _showFullImage(context, url),
              child: _buildImageWidget(url),
            ),
          )
        else
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.image_not_supported_outlined,
                  size: 16, color: textColor),
              const SizedBox(width: 4),
              Text('Imagen no disponible',
                  style: TextStyle(color: textColor, fontSize: 13)),
            ],
          ),
        if (msg.caption?.isNotEmpty == true)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              msg.caption!,
              style: TextStyle(color: textColor, fontSize: 13),
            ),
          ),
      ],
    );
  }

  Widget _buildImageWidget(String url) {
    if (url.startsWith('data:')) {
      try {
        final commaIdx = url.indexOf(',');
        if (commaIdx != -1) {
          final bytes = base64Decode(url.substring(commaIdx + 1));
          return Image.memory(
            bytes,
            width: 220,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _brokenImage(),
          );
        }
      } catch (_) {
        return _brokenImage();
      }
    }
    return Image.network(
      url,
      width: 220,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => _brokenImage(),
      loadingBuilder: (_, child, progress) {
        if (progress == null) return child;
        return Container(
          width: 220,
          height: 120,
          color: Colors.grey.shade200,
          child: const Center(child: CircularProgressIndicator()),
        );
      },
    );
  }

  Widget _brokenImage() => Container(
        width: 220,
        height: 120,
        color: Colors.grey.shade300,
        child: const Icon(Icons.broken_image_rounded, size: 40),
      );

  void _showFullImage(BuildContext context, String url) {
    Widget imageWidget;
    if (url.startsWith('data:')) {
      try {
        final commaIdx = url.indexOf(',');
        final bytes = base64Decode(url.substring(commaIdx + 1));
        imageWidget = Image.memory(bytes);
      } catch (_) {
        imageWidget = const Icon(Icons.broken_image_rounded,
            size: 64, color: Colors.white);
      }
    } else {
      imageWidget = Image.network(url);
    }
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.black,
        child: GestureDetector(
          onTap: () => Navigator.of(ctx).pop(),
          child: InteractiveViewer(child: imageWidget),
        ),
      ),
    );
  }
}

class _AudioContent extends StatelessWidget {
  const _AudioContent({required this.msg, required this.textColor});
  final WaCrmMessage msg;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.headphones_rounded, color: textColor, size: 18),
        const SizedBox(width: 8),
        Text(
          'Audio',
          style: TextStyle(color: textColor, fontSize: 13),
        ),
        if (msg.mediaUrl != null) ...[
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => _openAudio(context, msg.mediaUrl!),
            child: Icon(
              Icons.open_in_new_rounded,
              size: 14,
              color: textColor.withValues(alpha: 0.7),
            ),
          ),
        ],
      ],
    );
  }

  void _openAudio(BuildContext context, String url) {
    // Open in browser / system player
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Audio'),
        content: SelectableText(url),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }
}

class _VideoContent extends StatelessWidget {
  const _VideoContent({required this.msg, required this.textColor});
  final WaCrmMessage msg;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.videocam_rounded, color: textColor, size: 18),
        const SizedBox(width: 8),
        Text(
          msg.caption?.isNotEmpty == true ? msg.caption! : 'Video',
          style: TextStyle(color: textColor, fontSize: 13),
        ),
      ],
    );
  }
}

class _DocumentContent extends StatelessWidget {
  const _DocumentContent({required this.msg, required this.textColor});
  final WaCrmMessage msg;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.insert_drive_file_rounded, color: textColor, size: 18),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            msg.body ?? 'Documento',
            style: TextStyle(color: textColor, fontSize: 13),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

// ─── Chat Input ───────────────────────────────────────────────────────────────

class _ChatInput extends StatelessWidget {
  const _ChatInput({
    required this.controller,
    required this.sending,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.07),
            blurRadius: 6,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              decoration: InputDecoration(
                hintText: 'Escribe un mensaje...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: theme.colorScheme.surfaceContainerHighest
                    .withValues(alpha: 0.5),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                isDense: true,
              ),
              maxLines: 4,
              minLines: 1,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => onSend(),
            ),
          ),
          const SizedBox(width: 8),
          sending
              ? const SizedBox(
                  width: 44,
                  height: 44,
                  child: Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                )
              : FilledButton(
                  onPressed: onSend,
                  style: FilledButton.styleFrom(
                    shape: const CircleBorder(),
                    padding: const EdgeInsets.all(12),
                  ),
                  child: const Icon(Icons.send_rounded, size: 18),
                ),
        ],
      ),
    );
  }
}

// ─── Actions Panel (Column 3) ────────────────────────────────────────────────

class _ActionsPanel extends StatelessWidget {
  const _ActionsPanel({required this.state});

  final WaCrmState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final conv = state.selectedConversation;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Información',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          if (conv != null) ...[
            _InfoRow(
              icon: Icons.person_outline_rounded,
              label: 'Contacto',
              value: conv.displayName,
            ),
            if (conv.remotePhone != null)
              _InfoRow(
                icon: Icons.phone_outlined,
                label: 'Teléfono',
                value: '+${conv.remotePhone!}',
              ),
            _InfoRow(
              icon: Icons.message_outlined,
              label: 'JID',
              value: conv.remoteJid,
            ),
            if (conv.lastMessageAt != null)
              _InfoRow(
                icon: Icons.access_time_rounded,
                label: 'Último mensaje',
                value: DateFormat('dd/MM HH:mm').format(
                  conv.lastMessageAt!.toLocal(),
                ),
              ),
            const SizedBox(height: 20),
            Divider(color: theme.colorScheme.outlineVariant),
            const SizedBox(height: 12),
            Text(
              'Estadísticas',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            _InfoRow(
              icon: Icons.mark_unread_chat_alt_outlined,
              label: 'Sin leer',
              value: '${conv.unreadCount}',
            ),
            _InfoRow(
              icon: Icons.chat_bubble_outline_rounded,
              label: 'Mensajes',
              value: '${state.messages.length}',
            ),
          ] else
            Text(
              'Selecciona una conversación para ver detalles.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
          const SizedBox(height: 20),
          if (state.selectedUser != null) ...[
            Divider(color: theme.colorScheme.outlineVariant),
            const SizedBox(height: 12),
            Text(
              'Instancia activa',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            _InfoRow(
              icon: Icons.account_circle_outlined,
              label: 'Usuario',
              value: state.selectedUser!.name,
            ),
            _InfoRow(
              icon: Icons.wifi_tethering_rounded,
              label: 'Estado',
              value: state.selectedUser!.instanceStatus ?? 'N/A',
            ),
            if (state.selectedUser!.phone != null)
              _InfoRow(
                icon: Icons.sim_card_outlined,
                label: 'Número',
                value: state.selectedUser!.phone!,
              ),
          ],
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            size: 16,
            color: theme.colorScheme.primary.withValues(alpha: 0.8),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                  ),
                ),
                Text(
                  value,
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Empty state ──────────────────────────────────────────────────────────────

class _EmptyConvState extends StatelessWidget {
  const _EmptyConvState({required this.loading});
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.inbox_rounded,
            size: 48,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.2),
          ),
          const SizedBox(height: 12),
          Text(
            loading ? 'Cargando...' : 'Sin conversaciones',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
            ),
          ),
        ],
      ),
    );
  }
}
