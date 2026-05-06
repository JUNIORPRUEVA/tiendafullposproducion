import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
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
import '../../core/routing/routes.dart';
import '../../core/widgets/app_drawer.dart';
import '../../core/widgets/app_navigation.dart' show kDesktopShellBreakpoint;
import '../../core/widgets/custom_app_bar.dart';
import '../../core/widgets/responsive_shell.dart';
import '../../core/widgets/user_avatar.dart';
import '../whatsapp_crm/application/wa_crm_controller.dart';
import '../whatsapp_crm/data/wa_crm_repository.dart';
import '../whatsapp_crm/models/wa_crm_conversation.dart';
import '../whatsapp_crm/models/wa_crm_message.dart';

// ─── Breakpoints ─────────────────────────────────────────────────────────────

const double _kMobileBreak = 600;
const double _kTabletBreak = 1180;
final Map<String, Future<Uint8List>> _waMediaBytesCache = {};

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

String _mimeFromPickedFile(String name, String? extension) {
  final ext = (extension ?? name.split('.').last).toLowerCase();
  switch (ext) {
    case 'jpg':
    case 'jpeg':
      return 'image/jpeg';
    case 'png':
      return 'image/png';
    case 'webp':
      return 'image/webp';
    case 'gif':
      return 'image/gif';
    case 'mp4':
    case 'm4v':
      return 'video/mp4';
    case 'mov':
      return 'video/quicktime';
    case 'webm':
      return 'video/webm';
    case 'mp3':
      return 'audio/mpeg';
    case 'm4a':
      return 'audio/mp4';
    case 'ogg':
    case 'opus':
      return 'audio/ogg';
    case 'wav':
      return 'audio/wav';
    case 'pdf':
      return 'application/pdf';
    case 'doc':
      return 'application/msword';
    case 'docx':
      return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
    case 'xls':
      return 'application/vnd.ms-excel';
    case 'xlsx':
      return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
    case 'txt':
      return 'text/plain';
    default:
      return 'application/octet-stream';
  }
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
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
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
                            style: Theme.of(dialogContext).textTheme.bodyMedium
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
  final _conversationScrollController = ScrollController();
  late final WaCrmController _waCrmNotifier;
  late final StateController<DesktopShellRouteActions?> _desktopShellActions;
  late final OperationsRealtimeService _realtimeService;
  ProviderSubscription<WaCrmState>? _waCrmSubscription;
  StreamSubscription<Map<String, dynamic>>? _whatsappSub;
  Timer? _autoRefreshTimer;
  bool _autoRefreshInFlight = false;
  String _lastShellActionsSignature = '';
  bool _showActionPanel = true;
  bool _showAiPanel = false;
  bool _showNewMessagesButton = false;
  int _mobileTabIndex = 0;

  static const double _nearBottomThreshold = 140;

  @override
  void initState() {
    super.initState();
    _waCrmNotifier = ref.read(waCrmControllerProvider.notifier);
    _desktopShellActions = ref.read(desktopShellRouteActionsProvider.notifier);
    _realtimeService = ref.read(operationsRealtimeServiceProvider);
    _scrollController.addListener(_handleChatScroll);
    _waCrmSubscription = ref.listenManual<WaCrmState>(waCrmControllerProvider, (
      prev,
      next,
    ) {
      final previousConversationId = prev?.selectedConversation?.id;
      final nextConversationId = next.selectedConversation?.id;
      final conversationChanged = previousConversationId != nextConversationId;
      final messageCountIncreased =
          !conversationChanged &&
          (prev?.messages.length ?? 0) < next.messages.length;

      if (conversationChanged) {
        if (_showNewMessagesButton) {
          setState(() => _showNewMessagesButton = false);
        }
        if (next.messages.isNotEmpty) {
          _scrollToBottom(force: true, animated: false);
        }
        return;
      }

      if (messageCountIncreased) {
        if (_isChatNearBottom()) {
          _scrollToBottom(force: true);
        } else if (!_showNewMessagesButton) {
          setState(() => _showNewMessagesButton = true);
        }
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final user = ref.read(authStateProvider).user;
      if (user?.appRole != AppRole.admin) {
        context.go(
          RouteAccess.defaultHomeForRole(user?.appRole ?? AppRole.unknown),
        );
        return;
      }
      _waCrmNotifier.loadUsers();
      _listenRealtime();
      _startAutoRefresh();
    });
  }

  void _listenRealtime() {
    _whatsappSub = _realtimeService.whatsappStream.listen((data) {
      if (!mounted) return;
      _waCrmNotifier.handleRealtimeMessage(data);
    });
  }

  void _startAutoRefresh() {
    _autoRefreshTimer?.cancel();
    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 45), (_) async {
      if (!mounted) return;
      if (_autoRefreshInFlight) return;
      final state = ref.read(waCrmControllerProvider);
      if (state.loadingConversations ||
          state.loadingMessages ||
          state.syncingInBackground) {
        return;
      }
      _autoRefreshInFlight = true;
      try {
        await _waCrmNotifier.refreshActiveView();
      } finally {
        _autoRefreshInFlight = false;
      }
    });
  }

  @override
  void dispose() {
    if (_desktopShellActions.state?.route == Routes.whatsappCrm) {
      _desktopShellActions.state = null;
    }
    _autoRefreshTimer?.cancel();
    _whatsappSub?.cancel();
    _waCrmSubscription?.close();
    _msgController.dispose();
    _scrollController.dispose();
    _conversationScrollController.dispose();
    super.dispose();
  }

  void _handleChatScroll() {
    if (_showNewMessagesButton && _isChatNearBottom()) {
      setState(() => _showNewMessagesButton = false);
    }
  }

  void _publishDesktopShellActions({required bool enabled}) {
    final signature = enabled
        ? '${Routes.whatsappCrm}:$_showActionPanel:$_showAiPanel'
        : '${Routes.whatsappCrm}:disabled';
    if (_lastShellActionsSignature == signature) return;
    _lastShellActionsSignature = signature;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!enabled) {
        if (_desktopShellActions.state?.route == Routes.whatsappCrm) {
          _desktopShellActions.state = null;
        }
        return;
      }

      _desktopShellActions.state = DesktopShellRouteActions(
        route: Routes.whatsappCrm,
        actions: [
          DesktopShellActionItem(
            icon: Icons.view_sidebar_outlined,
            selectedIcon: Icons.view_sidebar,
            selected: _showActionPanel,
            tooltip: _showActionPanel
                ? 'Ocultar panel derecho'
                : 'Mostrar panel derecho',
            onPressed: () {
              if (!mounted) return;
              setState(() => _showActionPanel = !_showActionPanel);
              _lastShellActionsSignature = '';
            },
          ),
          DesktopShellActionItem(
            icon: Icons.auto_awesome_outlined,
            selectedIcon: Icons.auto_awesome,
            selected: _showAiPanel,
            tooltip: _showAiPanel ? 'Ocultar IA' : 'Mostrar IA',
            onPressed: () {
              if (!mounted) return;
              setState(() => _showAiPanel = !_showAiPanel);
              _lastShellActionsSignature = '';
            },
          ),
        ],
      );
    });
  }

  void _refreshActiveView() {
    _waCrmNotifier.refreshActiveView();
  }

  bool _isChatNearBottom() {
    if (!_scrollController.hasClients) return true;
    final position = _scrollController.position;
    if (!position.hasContentDimensions) return true;
    return position.maxScrollExtent - position.pixels <= _nearBottomThreshold;
  }

  void _scrollToBottom({bool force = false, bool animated = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!_scrollController.hasClients) return;
      if (!_scrollController.position.hasContentDimensions) return;
      if (!force && !_isChatNearBottom()) return;
      final target = _scrollController.position.maxScrollExtent;
      final current = _scrollController.position.pixels;
      if ((current - target).abs() < 1) {
        if (_showNewMessagesButton && mounted) {
          setState(() => _showNewMessagesButton = false);
        }
        return;
      }
      if (animated) {
        _scrollController.animateTo(
          target,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
        );
      } else {
        _scrollController.jumpTo(target);
      }
      if (_showNewMessagesButton && mounted) {
        setState(() => _showNewMessagesButton = false);
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
    final canShowSidePanels = size.width >= _kTabletBreak;
    final usesDesktopShellAppBar = size.width >= kDesktopShellBreakpoint;

    _publishDesktopShellActions(enabled: usesDesktopShellAppBar);

    // ── Listen for new messages to scroll ──────────────────────────────────
    Widget body;
    if (isMobile) {
      body = _buildMobileLayout(context, state, theme);
    } else if (isTablet) {
      body = _buildTwoColumnLayout(context, state, theme);
    } else {
      body = _buildThreeColumnLayout(context, state, theme);
    }

    return Scaffold(
      appBar: usesDesktopShellAppBar
          ? null
          : CustomAppBar(
              title: 'CRM WhatsApp',
              showLogo: false,
              showDepartmentLabel: false,
              actions: [
                if (canShowSidePanels)
                  IconButton(
                    icon: Icon(
                      _showActionPanel
                          ? Icons.view_sidebar_outlined
                          : Icons.view_sidebar,
                    ),
                    tooltip: _showActionPanel
                        ? 'Ocultar panel'
                        : 'Mostrar panel',
                    onPressed: () =>
                        setState(() => _showActionPanel = !_showActionPanel),
                  ),
                if (canShowSidePanels)
                  IconButton(
                    icon: Icon(
                      _showAiPanel
                          ? Icons.auto_awesome
                          : Icons.auto_awesome_outlined,
                    ),
                    tooltip: _showAiPanel ? 'Ocultar IA' : 'Resumen IA del dia',
                    onPressed: () =>
                        setState(() => _showAiPanel = !_showAiPanel),
                  ),
                IconButton(
                  icon: const Icon(Icons.refresh_rounded),
                  tooltip: 'Actualizar',
                  onPressed: _refreshActiveView,
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        final conversationWidth = maxWidth < 1320 ? 236.0 : 264.0;
        final actionWidth = maxWidth < 1320 ? 232.0 : 260.0;
        final aiWidth = maxWidth < 1320 ? 320.0 : 360.0;
        const minChatWidth = 430.0;

        var showActionPanel = _showActionPanel;
        var showAiPanel = _showAiPanel;

        if (showActionPanel && showAiPanel) {
          final chatWidth =
              maxWidth - conversationWidth - actionWidth - aiWidth - 3;
          if (chatWidth < minChatWidth) {
            showActionPanel = false;
          }
        }

        if (showAiPanel) {
          final chatWidth = maxWidth - conversationWidth - aiWidth - 2;
          if (chatWidth < minChatWidth) {
            showAiPanel = false;
          }
        }

        if (showActionPanel) {
          final chatWidth = maxWidth - conversationWidth - actionWidth - 2;
          if (chatWidth < minChatWidth) {
            showActionPanel = false;
          }
        }

        return Row(
          children: [
            SizedBox(
              width: conversationWidth,
              child: _ConversationsPanel(
                state: state,
                scrollController: _conversationScrollController,
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
                showNewMessagesButton: _showNewMessagesButton,
                onJumpToLatest: () => _scrollToBottom(force: true),
                onSend: () => _sendReply(),
                onAttach: () => _sendAttachment(),
                onDateFilterChanged: (filter, {customDate}) => ref
                    .read(waCrmControllerProvider.notifier)
                    .setMessageDateFilter(filter, customDate: customDate),
                onClearDateFilter: () => ref
                    .read(waCrmControllerProvider.notifier)
                    .clearMessageDateFilter(),
                onUnlock: _unlockComposer,
                agentName: state.selectedUser?.name,
              ),
            ),
            if (showActionPanel) ...[
              const VerticalDivider(width: 1),
              SizedBox(
                width: actionWidth,
                child: _ActionsPanel(state: state),
              ),
            ],
            if (showAiPanel) ...[
              const VerticalDivider(width: 1),
              SizedBox(
                width: aiWidth,
                child: _DailyAiPanel(
                  state: state,
                  onPickDate: _pickAiSummaryDate,
                  onGenerate: () => ref
                      .read(waCrmControllerProvider.notifier)
                      .generateDailyAiSummary(),
                  onAnalyzeConversation: () => ref
                      .read(waCrmControllerProvider.notifier)
                      .analyzeWithAi(scope: WaCrmAiAnalysisScope.conversation),
                  onAnalyzeFilter: () => ref
                      .read(waCrmControllerProvider.notifier)
                      .analyzeWithAi(scope: WaCrmAiAnalysisScope.filter),
                  onRefreshAnalysis: () => ref
                      .read(waCrmControllerProvider.notifier)
                      .analyzeWithAi(
                        scope: state.aiAnalysisScope,
                        forceRefresh: true,
                      ),
                  onAskReport: (question) => ref
                      .read(waCrmControllerProvider.notifier)
                      .askCurrentAiReport(question),
                ),
              ),
            ],
          ],
        );
      },
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
          width: 228,
          child: _ConversationsPanel(
            state: state,
            scrollController: _conversationScrollController,
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
            showNewMessagesButton: _showNewMessagesButton,
            onJumpToLatest: () => _scrollToBottom(force: true),
            onSend: () => _sendReply(),
            onAttach: () => _sendAttachment(),
            onDateFilterChanged: (filter, {customDate}) => ref
                .read(waCrmControllerProvider.notifier)
                .setMessageDateFilter(filter, customDate: customDate),
            onClearDateFilter: () => ref
                .read(waCrmControllerProvider.notifier)
                .clearMessageDateFilter(),
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
    final showAi = _mobileTabIndex == 1;
    final scheme = theme.colorScheme;
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          decoration: BoxDecoration(
            color: scheme.surface,
            border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
          ),
          child: Row(
            children: [
              Expanded(
                child: _MobileCrmTabButton(
                  selected: !showAi,
                  icon: state.selectedConversation == null
                      ? Icons.forum_outlined
                      : Icons.chat_bubble_outline_rounded,
                  label: state.selectedConversation == null ? 'Chats' : 'Chat',
                  onPressed: () => setState(() => _mobileTabIndex = 0),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _MobileCrmTabButton(
                  selected: showAi,
                  icon: Icons.auto_awesome_outlined,
                  label: 'IA',
                  onPressed: () => setState(() => _mobileTabIndex = 1),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: showAi
              ? _DailyAiPanel(
                  state: state,
                  onPickDate: _pickAiSummaryDate,
                  onGenerate: () => ref
                      .read(waCrmControllerProvider.notifier)
                      .generateDailyAiSummary(),
                  onAnalyzeConversation: () => ref
                      .read(waCrmControllerProvider.notifier)
                      .analyzeWithAi(scope: WaCrmAiAnalysisScope.conversation),
                  onAnalyzeFilter: () => ref
                      .read(waCrmControllerProvider.notifier)
                      .analyzeWithAi(scope: WaCrmAiAnalysisScope.filter),
                  onRefreshAnalysis: () => ref
                      .read(waCrmControllerProvider.notifier)
                      .analyzeWithAi(
                        scope: state.aiAnalysisScope,
                        forceRefresh: true,
                      ),
                  onAskReport: (question) => ref
                      .read(waCrmControllerProvider.notifier)
                      .askCurrentAiReport(question),
                )
              : state.selectedConversation != null
              ? Column(
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
                              const Icon(
                                Icons.arrow_back_ios_new_rounded,
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _waText(
                                    state.selectedConversation!.displayName,
                                  ),
                                  style: theme.textTheme.titleMedium,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              IconButton(
                                tooltip: 'Abrir IA',
                                onPressed: () =>
                                    setState(() => _mobileTabIndex = 1),
                                icon: const Icon(
                                  Icons.auto_awesome_outlined,
                                  size: 20,
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
                        showNewMessagesButton: _showNewMessagesButton,
                        onJumpToLatest: () => _scrollToBottom(force: true),
                        onSend: () => _sendReply(),
                        onAttach: () => _sendAttachment(),
                        onDateFilterChanged: (filter, {customDate}) => ref
                            .read(waCrmControllerProvider.notifier)
                            .setMessageDateFilter(
                              filter,
                              customDate: customDate,
                            ),
                        onClearDateFilter: () => ref
                            .read(waCrmControllerProvider.notifier)
                            .clearMessageDateFilter(),
                        onUnlock: _unlockComposer,
                        agentName: state.selectedUser?.name,
                      ),
                    ),
                  ],
                )
              : _ConversationsPanel(
                  state: state,
                  scrollController: _conversationScrollController,
                  onSelectConversation: (conv) {
                    setState(() => _mobileTabIndex = 0);
                    ref
                        .read(waCrmControllerProvider.notifier)
                        .selectConversation(conv);
                  },
                  onSelectUser: (u) {
                    ref.read(waCrmControllerProvider.notifier).selectUser(u);
                  },
                ),
        ),
      ],
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

  Future<void> _sendAttachment() async {
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

    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const [
        'jpg',
        'jpeg',
        'png',
        'webp',
        'gif',
        'mp4',
        'mov',
        'm4v',
        'webm',
        'mp3',
        'm4a',
        'ogg',
        'opus',
        'wav',
        'pdf',
        'doc',
        'docx',
        'xls',
        'xlsx',
        'txt',
      ],
      withData: true,
    );
    final file = picked?.files.single;
    if (file == null) return;

    final bytes =
        file.bytes ??
        (file.path != null ? await File(file.path!).readAsBytes() : null);
    if (bytes == null || bytes.isEmpty) return;

    final caption = _msgController.text.trim();
    _msgController.clear();
    await ref
        .read(waCrmControllerProvider.notifier)
        .sendMediaReply(
          bytes: bytes,
          fileName: file.name,
          mimeType: _mimeFromPickedFile(file.name, file.extension),
          caption: caption.isEmpty ? null : caption,
        );
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

class _MobileCrmTabButton extends StatelessWidget {
  const _MobileCrmTabButton({
    required this.selected,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final bool selected;
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final background = selected
        ? scheme.primaryContainer
        : scheme.surfaceContainerHighest.withValues(alpha: 0.58);
    final foreground = selected
        ? scheme.onPrimaryContainer
        : scheme.onSurfaceVariant;
    return Material(
      color: background,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onPressed,
        child: Container(
          height: 44,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? scheme.primary : scheme.outlineVariant,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: foreground),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  _waText(label),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: foreground,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Conversations Panel (Column 1) ─────────────────────────────────────────

class _ConversationsPanel extends StatefulWidget {
  const _ConversationsPanel({
    required this.state,
    required this.scrollController,
    required this.onSelectConversation,
    required this.onSelectUser,
  });

  final WaCrmState state;
  final ScrollController scrollController;
  final ValueChanged<WaCrmConversation> onSelectConversation;
  final ValueChanged<WaCrmUser> onSelectUser;

  @override
  State<_ConversationsPanel> createState() => _ConversationsPanelState();
}

class _ConversationsPanelState extends State<_ConversationsPanel> {
  bool _showInstances = false;
  WaCrmMessageDateFilter _chatDateFilter = WaCrmMessageDateFilter.all;
  DateTime? _customChatDate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = widget.state;
    final filteredConversations = _filterConversationsByDate(
      state.conversations,
      _chatDateFilter,
      _customChatDate,
    );

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
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          color: theme.colorScheme.surfaceContainerHighest.withValues(
            alpha: 0.28,
          ),
          child: _UserSelectorDropdown(
            users: state.users,
            selected: state.selectedUser,
            loading: state.loadingUsers,
            onChanged: widget.onSelectUser,
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 5, 10, 5),
          child: _DateFilterBar(
            selected: _chatDateFilter,
            customDate: _customChatDate,
            helpText: 'Filtrar chats por fecha',
            onChanged: (filter, {customDate}) {
              setState(() {
                _chatDateFilter = filter;
                _customChatDate = customDate;
              });
            },
            onClear: () {
              setState(() {
                _chatDateFilter = WaCrmMessageDateFilter.all;
                _customChatDate = null;
              });
            },
          ),
        ),
        const Divider(height: 1),
        _ConversationStatsStrip(
          chats: filteredConversations.length,
          unread: filteredConversations.fold<int>(
            0,
            (sum, conv) => sum + conv.unreadCount,
          ),
          selectedMessages: state.messages.length,
        ),
        const Divider(height: 1),
        // ── Conversations list ────────────────────────────────────────
        Expanded(
          child: state.loadingConversations && state.conversations.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : state.conversations.isEmpty
              ? _EmptyConvState(loading: state.loadingUsers)
              : filteredConversations.isEmpty
              ? const _EmptyConvState(
                  loading: false,
                  emptyLabel: 'Sin chats para este filtro',
                )
              : ListView.builder(
                  key: const PageStorageKey<String>('wa-conversations-list'),
                  controller: widget.scrollController,
                  itemCount: filteredConversations.length,
                  itemBuilder: (context, i) {
                    final conv = filteredConversations[i];
                    final isSelected =
                        state.selectedConversation?.id == conv.id;
                    return KeyedSubtree(
                      key: ValueKey<String>('wa-conv-${conv.id}'),
                      child: _ConversationTile(
                        conv: conv,
                        isSelected: isSelected,
                        isHighlighted: state.highlightedConversationIds
                            .contains(conv.id),
                        onTap: () => widget.onSelectConversation(conv),
                      ),
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      color: theme.colorScheme.surface,
      child: Row(
        children: [
          _MiniStat(label: 'Chats', value: '$chats'),
          const SizedBox(width: 8),
          _MiniStat(label: 'Pend.', value: '$unread'),
          const SizedBox(width: 8),
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
    final connected = instances.where((item) {
      final status = item.status.toLowerCase();
      return status == 'open' || status == 'connected';
    }).length;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: onToggleExpanded,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            color: theme.colorScheme.primaryContainer.withValues(alpha: 0.18),
            child: Row(
              children: [
                Icon(
                  Icons.wifi_tethering_rounded,
                  size: 14,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    expanded
                        ? 'Instancias (${instances.length})'
                        : 'Instancias · $connected/${instances.length} activas',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.2,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      child: Row(
        children: [
          _StatusDot(status: instance.status),
          const SizedBox(width: 7),
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
                          fontSize: 11,
                          height: 1.05,
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
                    fontSize: 9.5,
                    height: 1.05,
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
              constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
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
    required this.isHighlighted,
    required this.onTap,
  });

  final WaCrmConversation conv;
  final bool isSelected;
  final bool isHighlighted;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final last = conv.lastMessage;
    final timeStr = conv.lastMessageAt != null
        ? _formatTime(conv.lastMessageAt!)
        : '';
    final mediaIcon = _previewIcon(last?.messageType);
    final preview = last == null
        ? 'Sin mensajes'
        : '${last.isOutgoing ? 'Tu: ' : ''}${last.previewText}'.trim();
    final unread = conv.unreadCount > 0;
    final activeColor = theme.colorScheme.primary;
    final rowColor = isSelected
        ? activeColor.withValues(alpha: 0.14)
        : isHighlighted
        ? activeColor.withValues(alpha: 0.06)
        : null;
    final railColor = isSelected
        ? activeColor
        : isHighlighted
        ? activeColor.withValues(alpha: 0.72)
        : unread
        ? activeColor.withValues(alpha: 0.55)
        : Colors.transparent;

    return InkWell(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: rowColor,
          border: Border(left: BorderSide(width: 4, color: railColor)),
        ),
        padding: const EdgeInsets.fromLTRB(6, 7, 10, 7),
        child: Row(
          children: [
            SizedBox(
              width: 10,
              child: Icon(
                isSelected
                    ? Icons.check_circle_rounded
                    : Icons.fiber_manual_record_rounded,
                size: isSelected ? 12 : 8,
                color: isSelected || isHighlighted
                    ? activeColor
                    : Colors.transparent,
              ),
            ),
            Material(
              color: Colors.transparent,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () => _showChatAvatarPreview(context, conv),
                child: UserAvatar(
                  imageUrl: conv.remoteAvatarUrl,
                  radius: 19,
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
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Text(
                          _waText(conv.displayName),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: unread
                                ? FontWeight.bold
                                : FontWeight.w600,
                            fontSize: 13,
                            height: 1.1,
                            color: isSelected ? activeColor : null,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (isSelected) ...[
                        const SizedBox(width: 5),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 1.5,
                          ),
                          decoration: BoxDecoration(
                            color: activeColor,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            'Activo',
                            style: TextStyle(
                              color: theme.colorScheme.onPrimary,
                              fontSize: 8.5,
                              fontWeight: FontWeight.w800,
                              height: 1,
                            ),
                          ),
                        ),
                      ],
                      if (timeStr.isNotEmpty)
                        Text(
                          timeStr,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.5,
                            ),
                            fontSize: 10.5,
                            height: 1,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      if (mediaIcon != null) ...[
                        Icon(
                          mediaIcon,
                          size: 13,
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: unread ? 0.75 : 0.52,
                          ),
                        ),
                        const SizedBox(width: 4),
                      ],
                      Expanded(
                        child: Text(
                          _waText(preview),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: unread ? 0.82 : 0.58,
                            ),
                            fontWeight: unread ? FontWeight.w600 : null,
                            fontSize: 11.5,
                            height: 1.12,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (conv.unreadCount > 0)
                        Container(
                          margin: const EdgeInsets.only(left: 4),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 1.5,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary,
                            borderRadius: BorderRadius.circular(999),
                            boxShadow: [
                              BoxShadow(
                                color: theme.colorScheme.primary.withValues(
                                  alpha: 0.24,
                                ),
                                blurRadius: 8,
                              ),
                            ],
                          ),
                          child: Text(
                            conv.unreadCount > 99
                                ? '99+'
                                : '${conv.unreadCount}',
                            style: TextStyle(
                              color: theme.colorScheme.onPrimary,
                              fontSize: 9.5,
                              fontWeight: FontWeight.bold,
                              height: 1,
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

  static IconData? _previewIcon(WaMessageType? type) {
    return switch (type) {
      WaMessageType.image => Icons.photo_camera_outlined,
      WaMessageType.video => Icons.videocam_outlined,
      WaMessageType.audio => Icons.headphones_outlined,
      WaMessageType.document => Icons.description_outlined,
      WaMessageType.sticker => Icons.sticky_note_2_outlined,
      _ => null,
    };
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

Uint8List? _tryDecodeInlineMedia(String mediaUrl) {
  try {
    if (mediaUrl.startsWith('data:')) {
      final commaIdx = mediaUrl.indexOf(',');
      if (commaIdx == -1) return null;
      return Uint8List.fromList(base64Decode(mediaUrl.substring(commaIdx + 1)));
    }
    if (!mediaUrl.startsWith('http://') &&
        !mediaUrl.startsWith('https://') &&
        !mediaUrl.startsWith('/') &&
        !mediaUrl.startsWith('file://')) {
      return Uint8List.fromList(base64Decode(mediaUrl));
    }
  } catch (_) {
    return null;
  }
  return null;
}

String? _mimeFromDataUri(String mediaUrl) {
  if (!mediaUrl.startsWith('data:')) return null;
  final commaIdx = mediaUrl.indexOf(',');
  if (commaIdx == -1) return null;
  final header = mediaUrl.substring(5, commaIdx);
  final semiIdx = header.indexOf(';');
  return semiIdx == -1 ? header : header.substring(0, semiIdx);
}

String? _mediaUrlForMessage(WaCrmMessage msg) {
  final raw = msg.mediaUrl?.trim();
  if (raw == null || raw.isEmpty) return null;
  if (raw.startsWith('data:')) return raw;
  if (raw.startsWith('/whatsapp-inbox/media/')) return raw;
  if (msg.mediaStorageKey?.trim().isNotEmpty == true ||
      msg.mediaStatus?.toLowerCase() == 'ready') {
    return '/whatsapp-inbox/media/${msg.id}';
  }
  return raw;
}

Future<Uint8List> _bytesFromMediaUrl(
  String mediaUrl, {
  required Future<Uint8List> Function(String mediaUrl)? downloadBytes,
}) async {
  final inline = _tryDecodeInlineMedia(mediaUrl);
  if (inline != null) return inline;
  if (downloadBytes == null) throw Exception('No hay descargador de media');
  final bytes = await _waMediaBytesCache.putIfAbsent(
    mediaUrl,
    () => downloadBytes(mediaUrl),
  );
  if (bytes.isEmpty) throw Exception('Archivo vacio');
  return bytes;
}

Future<void> _openMedia(
  String mediaUrl,
  String? mimeType, {
  required Future<Uint8List> Function(String mediaUrl)? downloadBytes,
}) async {
  try {
    if (mediaUrl.startsWith('http://') && downloadBytes == null ||
        mediaUrl.startsWith('https://') && downloadBytes == null) {
      await launchUrl(
        Uri.parse(mediaUrl),
        mode: LaunchMode.externalApplication,
      );
      return;
    }
    final bytes = await _bytesFromMediaUrl(
      mediaUrl,
      downloadBytes: downloadBytes,
    );
    final detectedMime = mimeType ?? _mimeFromDataUri(mediaUrl);
    final ext = _mimeToExtension(detectedMime);
    final tempDir = await getTemporaryDirectory();
    final hash = mediaUrl.hashCode.abs();
    final file = File(
      '${tempDir.path}${Platform.pathSeparator}wa_media_$hash$ext',
    );
    await file.writeAsBytes(bytes, flush: true);
    await launchUrl(Uri.file(file.path), mode: LaunchMode.externalApplication);
  } catch (e) {
    debugPrint('[WaCrm] _openMedia error: $e');
  }
}

Future<String> _mediaSourceForPlayback(
  String mediaUrl,
  String? mimeType, {
  required String prefix,
  Future<Uint8List> Function(String mediaUrl)? downloadBytes,
}) async {
  if (!mediaUrl.startsWith('data:') &&
      (mediaUrl.startsWith('http://') ||
          mediaUrl.startsWith('https://') ||
          mediaUrl.startsWith('file://')) &&
      downloadBytes == null) {
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

  final bytes = await _bytesFromMediaUrl(
    mediaUrl,
    downloadBytes: downloadBytes,
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

DateTime _dayOnly(DateTime value) {
  final local = value.toLocal();
  return DateTime(local.year, local.month, local.day);
}

bool _sameDay(DateTime a, DateTime b) => _dayOnly(a) == _dayOnly(b);

List<WaCrmMessage> _filterMessagesByDate(
  List<WaCrmMessage> messages,
  WaCrmMessageDateFilter filter,
  DateTime? customDate,
) {
  if (filter == WaCrmMessageDateFilter.all) return messages;
  final today = _dayOnly(DateTime.now());
  bool matches(WaCrmMessage msg) {
    final day = _dayOnly(msg.sentAt);
    switch (filter) {
      case WaCrmMessageDateFilter.today:
        return day == today;
      case WaCrmMessageDateFilter.yesterday:
        return day == today.subtract(const Duration(days: 1));
      case WaCrmMessageDateFilter.last7Days:
        return !day.isBefore(today.subtract(const Duration(days: 6))) &&
            !day.isAfter(today);
      case WaCrmMessageDateFilter.thisMonth:
        return day.year == today.year && day.month == today.month;
      case WaCrmMessageDateFilter.custom:
        return customDate != null && day == _dayOnly(customDate);
      case WaCrmMessageDateFilter.all:
        return true;
    }
  }

  return messages.where(matches).toList();
}

List<WaCrmConversation> _filterConversationsByDate(
  List<WaCrmConversation> conversations,
  WaCrmMessageDateFilter filter,
  DateTime? customDate,
) {
  if (filter == WaCrmMessageDateFilter.all) return conversations;
  final today = _dayOnly(DateTime.now());

  bool matches(WaCrmConversation conv) {
    final value = conv.activityAt;
    if (value.millisecondsSinceEpoch == 0) return false;
    final day = _dayOnly(value);
    switch (filter) {
      case WaCrmMessageDateFilter.today:
        return day == today;
      case WaCrmMessageDateFilter.yesterday:
        return day == today.subtract(const Duration(days: 1));
      case WaCrmMessageDateFilter.last7Days:
        return !day.isBefore(today.subtract(const Duration(days: 6))) &&
            !day.isAfter(today);
      case WaCrmMessageDateFilter.thisMonth:
        return day.year == today.year && day.month == today.month;
      case WaCrmMessageDateFilter.custom:
        return customDate != null && day == _dayOnly(customDate);
      case WaCrmMessageDateFilter.all:
        return true;
    }
  }

  return conversations.where(matches).toList();
}

String _dateSeparatorLabel(DateTime value) {
  final day = _dayOnly(value);
  final today = _dayOnly(DateTime.now());
  if (day == today) return 'Hoy';
  if (day == today.subtract(const Duration(days: 1))) return 'Ayer';
  return DateFormat('dd/MM/yyyy').format(day);
}

class _DateFilterBar extends StatelessWidget {
  const _DateFilterBar({
    required this.selected,
    required this.customDate,
    required this.onChanged,
    required this.onClear,
    this.helpText = 'Filtrar mensajes por fecha',
  });

  final WaCrmMessageDateFilter selected;
  final DateTime? customDate;
  final void Function(WaCrmMessageDateFilter filter, {DateTime? customDate})
  onChanged;
  final VoidCallback onClear;
  final String helpText;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: 30,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _FilterChipButton(
            label: 'Hoy',
            selected: selected == WaCrmMessageDateFilter.today,
            onTap: () => onChanged(WaCrmMessageDateFilter.today),
          ),
          _FilterChipButton(
            label: 'Ayer',
            selected: selected == WaCrmMessageDateFilter.yesterday,
            onTap: () => onChanged(WaCrmMessageDateFilter.yesterday),
          ),
          _FilterChipButton(
            label: '7 dias',
            selected: selected == WaCrmMessageDateFilter.last7Days,
            onTap: () => onChanged(WaCrmMessageDateFilter.last7Days),
          ),
          _FilterChipButton(
            label: 'Este mes',
            selected: selected == WaCrmMessageDateFilter.thisMonth,
            onTap: () => onChanged(WaCrmMessageDateFilter.thisMonth),
          ),
          _FilterChipButton(
            label: customDate == null
                ? 'Fecha'
                : DateFormat('dd/MM').format(customDate!),
            selected: selected == WaCrmMessageDateFilter.custom,
            icon: Icons.calendar_today_outlined,
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: customDate ?? DateTime.now(),
                firstDate: DateTime.now().subtract(const Duration(days: 730)),
                lastDate: DateTime.now(),
                helpText: helpText,
              );
              if (picked != null) {
                onChanged(WaCrmMessageDateFilter.custom, customDate: picked);
              }
            },
          ),
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: TextButton.icon(
              onPressed: selected == WaCrmMessageDateFilter.all
                  ? null
                  : onClear,
              icon: const Icon(Icons.filter_alt_off_outlined, size: 16),
              label: const Text('Limpiar'),
              style: TextButton.styleFrom(
                foregroundColor: theme.colorScheme.onSurfaceVariant,
                visualDensity: VisualDensity.compact,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterChipButton extends StatelessWidget {
  const _FilterChipButton({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        selected: selected,
        label: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 13),
              const SizedBox(width: 4),
            ],
            Text(label),
          ],
        ),
        onSelected: (_) => onTap(),
        labelStyle: theme.textTheme.labelSmall?.copyWith(
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          fontSize: 11,
          height: 1,
        ),
        visualDensity: const VisualDensity(horizontal: -3, vertical: -3),
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }
}

class _DateSeparator extends StatelessWidget {
  const _DateSeparator({required this.date});

  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withValues(
              alpha: 0.72,
            ),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
          child: Text(
            _dateSeparatorLabel(date),
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

class _NewMessagesButton extends StatelessWidget {
  const _NewMessagesButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: theme.colorScheme.primary,
            borderRadius: BorderRadius.circular(999),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.16),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.keyboard_arrow_down_rounded,
                color: theme.colorScheme.onPrimary,
                size: 18,
              ),
              const SizedBox(width: 4),
              Text(
                'Nuevos mensajes',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Chat Panel ───────────────────────────────────────────────────────────────

class _ChatPanel extends StatelessWidget {
  const _ChatPanel({
    required this.state,
    required this.msgController,
    required this.scrollController,
    required this.showNewMessagesButton,
    required this.onJumpToLatest,
    required this.onSend,
    required this.onAttach,
    required this.onDateFilterChanged,
    required this.onClearDateFilter,
    required this.onUnlock,
    this.agentName,
  });

  final WaCrmState state;
  final TextEditingController msgController;
  final ScrollController scrollController;
  final bool showNewMessagesButton;
  final VoidCallback onJumpToLatest;
  final VoidCallback onSend;
  final VoidCallback onAttach;
  final void Function(WaCrmMessageDateFilter filter, {DateTime? customDate})
  onDateFilterChanged;
  final VoidCallback onClearDateFilter;
  final VoidCallback onUnlock;
  final String? agentName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final conv = state.selectedConversation;
    final filteredMessages = _filterMessagesByDate(
      state.messages,
      state.messageDateFilter,
      state.customMessageDate,
    );

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
          padding: const EdgeInsets.fromLTRB(14, 7, 14, 6),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            border: Border(
              bottom: BorderSide(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.65),
              ),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Material(
                    color: Colors.transparent,
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () => _showChatAvatarPreview(context, conv),
                      child: UserAvatar(
                        imageUrl: conv.remoteAvatarUrl,
                        radius: 17,
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
                  const SizedBox(width: 9),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _waText(conv.displayName),
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            fontSize: 13.5,
                            height: 1.1,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          [
                            if (conv.displayPhone != null) conv.displayPhone!,
                            '${state.messages.length} mensajes',
                            if (conv.lastMessageAt != null)
                              'Ultimo ${DateFormat('dd/MM HH:mm').format(conv.lastMessageAt!.toLocal())}',
                          ].join(' · '),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.55,
                            ),
                            fontSize: 11,
                            height: 1.15,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 5),
              _DateFilterBar(
                selected: state.messageDateFilter,
                customDate: state.customMessageDate,
                onChanged: onDateFilterChanged,
                onClear: onClearDateFilter,
              ),
            ],
          ),
        ),
        // Messages
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(
                child: state.loadingMessages && state.messages.isEmpty
                    ? const Center(child: CircularProgressIndicator())
                    : filteredMessages.isEmpty
                    ? Center(
                        child: Text(
                          state.messages.isEmpty
                              ? 'Sin mensajes aún'
                              : 'Sin mensajes para este filtro',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.4,
                            ),
                          ),
                        ),
                      )
                    : ListView.builder(
                        key: PageStorageKey<String>(
                          'wa-chat-messages-${conv.id}',
                        ),
                        controller: scrollController,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        itemCount: filteredMessages.length,
                        itemBuilder: (context, i) {
                          final msg = filteredMessages[i];
                          final showSeparator =
                              i == 0 ||
                              !_sameDay(
                                filteredMessages[i - 1].sentAt,
                                msg.sentAt,
                              );
                          return KeyedSubtree(
                            key: ValueKey<String>('wa-msg-${msg.id}'),
                            child: _MessageBubble(
                              msg: msg,
                              agentName: agentName,
                              showDateSeparator: showSeparator,
                            ),
                          );
                        },
                      ),
              ),
              if (showNewMessagesButton && filteredMessages.isNotEmpty)
                Positioned(
                  right: 16,
                  bottom: 12,
                  child: _NewMessagesButton(onTap: onJumpToLatest),
                ),
            ],
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
              onAttach: onAttach,
            );
          },
        ),
      ],
    );
  }
}

// ─── Message Bubble ───────────────────────────────────────────────────────────

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.msg,
    required this.showDateSeparator,
    this.agentName,
  });

  final WaCrmMessage msg;
  final bool showDateSeparator;
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showDateSeparator) _DateSeparator(date: msg.sentAt),
        Padding(
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
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
        ),
      ],
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

class _MediaUnavailable extends StatelessWidget {
  const _MediaUnavailable({
    required this.icon,
    required this.textColor,
    this.onRetry,
  });

  final IconData icon;
  final Color textColor;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: textColor),
        const SizedBox(width: 6),
        Text(
          'Archivo no disponible',
          style: TextStyle(color: textColor, fontSize: 13),
        ),
        if (onRetry != null) ...[
          const SizedBox(width: 6),
          InkWell(
            onTap: onRetry,
            child: Text(
              'Reintentar cargar',
              style: TextStyle(
                color: textColor,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                decoration: TextDecoration.underline,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _ImageContent extends ConsumerStatefulWidget {
  const _ImageContent({required this.msg, required this.textColor});

  final WaCrmMessage msg;
  final Color textColor;

  @override
  ConsumerState<_ImageContent> createState() => _ImageContentState();
}

class _ImageContentState extends ConsumerState<_ImageContent> {
  Future<Uint8List>? _bytesFuture;
  String? _url;

  @override
  void initState() {
    super.initState();
    _setFutureIfNeeded();
  }

  @override
  void didUpdateWidget(covariant _ImageContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.msg.id != widget.msg.id ||
        oldWidget.msg.mediaUrl != widget.msg.mediaUrl) {
      _setFutureIfNeeded();
    }
  }

  void _setFutureIfNeeded() {
    _url = _mediaUrlForMessage(widget.msg);
    if (_url == null || widget.msg.mediaFailed) {
      _bytesFuture = null;
      return;
    }
    final downloadBytes = ref.read(waCrmRepositoryProvider).downloadMediaBytes;
    _bytesFuture = _bytesFromMediaUrl(_url!, downloadBytes: downloadBytes);
  }

  @override
  Widget build(BuildContext context) {
    final downloadBytes = ref.read(waCrmRepositoryProvider).downloadMediaBytes;
    if (widget.msg.mediaFailed) {
      return _MediaUnavailable(
        icon: Icons.image_not_supported_outlined,
        textColor: widget.textColor,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_url != null && _bytesFuture != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: GestureDetector(
              onTap: () => _showFullImage(context, _url!, downloadBytes),
              child: _buildImageWidget(_bytesFuture!),
            ),
          )
        else
          _MediaUnavailable(
            icon: Icons.image_not_supported_outlined,
            textColor: widget.textColor,
          ),
        if (widget.msg.caption?.isNotEmpty == true)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              _waText(widget.msg.caption),
              style: TextStyle(color: widget.textColor, fontSize: 13),
            ),
          ),
      ],
    );
  }

  Widget _buildImageWidget(Future<Uint8List> future) {
    return FutureBuilder<Uint8List>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return Container(
            width: 220,
            height: 120,
            color: Colors.grey.shade200,
            child: const Center(
              child: Icon(Icons.image_outlined, size: 26, color: Colors.grey),
            ),
          );
        }
        final bytes = snapshot.data;
        if (snapshot.hasError || bytes == null || bytes.isEmpty) {
          return _brokenImage();
        }
        return Image.memory(
          bytes,
          width: 220,
          height: 120,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) => _brokenImage(),
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

  void _showFullImage(
    BuildContext context,
    String url,
    Future<Uint8List> Function(String mediaUrl) downloadBytes,
  ) {
    final imageFuture = _bytesFromMediaUrl(url, downloadBytes: downloadBytes);
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.black,
        child: GestureDetector(
          onTap: () => Navigator.of(ctx).pop(),
          child: InteractiveViewer(
            child: FutureBuilder<Uint8List>(
              future: imageFuture,
              builder: (context, snapshot) {
                final bytes = snapshot.data;
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError || bytes == null || bytes.isEmpty) {
                  return const Icon(
                    Icons.broken_image_rounded,
                    size: 64,
                    color: Colors.white,
                  );
                }
                return Image.memory(bytes);
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _AudioContent extends ConsumerStatefulWidget {
  const _AudioContent({required this.msg, required this.textColor});
  final WaCrmMessage msg;
  final Color textColor;
  @override
  ConsumerState<_AudioContent> createState() => _AudioContentState();
}

class _AudioContentState extends ConsumerState<_AudioContent> {
  static const double _minPlayerWidth = 188;
  static const double _maxPlayerWidth = 260;

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
      final url = _mediaUrlForMessage(widget.msg);
      if (url == null) throw Exception('Sin URL de audio');

      final source = await _mediaSourceForPlayback(
        url,
        widget.msg.mediaMimeType,
        prefix: 'wa_audio',
        downloadBytes: ref.read(waCrmRepositoryProvider).downloadMediaBytes,
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

  double _audioWidthFor(BoxConstraints constraints) {
    final maxWidth =
        constraints.hasBoundedWidth && constraints.maxWidth.isFinite
        ? constraints.maxWidth
        : _maxPlayerWidth;
    if (maxWidth <= _minPlayerWidth) return maxWidth.toDouble();
    return maxWidth.clamp(_minPlayerWidth, _maxPlayerWidth).toDouble();
  }

  Future<void> _seekFromLocalDx(double dx, double width) async {
    final player = _player;
    if (player == null || _duration <= Duration.zero || width <= 0) return;
    final progress = (dx / width).clamp(0.0, 1.0);
    final ms = (progress * _duration.inMilliseconds).round();
    await player.seek(Duration(milliseconds: ms));
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.textColor;

    if (_mediaUrlForMessage(widget.msg) == null || widget.msg.mediaFailed) {
      return _MediaUnavailable(icon: Icons.mic_off_rounded, textColor: color);
    }

    if (_error != null) {
      return _MediaUnavailable(
        icon: Icons.error_outline,
        textColor: color,
        onRetry: () {
          setState(() => _error = null);
          _ensureInitialized();
        },
      );
    }

    if (!_initialized) {
      return LayoutBuilder(
        builder: (context, constraints) {
          final width = _audioWidthFor(constraints);
          return GestureDetector(
            onTap: _ensureInitialized,
            child: SizedBox(
              width: width,
              height: 44,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox.square(
                    dimension: 34,
                    child: _initializing
                        ? Padding(
                            padding: const EdgeInsets.all(7),
                            child: CircularProgressIndicator(
                              strokeWidth: 2.4,
                              color: color,
                            ),
                          )
                        : DecoratedBox(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: color.withValues(alpha: 0.15),
                            ),
                            child: Icon(
                              Icons.play_arrow_rounded,
                              color: color,
                              size: 21,
                            ),
                          ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Audio',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: color,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            height: 1.05,
                          ),
                        ),
                        const SizedBox(height: 5),
                        _StaticWaveform(color: color),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    }

    final progress = _duration.inMilliseconds > 0
        ? (_position.inMilliseconds / _duration.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = _audioWidthFor(constraints);
        return SizedBox(
          width: width,
          height: 46,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              GestureDetector(
                onTap: _togglePlayPause,
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: color.withValues(alpha: 0.15),
                  ),
                  child: Icon(
                    _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    color: color,
                    size: 21,
                  ),
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    LayoutBuilder(
                      builder: (context, barConstraints) {
                        final barWidth = barConstraints.maxWidth;
                        final thumbTravel = (barWidth - 10).clamp(
                          0.0,
                          barWidth,
                        );
                        return GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTapDown: (details) => _seekFromLocalDx(
                            details.localPosition.dx,
                            barWidth,
                          ),
                          onHorizontalDragUpdate: (details) => _seekFromLocalDx(
                            details.localPosition.dx,
                            barWidth,
                          ),
                          child: SizedBox(
                            height: 24,
                            child: Center(
                              child: Stack(
                                alignment: Alignment.centerLeft,
                                children: [
                                  Container(
                                    height: 3,
                                    decoration: BoxDecoration(
                                      color: color.withValues(alpha: 0.24),
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                  ),
                                  FractionallySizedBox(
                                    widthFactor: progress.toDouble(),
                                    child: Container(
                                      height: 3,
                                      decoration: BoxDecoration(
                                        color: color,
                                        borderRadius: BorderRadius.circular(
                                          999,
                                        ),
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    left: (thumbTravel * progress).clamp(
                                      0.0,
                                      thumbTravel,
                                    ),
                                    child: Container(
                                      width: 10,
                                      height: 10,
                                      decoration: BoxDecoration(
                                        color: color,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 1),
                    SizedBox(
                      height: 12,
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              _fmt(_position),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: color.withValues(alpha: 0.7),
                                fontSize: 9.5,
                                height: 1,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              _fmt(_duration),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.right,
                              style: TextStyle(
                                color: color.withValues(alpha: 0.7),
                                fontSize: 9.5,
                                height: 1,
                              ),
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
      },
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : _heights.length * 5.0;
        final visibleCount = (availableWidth / 5).floor().clamp(
          4,
          _heights.length,
        );
        final heights = _heights.take(visibleCount).toList(growable: false);

        return SizedBox(
          height: 16,
          child: Row(
            mainAxisSize: MainAxisSize.max,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              for (var index = 0; index < heights.length; index++) ...[
                Flexible(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      width: 3,
                      height: heights[index].clamp(3.0, 14.0),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
                if (index < heights.length - 1) const SizedBox(width: 2),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _VideoContent extends ConsumerStatefulWidget {
  const _VideoContent({required this.msg, required this.textColor});
  final WaCrmMessage msg;
  final Color textColor;
  @override
  ConsumerState<_VideoContent> createState() => _VideoContentState();
}

class _VideoContentState extends ConsumerState<_VideoContent> {
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
    final mediaUrl = _mediaUrlForMessage(widget.msg);
    if (mediaUrl == null) return;
    setState(() => _loading = true);
    try {
      final source = await _mediaSourceForPlayback(
        mediaUrl,
        widget.msg.mediaMimeType ?? 'video/mp4',
        prefix: 'wa_video',
        downloadBytes: ref.read(waCrmRepositoryProvider).downloadMediaBytes,
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
    if (_mediaUrlForMessage(widget.msg) == null || widget.msg.mediaFailed) {
      return _MediaUnavailable(
        icon: Icons.videocam_off_outlined,
        textColor: color,
      );
    }
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
                  ? Center(
                      child: IconButton(
                        tooltip: 'Reintentar cargar',
                        onPressed: () {
                          setState(() => _error = null);
                          _initializeAndPlay();
                        },
                        icon: const Icon(
                          Icons.refresh_rounded,
                          color: Colors.white70,
                          size: 34,
                        ),
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

class _DocumentContent extends ConsumerStatefulWidget {
  const _DocumentContent({required this.msg, required this.textColor});
  final WaCrmMessage msg;
  final Color textColor;
  @override
  ConsumerState<_DocumentContent> createState() => _DocumentContentState();
}

class _DocumentContentState extends ConsumerState<_DocumentContent> {
  bool _loading = false;

  Future<void> _open() async {
    final mediaUrl = _mediaUrlForMessage(widget.msg);
    if (mediaUrl == null) return;
    setState(() => _loading = true);
    await _openMedia(
      mediaUrl,
      widget.msg.mediaMimeType,
      downloadBytes: ref.read(waCrmRepositoryProvider).downloadMediaBytes,
    );
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.textColor;
    if (_mediaUrlForMessage(widget.msg) == null || widget.msg.mediaFailed) {
      return _MediaUnavailable(
        icon: Icons.insert_drive_file_outlined,
        textColor: color,
      );
    }
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
        if (_mediaUrlForMessage(widget.msg) != null) ...[
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
    required this.onAttach,
  });

  final TextEditingController controller;
  final bool sending;
  final bool unlocked;
  final VoidCallback onUnlock;
  final VoidCallback onSend;
  final VoidCallback onAttach;

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
          IconButton(
            tooltip: 'Adjuntar archivo',
            onPressed: unlocked && !sending ? onAttach : onUnlock,
            icon: Icon(
              unlocked ? Icons.attach_file_rounded : Icons.lock_open_rounded,
              size: 20,
            ),
          ),
          const SizedBox(width: 4),
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
    required this.onAnalyzeConversation,
    required this.onAnalyzeFilter,
    required this.onRefreshAnalysis,
    required this.onAskReport,
  });

  final WaCrmState state;
  final VoidCallback onPickDate;
  final VoidCallback onGenerate;
  final VoidCallback onAnalyzeConversation;
  final VoidCallback onAnalyzeFilter;
  final VoidCallback onRefreshAnalysis;
  final ValueChanged<String> onAskReport;

  static String _filterLabel(WaCrmState state) {
    switch (state.messageDateFilter) {
      case WaCrmMessageDateFilter.today:
        return 'Hoy';
      case WaCrmMessageDateFilter.yesterday:
        return 'Ayer';
      case WaCrmMessageDateFilter.last7Days:
        return 'Últimos 7 días';
      case WaCrmMessageDateFilter.thisMonth:
        return 'Este mes';
      case WaCrmMessageDateFilter.custom:
        final date = state.customMessageDate;
        return date == null
            ? 'Fecha personalizada'
            : DateFormat('dd/MM/yyyy').format(date);
      case WaCrmMessageDateFilter.all:
        return 'Sin filtro de fecha';
    }
  }

  static String _scopeLabel(WaCrmAiAnalysisScope scope) {
    return scope == WaCrmAiAnalysisScope.conversation
        ? 'Conversación actual'
        : 'Filtro actual';
  }

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
    final executiveReport = summary?.report;
    final compactFilledButtonStyle = FilledButton.styleFrom(
      minimumSize: const Size(0, 38),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800),
    );
    final compactOutlinedButtonStyle = OutlinedButton.styleFrom(
      minimumSize: const Size(0, 38),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800),
    );

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
                  'Analiza conversaciones, riesgos, seguimiento, reclamos, media resumida y oportunidades segun el filtro activo.',
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        style: compactOutlinedButtonStyle,
                        onPressed: onPickDate,
                        icon: const Icon(
                          Icons.calendar_month_outlined,
                          size: 18,
                        ),
                        label: Text(DateFormat('dd/MM/yyyy').format(date)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filledTonal(
                      tooltip: 'Refrescar análisis IA',
                      onPressed: state.loadingAiSummary || summary == null
                          ? null
                          : onRefreshAnalysis,
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                    ),
                    const SizedBox(width: 6),
                    IconButton.filledTonal(
                      tooltip: 'Copiar reporte',
                      onPressed: executiveReport == null
                          ? null
                          : () async {
                              await Clipboard.setData(
                                ClipboardData(
                                  text: executiveReport.toPlainText(),
                                ),
                              );
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Reporte copiado'),
                                  ),
                                );
                              }
                            },
                      icon: const Icon(Icons.copy_rounded, size: 18),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Filtro actual: ${_filterLabel(state)} · Alcance: ${_scopeLabel(state.aiAnalysisScope)}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 8),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        style: compactFilledButtonStyle,
                        onPressed:
                            state.loadingAiSummary || state.selectedUser == null
                            ? null
                            : onAnalyzeFilter,
                        icon: state.loadingAiSummary
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.auto_awesome, size: 18),
                        label: const Text('Analizar filtro'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        style: compactOutlinedButtonStyle,
                        onPressed:
                            state.loadingAiSummary ||
                                state.selectedConversation == null
                            ? null
                            : onAnalyzeConversation,
                        icon: const Icon(Icons.forum_outlined, size: 18),
                        label: const Text('Conversación'),
                      ),
                    ),
                  ],
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed:
                        state.loadingAiSummary || state.selectedUser == null
                        ? null
                        : onGenerate,
                    icon: const Icon(Icons.history_edu_outlined, size: 16),
                    label: const Text('Resumen diario anterior'),
                  ),
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
                  if (executiveReport != null) ...[
                    _AiStatPill(
                      label: 'Estado',
                      value: executiveReport.estadoGeneral,
                      isAlert: executiveReport.estadoGeneral != 'Normal',
                    ),
                    _AiStatPill(
                      label: 'Casos alerta',
                      value: '${executiveReport.casosConAlerta}',
                      isAlert: executiveReport.casosConAlerta > 0,
                    ),
                    _AiStatPill(
                      label: 'Fraudes',
                      value: '${executiveReport.posiblesFraudesDetectados}',
                      isAlert: executiveReport.posiblesFraudesDetectados > 0,
                    ),
                    _AiStatPill(
                      label: 'Sin respuesta',
                      value: '${executiveReport.clientesSinRespuesta}',
                      isAlert: executiveReport.clientesSinRespuesta > 0,
                    ),
                  ],
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
                                  ? scheme.errorContainer.withValues(
                                      alpha: 0.55,
                                    )
                                  : Colors.orange.shade50.withValues(
                                      alpha: 0.5,
                                    ),
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
                                      style: theme.textTheme.labelMedium
                                          ?.copyWith(
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
                                                      .textTheme
                                                      .labelSmall
                                                      ?.copyWith(
                                                        fontWeight:
                                                            FontWeight.w700,
                                                        color: scheme.onSurface,
                                                      ),
                                                ),
                                              Text(
                                                _waText(alert.description),
                                                style: theme.textTheme.bodySmall
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
                                            borderRadius: BorderRadius.circular(
                                              6,
                                            ),
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
                        if (executiveReport != null &&
                            executiveReport
                                .recomendacionesConcretas
                                .isNotEmpty) ...[
                          const SizedBox(height: 16),
                          Text(
                            'Recomendaciones concretas',
                            style: theme.textTheme.labelMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: scheme.onSurfaceVariant,
                              letterSpacing: 0.4,
                            ),
                          ),
                          const SizedBox(height: 6),
                          ...executiveReport.recomendacionesConcretas.map(
                            (item) => Padding(
                              padding: const EdgeInsets.only(bottom: 5),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(
                                    Icons.check_circle_outline_rounded,
                                    size: 15,
                                    color: scheme.primary,
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      _waText(item),
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(height: 1.35),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                        if (executiveReport != null &&
                            executiveReport
                                .responsabilidadDetectada
                                .isNotEmpty) ...[
                          const SizedBox(height: 16),
                          Text(
                            'Responsabilidad detectada',
                            style: theme.textTheme.labelMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: scheme.onSurfaceVariant,
                              letterSpacing: 0.4,
                            ),
                          ),
                          const SizedBox(height: 8),
                          ...executiveReport.responsabilidadDetectada.map(
                            (item) => Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: scheme.surfaceContainerHighest
                                    .withValues(alpha: 0.42),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: scheme.outlineVariant,
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _waText(
                                      item['estado'],
                                      'No hay evidencia suficiente',
                                    ),
                                    style: theme.textTheme.labelMedium
                                        ?.copyWith(
                                          fontWeight: FontWeight.w800,
                                          color: scheme.primary,
                                        ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Cliente: ${_waText(item['cliente'], 'No identificado')}',
                                    style: theme.textTheme.bodySmall,
                                  ),
                                  Text(
                                    'Atendido por: ${_waText(item['atendidoPor'], 'No identificado')}',
                                    style: theme.textTheme.bodySmall,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _waText(
                                      item['evidencia'],
                                      'No hay evidencia suficiente',
                                    ),
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      height: 1.35,
                                      color: scheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
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
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
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
                                                    .textTheme
                                                    .labelSmall
                                                    ?.copyWith(
                                                      fontSize: 10,
                                                      color: scheme
                                                          .onErrorContainer,
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
                        if (summary.analysisReportId?.isNotEmpty == true) ...[
                          const SizedBox(height: 18),
                          _AiReportQuestionBox(
                            history: state.aiQuestionHistory,
                            asking: state.askingAiQuestion,
                            onAsk: onAskReport,
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

class _AiReportQuestionBox extends StatefulWidget {
  const _AiReportQuestionBox({
    required this.history,
    required this.asking,
    required this.onAsk,
  });

  final List<WaCrmAiQuestionAnswer> history;
  final bool asking;
  final ValueChanged<String> onAsk;

  @override
  State<_AiReportQuestionBox> createState() => _AiReportQuestionBoxState();
}

class _AiReportQuestionBoxState extends State<_AiReportQuestionBox> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _controller.text.trim();
    if (text.isEmpty || widget.asking) return;
    widget.onAsk(text);
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Preguntar sobre este informe',
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  minLines: 1,
                  maxLines: 3,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _submit(),
                  decoration: const InputDecoration(
                    hintText: 'Preguntar sobre este informe',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                tooltip: 'Enviar pregunta',
                onPressed: widget.asking ? null : _submit,
                icon: widget.asking
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send_rounded, size: 18),
              ),
            ],
          ),
          if (widget.history.isNotEmpty) ...[
            const SizedBox(height: 12),
            ...widget.history.reversed
                .take(4)
                .map(
                  (item) => Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: scheme.surface.withValues(alpha: 0.78),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: scheme.outlineVariant),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _waText(item.question),
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: scheme.primary,
                          ),
                        ),
                        const SizedBox(height: 5),
                        SelectableText(
                          _waText(item.answer),
                          style: theme.textTheme.bodySmall?.copyWith(
                            height: 1.35,
                          ),
                        ),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            onPressed: () async {
                              await Clipboard.setData(
                                ClipboardData(text: item.answer),
                              );
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Respuesta copiada'),
                                  ),
                                );
                              }
                            },
                            icon: const Icon(Icons.copy_rounded, size: 15),
                            label: const Text('Copiar'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
          ],
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
    final last =
        conv?.lastMessage ??
        (state.messages.isNotEmpty ? state.messages.last : null);
    final totalMessages = conv == null
        ? 0
        : (conv.messageCount > 0 ? conv.messageCount : state.messages.length);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (conv != null) ...[
            _PanelSection(
              title: 'Información',
              icon: Icons.info_outline_rounded,
              children: [
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
                if (last != null)
                  _InfoRow(
                    icon: Icons.short_text_rounded,
                    label: 'Vista previa',
                    value:
                        '${last.isOutgoing ? 'Tu: ' : ''}${last.previewText}',
                    maxLines: 2,
                  ),
              ],
            ),
            const SizedBox(height: 10),
            _PanelSection(
              title: 'Estadísticas',
              icon: Icons.query_stats_rounded,
              children: [
                _InfoRow(
                  icon: Icons.mark_unread_chat_alt_outlined,
                  label: 'Sin leer',
                  value: '${conv.unreadCount}',
                ),
                _InfoRow(
                  icon: Icons.chat_bubble_outline_rounded,
                  label: 'Mensajes',
                  value: '$totalMessages',
                ),
                _InfoRow(
                  icon: Icons.perm_media_outlined,
                  label: 'Media cargada',
                  value:
                      '${state.messages.where((m) => m.messageType != WaMessageType.text).length}',
                ),
              ],
            ),
          ] else
            _PanelSection(
              title: 'Información',
              icon: Icons.info_outline_rounded,
              children: [
                Text(
                  'Selecciona una conversación para ver detalles.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.58),
                  ),
                ),
              ],
            ),
          const SizedBox(height: 10),
          if (state.selectedUser != null)
            _PanelSection(
              title: 'Instancia activa',
              icon: Icons.wifi_tethering_rounded,
              children: [
                _InfoRow(
                  icon: Icons.account_circle_outlined,
                  label: 'Usuario',
                  value: _waText(state.selectedUser!.name),
                ),
                _InfoRow(
                  icon: Icons.circle_rounded,
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
            ),
        ],
      ),
    );
  }
}

class _PanelSection extends StatelessWidget {
  const _PanelSection({
    required this.title,
    required this.icon,
    required this.children,
  });

  final String title;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.55),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 15, color: theme.colorScheme.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    fontSize: 12.5,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...children,
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
    this.maxLines = 1,
  });

  final IconData icon;
  final String label;
  final String value;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            size: 14,
            color: theme.colorScheme.primary.withValues(alpha: 0.8),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _waText(label),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                    fontSize: 10.5,
                    height: 1,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  _waText(value),
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 11.5,
                    height: 1.2,
                  ),
                  maxLines: maxLines,
                  overflow: TextOverflow.ellipsis,
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
  const _EmptyConvState({required this.loading, this.emptyLabel});

  final bool loading;
  final String? emptyLabel;

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
            loading ? 'Cargando...' : emptyLabel ?? 'Sin conversaciones',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
            ),
          ),
        ],
      ),
    );
  }
}
