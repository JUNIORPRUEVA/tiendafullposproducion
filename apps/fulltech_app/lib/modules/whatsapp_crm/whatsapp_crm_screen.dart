import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:media_kit/media_kit.dart' as media_kit;
import 'package:media_kit_video/media_kit_video.dart' as media_kit_video;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api/env.dart';
import '../../core/auth/auth_provider.dart';
import '../../core/auth/app_role.dart';
import '../../core/realtime/operations_realtime_service.dart';
import '../../core/routing/route_access.dart';
import '../../core/widgets/app_drawer.dart';
import '../../core/widgets/custom_app_bar.dart';
import '../../core/widgets/user_avatar.dart';
import '../whatsapp_crm/application/wa_crm_controller.dart';
import '../whatsapp_crm/models/wa_crm_conversation.dart';
import '../whatsapp_crm/models/wa_crm_message.dart';

// ─── Breakpoints ─────────────────────────────────────────────────────────────

const double _kMobileBreak = 600;
const double _kTabletBreak = 960;

String _waText(dynamic value, [String fallback = '']) {
  return sanitizeWaText(value) ?? fallback;
}

String _waInitial(dynamic value, [String fallback = '?']) {
  final text = _waText(value).trim();
  if (text.isEmpty) return fallback;
  final firstRune = text.runes.first;
  return String.fromCharCode(firstRune).toUpperCase();
}

String _resolveChatAvatarUrl(String? rawUrl) {
  final value = (rawUrl ?? '').trim();
  if (value.isEmpty) return '';
  if (value.startsWith('http://') || value.startsWith('https://')) {
    return value;
  }

  final base = Env.apiBaseUrl.trim();
  if (base.isEmpty) return value;

  final normalizedBase = base.endsWith('/')
      ? base.substring(0, base.length - 1)
      : base;
  final normalizedPath = value.startsWith('/')
      ? value
      : (value.startsWith('uploads/') ? '/$value' : '/uploads/$value');
  return '$normalizedBase$normalizedPath';
}

Future<void> _showChatAvatarPreview(
  BuildContext context,
  WaCrmConversation conv,
) async {
  final resolvedUrl = _resolveChatAvatarUrl(conv.remoteAvatarUrl);
  if (resolvedUrl.isEmpty) return;

  final size = MediaQuery.sizeOf(context);
  await showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.88),
    builder: (dialogContext) {
      return Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 20),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: size.width * 0.95,
            maxHeight: size.height * 0.88,
          ),
          child: GestureDetector(
            onDoubleTap: () => Navigator.of(dialogContext).pop(),
            onVerticalDragEnd: (details) {
              final velocity = details.primaryVelocity ?? 0;
              if (velocity > 700) {
                Navigator.of(dialogContext).pop();
              }
            },
            child: Stack(
              children: [
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      color: Colors.black,
                      child: InteractiveViewer(
                        minScale: 1,
                        maxScale: 4,
                        child: Center(
                          child: Image.network(
                            resolvedUrl,
                            fit: BoxFit.contain,
                            loadingBuilder: (context, child, loadingProgress) {
                              if (loadingProgress == null) return child;
                              return const Center(
                                child: CircularProgressIndicator(strokeWidth: 2),
                              );
                            },
                            errorBuilder: (context, _, __) => Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.broken_image_outlined,
                                    color: Colors.white70,
                                    size: 46,
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    'No se pudo cargar la foto',
                                    style: Theme.of(dialogContext)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(color: Colors.white70),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              Positioned(
                top: 10,
                right: 10,
                child: Material(
                  color: Colors.black45,
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () => Navigator.of(dialogContext).pop(),
                    child: const Padding(
                      padding: EdgeInsets.all(8),
                      child: Icon(Icons.close, color: Colors.white),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 12,
                right: 12,
                bottom: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _waText(conv.displayName),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(dialogContext)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Doble toque o desliza abajo para cerrar',
                        style: Theme.of(dialogContext).textTheme.bodySmall
                            ?.copyWith(color: Colors.white70),
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

class WhatsappCrmScreen extends ConsumerStatefulWidget {
  const WhatsappCrmScreen({super.key});

  @override
  ConsumerState<WhatsappCrmScreen> createState() => _WhatsappCrmScreenState();
}

class _WhatsappCrmScreenState extends ConsumerState<WhatsappCrmScreen> {
  final _msgController = TextEditingController();
  final _scrollController = ScrollController();
  StreamSubscription<Map<String, dynamic>>? _whatsappSub;
  Timer? _autoRefreshTimer;
  bool _showActionPanel = true;
  bool _showAiPanel = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final user = ref.read(authStateProvider).user;
      if (user?.appRole != AppRole.admin) {
        context.go(
          RouteAccess.defaultHomeForRole(user?.appRole ?? AppRole.unknown),
        );
        return;
      }
      ref.read(waCrmControllerProvider.notifier).loadUsers();
      _listenRealtime();
      _startAutoRefresh();
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

  void _startAutoRefresh() {
    _autoRefreshTimer?.cancel();
    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 6), (_) {
      if (!mounted) return;
      ref.read(waCrmControllerProvider.notifier).refreshActiveView();
    });
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
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
          if (!isMobile)
            IconButton(
              icon: Icon(
                _showAiPanel ? Icons.auto_awesome : Icons.auto_awesome_outlined,
              ),
              tooltip: _showAiPanel ? 'Ocultar IA' : 'Resumen IA del dia',
              onPressed: () => setState(() => _showAiPanel = !_showAiPanel),
            ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Actualizar',
            onPressed: () {
              ref.read(waCrmControllerProvider.notifier).refreshActiveView();
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
              ref
                  .read(waCrmControllerProvider.notifier)
                  .selectConversation(conv);
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
            onUnlock: _unlockComposer,
            agentName: state.selectedUser?.name,
          ),
        ),
        if (_showActionPanel) ...[
          const VerticalDivider(width: 1),
          // Column 3: Actions
          SizedBox(width: 260, child: _ActionsPanel(state: state)),
        ],
        if (_showAiPanel) ...[
          const VerticalDivider(width: 1),
          SizedBox(
            width: 360,
            child: _DailyAiPanel(
              state: state,
              onPickDate: _pickAiSummaryDate,
              onGenerate: () => ref
                  .read(waCrmControllerProvider.notifier)
                  .generateDailyAiSummary(),
            ),
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
              ref
                  .read(waCrmControllerProvider.notifier)
                  .selectConversation(conv);
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
            onUnlock: _unlockComposer,
            agentName: state.selectedUser?.name,
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
                ref.read(waCrmControllerProvider.notifier).clearSelection();
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
                        _waText(state.selectedConversation!.displayName),
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
              onUnlock: _unlockComposer,
              agentName: state.selectedUser?.name,
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
    final state = ref.read(waCrmControllerProvider);
    final conv = state.selectedConversation;
    final canWrite =
        conv != null &&
        state.composerUnlocked &&
        state.composerUnlockedConversationKey == conv.mergeKey;
    if (!canWrite) {
      await _unlockComposer();
      final latest = ref.read(waCrmControllerProvider);
      final latestConv = latest.selectedConversation;
      final latestCanWrite =
          latestConv != null &&
          latest.composerUnlocked &&
          latest.composerUnlockedConversationKey == latestConv.mergeKey;
      if (!latestCanWrite) return;
    }
    final text = _msgController.text.trim();
    if (text.isEmpty) return;
    _msgController.clear();
    await ref.read(waCrmControllerProvider.notifier).sendReply(text);
  }

  Future<void> _unlockComposer() async {
    final passwordCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        bool obscure = true;
        bool loading = false;
        String? error;
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: const Text('Desbloquear envio'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: passwordCtrl,
                    autofocus: true,
                    obscureText: obscure,
                    decoration: InputDecoration(
                      labelText: 'Contrasena de administrador',
                      errorText: error,
                      suffixIcon: IconButton(
                        icon: Icon(
                          obscure ? Icons.visibility : Icons.visibility_off,
                        ),
                        onPressed: () =>
                            setDialogState(() => obscure = !obscure),
                      ),
                    ),
                    onSubmitted: (_) async {
                      if (loading) return;
                      setDialogState(() {
                        loading = true;
                        error = null;
                      });
                      final unlocked = await ref
                          .read(waCrmControllerProvider.notifier)
                          .unlockComposer(passwordCtrl.text);
                      if (!ctx.mounted) return;
                      if (unlocked) {
                        Navigator.of(ctx).pop(true);
                      } else {
                        setDialogState(() {
                          loading = false;
                          error = 'Contrasena incorrecta';
                        });
                      }
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: loading
                      ? null
                      : () => Navigator.of(ctx).pop(false),
                  child: const Text('Cancelar'),
                ),
                FilledButton.icon(
                  onPressed: loading
                      ? null
                      : () async {
                          setDialogState(() {
                            loading = true;
                            error = null;
                          });
                          final unlocked = await ref
                              .read(waCrmControllerProvider.notifier)
                              .unlockComposer(passwordCtrl.text);
                          if (!ctx.mounted) return;
                          if (unlocked) {
                            Navigator.of(ctx).pop(true);
                          } else {
                            setDialogState(() {
                              loading = false;
                              error = 'Contrasena incorrecta';
                            });
                          }
                        },
                  icon: loading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.lock_open_rounded),
                  label: const Text('Desbloquear'),
                ),
              ],
            );
          },
        );
      },
    );
    passwordCtrl.dispose();
    if (ok == true && mounted) {
      FocusScope.of(context).requestFocus(FocusNode());
    }
  }

  Future<void> _pickAiSummaryDate() async {
    final current =
        ref.read(waCrmControllerProvider).aiSummaryDate ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now(),
      helpText: 'Dia del resumen',
    );
    if (picked == null || !mounted) return;
    await ref
        .read(waCrmControllerProvider.notifier)
        .generateDailyAiSummary(date: picked);
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
          color: theme.colorScheme.surfaceContainerHighest.withValues(
            alpha: 0.4,
          ),
          child: _UserSelectorDropdown(
            users: state.users,
            selected: state.selectedUser,
            loading: state.loadingUsers,
            onChanged: widget.onSelectUser,
          ),
        ),
        const Divider(height: 1),
        _ConversationStatsStrip(
          chats: state.conversations.length,
          unread: state.conversations.fold<int>(
            0,
            (sum, conv) => sum + conv.unreadCount,
          ),
          selectedMessages: state.messages.length,
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

class _ConversationStatsStrip extends StatelessWidget {
  const _ConversationStatsStrip({
    required this.chats,
    required this.unread,
    required this.selectedMessages,
  });

  final int chats;
  final int unread;
  final int selectedMessages;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      color: theme.colorScheme.surface,
      child: Row(
        children: [
          _MiniStat(label: 'Chats', value: '$chats'),
          const SizedBox(width: 10),
          _MiniStat(label: 'Sin responder', value: '$unread'),
          const SizedBox(width: 10),
          _MiniStat(label: 'Mensajes', value: '$selectedMessages'),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              _waText(label),
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                fontSize: 10,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            _waText(value),
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w800,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

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
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            color: theme.colorScheme.primaryContainer.withValues(alpha: 0.25),
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
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Text(
                'Sin instancias configuradas',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                ),
              ),
            )
          else
            ...instances.map((inst) => _InstanceRow(instance: inst)),
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
                        _waText(instance.userName),
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
                  _waText(instance.instanceName),
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 10,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.45),
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
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              icon: Icon(
                instance.webhookEnabled
                    ? Icons.webhook_rounded
                    : Icons.webhook_outlined,
                color: instance.webhookEnabled
                    ? Colors.green
                    : theme.colorScheme.onSurface.withValues(alpha: 0.35),
              ),
              onPressed: () => _showWebhookDialog(context, ref, instance),
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
          .setInstanceWebhook(widget.instance.instanceName, enabled: value);
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

  Future<void> _resync() => _toggle(true);

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
                color: theme.colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.5,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (inst.isCompany)
                        const Icon(Icons.business_rounded, size: 14)
                      else
                        const Icon(Icons.person_rounded, size: 14),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _waText(inst.userName),
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
                    _waText(inst.instanceName),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(
                        alpha: 0.55,
                      ),
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
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.55,
                          ),
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
                _waText(_error),
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
                        _waText(_configuredUrl),
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
            if (_enabled) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _saving ? null : _resync,
                  icon: const Icon(Icons.sync_rounded, size: 18),
                  label: const Text('Reconfigurar eventos'),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Actualiza la instancia para recibir mensajes entrantes y enviados.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
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
                _StatusDot(status: u.instanceStatus),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _waText(u.name),
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
            Material(
              color: Colors.transparent,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () => _showChatAvatarPreview(context, conv),
                child: UserAvatar(
                  imageUrl: conv.remoteAvatarUrl,
                  radius: 22,
                  backgroundColor: theme.colorScheme.primary.withValues(
                    alpha: 0.15,
                  ),
                  child: Text(
                    _waInitial(conv.displayName),
                    style: TextStyle(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
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
                          _waText(conv.displayName),
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
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.5,
                            ),
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
                          _waText(last?.previewText),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.6,
                            ),
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

// ─── Media helpers ────────────────────────────────────────────────────────────

String _mimeToExtension(String? mime) {
  switch (mime) {
    case 'audio/ogg':
    case 'audio/ogg; codecs=opus':
      return '.ogg';
    case 'audio/mpeg':
      return '.mp3';
    case 'audio/mp4':
    case 'audio/aac':
      return '.m4a';
    case 'audio/wav':
      return '.wav';
    case 'video/mp4':
      return '.mp4';
    case 'video/webm':
      return '.webm';
    case 'video/3gpp':
      return '.3gp';
    case 'image/jpeg':
      return '.jpg';
    case 'image/png':
      return '.png';
    case 'image/webp':
      return '.webp';
    case 'application/pdf':
      return '.pdf';
    default:
      return '';
  }
}

Future<void> _openMedia(String mediaUrl, String? mimeType) async {
  try {
    if (mediaUrl.startsWith('data:')) {
      final commaIdx = mediaUrl.indexOf(',');
      if (commaIdx == -1) return;

      // Detect mime from the data URI header if not provided
      String? detectedMime = mimeType;
      if (detectedMime == null) {
        final header = mediaUrl.substring(5, commaIdx); // strip 'data:'
        final semiIdx = header.indexOf(';');
        if (semiIdx != -1) detectedMime = header.substring(0, semiIdx);
      }

      final bytes = base64Decode(mediaUrl.substring(commaIdx + 1));
      final ext = _mimeToExtension(detectedMime);
      final tempDir = await getTemporaryDirectory();
      final hash = mediaUrl.hashCode.abs();
      final file = File(
        '${tempDir.path}${Platform.pathSeparator}wa_media_$hash$ext',
      );
      await file.writeAsBytes(bytes, flush: true);
      await launchUrl(
        Uri.file(file.path),
        mode: LaunchMode.externalApplication,
      );
    } else {
      await launchUrl(
        Uri.parse(mediaUrl),
        mode: LaunchMode.externalApplication,
      );
    }
  } catch (e) {
    debugPrint('[WaCrm] _openMedia error: $e');
  }
}

Future<String> _mediaSourceForPlayback(
  String mediaUrl,
  String? mimeType, {
  required String prefix,
}) async {
  if (!mediaUrl.startsWith('data:') &&
      (mediaUrl.startsWith('http://') ||
          mediaUrl.startsWith('https://') ||
          mediaUrl.startsWith('file://'))) {
    return mediaUrl;
  }

  final commaIdx = mediaUrl.indexOf(',');
  final isDataUri = mediaUrl.startsWith('data:');
  if (isDataUri && commaIdx == -1) throw Exception('URI base64 inválido');

  String? detectedMime = mimeType;
  if (detectedMime == null || detectedMime.trim().isEmpty) {
    if (isDataUri) {
      final header = mediaUrl.substring(5, commaIdx);
      final semiIdx = header.indexOf(';');
      detectedMime = semiIdx == -1 ? header : header.substring(0, semiIdx);
    } else {
      detectedMime = 'application/octet-stream';
    }
  }

  final bytes = base64Decode(
    isDataUri ? mediaUrl.substring(commaIdx + 1) : mediaUrl,
  );
  final ext = _mimeToExtension(detectedMime);
  final tempDir = await getTemporaryDirectory();
  final hash = mediaUrl.hashCode.abs();
  final file = File(
    '${tempDir.path}${Platform.pathSeparator}${prefix}_$hash$ext',
  );
  if (!await file.exists()) {
    await file.writeAsBytes(bytes, flush: true);
  }
  return Uri.file(file.path).toString();
}

// ─── Chat Panel ───────────────────────────────────────────────────────────────

class _ChatPanel extends StatelessWidget {
  const _ChatPanel({
    required this.state,
    required this.msgController,
    required this.scrollController,
    required this.onSend,
    required this.onUnlock,
    this.agentName,
  });

  final WaCrmState state;
  final TextEditingController msgController;
  final ScrollController scrollController;
  final VoidCallback onSend;
  final VoidCallback onUnlock;
  final String? agentName;

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
              Material(
                color: Colors.transparent,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => _showChatAvatarPreview(context, conv),
                  child: UserAvatar(
                    imageUrl: conv.remoteAvatarUrl,
                    radius: 18,
                    backgroundColor: theme.colorScheme.primary.withValues(
                      alpha: 0.15,
                    ),
                    child: Text(
                      _waInitial(conv.displayName),
                      style: TextStyle(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _waText(conv.displayName),
                      style: theme.textTheme.titleSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (conv.displayPhone != null)
                      Text(
                        _waText(conv.displayPhone),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.5,
                          ),
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
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
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
                    return _MessageBubble(
                      msg: state.messages[i],
                      agentName: agentName,
                    );
                  },
                ),
        ),
        // Error banner
        if (state.error != null)
          Container(
            color: theme.colorScheme.errorContainer,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Text(
              _waText(state.error),
              style: TextStyle(
                color: theme.colorScheme.onErrorContainer,
                fontSize: 12,
              ),
            ),
          ),
        // Input
        Builder(
          builder: (context) {
            final inputUnlocked =
                state.selectedConversation != null &&
                state.composerUnlocked &&
                state.composerUnlockedConversationKey ==
                    state.selectedConversation!.mergeKey;
            return _ChatInput(
              controller: msgController,
              sending: state.sending,
              unlocked: inputUnlocked,
              onUnlock: onUnlock,
              onSend: onSend,
            );
          },
        ),
      ],
    );
  }
}

// ─── Message Bubble ───────────────────────────────────────────────────────────

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.msg, this.agentName});

  final WaCrmMessage msg;
  final String? agentName;

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
                _waText(msg.senderName),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          if (isOut)
            Padding(
              padding: const EdgeInsets.only(right: 8, bottom: 2),
              child: Text(
                agentName?.trim().isNotEmpty == true
                    ? 'Enviado por ${_waText(agentName!.trim())}'
                    : 'Enviado desde la instancia',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.primary.withValues(alpha: 0.7),
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
          _waText(msg.body),
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
              Icon(
                Icons.image_not_supported_outlined,
                size: 16,
                color: textColor,
              ),
              const SizedBox(width: 4),
              Text(
                'Imagen no disponible',
                style: TextStyle(color: textColor, fontSize: 13),
              ),
            ],
          ),
        if (msg.caption?.isNotEmpty == true)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              _waText(msg.caption),
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
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      try {
        return Image.memory(
          base64Decode(url),
          width: 220,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _brokenImage(),
        );
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
        imageWidget = const Icon(
          Icons.broken_image_rounded,
          size: 64,
          color: Colors.white,
        );
      }
    } else if (!url.startsWith('http://') && !url.startsWith('https://')) {
      try {
        imageWidget = Image.memory(base64Decode(url));
      } catch (_) {
        imageWidget = const Icon(
          Icons.broken_image_rounded,
          size: 64,
          color: Colors.white,
        );
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

class _AudioContent extends StatefulWidget {
  const _AudioContent({required this.msg, required this.textColor});
  final WaCrmMessage msg;
  final Color textColor;
  @override
  State<_AudioContent> createState() => _AudioContentState();
}

class _AudioContentState extends State<_AudioContent> {
  media_kit.Player? _player;
  StreamSubscription<bool>? _playingSub;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration>? _durationSub;
  bool _initializing = false;
  bool _initialized = false;
  bool _playing = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  String? _error;

  @override
  void dispose() {
    _playingSub?.cancel();
    _positionSub?.cancel();
    _durationSub?.cancel();
    _player?.dispose();
    super.dispose();
  }

  Future<void> _ensureInitialized() async {
    if (_initializing || _initialized) return;
    setState(() => _initializing = true);

    try {
      final url = widget.msg.mediaUrl;
      if (url == null) throw Exception('Sin URL de audio');

      final source = await _mediaSourceForPlayback(
        url,
        widget.msg.mediaMimeType,
        prefix: 'wa_audio',
      );

      final player = media_kit.Player();
      await player.setVolume(100);
      _playingSub = player.stream.playing.listen((value) {
        if (mounted) setState(() => _playing = value);
      });
      _positionSub = player.stream.position.listen((value) {
        if (mounted) setState(() => _position = value);
      });
      _durationSub = player.stream.duration.listen((value) {
        if (mounted) setState(() => _duration = value);
      });

      await player.open(media_kit.Media(source), play: true);

      if (mounted) {
        setState(() {
          _player = player;
          _initializing = false;
          _initialized = true;
        });
      } else {
        await player.dispose();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _initializing = false;
          _error = e.toString();
        });
      }
    }
  }

  Future<void> _togglePlayPause() async {
    final player = _player;
    if (player == null) return;
    if (_playing) {
      await player.pause();
    } else {
      if (_duration > Duration.zero && _position >= _duration) {
        await player.seek(Duration.zero);
      }
      await player.play();
    }
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.textColor;

    if (widget.msg.mediaUrl == null) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.mic_off_rounded, color: color, size: 16),
          const SizedBox(width: 6),
          Text(
            'Audio no disponible',
            style: TextStyle(color: color, fontSize: 13),
          ),
        ],
      );
    }

    if (_error != null) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, color: color, size: 16),
          const SizedBox(width: 6),
          Text(
            'Error al cargar audio',
            style: TextStyle(color: color, fontSize: 13),
          ),
        ],
      );
    }

    // Not yet loaded — show tap-to-play
    if (!_initialized) {
      return GestureDetector(
        onTap: _ensureInitialized,
        child: SizedBox(
          width: 220,
          child: Row(
            children: [
              _initializing
                  ? SizedBox(
                      width: 36,
                      height: 36,
                      child: Padding(
                        padding: const EdgeInsets.all(7),
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: color,
                        ),
                      ),
                    )
                  : Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: color.withValues(alpha: 0.15),
                      ),
                      child: Icon(
                        Icons.play_arrow_rounded,
                        color: color,
                        size: 22,
                      ),
                    ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Audio',
                      style: TextStyle(
                        color: color,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    // Fake waveform bar
                    _StaticWaveform(color: color),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Initialized — show inline player
    final player = _player!;
    final progress = _duration.inMilliseconds > 0
        ? (_position.inMilliseconds / _duration.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;

    return SizedBox(
      width: 230,
      child: Row(
        children: [
          GestureDetector(
            onTap: _togglePlayPause,
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withValues(alpha: 0.15),
              ),
              child: Icon(
                _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                color: color,
                size: 22,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SliderTheme(
                  data: SliderThemeData(
                    trackHeight: 2.5,
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 5,
                    ),
                    overlayShape: SliderComponentShape.noOverlay,
                    activeTrackColor: color,
                    inactiveTrackColor: color.withValues(alpha: 0.25),
                    thumbColor: color,
                  ),
                  child: Slider(
                    value: progress.toDouble(),
                    onChanged: (v) {
                      final ms = (v * _duration.inMilliseconds).round();
                      player.seek(Duration(milliseconds: ms));
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _fmt(_position),
                        style: TextStyle(
                          color: color.withValues(alpha: 0.7),
                          fontSize: 9,
                        ),
                      ),
                      Text(
                        _fmt(_duration),
                        style: TextStyle(
                          color: color.withValues(alpha: 0.7),
                          fontSize: 9,
                        ),
                      ),
                    ],
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

/// A decorative static waveform bar shown before audio is loaded.
class _StaticWaveform extends StatelessWidget {
  const _StaticWaveform({required this.color});
  final Color color;

  static const _heights = [
    4.0,
    8.0,
    12.0,
    6.0,
    14.0,
    8.0,
    10.0,
    6.0,
    4.0,
    12.0,
    8.0,
    14.0,
    6.0,
    10.0,
    8.0,
    4.0,
    12.0,
    6.0,
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 20,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: _heights
            .map(
              (h) => Container(
                width: 3,
                height: h,
                margin: const EdgeInsets.symmetric(horizontal: 1),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}

class _VideoContent extends StatefulWidget {
  const _VideoContent({required this.msg, required this.textColor});
  final WaCrmMessage msg;
  final Color textColor;
  @override
  State<_VideoContent> createState() => _VideoContentState();
}

class _VideoContentState extends State<_VideoContent> {
  media_kit.Player? _player;
  media_kit_video.VideoController? _videoController;
  StreamSubscription<bool>? _playingSub;
  bool _loading = false;
  bool _initialized = false;
  bool _playing = false;
  String? _error;

  @override
  void dispose() {
    _playingSub?.cancel();
    _player?.dispose();
    super.dispose();
  }

  Future<void> _initializeAndPlay() async {
    if (widget.msg.mediaUrl == null) return;
    setState(() => _loading = true);
    try {
      final source = await _mediaSourceForPlayback(
        widget.msg.mediaUrl!,
        widget.msg.mediaMimeType ?? 'video/mp4',
        prefix: 'wa_video',
      );
      final player = media_kit.Player();
      await player.setVolume(100);
      final controller = media_kit_video.VideoController(player);
      _playingSub = player.stream.playing.listen((value) {
        if (mounted) setState(() => _playing = value);
      });
      await player.open(media_kit.Media(source), play: true);
      if (!mounted) {
        await player.dispose();
        return;
      }
      setState(() {
        _player = player;
        _videoController = controller;
        _initialized = true;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.toString();
        });
      }
    }
  }

  Future<void> _togglePlayPause() async {
    final player = _player;
    if (player == null) return;
    if (_playing) {
      await player.pause();
    } else {
      await player.play();
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.textColor;
    final controller = _videoController;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: GestureDetector(
            onTap: _initialized ? _togglePlayPause : _initializeAndPlay,
            child: Container(
              width: 260,
              height: 150,
              color: Colors.black87,
              child: _error != null
                  ? const Center(
                      child: Icon(
                        Icons.error_outline,
                        color: Colors.white70,
                        size: 34,
                      ),
                    )
                  : _initialized && controller != null
                  ? Stack(
                      alignment: Alignment.center,
                      children: [
                        media_kit_video.Video(controller: controller),
                        if (!_playing)
                          Container(
                            width: 52,
                            height: 52,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.black45,
                            ),
                            child: const Icon(
                              Icons.play_arrow_rounded,
                              color: Colors.white,
                              size: 34,
                            ),
                          ),
                      ],
                    )
                  : _loading
                  ? const Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    )
                  : Stack(
                      alignment: Alignment.center,
                      children: [
                        const Icon(
                          Icons.videocam_rounded,
                          color: Colors.white54,
                          size: 40,
                        ),
                        Container(
                          width: 52,
                          height: 52,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.black45,
                          ),
                          child: const Icon(
                            Icons.play_arrow_rounded,
                            color: Colors.white,
                            size: 34,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
        if (widget.msg.caption?.isNotEmpty == true)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              _waText(widget.msg.caption),
              style: TextStyle(color: color, fontSize: 13),
            ),
          ),
      ],
    );
  }
}

class _DocumentContent extends StatefulWidget {
  const _DocumentContent({required this.msg, required this.textColor});
  final WaCrmMessage msg;
  final Color textColor;
  @override
  State<_DocumentContent> createState() => _DocumentContentState();
}

class _DocumentContentState extends State<_DocumentContent> {
  bool _loading = false;

  Future<void> _open() async {
    if (widget.msg.mediaUrl == null) return;
    setState(() => _loading = true);
    await _openMedia(widget.msg.mediaUrl!, widget.msg.mediaMimeType);
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.textColor;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _loading
            ? SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: color),
              )
            : Icon(Icons.insert_drive_file_rounded, color: color, size: 18),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            _waText(widget.msg.body, 'Documento'),
            style: TextStyle(color: color, fontSize: 13),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (widget.msg.mediaUrl != null) ...[
          const SizedBox(width: 6),
          GestureDetector(
            onTap: _open,
            child: Icon(Icons.download_rounded, color: color, size: 16),
          ),
        ],
      ],
    );
  }
}

// ─── Chat Input ───────────────────────────────────────────────────────────────

class _ChatInput extends StatelessWidget {
  const _ChatInput({
    required this.controller,
    required this.sending,
    required this.unlocked,
    required this.onUnlock,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool sending;
  final bool unlocked;
  final VoidCallback onUnlock;
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
            child: unlocked
                ? TextField(
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
                  )
                : OutlinedButton.icon(
                    onPressed: onUnlock,
                    icon: const Icon(Icons.lock_rounded, size: 18),
                    label: const Text('Desbloquear escritura'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(42),
                      alignment: Alignment.centerLeft,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                    ),
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
                  onPressed: unlocked ? onSend : onUnlock,
                  style: FilledButton.styleFrom(
                    shape: const CircleBorder(),
                    padding: const EdgeInsets.all(12),
                  ),
                  child: Icon(
                    unlocked ? Icons.send_rounded : Icons.lock_open_rounded,
                    size: 18,
                  ),
                ),
        ],
      ),
    );
  }
}

// ─── Actions Panel (Column 3) ────────────────────────────────────────────────

class _DailyAiPanel extends StatelessWidget {
  const _DailyAiPanel({
    required this.state,
    required this.onPickDate,
    required this.onGenerate,
  });

  final WaCrmState state;
  final VoidCallback onPickDate;
  final VoidCallback onGenerate;

  static Color _severityColor(BuildContext context, String severity) {
    final scheme = Theme.of(context).colorScheme;
    switch (severity) {
      case 'high':
        return scheme.error;
      case 'medium':
        return Colors.orange.shade700;
      default:
        return scheme.primary;
    }
  }

  static IconData _alertIcon(String type) {
    switch (type) {
      case 'fraud':
        return Icons.gpp_bad_outlined;
      case 'misconduct':
        return Icons.report_problem_outlined;
      case 'angry_customer':
        return Icons.mood_bad_outlined;
      case 'no_response':
      case 'unanswered':
        return Icons.chat_bubble_outline;
      case 'spelling':
        return Icons.spellcheck_outlined;
      default:
        return Icons.warning_amber_outlined;
    }
  }

  static Color _statusColor(BuildContext context, String status) {
    final scheme = Theme.of(context).colorScheme;
    switch (status) {
      case 'interested':
        return Colors.green.shade700;
      case 'angry':
        return scheme.error;
      case 'no_response':
        return Colors.orange.shade700;
      case 'closed':
        return scheme.onSurfaceVariant;
      default:
        return scheme.primary;
    }
  }

  static String _statusLabel(String status) {
    switch (status) {
      case 'interested':
        return 'Interesado';
      case 'not_interested':
        return 'No interesado';
      case 'angry':
        return 'Enojado';
      case 'no_response':
        return 'Sin respuesta';
      case 'closed':
        return 'Cerrado';
      case 'pending':
        return 'Pendiente';
      default:
        return status;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final date = state.aiSummaryDate ?? DateTime.now();
    final summary = state.aiSummary;
    final stats = summary?.stats ?? const <String, dynamic>{};
    final alerts = summary?.alerts ?? const <WaCrmAiAlert>[];
    final convAnalysis =
        summary?.conversationAnalysis ?? const <WaCrmConversationAnalysis>[];
    final highAlerts = alerts.where((a) => a.severity == 'high').toList();

    return Container(
      color: scheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  scheme.primaryContainer.withValues(alpha: 0.9),
                  scheme.secondaryContainer.withValues(alpha: 0.75),
                ],
              ),
              border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: scheme.surface.withValues(alpha: 0.72),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.auto_awesome, color: scheme.primary),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'IA del dia',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                          color: scheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Resumen de actividad, interes comercial y seguimiento del WhatsApp seleccionado.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onPrimaryContainer.withValues(alpha: 0.78),
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onPickDate,
                    icon: const Icon(Icons.calendar_month_outlined, size: 18),
                    label: Text(DateFormat('dd/MM/yyyy').format(date)),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed:
                      state.loadingAiSummary || state.selectedUser == null
                      ? null
                      : onGenerate,
                  icon: state.loadingAiSummary
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.analytics_outlined, size: 18),
                  label: const Text('Generar'),
                ),
              ],
            ),
          ),
          if (summary != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _AiStatPill(
                    label: 'Contactos',
                    value: '${stats['contacts'] ?? 0}',
                  ),
                  _AiStatPill(
                    label: 'Recibidos',
                    value: '${stats['incomingMessages'] ?? 0}',
                  ),
                  _AiStatPill(
                    label: 'Enviados',
                    value: '${stats['outgoingMessages'] ?? 0}',
                  ),
                  _AiStatPill(
                    label: 'Media',
                    value: '${stats['mediaMessages'] ?? 0}',
                  ),
                  if (highAlerts.isNotEmpty)
                    _AiStatPill(
                      label: 'Alertas críticas',
                      value: '${highAlerts.length}',
                      isAlert: true,
                    ),
                ],
              ),
            ),
          if (state.aiSummaryError != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                _waText(state.aiSummaryError),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.error,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          Expanded(
            child: summary == null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(22),
                      child: Text(
                        state.selectedUser == null
                            ? 'Selecciona una instancia para analizar el dia.'
                            : 'Genera un resumen para revisar ventas gestionadas, clientes interesados y seguimientos.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                          height: 1.35,
                        ),
                      ),
                    ),
                  )
                : SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ── Critical alerts banner ─────────────────────
                        if (alerts.isNotEmpty) ...[
                          Container(
                            margin: const EdgeInsets.only(bottom: 14),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: highAlerts.isNotEmpty
                                  ? scheme.errorContainer.withValues(alpha: 0.55)
                                  : Colors.orange.shade50.withValues(alpha: 0.5),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: highAlerts.isNotEmpty
                                    ? scheme.error.withValues(alpha: 0.5)
                                    : Colors.orange.shade300,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      highAlerts.isNotEmpty
                                          ? Icons.gpp_bad_outlined
                                          : Icons.warning_amber_outlined,
                                      color: highAlerts.isNotEmpty
                                          ? scheme.error
                                          : Colors.orange.shade700,
                                      size: 18,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      'Alertas detectadas (${alerts.length})',
                                      style: theme.textTheme.labelMedium?.copyWith(
                                        fontWeight: FontWeight.w800,
                                        color: highAlerts.isNotEmpty
                                            ? scheme.error
                                            : Colors.orange.shade700,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                ...alerts.map(
                                  (alert) => Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Icon(
                                          _alertIcon(alert.type),
                                          size: 15,
                                          color: _severityColor(
                                            context,
                                            alert.severity,
                                          ),
                                        ),
                                        const SizedBox(width: 7),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              if (alert.contact.isNotEmpty)
                                                Text(
                                                  alert.contact,
                                                  style: theme
                                                      .textTheme.labelSmall
                                                      ?.copyWith(
                                                    fontWeight: FontWeight.w700,
                                                    color: scheme.onSurface,
                                                  ),
                                                ),
                                              Text(
                                                _waText(alert.description),
                                                style: theme
                                                    .textTheme.bodySmall
                                                    ?.copyWith(
                                                  height: 1.35,
                                                  color: scheme.onSurface,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Container(
                                          margin: const EdgeInsets.only(
                                            left: 6,
                                            top: 1,
                                          ),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 7,
                                            vertical: 3,
                                          ),
                                          decoration: BoxDecoration(
                                            color: _severityColor(
                                              context,
                                              alert.severity,
                                            ).withValues(alpha: 0.12),
                                            borderRadius:
                                                BorderRadius.circular(6),
                                            border: Border.all(
                                              color: _severityColor(
                                                context,
                                                alert.severity,
                                              ).withValues(alpha: 0.4),
                                            ),
                                          ),
                                          child: Text(
                                            alert.severity.toUpperCase(),
                                            style: theme.textTheme.labelSmall
                                                ?.copyWith(
                                              fontSize: 9,
                                              fontWeight: FontWeight.w800,
                                              color: _severityColor(
                                                context,
                                                alert.severity,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        // ── Summary text ───────────────────────────────
                        Text(
                          'Resumen ejecutivo',
                          style: theme.textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: scheme.onSurfaceVariant,
                            letterSpacing: 0.4,
                          ),
                        ),
                        const SizedBox(height: 6),
                        SelectableText(
                          _waText(summary.summary),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            height: 1.42,
                            color: scheme.onSurface,
                          ),
                        ),
                        // ── Per-conversation analysis ──────────────────
                        if (convAnalysis.isNotEmpty) ...[
                          const SizedBox(height: 18),
                          Text(
                            'Análisis por conversación',
                            style: theme.textTheme.labelMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: scheme.onSurfaceVariant,
                              letterSpacing: 0.4,
                            ),
                          ),
                          const SizedBox(height: 8),
                          ...convAnalysis.map(
                            (conv) => Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.all(11),
                              decoration: BoxDecoration(
                                color: scheme.surfaceContainerHighest
                                    .withValues(alpha: 0.45),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: scheme.outlineVariant,
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          _waText(conv.contact),
                                          style: theme.textTheme.labelMedium
                                              ?.copyWith(
                                            fontWeight: FontWeight.w700,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 3,
                                        ),
                                        decoration: BoxDecoration(
                                          color: _statusColor(
                                            context,
                                            conv.status,
                                          ).withValues(alpha: 0.1),
                                          borderRadius:
                                              BorderRadius.circular(8),
                                          border: Border.all(
                                            color: _statusColor(
                                              context,
                                              conv.status,
                                            ).withValues(alpha: 0.35),
                                          ),
                                        ),
                                        child: Text(
                                          _statusLabel(conv.status),
                                          style: theme.textTheme.labelSmall
                                              ?.copyWith(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 10,
                                            color: _statusColor(
                                              context,
                                              conv.status,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (conv.summary.isNotEmpty) ...[
                                    const SizedBox(height: 5),
                                    Text(
                                      _waText(conv.summary),
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                        height: 1.35,
                                        color: scheme.onSurface,
                                      ),
                                    ),
                                  ],
                                  if (conv.issues.isNotEmpty) ...[
                                    const SizedBox(height: 6),
                                    Wrap(
                                      spacing: 5,
                                      runSpacing: 4,
                                      children: conv.issues
                                          .map(
                                            (issue) => Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 7,
                                                vertical: 3,
                                              ),
                                              decoration: BoxDecoration(
                                                color: scheme.errorContainer
                                                    .withValues(alpha: 0.35),
                                                borderRadius:
                                                    BorderRadius.circular(6),
                                              ),
                                              child: Text(
                                                _waText(issue),
                                                style: theme
                                                    .textTheme.labelSmall
                                                    ?.copyWith(
                                                  fontSize: 10,
                                                  color:
                                                      scheme.onErrorContainer,
                                                ),
                                              ),
                                            ),
                                          )
                                          .toList(),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _AiStatPill extends StatelessWidget {
  const _AiStatPill({
    required this.label,
    required this.value,
    this.isAlert = false,
  });

  final String label;
  final String value;
  final bool isAlert;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final alertColor = scheme.error;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: isAlert
            ? alertColor.withValues(alpha: 0.1)
            : scheme.surfaceContainerHighest.withValues(alpha: 0.58),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isAlert
              ? alertColor.withValues(alpha: 0.4)
              : scheme.outlineVariant,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _waText(label),
            style: theme.textTheme.labelSmall?.copyWith(
              color: isAlert ? alertColor : scheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            _waText(value),
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w900,
              color: isAlert ? alertColor : null,
            ),
          ),
        ],
      ),
    );
  }
}

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
              value: _waText(conv.displayName),
            ),
            if (conv.displayPhone != null)
              _InfoRow(
                icon: Icons.phone_outlined,
                label: 'Teléfono',
                value: _waText(conv.displayPhone),
              ),
            if (conv.lastMessageAt != null)
              _InfoRow(
                icon: Icons.access_time_rounded,
                label: 'Último mensaje',
                value: DateFormat(
                  'dd/MM HH:mm',
                ).format(conv.lastMessageAt!.toLocal()),
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
              value: _waText(state.selectedUser!.name),
            ),
            _InfoRow(
              icon: Icons.wifi_tethering_rounded,
              label: 'Estado',
              value: _waText(state.selectedUser!.instanceStatus, 'N/A'),
            ),
            if (state.selectedUser!.phone != null)
              _InfoRow(
                icon: Icons.sim_card_outlined,
                label: 'Número',
                value: _waText(state.selectedUser!.phone),
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
                  _waText(label),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                  ),
                ),
                Text(_waText(value), style: theme.textTheme.bodySmall),
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
