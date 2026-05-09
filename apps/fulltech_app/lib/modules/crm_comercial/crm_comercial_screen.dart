import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:media_kit/media_kit.dart' as media_kit;
import 'package:media_kit_video/media_kit_video.dart' as media_kit_video;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/auth/auth_provider.dart';
import '../../core/auth/app_role.dart';
import '../../core/errors/api_exception.dart';
import '../../core/routing/routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/app_navigation.dart' show kDesktopShellBreakpoint;
import '../../core/widgets/responsive_shell.dart';
import '../../core/company/company_settings_model.dart';
import '../../core/company/company_settings_repository.dart';
import '../../core/cache/local_json_cache.dart';
import '../../features/catalogo/data/catalog_repository.dart';
import 'data/crm_comercial_repository.dart';
import 'models/crm_comercial_models.dart';

const Color _waBg = Color(0xFFF0F2F5);
const Color _waSidebar = Color(0xFFFFFFFF);
const Color _waPanel = Color(0xFFFFFFFF);
const Color _waChat = Color(0xFFEFEAE2);
const Color _waHover = Color(0xFFF5F6F6);
const Color _waSelected = Color(0xFFE9EDEF);
const Color _waBorder = Color(0xFFD9DEE3);
const Color _waGreen = Color(0xFF25D366);
const Color _waGreenDark = Color(0xFF1FA855);
const Color _waText = Color(0xFF111B21);
const Color _waTextMuted = Color(0xFF667781);

// ─── CRM Comercial media helpers ─────────────────────────────────────────────

/// In-memory cache for media bytes. Keyed by media URL.
final Map<String, Future<Uint8List>> _crmMediaBytesCache = {};

/// Resolves the URL to use to fetch media bytes via the authenticated proxy.
/// The `/whatsapp-inbox/media/:messageId` endpoint works for any WhatsappMessage
/// regardless of which CRM module is reading it.
String? _mediaUrlForCrmMsg(CrmComercialInboxMessage msg) {
  final raw = (msg.mediaUrl ?? '').trim();
  if (raw.isEmpty) return null;
  if (msg.mediaFailed) return null;
  // Prefer the storage proxy route when we have a storage key or status=ready
  if (!raw.startsWith('/whatsapp-inbox/media/') &&
      (msg.mediaStorageKey?.trim().isNotEmpty == true ||
          (msg.mediaStatus ?? '').toLowerCase() == 'ready')) {
    final base = '/whatsapp-inbox/media/${msg.id}';
    final versionSeed = [
      msg.mediaStorageKey?.trim() ?? '',
      msg.mediaMimeType?.trim() ?? '',
      msg.mediaFileSize?.toString() ?? '',
      msg.mediaStatus?.trim() ?? '',
    ].join('|');
    if (versionSeed.replaceAll('|', '').isNotEmpty) {
      return '$base?v=${versionSeed.hashCode.abs()}';
    }
    return base;
  }
  // If the URL is already a proper backend path, use it directly
  if (raw.startsWith('/whatsapp-inbox/media/') ||
      raw.startsWith('/crm-commercial/media/')) {
    return raw;
  }
  // Fallback: return as-is (external URL or data URI)
  return raw.isEmpty ? null : raw;
}

/// Returns bytes from a media URL, using the authenticated Dio-based downloader
/// and caching the result to avoid repeated network calls.
Future<Uint8List> _crmBytesFromMediaUrl(
  String mediaUrl, {
  required Future<Uint8List> Function(String) downloadBytes,
}) async {
  return _crmMediaBytesCache.putIfAbsent(mediaUrl, () => downloadBytes(mediaUrl));
}

String _crmMimeToExtension(String? mime) {
  switch ((mime ?? '').split(';').first.trim()) {
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

/// Opens a media file: downloads bytes, writes to temp, opens with system viewer.
Future<void> _crmOpenMedia(
  String mediaUrl,
  String? mimeType, {
  required Future<Uint8List> Function(String) downloadBytes,
}) async {
  try {
    final bytes = await _crmBytesFromMediaUrl(mediaUrl, downloadBytes: downloadBytes);
    if (bytes.isEmpty) return;
    final ext = _crmMimeToExtension(mimeType);
    final dir = await getTemporaryDirectory();
    final hash = mediaUrl.hashCode.abs();
    final file = File('${dir.path}${Platform.pathSeparator}crm_media_$hash$ext');
    await file.writeAsBytes(bytes, flush: true);
    await launchUrl(Uri.file(file.path), mode: LaunchMode.externalApplication);
  } catch (e) {
    debugPrint('[CrmComercial] _crmOpenMedia error: $e');
  }
}

/// Resolves a playable source (file URI for media_kit) from a media URL.
Future<String> _crmMediaSourceForPlayback(
  String mediaUrl,
  String? mimeType, {
  required Future<Uint8List> Function(String) downloadBytes,
}) async {
  final bytes = await _crmBytesFromMediaUrl(mediaUrl, downloadBytes: downloadBytes);
  if (bytes.isEmpty) throw Exception('Archivo vacío o no disponible');
  final ext = _crmMimeToExtension(mimeType);
  final dir = await getTemporaryDirectory();
  final hash = mediaUrl.hashCode.abs();
  final file = File('${dir.path}${Platform.pathSeparator}crm_play_$hash$ext');
  await file.writeAsBytes(bytes, flush: true);
  return file.uri.toString();
}

bool _isSafePublicNetworkUrl(String? raw) {
  final value = (raw ?? '').trim();
  if (value.isEmpty) return false;
  final uri = Uri.tryParse(value);
  if (uri == null) return false;
  if (!uri.hasScheme || (uri.scheme != 'http' && uri.scheme != 'https')) {
    return false;
  }
  final host = uri.host.trim().toLowerCase();
  if (host.isEmpty) return false;
  if (host == 'localhost' || host == '127.0.0.1' || host == '0.0.0.0' || host == '::1') {
    return false;
  }
  return true;
}

// CRM Comercial: 7 estados principales del flujo comercial
// Los estados operacionales (instalación/servicio) se manejan en módulo Operations
const List<String> _crmStatuses = <String>[
  'NUEVO',
  'COTIZACION',
  'NEGOCIACION',
  'RESERVADO',
  'PENDIENTE_PAGO',
  'GANADO',
  'PERDIDO',
];

const List<String> _taskPriorities = <String>[
  'BAJA',
  'NORMAL',
  'ALTA',
  'URGENTE',
];

enum _CrmRightPanelTab { detail, ia }

class CrmComercialScreen extends ConsumerStatefulWidget {
  const CrmComercialScreen({super.key});

  @override
  ConsumerState<CrmComercialScreen> createState() => _CrmComercialScreenState();
}

class _CrmComercialScreenState extends ConsumerState<CrmComercialScreen> {
  static const String _quickRepliesCacheKey = 'crm_comercial_quick_replies_v1';

  // Phase 1 controllers
  final TextEditingController _searchCtrl = TextEditingController();
  final TextEditingController _noteCtrl = TextEditingController();
  final TextEditingController _nextActionCtrl = TextEditingController();
  final TextEditingController _activityTypeCtrl = TextEditingController(
    text: 'NEGOCIACION',
  );
  final TextEditingController _activityDescriptionCtrl =
      TextEditingController();

  // Phase 2 controllers
  final TextEditingController _taskTitleCtrl = TextEditingController();
  final TextEditingController _taskDescCtrl = TextEditingController();
  final TextEditingController _chatComposerCtrl = TextEditingController();
  final TextEditingController _newChatPhoneCtrl = TextEditingController();
  final TextEditingController _newChatMessageCtrl = TextEditingController();
  final TextEditingController _conversationSearchCtrl = TextEditingController();
  final ScrollController _conversationListScrollCtrl = ScrollController();
  final ScrollController _chatScrollCtrl = ScrollController();
  final FocusNode _sidebarSearchFocusNode = FocusNode();
  late final StateController<DesktopShellRouteActions?> _desktopShellActions;

  bool _loading = true;
  bool _saving = false;
  bool _onlyMine = false;
  String _statusFilter = '';
  String _error = '';
  List<CrmComercialUserRef> _users = const <CrmComercialUserRef>[];
  List<CrmComercialWhatsappInstance> _availableWhatsappInstances =
      const <CrmComercialWhatsappInstance>[];
  CrmComercialSettings? _crmSettings;
  CrmComercialCustomer? _selected;
  List<CrmComercialInboxConversation> _conversations =
      const <CrmComercialInboxConversation>[];
  CrmComercialInboxConversation? _selectedConversation;
  List<CrmComercialInboxMessage> _messages =
      const <CrmComercialInboxMessage>[];
  String? _conversationWarning;

  // Phase 2 state
  List<CrmComercialFollowupTask> _allTasks = const <CrmComercialFollowupTask>[];
  bool _loadingTasks = false;
  bool _showDetailsPanel = false;
  bool _mobileConversationMode = false;
  bool _showSidebarSearch = false;
  bool _showConversationSearch = false;
  bool _sendingChatMessage = false;
  String _lastShellActionsSignature = '';
  _CrmRightPanelTab _activeRightPanelTab = _CrmRightPanelTab.detail;

  // Composer support state
  CompanySettings? _companySettings;
  Timer? _composerSpellTimer;
  String? _composerOrthographySuggestion;
  String? _lastIgnoredComposerSuggestion;
  String _lastOrthographyInputKey = '';
  String _lastOrthographyRequestedText = '';
  int _orthographyRequestSeq = 0;
  DateTime? _lastOrthographyRequestAt;

  // Commercial AI suggestion state (separate from orthography)
  Timer? _commercialAiTimer;
  CrmComercialAiReplySuggestion? _commercialAiSuggestion;
  bool _loadingCommercialSuggestion = false;
  String _lastIgnoredCommercialSuggestion = '';
  String _lastAutoSuggestedIncomingMessageId = '';

  // Media composer state
  final TextEditingController _mediaCaptionCtrl = TextEditingController();
  Uint8List? _selectedMediaBytes;
  String? _selectedMediaName;
  String? _selectedMediaType; // 'image', 'video', 'audio', 'document'
  String? _selectedMediaMimeType;
  bool _sendingMedia = false;
  final LocalJsonCache _quickRepliesCache = LocalJsonCache();
  List<_CrmQuickReplyTemplate> _quickReplies = const [];

  @override
  void initState() {
    super.initState();
    _desktopShellActions = ref.read(desktopShellRouteActionsProvider.notifier);
    _chatComposerCtrl.addListener(_onComposerTextChanged);
    _loadQuickReplies();
    _loadAll();
  }

  @override
  void dispose() {
    if (_desktopShellActions.state?.route == Routes.crmComercial) {
      _desktopShellActions.state = null;
    }
    _searchCtrl.dispose();
    _noteCtrl.dispose();
    _nextActionCtrl.dispose();
    _activityTypeCtrl.dispose();
    _activityDescriptionCtrl.dispose();
    _taskTitleCtrl.dispose();
    _taskDescCtrl.dispose();
    _chatComposerCtrl.removeListener(_onComposerTextChanged);
    _chatComposerCtrl.dispose();
    _newChatPhoneCtrl.dispose();
    _newChatMessageCtrl.dispose();
    _conversationSearchCtrl.dispose();
    _mediaCaptionCtrl.dispose();
    _composerSpellTimer?.cancel();
    _commercialAiTimer?.cancel();
    _conversationListScrollCtrl.dispose();
    _chatScrollCtrl.dispose();
    _sidebarSearchFocusNode.dispose();
    super.dispose();
  }

  void _publishDesktopShellActions({required bool enabled}) {
    final signature = enabled
        ? '${Routes.crmComercial}:${_crmInstanceWarning.toString()}'
        : '${Routes.crmComercial}:disabled';
    if (_lastShellActionsSignature == signature) return;
    _lastShellActionsSignature = signature;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!enabled) {
        if (_desktopShellActions.state?.route == Routes.crmComercial) {
          _desktopShellActions.state = null;
        }
        return;
      }

      _desktopShellActions.state = DesktopShellRouteActions(
        route: Routes.crmComercial,
        actions: [
          DesktopShellActionItem(
            icon: Icons.tune_rounded,
            selectedIcon: Icons.tune,
            selected: _crmInstanceWarning,
            tooltip: 'Configuracion de instancia',
            onPressed: _saving ? () {} : _openCrmSettingsDialog,
          ),
        ],
      );
    });
  }

  List<CrmComercialInboxMessage> get _filteredMessages {
    final query = _conversationSearchCtrl.text.trim().toLowerCase();
    if (query.isEmpty) return _messages;
    return _messages.where((message) {
      final text = message.displayText.toLowerCase();
      final sender = (message.senderName ?? '').toLowerCase();
      return text.contains(query) || sender.contains(query);
    }).toList(growable: false);
  }

  List<CrmComercialInboxConversation> get _filteredConversations {
    final query = _searchCtrl.text.trim().toLowerCase();
    return _conversations.where((conversation) {
      if (_statusFilter.isNotEmpty &&
          _conversationEffectiveStatus(conversation) != _statusFilter) {
        return false;
      }
      if (query.isEmpty) return true;
      final visibleName = _conversationVisibleName(conversation).toLowerCase();
      final phone = (conversation.remotePhone ?? '').toLowerCase();
      final customerName = (conversation.crmCustomerName ?? '').toLowerCase();
      final preview = _conversationPreviewText(conversation).toLowerCase();
      return visibleName.contains(query) ||
          phone.contains(query) ||
          customerName.contains(query) ||
          preview.contains(query);
    }).toList(growable: false);
  }

  String _conversationEffectiveStatus(CrmComercialInboxConversation conversation) {
    final linkedCustomerId = (conversation.crmCustomerId ?? '').trim();
    final rawStatus = (conversation.crmCustomerStatus ?? '').trim();
    if (linkedCustomerId.isEmpty || rawStatus.isEmpty) {
      return 'NUEVO';
    }
    return _mapLegacyStatus(rawStatus);
  }

  String _conversationVisibleName(CrmComercialInboxConversation conversation) {
    final customerName = (conversation.crmCustomerName ?? '').trim();
    if (customerName.isNotEmpty) return customerName;

    final contactName = conversation.contactName.trim();
    if (contactName.isNotEmpty &&
        contactName.toLowerCase() != 'nuevo contacto') {
      return contactName;
    }

    final phone = (conversation.remotePhone ?? '').trim();
    if (phone.isNotEmpty) return phone;

    return 'Contacto';
  }

  String _conversationPreviewText(CrmComercialInboxConversation conversation) {
    final messageType = (conversation.lastMessageType ?? 'TEXT').toUpperCase();
    switch (messageType) {
      case 'IMAGE':
        return '📷 Imagen';
      case 'VIDEO':
        return '🎥 Video';
      case 'AUDIO':
        return '🎙️ Audio';
      case 'DOCUMENT':
        return '📄 Documento';
    }

    final preview = (conversation.lastMessagePreview ?? '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (preview.isNotEmpty) return preview;

    final phone = (conversation.remotePhone ?? '').trim();
    if (phone.isNotEmpty) return phone;

    return 'Sin mensajes';
  }

  String _formatConversationListTime(DateTime? value) {
    if (value == null) return '--:--';

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(value.year, value.month, value.day);
    final diff = today.difference(day).inDays;

    if (diff == 0) return DateFormat('HH:mm').format(value);
    if (diff == 1) return 'Ayer';
    if (diff > 1 && diff < 7) {
      final raw = DateFormat('EEE', 'es').format(value).replaceAll('.', '');
      return raw.substring(0, 1).toUpperCase() + raw.substring(1);
    }
    return DateFormat('dd/MM').format(value);
  }

  void _scrollChatToBottom({bool animated = true}) {
    if (!_chatScrollCtrl.hasClients) return;
    final target = _chatScrollCtrl.position.maxScrollExtent;
    if (animated) {
      _chatScrollCtrl.animateTo(
        target,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
      return;
    }
    _chatScrollCtrl.jumpTo(target);
  }

  bool _isSafeNetworkImageUrl(String? raw) {
    return _isSafePublicNetworkUrl(raw);
  }

  List<CrmComercialFollowupTask> get _selectedTasks {
    final sel = _selected;
    if (sel == null) return const [];
    return _allTasks.where((t) => t.customerId == sel.id).toList();
  }

  int get _pendingTodayCount {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final todayEnd = todayStart.add(const Duration(days: 1));
    return _allTasks.where((t) {
      if (!t.isActive) return false;
      final d = t.dueDate;
      if (d == null) return false;
      return d.isAfter(todayStart.subtract(const Duration(milliseconds: 1))) &&
          d.isBefore(todayEnd);
    }).length;
  }

  int get _overdueCount => _allTasks.where((t) => t.isOverdue).length;

  int get _upcomingCount {
    final now = DateTime.now();
    final in7Days = now.add(const Duration(days: 7));
    return _allTasks.where((t) {
      if (!t.isActive) return false;
      final d = t.dueDate;
      if (d == null) return false;
      return d.isAfter(now) && d.isBefore(in7Days);
    }).length;
  }

  Future<void> _loadAll() async {
    setState(() {
      _loading = true;
      _error = '';
    });

    try {
      final repo = ref.read(crmComercialRepositoryProvider);
      final customers = await repo.listCustomers(
        q: _searchCtrl.text,
        status: _statusFilter,
        onlyMine: _onlyMine,
      );
      final users = await repo.listUsers();
      final allTasks = await repo.listFollowupTasks();
      final crmSettings = await repo.getSettings();
      final availableInstances = await repo.listAvailableWhatsappInstances();
      final conversationsResponse = await repo.listConversations();

      CrmComercialCustomer? selected = _selected;
      if (selected != null) {
        final found = customers.items.where((e) => e.id == selected!.id);
        selected = found.isEmpty ? null : found.first;
      }
      selected ??= customers.items.isEmpty ? null : customers.items.first;

      CrmComercialInboxConversation? selectedConversation = _selectedConversation;
      if (selectedConversation != null) {
        final found = conversationsResponse.items.where(
          (e) => e.id == selectedConversation!.id,
        );
        selectedConversation = found.isEmpty ? null : found.first;
      }
      selectedConversation ??=
          conversationsResponse.items.isEmpty ? null : conversationsResponse.items.first;

      List<CrmComercialInboxMessage> messages = const [];
      if (selectedConversation != null) {
        final messageResponse = await repo.getConversationMessages(
          selectedConversation.id,
        );
        messages = messageResponse.items;
        if (messageResponse.conversation != null) {
          selectedConversation = messageResponse.conversation;
        }
      }

      if (selected != null) {
        selected = await repo.getCustomer(selected.id);
        _nextActionCtrl.text = selected.nextAction ?? '';
      }

      if (selectedConversation != null && selectedConversation.crmCustomerId != null) {
        final linked = customers.items
            .where((e) => e.id == selectedConversation!.crmCustomerId)
            .toList(growable: false);
        if (linked.isNotEmpty) {
          selected = await repo.getCustomer(linked.first.id);
          _nextActionCtrl.text = selected.nextAction ?? '';
        }
      }

      if (!mounted) return;
      setState(() {
        _users = users;
        _crmSettings = crmSettings;
        _availableWhatsappInstances = availableInstances;
        _selected = selected;
        _allTasks = allTasks;
        _conversations = conversationsResponse.items;
        _selectedConversation = selectedConversation;
        _messages = messages;
        _conversationWarning = conversationsResponse.warning;
        _loading = false;
      });
      _scheduleSilentCommercialSuggestion();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _reloadTasks() async {
    if (!mounted) return;
    setState(() => _loadingTasks = true);
    try {
      final tasks = await ref
          .read(crmComercialRepositoryProvider)
          .listFollowupTasks();
      if (!mounted) return;
      setState(() => _allTasks = tasks);
    } finally {
      if (mounted) setState(() => _loadingTasks = false);
    }
  }

  Future<void> _openCrmSettingsDialog() async {
    final repo = ref.read(crmComercialRepositoryProvider);

    setState(() => _saving = true);
    try {
      final settings = await repo.getSettings();
      var instances = _availableWhatsappInstances;
      final refreshedInstances = await repo.listAvailableWhatsappInstances();
      if (refreshedInstances.isNotEmpty || instances.isEmpty) {
        instances = refreshedInstances;
      }
      if (!mounted) return;

      setState(() {
        _crmSettings = settings;
        _availableWhatsappInstances = instances;
      });

      String? selectedId = settings.selectedWhatsappInstanceId;
      bool enabled = settings.enabled;
      bool dialogSaving = false;
      String dialogError = '';

      await showDialog<void>(
        context: context,
        builder: (dialogContext) {
          return StatefulBuilder(
            builder: (context, setDialogState) {
              return AlertDialog(
                title: const Text('Configuracion CRM Comercial'),
                content: SizedBox(
                  width: 560,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Habilitar instancia para mensajes reales'),
                        subtitle: const Text(
                          'El CRM Comercial seguira funcionando sin mensajes reales si esta desactivado.',
                        ),
                        value: enabled,
                        onChanged: dialogSaving
                            ? null
                            : (value) {
                                setDialogState(() => enabled = value);
                              },
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'Instancia WhatsApp/Evolution disponible',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                      if (instances.isEmpty)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.amber.withAlpha(26),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            'No hay instancias disponibles en este momento.',
                          ),
                        )
                      else
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 300),
                          child: ListView.separated(
                            shrinkWrap: true,
                            itemCount: instances.length,
                            separatorBuilder: (_, __) =>
                                Divider(height: 1, color: _waBorder.withAlpha(100)),
                            itemBuilder: (context, index) {
                              final instance = instances[index];
                              final isSelected = selectedId == instance.id;
                              final subtitleParts = <String>[
                                if (instance.isCompany) 'Empresa',
                                if ((instance.userName ?? '').trim().isNotEmpty)
                                  instance.userName!.trim(),
                                'Estado: ${instance.status}',
                              ];
                              return ListTile(
                                dense: true,
                                enabled: !dialogSaving,
                                onTap: dialogSaving
                                    ? null
                                    : () {
                                        setDialogState(() {
                                          selectedId = instance.id;
                                          dialogError = '';
                                        });
                                      },
                                title: Text(instance.instanceName),
                                subtitle: Text(subtitleParts.join(' | ')),
                                trailing: Icon(
                                  isSelected
                                      ? Icons.radio_button_checked_rounded
                                      : Icons.radio_button_unchecked_rounded,
                                  color: isSelected ? _waGreenDark : _waTextMuted,
                                ),
                              );
                            },
                          ),
                        ),
                      if (dialogError.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Text(
                          dialogError,
                          style: const TextStyle(color: AppColors.error, fontSize: 12),
                        ),
                      ],
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: dialogSaving
                        ? null
                        : () => Navigator.of(dialogContext).pop(),
                    child: const Text('Cancelar'),
                  ),
                  FilledButton(
                    onPressed: dialogSaving
                        ? null
                        : () async {
                            if (enabled && (selectedId ?? '').trim().isEmpty) {
                              setDialogState(() {
                                dialogError =
                                    'Selecciona una instancia para habilitar mensajes reales.';
                              });
                              return;
                            }
                            setDialogState(() {
                              dialogSaving = true;
                              dialogError = '';
                            });
                            try {
                              CrmComercialWhatsappInstance? selected;
                              for (final instance in instances) {
                                if (instance.id == selectedId) {
                                  selected = instance;
                                  break;
                                }
                              }
                              final updated = await repo.updateSettings(
                                enabled: enabled,
                                selectedWhatsappInstanceId:
                                    (selectedId ?? '').trim().isEmpty
                                        ? null
                                        : selectedId,
                                selectedWhatsappInstanceName: selected?.instanceName,
                              );
                              if (!mounted) return;
                              setState(() => _crmSettings = updated);
                              if (!dialogContext.mounted) return;
                              Navigator.of(dialogContext).pop();
                            } catch (error) {
                              setDialogState(() {
                                dialogSaving = false;
                                dialogError = error.toString();
                              });
                            }
                          },
                    style: FilledButton.styleFrom(
                      backgroundColor: _waGreenDark,
                      foregroundColor: Colors.white,
                    ),
                    child: dialogSaving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Guardar'),
                  ),
                ],
              );
            },
          );
        },
      );

      if (!mounted) return;
      await _loadAll();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  bool get _crmInstanceWarning {
    final settings = _crmSettings;
    if (settings == null) return false;
    return (settings.selectedWhatsappInstanceId ?? '').trim().isEmpty ||
        settings.selectedInstanceExists == false;
  }

  Future<void> _openCustomer(String id) async {
    setState(() {
      _saving = true;
      _error = '';
    });
    try {
      final detail = await ref
          .read(crmComercialRepositoryProvider)
          .getCustomer(id);
      if (!mounted) return;
      setState(() {
        _selected = detail;
        _nextActionCtrl.text = detail.nextAction ?? '';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  Future<void> _openConversation(String conversationId) async {
    setState(() {
      _saving = true;
      _error = '';
    });
    try {
      final repo = ref.read(crmComercialRepositoryProvider);
      final response = await repo.getConversationMessages(conversationId);
      CrmComercialInboxConversation? conversation = response.conversation;
      if (conversation == null) {
        final found = _conversations.where((e) => e.id == conversationId).toList();
        if (found.isNotEmpty) {
          conversation = found.first;
        }
      }
      CrmComercialCustomer? linkedCustomer;
      if (conversation?.crmCustomerId != null) {
        linkedCustomer = await repo.getCustomer(conversation!.crmCustomerId!);
      }

      if (!mounted) return;
      setState(() {
        _selectedConversation = conversation;
        _messages = response.items;
        _conversationWarning = response.warning;
        _selected = linkedCustomer;
        _nextActionCtrl.text = linkedCustomer?.nextAction ?? '';
      });
      _scheduleSilentCommercialSuggestion();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _scrollChatToBottom(animated: false);
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  String? _normalizePhoneForSend(String raw) {
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 7) return null;
    return digits;
  }

  Future<void> _sendMessageToCurrentConversation() async {
    final selectedConversation = _selectedConversation;
    final rawText = _chatComposerCtrl.text;
    final text = rawText.trim();
    debugPrint(
      '[CRM][UI][_sendMessageToCurrentConversation] called hasConversation=${selectedConversation != null} textLen=${text.length} sending=$_sendingChatMessage',
    );
    if (selectedConversation == null || text.isEmpty || _sendingChatMessage) {
      return;
    }

    setState(() {
      _sendingChatMessage = true;
      _error = '';
      _chatComposerCtrl.clear();
      _composerOrthographySuggestion = null;
      _commercialAiSuggestion = null;
    });
    debugPrint(
      '[CRM][UI][_sendMessageToCurrentConversation] sending=true conversationId=${selectedConversation.id}',
    );

    try {
      await ref.read(crmComercialRepositoryProvider).replyConversation(
            conversationId: selectedConversation.id,
            text: text,
          );
      debugPrint(
        '[CRM][UI][_sendMessageToCurrentConversation] success conversationId=${selectedConversation.id}',
      );
      try {
        await _openConversation(selectedConversation.id);
        await _loadAll();
      } catch (refreshError) {
        debugPrint(
          '[CRM][UI][_sendMessageToCurrentConversation] post-send refresh error=$refreshError',
        );
      }
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _scrollChatToBottom();
        });
      }
    } catch (error) {
      debugPrint(
        '[CRM][UI][_sendMessageToCurrentConversation] error=${error is ApiException ? error.message : error.toString()}',
      );
      if (!mounted) return;
      setState(() {
        _error = error is ApiException ? error.message : error.toString();
        if (_chatComposerCtrl.text.trim().isEmpty) {
          _chatComposerCtrl.text = rawText;
          _chatComposerCtrl.selection = TextSelection.collapsed(
            offset: _chatComposerCtrl.text.length,
          );
        }
      });
    } finally {
      if (mounted) {
        setState(() => _sendingChatMessage = false);
      }
      debugPrint('[CRM][UI][_sendMessageToCurrentConversation] sending=false');
    }
  }

  Future<CompanySettings?> _resolveCompanySettings() async {
    if (_companySettings != null) return _companySettings;
    try {
      final settings = await ref.read(companySettingsRepositoryProvider).getSettings();
      if (mounted) {
        setState(() => _companySettings = settings);
      }
      return settings;
    } catch (_) {
      return _companySettings;
    }
  }

  void _onComposerTextChanged() {
    _composerSpellTimer?.cancel();
    final current = _chatComposerCtrl.text;
    if (_shouldSkipOrthographyAi(current)) {
      if (_composerOrthographySuggestion != null) {
        setState(() => _composerOrthographySuggestion = null);
      }
      return;
    }

    _composerSpellTimer = Timer(const Duration(milliseconds: 680), () async {
      await _requestOrthographySuggestion(current);
    });
  }

  bool _shouldSkipOrthographyAi(String raw) {
    final trimmed = raw.trim();
    if (trimmed.length < 6) return true;
    if (trimmed.length > 2500) return true;
    final words = trimmed
        .split(RegExp(r'\s+'))
        .where((w) => w.trim().isNotEmpty)
        .length;
    if (words <= 1) {
      final low = trimmed.toLowerCase();
      if (const {'ok', 'dale', 'si', 'sí', 'gracias', 'hola'}.contains(low)) {
        return true;
      }
    }
    return false;
  }

  String _orthographyInputKey(String raw) {
    return raw
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ')
        .toLowerCase();
  }

  Future<void> _requestOrthographySuggestion(String snapshotText) async {
    if (!mounted) return;
    if (_chatComposerCtrl.text != snapshotText) return;
    if (_shouldSkipOrthographyAi(snapshotText)) return;

    final key = _orthographyInputKey(snapshotText);
    if (key == _lastOrthographyInputKey &&
        _composerOrthographySuggestion != null) {
      return;
    }

    final now = DateTime.now();
    final recent = _lastOrthographyRequestAt != null &&
        now.difference(_lastOrthographyRequestAt!).inMilliseconds < 350;
    if (recent &&
        _lastOrthographyRequestedText.isNotEmpty &&
        (snapshotText.length - _lastOrthographyRequestedText.length).abs() <= 2) {
      return;
    }

    final previousRequested = _lastOrthographyRequestedText;
    _lastOrthographyRequestAt = now;
    _lastOrthographyRequestedText = snapshotText;
    final requestSeq = ++_orthographyRequestSeq;

    final suggestion = await ref
        .read(crmComercialRepositoryProvider)
        .suggestOrthography(
          text: snapshotText,
          previousText: previousRequested,
        );

    if (!mounted) return;
    if (requestSeq != _orthographyRequestSeq) return;
    if (_chatComposerCtrl.text != snapshotText) return;

    if (suggestion == null ||
        suggestion == snapshotText ||
        suggestion == _lastIgnoredComposerSuggestion) {
      _lastOrthographyInputKey = key;
      if (_composerOrthographySuggestion != null) {
        setState(() => _composerOrthographySuggestion = null);
      }
      return;
    }

    _lastOrthographyInputKey = key;
    setState(() => _composerOrthographySuggestion = suggestion);
  }

  void _applyOrthographySuggestion() {
    final suggestion = _composerOrthographySuggestion;
    if (suggestion == null || suggestion.isEmpty) return;
    setState(() {
      _chatComposerCtrl.text = suggestion;
      _chatComposerCtrl.selection = TextSelection.collapsed(
        offset: _chatComposerCtrl.text.length,
      );
      _composerOrthographySuggestion = null;
      _lastIgnoredComposerSuggestion = null;
    });
  }

  void _ignoreOrthographySuggestion() {
    setState(() {
      _lastIgnoredComposerSuggestion = _composerOrthographySuggestion;
      _composerOrthographySuggestion = null;
    });
  }

  void _insertTextInComposer(String text) {
    final clean = text.trim();
    if (clean.isEmpty) return;
    final current = _chatComposerCtrl.text.trimRight();
    final merged = current.isEmpty ? clean : '$current\n$clean';
    setState(() {
      _chatComposerCtrl.text = merged;
      _chatComposerCtrl.selection = TextSelection.collapsed(offset: merged.length);
      _composerOrthographySuggestion = null;
      _lastIgnoredComposerSuggestion = null;
    });
  }

  CrmComercialInboxMessage? _latestIncomingMessage() {
    for (var i = _messages.length - 1; i >= 0; i--) {
      final item = _messages[i];
      if (!item.isOutgoing) {
        final text = (item.body ?? item.caption ?? '').trim();
        if (text.isNotEmpty) return item;
      }
    }
    return null;
  }

  Future<String> _catalogSummaryForAi() async {
    try {
      final products = await ref.read(catalogRepositoryProvider).fetchProducts(silent: true);
      if (products.isEmpty) return '';
      return products
          .take(6)
          .map((item) => item.nombre.trim())
          .where((name) => name.isNotEmpty)
          .join(', ');
    } catch (_) {
      return '';
    }
  }

  Future<void> _requestCommercialReplySuggestion({
    required bool manual,
  }) async {
    final selectedConversation = _selectedConversation;
    if (selectedConversation == null) return;
    final incoming = _latestIncomingMessage();
    if (incoming == null) return;

    final incomingText = (incoming.body ?? incoming.caption ?? '').trim();
    if (incomingText.isEmpty) return;
    if (!manual && _lastAutoSuggestedIncomingMessageId == incoming.id) return;

    if (mounted) {
      setState(() => _loadingCommercialSuggestion = true);
    }
    try {
      final settings = await _resolveCompanySettings();
      final catalogSummary = await _catalogSummaryForAi();
      final bankAccounts = (settings?.bankAccounts ?? const <BankAccountEntry>[])
          .map((entry) {
            final parts = <String>[];
            if (entry.name.trim().isNotEmpty) parts.add(entry.name.trim());
            if (entry.bankName.trim().isNotEmpty) parts.add(entry.bankName.trim());
            if (entry.accountNumber.trim().isNotEmpty) parts.add(entry.accountNumber.trim());
            return parts.join(' | ');
          })
          .where((row) => row.trim().isNotEmpty)
          .toList(growable: false);

      final suggestion = await ref.read(crmComercialRepositoryProvider).suggestReply(
            conversationId: selectedConversation.id,
            lastCustomerMessage: incomingText,
            recentMessages: _messages,
            crmStatus: selectedConversation.crmCustomerStatus,
            customerInfo: {
              'name': selectedConversation.crmCustomerName ?? selectedConversation.contactName,
              'phone': selectedConversation.remotePhone,
            },
            availableBusinessData: {
              'location': (settings?.gpsLocationUrl ?? '').trim().isNotEmpty
                  ? settings!.gpsLocationUrl.trim()
                  : (settings?.address ?? '').trim(),
              'businessHours': (settings?.businessHours ?? '').trim(),
              'bankAccounts': bankAccounts,
              'catalogSummary': catalogSummary,
            },
          );

      if (!mounted) return;
      if (suggestion == null) return;
      if (suggestion.suggestedReply.trim().isEmpty) return;
      if (suggestion.suggestedReply.trim() == _lastIgnoredCommercialSuggestion) return;

      setState(() {
        _commercialAiSuggestion = suggestion;
        _lastAutoSuggestedIncomingMessageId = incoming.id;
      });
    } finally {
      if (mounted) {
        setState(() => _loadingCommercialSuggestion = false);
      }
    }
  }

  void _scheduleSilentCommercialSuggestion() {
    _commercialAiTimer?.cancel();
    _commercialAiTimer = Timer(const Duration(milliseconds: 900), () async {
      await _requestCommercialReplySuggestion(manual: false);
    });
  }

  void _insertCommercialSuggestionInComposer() {
    final suggestion = _commercialAiSuggestion;
    if (suggestion == null || suggestion.suggestedReply.trim().isEmpty) return;
    _insertTextInComposer(suggestion.suggestedReply.trim());
  }

  Future<void> _sendCommercialSuggestion() async {
    final suggestion = _commercialAiSuggestion;
    if (suggestion == null || suggestion.suggestedReply.trim().isEmpty) return;
    setState(() {
      _chatComposerCtrl.text = suggestion.suggestedReply.trim();
      _chatComposerCtrl.selection = TextSelection.collapsed(
        offset: _chatComposerCtrl.text.length,
      );
    });
    await _sendMessageToCurrentConversation();
  }

  void _ignoreCommercialSuggestion() {
    final suggestion = _commercialAiSuggestion;
    setState(() {
      _lastIgnoredCommercialSuggestion = suggestion?.suggestedReply.trim() ?? '';
      _commercialAiSuggestion = null;
    });
  }

  Future<void> _openInternalNoteDialog() async {
    final hasSelection = _selected != null;
    if (!hasSelection) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Selecciona un cliente para guardar nota interna.')),
        );
      }
      return;
    }

    final noteCtrl = TextEditingController();
    var saving = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Nota interna'),
              content: SizedBox(
                width: 420,
                child: TextField(
                  controller: noteCtrl,
                  minLines: 3,
                  maxLines: 6,
                  decoration: const InputDecoration(
                    hintText: 'Escribe una nota interna para el equipo',
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: saving ? null : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: saving
                      ? null
                      : () async {
                          final value = noteCtrl.text.trim();
                          if (value.isEmpty) {
                            return;
                          }
                          setDialogState(() {
                            saving = true;
                          });
                          _noteCtrl.text = value;
                          try {
                            await _addNote();
                            if (!dialogContext.mounted) return;
                            Navigator.of(dialogContext).pop();
                          } catch (_) {
                            setDialogState(() {
                              saving = false;
                            });
                          }
                        },
                  child: saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Guardar nota'),
                ),
              ],
            );
          },
        );
      },
    );

    noteCtrl.dispose();
  }

  Future<void> _openComposerActivityDialog() async {
    final hasSelection = _selected != null;
    if (!hasSelection) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Selecciona un cliente para crear actividad.')),
        );
      }
      return;
    }

    String selectedType = _crmStatuses.first;
    final descCtrl = TextEditingController();
    var saving = false;
    String? dialogError;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Crear actividad'),
              content: SizedBox(
                width: 440,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      value: selectedType,
                      items: _crmStatuses
                          .map(
                            (status) => DropdownMenuItem<String>(
                              value: status,
                              child: Text(_statusLabel(status)),
                            ),
                          )
                          .toList(growable: false),
                      onChanged: saving
                          ? null
                          : (value) {
                              if (value == null) return;
                              setDialogState(() => selectedType = value);
                            },
                      decoration: const InputDecoration(labelText: 'Tipo/Estado CRM'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: descCtrl,
                      minLines: 3,
                      maxLines: 6,
                      decoration: const InputDecoration(
                        hintText: 'Describe la actividad comercial',
                      ),
                    ),
                    if ((dialogError ?? '').isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          dialogError!,
                          style: const TextStyle(color: AppColors.error, fontSize: 12),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: saving ? null : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: saving
                      ? null
                      : () async {
                          final description = descCtrl.text.trim();
                          if (description.isEmpty) {
                            setDialogState(
                              () => dialogError = 'La actividad necesita descripción.',
                            );
                            return;
                          }
                          setDialogState(() {
                            saving = true;
                            dialogError = null;
                          });
                          _activityTypeCtrl.text = selectedType;
                          _activityDescriptionCtrl.text = description;
                          try {
                            await _addActivity();
                            if (!dialogContext.mounted) return;
                            Navigator.of(dialogContext).pop();
                          } catch (error) {
                            setDialogState(() {
                              saving = false;
                              dialogError = error.toString();
                            });
                          }
                        },
                  child: saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Guardar actividad'),
                ),
              ],
            );
          },
        );
      },
    );

    descCtrl.dispose();
  }

  Future<String> _buildStoreHoursMessage() async {
    final settings = await _resolveCompanySettings();
    final hours = (settings?.businessHours ?? '').trim();
    if (hours.isEmpty) return 'No hay horario configurado.';
    return hours;
  }

  Future<String> _buildGpsMessage() async {
    final settings = await _resolveCompanySettings();
    final gps = (settings?.gpsLocationUrl ?? '').trim();
    if (gps.isEmpty) return 'No hay ubicación configurada.';
    return gps;
  }

  Future<String> _buildBankAccountsMessage() async {
    final settings = await _resolveCompanySettings();
    final accounts = settings?.bankAccounts ?? const <BankAccountEntry>[];
    if (accounts.isEmpty) return 'No hay cuentas bancarias configuradas.';
    final rows = accounts
        .where((entry) =>
            entry.name.trim().isNotEmpty ||
            entry.accountNumber.trim().isNotEmpty ||
            entry.bankName.trim().isNotEmpty)
        .map((entry) {
          final parts = <String>[];
          if (entry.name.trim().isNotEmpty) parts.add(entry.name.trim());
          if (entry.bankName.trim().isNotEmpty) parts.add(entry.bankName.trim());
          if (entry.accountNumber.trim().isNotEmpty) {
            parts.add(entry.accountNumber.trim());
          }
          return '- ${parts.join(' | ')}';
        })
        .toList(growable: false);
    if (rows.isEmpty) return 'No hay cuentas bancarias configuradas.';
    return 'Cuentas bancarias disponibles:\n${rows.join('\n')}';
  }

  Future<String> _buildCatalogMessage() async {
    try {
      final products = await ref.read(catalogRepositoryProvider).fetchProducts(
            silent: true,
          );
      if (products.isEmpty) return 'No hay catálogo configurado.';
      final sample = products
          .take(4)
          .map((item) => '- ${item.nombre.trim()}')
          .toList(growable: false);
      return 'Catálogo disponible (${products.length} productos):\n${sample.join('\n')}';
    } catch (_) {
      return 'No hay catálogo configurado.';
    }
  }

  Future<void> _openQuickMessagesDialog() async {
    if (_quickReplies.isEmpty) {
      await _loadQuickReplies();
    }

    var query = '';
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final filtered = _quickReplies
                .where(
                  (item) =>
                      item.label.toLowerCase().contains(query.toLowerCase()) ||
                      item.text.toLowerCase().contains(query.toLowerCase()),
                )
                .toList(growable: false);

            Future<void> insertSpecial(Future<String> Function() builder) async {
              Navigator.of(dialogContext).pop();
              final text = await builder();
              if (!mounted) return;
              _insertTextInComposer(text);
            }

            return AlertDialog(
              title: const Text('Mensajes rápidos'),
              content: SizedBox(
                width: 520,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      onChanged: (value) => setDialogState(() => query = value),
                      decoration: const InputDecoration(
                        hintText: 'Buscar mensaje rápido',
                        prefixIcon: Icon(Icons.search_rounded),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        OutlinedButton.icon(
                          onPressed: () => insertSpecial(_buildGpsMessage),
                          icon: const Icon(Icons.location_on_outlined, size: 16),
                          label: const Text('Ubicación GPS'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () => insertSpecial(_buildStoreHoursMessage),
                          icon: const Icon(Icons.schedule_rounded, size: 16),
                          label: const Text('Horario'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () => insertSpecial(_buildBankAccountsMessage),
                          icon: const Icon(Icons.account_balance_rounded, size: 16),
                          label: const Text('Cuentas'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () => insertSpecial(_buildCatalogMessage),
                          icon: const Icon(Icons.inventory_2_outlined, size: 16),
                          label: const Text('Catálogo'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () async {
                            Navigator.of(dialogContext).pop();
                            await _openQuickRepliesManagerDialog();
                          },
                          icon: const Icon(Icons.edit_note_rounded, size: 16),
                          label: const Text('Configurar'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 260),
                      child: filtered.isEmpty
                          ? const Center(
                              child: Padding(
                                padding: EdgeInsets.all(16),
                                child: Text('No se encontraron mensajes.'),
                              ),
                            )
                          : ListView.separated(
                              shrinkWrap: true,
                              itemCount: filtered.length,
                              separatorBuilder: (_, __) =>
                                  Divider(height: 1, color: _waBorder.withAlpha(80)),
                              itemBuilder: (context, index) {
                                final item = filtered[index];
                                return ListTile(
                                  dense: true,
                                  leading: const Icon(Icons.flash_on_rounded, size: 18),
                                  title: Text(
                                    item.label,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 12.5),
                                  ),
                                  subtitle: Text(
                                    item.text,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 11, color: _waTextMuted),
                                  ),
                                  onTap: () {
                                    Navigator.of(dialogContext).pop();
                                    _insertTextInComposer(item.text);
                                  },
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cerrar'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _openAttachmentMenu() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        Widget tile({
          required IconData icon,
          required String label,
          required Future<void> Function() onTap,
        }) {
          return ListTile(
            dense: true,
            leading: Icon(icon, color: _waGreenDark),
            title: Text(label),
            onTap: () async {
              Navigator.of(context).pop();
              await onTap();
            },
          );
        }

        return SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                tile(
                  icon: Icons.photo_outlined,
                  label: 'Imagen',
                  onTap: () => _pickAndSendMedia(kind: 'image'),
                ),
                tile(
                  icon: Icons.videocam_outlined,
                  label: 'Video',
                  onTap: () => _pickAndSendMedia(kind: 'video'),
                ),
                tile(
                  icon: Icons.insert_drive_file_outlined,
                  label: 'Documento',
                  onTap: () => _pickAndSendMedia(kind: 'document'),
                ),
                tile(
                  icon: Icons.audiotrack_rounded,
                  label: 'Audio',
                  onTap: () => _pickAndSendMedia(kind: 'audio'),
                ),
                tile(
                  icon: Icons.sticky_note_2_outlined,
                  label: 'Nota interna',
                  onTap: _openInternalNoteDialog,
                ),
                tile(
                  icon: Icons.task_alt_rounded,
                  label: 'Crear actividad',
                  onTap: _openComposerActivityDialog,
                ),
                tile(
                  icon: Icons.location_on_outlined,
                  label: 'Ubicación GPS',
                  onTap: () async {
                    final text = await _buildGpsMessage();
                    _insertTextInComposer(text);
                  },
                ),
                tile(
                  icon: Icons.schedule_rounded,
                  label: 'Horario de tienda',
                  onTap: () async {
                    final text = await _buildStoreHoursMessage();
                    _insertTextInComposer(text);
                  },
                ),
                tile(
                  icon: Icons.account_balance_rounded,
                  label: 'Cuentas bancarias',
                  onTap: () async {
                    final text = await _buildBankAccountsMessage();
                    _insertTextInComposer(text);
                  },
                ),
                tile(
                  icon: Icons.inventory_2_outlined,
                  label: 'Catálogo de productos',
                  onTap: () async {
                    final text = await _buildCatalogMessage();
                    _insertTextInComposer(text);
                  },
                ),
                tile(
                  icon: Icons.flash_on_rounded,
                  label: 'Mensajes rápidos',
                  onTap: _openQuickMessagesDialog,
                ),
                tile(
                  icon: Icons.edit_note_rounded,
                  label: 'Configurar mensajes rápidos',
                  onTap: _openQuickRepliesManagerDialog,
                ),
                const SizedBox(height: 6),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _pickAndSendMedia({String? kind}) async {
    FileType pickerType = FileType.media;
    List<String>? allowedExtensions;
    if (kind == 'document') {
      pickerType = FileType.custom;
      allowedExtensions = ['pdf', 'doc', 'docx', 'xls', 'xlsx', 'txt'];
    } else if (kind == 'audio') {
      pickerType = FileType.custom;
      allowedExtensions = ['mp3', 'wav', 'm4a', 'aac', 'ogg'];
    } else if (kind == 'video') {
      pickerType = FileType.custom;
      allowedExtensions = ['mp4', 'mov', 'avi', 'mkv'];
    } else if (kind == 'image') {
      pickerType = FileType.custom;
      allowedExtensions = ['jpg', 'jpeg', 'png', 'gif', 'webp'];
    }

    final result = await FilePicker.platform.pickFiles(
      type: pickerType,
      allowedExtensions: allowedExtensions,
      allowMultiple: false,
      withData: true,
    );

    if (result == null || result.files.isEmpty) return;

    final file = result.files.first;
    final bytes = file.bytes;

    if (bytes == null) {
      if (mounted) {
        setState(() => _error = 'No se pudo leer el archivo seleccionado.');
      }
      return;
    }

    // Determine media type and MIME type
    final fileName = file.name.toLowerCase();
    final extension =
        (file.extension ?? fileName.split('.').lastOrNull ?? '').toLowerCase();
    String mediaType = 'document';
    String mimeType = 'application/octet-stream';

    if (extension == 'jpg' ||
        extension == 'jpeg' ||
        extension == 'png' ||
        extension == 'gif') {
      mediaType = 'image';
      mimeType = extension == 'jpg' ? 'image/jpeg' : 'image/$extension';
    } else if (extension == 'mp4' || extension == 'mov' || extension == 'avi') {
      mediaType = 'video';
      mimeType = extension == 'mov' ? 'video/quicktime' : 'video/$extension';
    } else if (extension == 'mp3' || extension == 'wav' || extension == 'm4a') {
      mediaType = 'audio';
      mimeType = extension == 'mp3'
          ? 'audio/mpeg'
          : extension == 'm4a'
              ? 'audio/mp4'
              : 'audio/$extension';
    } else if (extension == 'pdf') {
      mimeType = 'application/pdf';
    }

    if (mounted) {
      setState(() {
        _selectedMediaBytes = bytes;
        _selectedMediaName = file.name;
        _selectedMediaType = mediaType;
        _selectedMediaMimeType = mimeType;
      });
    }

    _showMediaPreviewDialog(mediaType, file.name, bytes);
  }

  void _showMediaPreviewDialog(String mediaType, String fileName, Uint8List bytes) {
    setState(() => _sendingMedia = false);
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Preview y enviar media'),
              content: SizedBox(
                width: 500,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Media preview
                    if (mediaType == 'image')
                      Container(
                        height: 200,
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey[300]!),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Image.memory(bytes, fit: BoxFit.cover),
                      )
                    else if (mediaType == 'video')
                      Container(
                        height: 150,
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey[300]!),
                          borderRadius: BorderRadius.circular(8),
                          color: Colors.grey[100],
                        ),
                        child: const Center(
                          child: Icon(Icons.video_library_rounded, size: 48),
                        ),
                      )
                    else if (mediaType == 'audio')
                      Container(
                        height: 80,
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey[300]!),
                          borderRadius: BorderRadius.circular(8),
                          color: Colors.grey[100],
                        ),
                        child: const Center(
                          child: Icon(Icons.music_note_rounded, size: 48),
                        ),
                      )
                    else
                      Container(
                        height: 100,
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey[300]!),
                          borderRadius: BorderRadius.circular(8),
                          color: Colors.grey[100],
                        ),
                        child: const Center(
                          child: Icon(Icons.description_rounded, size: 48),
                        ),
                      ),
                    const SizedBox(height: 12),

                    // File name
                    Text(
                      'Archivo: $fileName',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 12),

                    // Caption input
                    TextField(
                      controller: _mediaCaptionCtrl,
                      maxLines: 3,
                      minLines: 1,
                      decoration: InputDecoration(
                        hintText: 'Agregar caption (opcional)',
                        isDense: true,
                        filled: true,
                        fillColor: Colors.grey[50],
                        border: OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.grey[300]!),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: _sendingMedia
                      ? null
                      : () {
                          Navigator.of(context).pop();
                          setState(() {
                            _selectedMediaBytes = null;
                            _selectedMediaName = null;
                            _selectedMediaType = null;
                            _selectedMediaMimeType = null;
                            _sendingMedia = false;
                          });
                          _mediaCaptionCtrl.clear();
                        },
                  child: const Text('Cancelar'),
                ),
                FilledButton.icon(
                  onPressed: _sendingMedia
                      ? null
                      : () => _confirmSendMedia(dialogContext, setDialogState),
                  icon: Icon(
                    _sendingMedia ? Icons.hourglass_bottom_rounded : Icons.send_rounded,
                  ),
                  label: Text(_sendingMedia ? 'Enviando...' : 'Enviar'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _confirmSendMedia(BuildContext dialogContext, StateSetter setDialogState) async {
    final selectedConversation = _selectedConversation;
    final mediaBytes = _selectedMediaBytes;
    final mediaName = _selectedMediaName;
    final mediaType = _selectedMediaType;
    final mimeType = _selectedMediaMimeType;
    final caption = _mediaCaptionCtrl.text.trim();

    if (selectedConversation == null || mediaBytes == null || mediaType == null || mimeType == null) {
      return;
    }

    if (mounted) {
      setState(() => _sendingMedia = true);
    }
    setDialogState(() {});

    try {
      final base64Data = base64Encode(mediaBytes);

      await ref.read(crmComercialRepositoryProvider).replyConversationMedia(
            conversationId: selectedConversation.id,
            mediaType: mediaType,
            mimeType: mimeType,
            fileName: mediaName ?? 'media',
            base64Data: base64Data,
            caption: caption.isEmpty ? null : caption,
          );

      if (mounted) {
        Navigator.of(dialogContext).pop();
        setState(() {
          _selectedMediaBytes = null;
          _selectedMediaName = null;
          _selectedMediaType = null;
          _selectedMediaMimeType = null;
          _sendingMedia = false;
        });
        _mediaCaptionCtrl.clear();

        _openConversation(selectedConversation.id);
        _loadAll();

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _scrollChatToBottom();
        });
      }
    } catch (error) {
      if (!mounted) return;
      final normalized = error.toString().toLowerCase();
      final mediaUnavailable = normalized.contains('404') ||
          normalized.contains('501') ||
          normalized.contains('not implemented') ||
          normalized.contains('unsupported');
      setDialogState(() {});
      setState(() {
        _sendingMedia = false;
        _error = mediaUnavailable
            ? 'Envío de archivos aún no disponible'
            : error.toString();
      });
    }
  }

  Future<void> _openNewChatDialog() async {
    _newChatPhoneCtrl.clear();
    _newChatMessageCtrl.clear();
    String? dialogError;
    var sending = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Nuevo chat por numero'),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: _newChatPhoneCtrl,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'Numero de telefono',
                        hintText: 'Ej. 8095551234',
                        prefixIcon: Icon(Icons.phone_rounded),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _newChatMessageCtrl,
                      minLines: 2,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        labelText: 'Mensaje',
                        hintText: 'Escribe el primer mensaje...',
                        prefixIcon: Icon(Icons.message_rounded),
                      ),
                    ),
                    if ((dialogError ?? '').isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          dialogError!,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.error,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: sending
                      ? null
                      : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancelar'),
                ),
                FilledButton.icon(
                  onPressed: sending
                      ? null
                      : () async {
                          final settings = _crmSettings;
                          if (settings == null ||
                              (settings.selectedWhatsappInstanceId ?? '')
                                  .trim()
                                  .isEmpty) {
                            setDialogState(() {
                              dialogError =
                                  'Selecciona una instancia antes de enviar mensajes.';
                            });
                            return;
                          }

                          final normalized = _normalizePhoneForSend(
                            _newChatPhoneCtrl.text.trim(),
                          );
                          if (normalized == null) {
                            setDialogState(() {
                              dialogError = 'Numero de telefono invalido.';
                            });
                            return;
                          }

                          final message = _newChatMessageCtrl.text.trim();
                          if (message.isEmpty) {
                            setDialogState(() {
                              dialogError =
                                  'Escribe un mensaje para iniciar la conversacion.';
                            });
                            return;
                          }

                          setDialogState(() {
                            sending = true;
                            dialogError = null;
                          });

                          try {
                            final result = await ref
                                .read(crmComercialRepositoryProvider)
                                .startConversationMessage(
                                  phone: normalized,
                                  text: message,
                                );

                            final createdConversationId =
                                (result['conversationId'] ?? '').toString();

                            if (!mounted) return;
                            await _loadAll();

                            if (createdConversationId.isNotEmpty) {
                              await _openConversation(createdConversationId);
                            } else {
                              final matched = _conversations
                                  .where(
                                    (c) =>
                                        (c.remotePhone ?? '')
                                            .replaceAll(RegExp(r'\D'), '') ==
                                        normalized,
                                  )
                                  .toList(growable: false);
                              if (matched.isNotEmpty) {
                                await _openConversation(matched.first.id);
                              }
                            }

                            if (!dialogContext.mounted) return;
                            Navigator.of(dialogContext).pop();
                          } catch (error) {
                            setDialogState(() {
                              sending = false;
                              dialogError = error.toString();
                            });
                          }
                        },
                  icon: sending
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send_rounded, size: 16),
                  label: const Text('Iniciar chat'),
                  style: FilledButton.styleFrom(
                    backgroundColor: _waGreenDark,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _openRightPanelSheet(
    _CrmRightPanelTab tab,
    CrmComercialCustomer? selected,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return SafeArea(
          child: FractionallySizedBox(
            heightFactor: 0.9,
            child: Container(
              decoration: const BoxDecoration(
                color: _waPanel,
                borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
              ),
              child: _buildDetailsPanel(
                context,
                selected,
                compact: false,
                tabOverride: tab,
                onClose: () => Navigator.of(context).pop(),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _openRightPanelDrawer(
    _CrmRightPanelTab tab,
    CrmComercialCustomer? selected,
  ) async {
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Cerrar panel',
      barrierColor: Colors.black.withAlpha(80),
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (_, __, ___) {
        return SafeArea(
          child: Align(
            alignment: Alignment.centerRight,
            child: Material(
              color: Colors.transparent,
              child: Container(
                width: 360,
                margin: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _waPanel,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _waBorder.withAlpha(120)),
                ),
                child: _buildDetailsPanel(
                  context,
                  selected,
                  compact: false,
                  tabOverride: tab,
                  onClose: () => Navigator.of(context).pop(),
                ),
              ),
            ),
          ),
        );
      },
      transitionBuilder: (context, animation, _, child) {
        final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0.08, 0),
            end: Offset.zero,
          ).animate(curved),
          child: FadeTransition(opacity: curved, child: child),
        );
      },
    );
  }

  void _showConvertPlaceholder() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Proximamente: convertir contacto WhatsApp a cliente CRM comercial.',
        ),
      ),
    );
  }

  Future<void> _openAvatarPreview(
    String title, {
    String? imageUrl,
  }) async {
    final hasImage = _isSafeNetworkImageUrl(imageUrl);
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withAlpha(200),
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 260,
                height: 260,
                decoration: BoxDecoration(
                  color: const Color(0xFF0F171A),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: Colors.white.withAlpha(160), width: 2),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: hasImage
                        ? Image.network(
                          imageUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) {
                            return Center(
                              child: Text(
                                _initials(title),
                                style: const TextStyle(
                                  fontSize: 72,
                                  fontWeight: FontWeight.w700,
                                  color: _waGreen,
                                ),
                              ),
                            );
                          },
                        )
                      : Center(
                          child: Text(
                            _initials(title),
                            style: const TextStyle(
                              fontSize: 72,
                              fontWeight: FontWeight.w700,
                              color: _waGreen,
                            ),
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
              if (hasImage) ...[
                const SizedBox(height: 4),
                Text(
                  'Foto de perfil',
                  style: TextStyle(
                    color: Colors.white.withAlpha(190),
                    fontSize: 12,
                  ),
                ),
              ] else ...[
                const SizedBox(height: 4),
                Text(
                  'Sin foto disponible',
                  style: TextStyle(
                    color: Colors.white.withAlpha(190),
                    fontSize: 12,
                  ),
                ),
              ],
              const SizedBox(height: 4),
              TextButton.icon(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(
                  Icons.close_rounded,
                  size: 16,
                  color: Colors.white,
                ),
                label: const Text(
                  'Cerrar',
                  style: TextStyle(color: Colors.white),
                ),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildConversationAvatar({
    required String title,
    required Color accent,
    required double radius,
    String? imageUrl,
  }) {
    final hasImage = _isSafeNetworkImageUrl(imageUrl);
    return CircleAvatar(
      radius: radius,
      backgroundColor: accent.withAlpha(24),
      backgroundImage: hasImage ? NetworkImage(imageUrl!) : null,
      child: hasImage
          ? null
          : Text(
              _initials(title),
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: accent,
                fontSize: radius < 18 ? 10 : 12,
              ),
            ),
    );
  }

  Future<void> _saveNextAction() async {
    final selected = _selected;
    if (selected == null) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(crmComercialRepositoryProvider)
          .updateCustomer(selected.id, nextAction: _nextActionCtrl.text.trim());
      await _openCustomer(selected.id);
      await _loadAll();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _changeStatus(String status) async {
    final selected = _selected;
    if (selected == null || status == selected.estadoActual) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(crmComercialRepositoryProvider)
          .changeStatus(selected.id, status);
      await _openCustomer(selected.id);
      await _loadAll();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _addNote() async {
    final selected = _selected;
    final note = _noteCtrl.text.trim();
    if (selected == null || note.isEmpty) return;

    setState(() => _saving = true);
    try {
      await ref.read(crmComercialRepositoryProvider).addNote(selected.id, note);
      _noteCtrl.clear();
      await _openCustomer(selected.id);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _assignResponsible(String? userId) async {
    final selected = _selected;
    if (selected == null || userId == null || userId.isEmpty) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(crmComercialRepositoryProvider)
          .updateCustomer(selected.id, responsableUserId: userId);
      await _openCustomer(selected.id);
      await _loadAll();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _addActivity() async {
    final selected = _selected;
    final type = _activityTypeCtrl.text.trim();
    final description = _activityDescriptionCtrl.text.trim();
    if (selected == null || type.isEmpty || description.isEmpty) return;

    setState(() => _saving = true);
    try {
      await ref
          .read(crmComercialRepositoryProvider)
          .addActivity(selected.id, type: type, description: description);
      _activityDescriptionCtrl.clear();
      await _openCustomer(selected.id);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // Phase 2 actions

  Future<void> _completeTask(String taskId) async {
    setState(() => _saving = true);
    try {
      await ref
          .read(crmComercialRepositoryProvider)
          .completeFollowupTask(taskId);
      await _reloadTasks();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _cancelTask(String taskId) async {
    setState(() => _saving = true);
    try {
      await ref.read(crmComercialRepositoryProvider).cancelFollowupTask(taskId);
      await _reloadTasks();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _openCreateTaskDialog(BuildContext context) async {
    final selected = _selected;
    if (selected == null) return;

    _taskTitleCtrl.clear();
    _taskDescCtrl.clear();
    DateTime? dueDate;
    String priority = 'NORMAL';
    String? assignedUserId;
    String? dialogError;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            title: const Text('Nueva tarea de seguimiento'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: _taskTitleCtrl,
                    decoration: const InputDecoration(labelText: 'Titulo *'),
                    maxLength: 200,
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _taskDescCtrl,
                    decoration: const InputDecoration(labelText: 'Descripcion'),
                    minLines: 2,
                    maxLines: 3,
                    maxLength: 2000,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          dueDate == null
                              ? 'Sin fecha'
                              : DateFormat('dd/MM/yyyy').format(dueDate!),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: ctx,
                            initialDate: DateTime.now().add(
                              const Duration(days: 1),
                            ),
                            firstDate: DateTime.now(),
                            lastDate: DateTime.now().add(
                              const Duration(days: 365),
                            ),
                          );
                          if (picked != null) {
                            setDialogState(() => dueDate = picked);
                          }
                        },
                        icon: const Icon(Icons.calendar_today, size: 16),
                        label: const Text('Fecha'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    key: ValueKey('priority-$priority'),
                    initialValue: priority,
                    decoration: const InputDecoration(labelText: 'Prioridad'),
                    items: _taskPriorities
                        .map(
                          (p) => DropdownMenuItem<String>(
                            value: p,
                            child: Text(p),
                          ),
                        )
                        .toList(growable: false),
                    onChanged: (v) {
                      if (v != null) setDialogState(() => priority = v);
                    },
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    key: ValueKey('assigned-${assignedUserId ?? ''}'),
                    initialValue: assignedUserId,
                    decoration: const InputDecoration(labelText: 'Responsable'),
                    items: [
                      const DropdownMenuItem<String>(
                        value: null,
                        child: Text('Sin asignar'),
                      ),
                      ..._users.map(
                        (u) => DropdownMenuItem<String>(
                          value: u.id,
                          child: Text(u.nombreCompleto),
                        ),
                      ),
                    ],
                    onChanged: (v) => setDialogState(() => assignedUserId = v),
                  ),
                  if (dialogError != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        dialogError!,
                        style: TextStyle(
                          color: Theme.of(ctx).colorScheme.error,
                          fontSize: 12,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () async {
                  final title = _taskTitleCtrl.text.trim();
                  if (title.length < 2) {
                    setDialogState(
                      () => dialogError =
                          'El titulo debe tener al menos 2 caracteres',
                    );
                    return;
                  }
                  setDialogState(() => dialogError = null);
                  Navigator.of(ctx).pop();
                  setState(() => _saving = true);
                  try {
                    await ref
                        .read(crmComercialRepositoryProvider)
                        .createFollowupTask(
                          selected.id,
                          title: title,
                          description: _taskDescCtrl.text.trim().isEmpty
                              ? null
                              : _taskDescCtrl.text.trim(),
                          dueDate: dueDate,
                          priority: priority,
                          assignedUserId: assignedUserId,
                        );
                    await _reloadTasks();
                  } catch (error) {
                    if (mounted) setState(() => _error = error.toString());
                  } finally {
                    if (mounted) setState(() => _saving = false);
                  }
                },
                child: const Text('Crear tarea'),
              ),
            ],
          );
        },
      ),
    );
  }

  List<_CrmQuickReplyTemplate> _defaultQuickReplies() {
    return const [
      _CrmQuickReplyTemplate(
        id: 'greeting',
        label: 'Saludo inicial',
        text: 'Gracias por escribirnos. Te atendemos de inmediato.',
      ),
      _CrmQuickReplyTemplate(
        id: 'availability',
        label: 'Confirmar disponibilidad',
        text: 'Perfecto, te confirmo disponibilidad en unos minutos.',
      ),
      _CrmQuickReplyTemplate(
        id: 'photo_request',
        label: 'Solicitar foto',
        text: '¿Podrías compartirnos una foto del área para cotizar mejor?',
      ),
      _CrmQuickReplyTemplate(
        id: 'quote_offer',
        label: 'Enviar cotización',
        text: 'Con gusto te enviamos una cotización formal hoy.',
      ),
      _CrmQuickReplyTemplate(
        id: 'schedule_question',
        label: 'Preferencia de instalación',
        text: '¿Prefieres instalación esta semana o la próxima?',
      ),
    ];
  }

  Future<void> _loadQuickReplies() async {
    final cached = await _quickRepliesCache.readMap(
      _quickRepliesCacheKey,
      maxAge: const Duration(days: 3650),
    );
    final rawList = (cached?['items'] as List?) ?? const [];
    final parsed = rawList
        .whereType<Map>()
        .map((raw) => _CrmQuickReplyTemplate.fromMap(raw.cast<String, dynamic>()))
        .where((item) => item.label.trim().isNotEmpty && item.text.trim().isNotEmpty)
        .toList(growable: false);
    final value = parsed.isEmpty ? _defaultQuickReplies() : parsed;
    if (!mounted) return;
    setState(() => _quickReplies = value);
    if (parsed.isEmpty) {
      await _saveQuickReplies(value);
    }
  }

  Future<void> _saveQuickReplies(List<_CrmQuickReplyTemplate> items) async {
    await _quickRepliesCache.writeMap(_quickRepliesCacheKey, {
      'items': items.map((item) => item.toMap()).toList(growable: false),
      'updatedAt': DateTime.now().toIso8601String(),
    });
  }

  String _createQuickReplyId() {
    final now = DateTime.now().microsecondsSinceEpoch;
    return 'qr_$now';
  }

  Future<_CrmQuickReplyTemplate?> _openQuickReplyEditorDialog({
    _CrmQuickReplyTemplate? initial,
  }) async {
    final labelCtrl = TextEditingController(text: initial?.label ?? '');
    final textCtrl = TextEditingController(text: initial?.text ?? '');
    String error = '';

    final result = await showDialog<_CrmQuickReplyTemplate>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(initial == null ? 'Agregar mensaje rápido' : 'Editar mensaje rápido'),
              content: SizedBox(
                width: 480,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: labelCtrl,
                      maxLength: 40,
                      decoration: const InputDecoration(
                        labelText: 'Título',
                        hintText: 'Ej. Ubicación GPS',
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: textCtrl,
                      minLines: 3,
                      maxLines: 6,
                      decoration: const InputDecoration(
                        labelText: 'Contenido',
                        hintText: 'Texto que se enviará al cliente.',
                      ),
                    ),
                    if (error.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          error,
                          style: const TextStyle(fontSize: 12, color: AppColors.error),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: () {
                    final label = labelCtrl.text.trim();
                    final text = textCtrl.text.trim();
                    if (label.isEmpty || text.isEmpty) {
                      setDialogState(() {
                        error = 'Completa título y contenido.';
                      });
                      return;
                    }
                    Navigator.of(dialogContext).pop(
                      _CrmQuickReplyTemplate(
                        id: initial?.id ?? _createQuickReplyId(),
                        label: label,
                        text: text,
                      ),
                    );
                  },
                  child: const Text('Guardar'),
                ),
              ],
            );
          },
        );
      },
    );

    labelCtrl.dispose();
    textCtrl.dispose();
    return result;
  }

  Future<void> _openQuickRepliesManagerDialog() async {
    if (_quickReplies.isEmpty) {
      await _loadQuickReplies();
    }
    final working = List<_CrmQuickReplyTemplate>.from(_quickReplies);

    Future<void> addTemplate(StateSetter setDialogState) async {
      final created = await _openQuickReplyEditorDialog();
      if (created == null) return;
      setDialogState(() => working.add(created));
    }

    Future<void> editTemplate(int index, StateSetter setDialogState) async {
      final edited = await _openQuickReplyEditorDialog(initial: working[index]);
      if (edited == null) return;
      setDialogState(() => working[index] = edited);
    }

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Configurar mensajes rápidos'),
              content: SizedBox(
                width: 560,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton.icon(
                        onPressed: () => addTemplate(setDialogState),
                        icon: const Icon(Icons.add_rounded, size: 16),
                        label: const Text('Agregar'),
                        style: FilledButton.styleFrom(
                          backgroundColor: _waGreenDark,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 340),
                      child: working.isEmpty
                          ? const Center(
                              child: Padding(
                                padding: EdgeInsets.all(20),
                                child: Text('Aún no hay mensajes rápidos configurados.'),
                              ),
                            )
                          : ListView.separated(
                              shrinkWrap: true,
                              itemCount: working.length,
                              separatorBuilder: (_, __) =>
                                  Divider(height: 1, color: _waBorder.withAlpha(80)),
                              itemBuilder: (context, index) {
                                final item = working[index];
                                return ListTile(
                                  dense: true,
                                  title: Text(
                                    item.label,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  subtitle: Text(
                                    item.text,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        tooltip: 'Editar',
                                        visualDensity: VisualDensity.compact,
                                        onPressed: () => editTemplate(index, setDialogState),
                                        icon: const Icon(Icons.edit_outlined, size: 18),
                                      ),
                                      IconButton(
                                        tooltip: 'Eliminar',
                                        visualDensity: VisualDensity.compact,
                                        onPressed: () {
                                          setDialogState(() => working.removeAt(index));
                                        },
                                        icon: const Icon(Icons.delete_outline_rounded, size: 18),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: () async {
                    final sanitized = working
                        .where(
                          (item) =>
                              item.label.trim().isNotEmpty && item.text.trim().isNotEmpty,
                        )
                        .toList(growable: false);
                    await _saveQuickReplies(sanitized);
                    if (!mounted) return;
                    setState(() => _quickReplies = sanitized);
                    if (!dialogContext.mounted) return;
                    Navigator.of(dialogContext).pop();
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: _waGreenDark,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Guardar cambios'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  String _statusLabel(String value) {
    return value
        .replaceAll('_', ' ')
        .split(' ')
        .where((part) => part.isNotEmpty)
        .map(
          (part) =>
              '${part.substring(0, 1).toUpperCase()}${part.substring(1).toLowerCase()}',
        )
        .join(' ');
  }

  Color _taskStatusColor(CrmComercialFollowupTask task) {
    if (task.isCompleted) return Colors.green;
    if (task.isCancelled) return Colors.grey;
    if (task.isOverdue) return Colors.red;
    return Colors.orange;
  }

  String _taskStatusLabel(CrmComercialFollowupTask task) {
    if (task.isCompleted) return 'Completada';
    if (task.isCancelled) return 'Cancelada';
    if (task.isOverdue) return 'Vencida';
    return 'Pendiente';
  }

  Widget _buildTaskTile(CrmComercialFollowupTask task, BuildContext context) {
    final color = _taskStatusColor(task);
    final priorityColors = <String, Color>{
      'URGENTE': Colors.red.shade700,
      'ALTA': Colors.orange.shade700,
      'NORMAL': Colors.blue.shade700,
      'BAJA': Colors.grey.shade600,
    };
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  task.title,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withAlpha(22),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _taskStatusLabel(task),
                  style: TextStyle(fontSize: 11, color: color),
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: (priorityColors[task.priority] ?? Colors.grey)
                      .withAlpha(16),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  task.priority,
                  style: TextStyle(
                    fontSize: 10,
                    color: priorityColors[task.priority] ?? Colors.grey,
                  ),
                ),
              ),
            ],
          ),
          if (task.description != null) ...[
            const SizedBox(height: 4),
            Text(task.description!, style: const TextStyle(fontSize: 13)),
          ],
          const SizedBox(height: 6),
          Row(
            children: [
              if (task.dueDate != null)
                Text(
                  'Vence: ${DateFormat('dd/MM/yyyy').format(task.dueDate!)}',
                  style: TextStyle(
                    fontSize: 12,
                    color: task.isOverdue
                        ? Colors.red
                        : AppColors.textSecondary,
                  ),
                ),
              if (task.assignedTo != null) ...[
                const SizedBox(width: 12),
                Text(
                  task.assignedTo!.nombreCompleto,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
              const Spacer(),
              if (task.isActive) ...[
                TextButton(
                  onPressed: _saving ? null : () => _completeTask(task.id),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.success,
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  child: const Text('Completar'),
                ),
                TextButton(
                  onPressed: _saving ? null : () => _cancelTask(task.id),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.textSecondary,
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  child: const Text('Cancelar'),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authStateProvider);
    final isAdmin = auth.user?.appRole == AppRole.admin;
    final usesDesktopShellAppBar =
        MediaQuery.sizeOf(context).width >= kDesktopShellBreakpoint;
    _publishDesktopShellActions(enabled: isAdmin && usesDesktopShellAppBar);
    if (!isAdmin) {
      return const Scaffold(
        backgroundColor: _waBg,
        body: Center(
          child: Text('Acceso denegado. Solo ADMIN puede usar CRM Comercial.'),
        ),
      );
    }

    final selected = _selected;
    return Scaffold(
      backgroundColor: _waBg,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _buildCrmShell(context, selected),
    );
  }

  Widget _buildCrmShell(BuildContext context, CrmComercialCustomer? selected) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 6, 6, 6),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          if (kDebugMode) {
            debugPrint(
              '[CRM][Shell] width=${width.toStringAsFixed(1)} loading=$_loading conversations=${_conversations.length} selected=${_selectedConversation?.id ?? 'null'}',
            );
          }
          final isMobile = width < 720;
          final isTablet = width >= 720 && width < 1220;

          if (isMobile) {
            if (!_mobileConversationMode || _selectedConversation == null) {
              return _buildSidebarPanel(
                context,
                selected: selected,
                isMobile: true,
              );
            }
            return _buildConversationPanel(
              context,
              selected,
              _selectedConversation,
              allowDetailToggle: true,
              isTablet: false,
              isMobile: true,
              onBackToList: () {
                setState(() => _mobileConversationMode = false);
              },
            );
          }

          final leftWidth = isTablet ? 296.0 : 338.0;
          final rightWidth = _showDetailsPanel ? 360.0 : 0.0;

          return Row(
            children: [
              SizedBox(
                width: leftWidth,
                child: _buildSidebarPanel(
                  context,
                  selected: selected,
                  isMobile: false,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildConversationPanel(
                  context,
                  selected,
                  _selectedConversation,
                  allowDetailToggle: true,
                  isTablet: isTablet,
                  isMobile: false,
                ),
              ),
              if (!isTablet) ...[
                const SizedBox(width: 8),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOut,
                  width: rightWidth,
                  child: _showDetailsPanel
                      ? _buildDetailsPanel(
                          context,
                          selected,
                          compact: false,
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _buildSidebarPanel(
    BuildContext context, {
    required CrmComercialCustomer? selected,
    required bool isMobile,
  }) {
    final filteredConversations = _filteredConversations;

    return Container(
      decoration: BoxDecoration(
        color: _waSidebar,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _waBorder.withAlpha(120)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
            child: Column(
              children: [
                LayoutBuilder(
                  builder: (context, toolbarConstraints) {
                    final compact = toolbarConstraints.maxWidth < 310;
                    final maxSearchWidth = (toolbarConstraints.maxWidth - (compact ? 230 : 248))
                        .clamp(0.0, compact ? 110.0 : 170.0);
                    final searchWidth = _showSidebarSearch ? maxSearchWidth : 0.0;
                    return Row(
                      children: [
                        IconButton(
                          tooltip: 'Buscar',
                          visualDensity: VisualDensity.compact,
                          constraints: const BoxConstraints(
                            minWidth: 34,
                            minHeight: 34,
                          ),
                          padding: EdgeInsets.zero,
                          onPressed: () {
                            setState(() => _showSidebarSearch = !_showSidebarSearch);
                            if (_showSidebarSearch) {
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                if (!mounted) return;
                                _sidebarSearchFocusNode.requestFocus();
                              });
                            }
                          },
                          icon: const Icon(Icons.search_rounded, size: 19),
                        ),
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          curve: Curves.easeOutCubic,
                          width: searchWidth,
                          child: searchWidth <= 0
                              ? const SizedBox.shrink()
                              : TextField(
                                  focusNode: _sidebarSearchFocusNode,
                                  controller: _searchCtrl,
                                  onChanged: (_) {
                                    if (!mounted) return;
                                    setState(() {});
                                  },
                                  onSubmitted: (_) => setState(() {}),
                                  decoration: InputDecoration(
                                    hintText: compact ? 'Buscar' : 'Buscar',
                                    isDense: true,
                                    filled: true,
                                    fillColor: const Color(0xFFF6F7F7),
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 7,
                                    ),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      borderSide: BorderSide(
                                        color: _waBorder.withAlpha(110),
                                      ),
                                    ),
                                  ),
                                ),
                        ),
                        const SizedBox(width: 2),
                        PopupMenuButton<String>(
                          tooltip: 'Filtrar estado',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 34,
                            minHeight: 34,
                          ),
                          onSelected: (value) {
                            setState(() {
                              _statusFilter = value;
                            });
                            _loadAll();
                          },
                          itemBuilder: (context) => [
                            const PopupMenuItem<String>(
                              value: '',
                              child: Text('Todos'),
                            ),
                            ..._crmStatuses.map(
                              (status) => PopupMenuItem<String>(
                                value: status,
                                child: Text(_statusLabel(status)),
                              ),
                            ),
                          ],
                          icon: Icon(
                            Icons.filter_list_rounded,
                            size: 20,
                            color: _statusFilter.isEmpty ? _waTextMuted : _waGreenDark,
                          ),
                        ),
                        const SizedBox(width: 2),
                        FilterChip(
                          selected: _onlyMine,
                          showCheckmark: false,
                          side: BorderSide(color: _waBorder.withAlpha(100)),
                          backgroundColor: const Color(0xFFF6F7F7),
                          selectedColor: _waGreen.withAlpha(20),
                          visualDensity: VisualDensity.compact,
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          labelPadding: const EdgeInsets.symmetric(horizontal: 2),
                          label: const Text('Mio', style: TextStyle(fontSize: 11)),
                          onSelected: (value) {
                            setState(() => _onlyMine = value);
                            _loadAll();
                          },
                        ),
                        const SizedBox(width: 2),
                        IconButton(
                          tooltip: 'Nuevo chat',
                          visualDensity: VisualDensity.compact,
                          constraints: const BoxConstraints(
                            minWidth: 34,
                            minHeight: 34,
                          ),
                          padding: EdgeInsets.zero,
                          onPressed: _openNewChatDialog,
                          icon: const Icon(Icons.add_rounded, size: 20),
                        ),
                        PopupMenuButton<String>(
                          tooltip: 'Mas acciones',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 34,
                            minHeight: 34,
                          ),
                          onSelected: (value) {
                            if (value == 'new-chat') {
                              _openNewChatDialog();
                            }
                            if (value == 'refresh') {
                              _loadAll();
                            }
                            if (value == 'clear-status') {
                              setState(() => _statusFilter = '');
                              _loadAll();
                            }
                          },
                          itemBuilder: (context) => const [
                            PopupMenuItem<String>(
                              value: 'new-chat',
                              child: Text('Nuevo chat por numero'),
                            ),
                            PopupMenuItem<String>(
                              value: 'refresh',
                              child: Text('Actualizar lista'),
                            ),
                            PopupMenuItem<String>(
                              value: 'clear-status',
                              child: Text('Quitar filtro de estado'),
                            ),
                          ],
                        ),
                      ],
                    );
                  },
                ),
                if (_allTasks.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _SummaryChip(
                          label: 'Hoy',
                          count: _pendingTodayCount,
                          color: _waGreenDark,
                        ),
                        const SizedBox(width: 8),
                        _SummaryChip(
                          label: 'Vencidas',
                          count: _overdueCount,
                          color: AppColors.error,
                        ),
                        const SizedBox(width: 8),
                        _SummaryChip(
                          label: '7 dias',
                          count: _upcomingCount,
                          color: const Color(0xFF8C8C8C),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (_error.isNotEmpty)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.error.withAlpha(14),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _error,
                style: const TextStyle(fontSize: 12, color: AppColors.error),
              ),
            ),
          Expanded(
            child: filteredConversations.isEmpty
                ? Center(
                    child: Text(
                      _searchCtrl.text.trim().isNotEmpty
                          ? 'No hay resultados para esa busqueda.'
                          : (_conversationWarning ??
                              'Sin conversaciones para la instancia seleccionada.'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 12, color: _waTextMuted),
                    ),
                  )
                : ScrollConfiguration(
                    behavior: const MaterialScrollBehavior().copyWith(
                      scrollbars: false,
                    ),
                    child: Scrollbar(
                      controller: _conversationListScrollCtrl,
                      thickness: 4,
                      radius: const Radius.circular(999),
                      thumbVisibility: false,
                      child: ListView.builder(
                        controller: _conversationListScrollCtrl,
                        padding: const EdgeInsets.only(bottom: 8),
                        itemCount: filteredConversations.length,
                        itemExtent: 78,
                        itemBuilder: (context, index) {
                          final item = filteredConversations[index];
                          final isActive = _selectedConversation?.id == item.id;
                          final effectiveStatus = _conversationEffectiveStatus(item);
                          return _CrmConversationListItem(
                            key: ValueKey(item.id),
                            item: item,
                            isActive: isActive,
                            visibleName: _conversationVisibleName(item),
                            previewText: _conversationPreviewText(item),
                            timeLabel: _formatConversationListTime(item.lastMessageAt),
                            statusLabel: _statusLabel(effectiveStatus),
                            statusColor: _statusAccentColor(effectiveStatus),
                            onAvatarTap: () => _openAvatarPreview(
                              _conversationVisibleName(item),
                              imageUrl: item.remoteAvatarUrl,
                            ),
                            onTap: _saving
                                ? null
                                : () async {
                                    await _openConversation(item.id);
                                    if (!mounted) return;
                                    if (isMobile) {
                                      setState(() => _mobileConversationMode = true);
                                    }
                                  },
                          );
                        },
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildConversationPanel(
    BuildContext context,
    CrmComercialCustomer? selected,
    CrmComercialInboxConversation? selectedConversation, {
    required bool allowDetailToggle,
    required bool isTablet,
    required bool isMobile,
    VoidCallback? onBackToList,
  }) {
    final hasConversation = selectedConversation != null;
    final canSendText = hasConversation && !_sendingChatMessage && !_saving;
    if (kDebugMode) {
      debugPrint(
        '[CRM][ConversationPanel] called hasConversation=$hasConversation selected=${selectedConversation?.id ?? 'null'} messages=${_messages.length} filtered=${_filteredMessages.length}',
      );
    }

    List<_CrmTimelineEntry> timeline;
    try {
      timeline = _filteredMessages
          .map(
            (message) => _CrmTimelineEntry(
              title: message.displayText,
              subtitle: message.isOutgoing ? 'Tu mensaje' : 'Cliente',
              author: message.senderName ??
                  (message.isOutgoing ? 'Equipo FULLTECH' : 'Cliente'),
              createdAt: message.sentAt,
              icon: message.isOutgoing
                  ? Icons.north_east_rounded
                  : Icons.south_west_rounded,
              isOutgoing: message.isOutgoing,
              messageType: message.messageType,
              mediaUrl: message.mediaUrl,
              caption: message.caption,
              messageId: message.id,
              mediaStorageKey: message.mediaStorageKey,
              mediaStatus: message.mediaStatus,
              mediaMimeType: message.mediaMimeType,
              originalFileName: message.originalFileName,
              mediaFileSize: message.mediaFileSize,
            ),
          )
          .toList(growable: false);
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint('[CRM][ConversationPanel] timeline build failed: $error');
        debugPrint('$stackTrace');
      }
      timeline = const <_CrmTimelineEntry>[];
    }

    return Container(
      decoration: BoxDecoration(
        color: _waPanel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _waBorder.withAlpha(110)),
      ),
      child: Column(
        children: [
          Container(
            height: 58,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFF7F8F8),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(12),
              ),
              border: Border(
                bottom: BorderSide(color: _waBorder.withAlpha(110)),
              ),
            ),
            child: Row(
              children: [
                if (isMobile && onBackToList != null)
                  IconButton(
                    onPressed: onBackToList,
                    icon: const Icon(Icons.arrow_back_rounded),
                  ),
                GestureDetector(
                  onTap: () => _openAvatarPreview(
                    selectedConversation?.contactName ?? 'Contacto',
                    imageUrl: selectedConversation?.remoteAvatarUrl,
                  ),
                  child: _buildConversationAvatar(
                    title: selectedConversation?.contactName ?? 'CRM',
                    accent: _waGreenDark,
                    radius: 18,
                    imageUrl: selectedConversation?.remoteAvatarUrl,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        selectedConversation?.contactName ?? 'Conversaciones CRM',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: _waText,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              hasConversation
                                  ? (selectedConversation.crmCustomerName ??
                                      (selectedConversation.isNewContact
                                          ? 'Nuevo contacto'
                                          : 'Sin CRM'))
                                  : 'Selecciona una conversacion para ver mensajes reales',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 10.5,
                                color: _waTextMuted,
                              ),
                            ),
                          ),
                          if (hasConversation &&
                              (selectedConversation.crmCustomerStatus ?? '')
                                  .isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: _statusAccentColor(
                                  selectedConversation.crmCustomerStatus!,
                                ).withAlpha(20),
                                borderRadius: BorderRadius.circular(7),
                              ),
                              child: Text(
                                _statusLabel(
                                  selectedConversation.crmCustomerStatus!,
                                ),
                                style: TextStyle(
                                  fontSize: 8.5,
                                  color: _statusAccentColor(
                                    selectedConversation.crmCustomerStatus!,
                                  ),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (selectedConversation?.canConvertToCrm == true)
                  TextButton.icon(
                    onPressed: _saving ? null : _showConvertPlaceholder,
                    icon: const Icon(Icons.person_add_alt_1_rounded, size: 16),
                    label: const Text('Convertir'),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                IconButton(
                  tooltip: 'Buscar en conversacion',
                  onPressed: hasConversation
                      ? () {
                          setState(() {
                            _showConversationSearch = !_showConversationSearch;
                          });
                        }
                      : null,
                  icon: const Icon(Icons.search_rounded, size: 20),
                ),
                IconButton(
                  tooltip: 'Panel IA',
                  onPressed: !hasConversation
                      ? null
                      : () {
                          if (isMobile) {
                            _openRightPanelSheet(
                              _CrmRightPanelTab.ia,
                              selected,
                            );
                            return;
                          }
                          if (isTablet) {
                            _openRightPanelDrawer(
                              _CrmRightPanelTab.ia,
                              selected,
                            );
                            return;
                          }
                          setState(() {
                            _activeRightPanelTab = _CrmRightPanelTab.ia;
                            _showDetailsPanel = true;
                          });
                        },
                  icon: const Icon(Icons.auto_awesome_rounded, size: 20),
                ),
                if (allowDetailToggle)
                  IconButton(
                    tooltip: 'Panel detalle',
                    onPressed: !hasConversation
                        ? null
                        : () {
                            if (isMobile) {
                              _openRightPanelSheet(
                                _CrmRightPanelTab.detail,
                                selected,
                              );
                              return;
                            }
                            if (isTablet) {
                              _openRightPanelDrawer(
                                _CrmRightPanelTab.detail,
                                selected,
                              );
                              return;
                            }
                            setState(() {
                              _activeRightPanelTab = _CrmRightPanelTab.detail;
                              _showDetailsPanel = !_showDetailsPanel;
                            });
                          },
                    icon: const Icon(Icons.info_outline_rounded, size: 20),
                  ),
                IconButton(
                  tooltip: 'Actualizar conversacion',
                  onPressed: !hasConversation || _saving
                      ? null
                      : () => _openConversation(selectedConversation.id),
                  icon: const Icon(Icons.refresh_rounded, size: 20),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Mas opciones',
                  onSelected: (value) {
                    if (value == 'new-chat') {
                      _openNewChatDialog();
                    }
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem<String>(
                      value: 'new-chat',
                      child: Text('Nuevo chat por numero'),
                    ),
                  ],
                  icon: const Icon(Icons.more_vert_rounded, size: 20),
                ),
              ],
            ),
          ),
          if (_showConversationSearch)
            Container(
              padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
              decoration: BoxDecoration(
                color: const Color(0xFFF7F8F8),
                border: Border(
                  bottom: BorderSide(color: _waBorder.withAlpha(90)),
                ),
              ),
              child: TextField(
                controller: _conversationSearchCtrl,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  hintText: 'Buscar en la conversacion',
                  isDense: true,
                  filled: true,
                  fillColor: Colors.white,
                  prefixIcon: Icon(Icons.search_rounded, size: 18),
                ),
              ),
            ),
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      const DecoratedBox(
                        decoration: BoxDecoration(color: _waChat),
                      ),
                      Opacity(
                        opacity: 0.30,
                        child: Image.asset(
                          'assets/image/wa_bg_light.png',
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                        ),
                      ),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.white.withAlpha(24),
                              Colors.transparent,
                              Colors.white.withAlpha(16),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  top: -30,
                  right: -24,
                  child: Container(
                    width: 140,
                    height: 140,
                    decoration: BoxDecoration(
                      color: Colors.white.withAlpha(24),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                Positioned(
                  bottom: 60,
                  left: -38,
                  child: Container(
                    width: 160,
                    height: 160,
                    decoration: BoxDecoration(
                      color: Colors.white.withAlpha(18),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                if (timeline.isEmpty)
                  Center(
                    child: Text(
                      hasConversation
                          ? (_conversationWarning ?? 'Sin mensajes en esta conversacion.')
                          : 'Selecciona una conversacion para ver mensajes reales',
                      style: const TextStyle(fontSize: 13, color: _waTextMuted),
                    ),
                  )
                else
                  ScrollConfiguration(
                    behavior: const MaterialScrollBehavior().copyWith(
                      scrollbars: false,
                    ),
                    child: ListView.builder(
                      controller: _chatScrollCtrl,
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(7, 6, 7, 6),
                      itemCount: timeline.length,
                      itemBuilder: (context, index) {
                        final entry = timeline[index];
                        final previous = index > 0 ? timeline[index - 1] : null;
                        final showDate =
                            previous == null ||
                            !_isSameDay(entry.createdAt, previous.createdAt);
                        return Column(
                          children: [
                            if (showDate)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8, top: 2),
                                child: _DateSeparator(
                                  label: _formatDayLabel(entry.createdAt),
                                ),
                              ),
                            _CrmTimelineTile(entry: entry),
                            const SizedBox(height: 5),
                          ],
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
            decoration: BoxDecoration(
              color: const Color(0xFFF7F8F8),
              border: Border(top: BorderSide(color: _waBorder.withAlpha(110))),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if ((_commercialAiSuggestion?.suggestedReply ?? '').isNotEmpty)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: _waBorder.withAlpha(130)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.auto_awesome_rounded, size: 16, color: _waGreenDark),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Sugerencia IA (${_commercialAiSuggestion!.intent.replaceAll('_', ' ')})',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: _waText,
                                ),
                              ),
                            ),
                            Text(
                              '${(_commercialAiSuggestion!.confidence * 100).round()}%',
                              style: const TextStyle(fontSize: 10, color: _waTextMuted),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _commercialAiSuggestion!.suggestedReply,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11.5, color: _waTextMuted),
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            OutlinedButton(
                              onPressed: _insertCommercialSuggestionInComposer,
                              style: OutlinedButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                              ),
                              child: const Text('Insertar en input'),
                            ),
                            FilledButton(
                              onPressed: _sendingChatMessage ? null : _sendCommercialSuggestion,
                              style: FilledButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                backgroundColor: _waGreenDark,
                                foregroundColor: Colors.white,
                              ),
                              child: const Text('Enviar'),
                            ),
                            TextButton(
                              onPressed: _insertCommercialSuggestionInComposer,
                              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                              child: const Text('Editar'),
                            ),
                            TextButton(
                              onPressed: _ignoreCommercialSuggestion,
                              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                              child: const Text('Ignorar'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                if ((_composerOrthographySuggestion ?? '').isNotEmpty)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: _waBorder.withAlpha(130)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.auto_fix_high_rounded, size: 16, color: _waGreenDark),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _composerOrthographySuggestion!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 11.5, color: _waTextMuted),
                          ),
                        ),
                        TextButton(
                          onPressed: _ignoreOrthographySuggestion,
                          style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                          child: const Text('Ignorar'),
                        ),
                        FilledButton(
                          onPressed: _applyOrthographySuggestion,
                          style: FilledButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            backgroundColor: _waGreenDark,
                          ),
                          child: const Text('Aceptar corrección'),
                        ),
                      ],
                    ),
                  ),
                Row(
                  children: [
                    IconButton(
                      tooltip: 'Emoji',
                      visualDensity: VisualDensity.compact,
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Selector de emoji disponible próximamente.'),
                          ),
                        );
                      },
                      icon: const Icon(Icons.emoji_emotions_outlined, size: 20),
                    ),
                    IconButton(
                      tooltip: 'Adjuntar',
                      visualDensity: VisualDensity.compact,
                      onPressed: _openAttachmentMenu,
                      icon: const Icon(Icons.attach_file_rounded, size: 20),
                    ),
                    IconButton(
                      tooltip: 'Mensajes rápidos',
                      visualDensity: VisualDensity.compact,
                      onPressed: _openQuickMessagesDialog,
                      icon: const Icon(Icons.flash_on_rounded, size: 20),
                    ),
                    IconButton(
                      tooltip: 'Sugerir respuesta IA',
                      visualDensity: VisualDensity.compact,
                      onPressed: !hasConversation || _loadingCommercialSuggestion
                          ? null
                          : () => _requestCommercialReplySuggestion(manual: true),
                      icon: _loadingCommercialSuggestion
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.auto_awesome_rounded, size: 20),
                    ),
                    Expanded(
                      child: TextField(
                        controller: _chatComposerCtrl,
                        minLines: 1,
                        maxLines: 4,
                        decoration: const InputDecoration(
                          hintText: 'Escribe un mensaje',
                          isDense: true,
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(
                            borderSide: BorderSide(color: _waBorder),
                          ),
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Nota de voz',
                      visualDensity: VisualDensity.compact,
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Grabación de audio disponible próximamente.'),
                          ),
                        );
                      },
                      icon: const Icon(Icons.mic_none_rounded, size: 20),
                    ),
                    FilledButton.icon(
                      onPressed: canSendText ? _sendMessageToCurrentConversation : null,
                      icon: _sendingChatMessage
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.send_rounded, size: 16),
                      label: Text(_sendingChatMessage ? 'Enviando...' : 'Enviar'),
                      style: FilledButton.styleFrom(
                        backgroundColor: _waGreenDark,
                        foregroundColor: Colors.white,
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailsPanel(
    BuildContext context,
    CrmComercialCustomer? selected, {
    required bool compact,
    _CrmRightPanelTab? tabOverride,
    VoidCallback? onClose,
  }) {
    final activeTab = tabOverride ?? _activeRightPanelTab;
    if (compact) {
      return Container(
        decoration: BoxDecoration(
          color: _waPanel,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _waBorder.withAlpha(110)),
        ),
        child: Center(
          child: IconButton(
            tooltip: 'Mostrar detalles',
            onPressed: () => setState(() {
              _activeRightPanelTab = _CrmRightPanelTab.detail;
              _showDetailsPanel = true;
            }),
            icon: const Icon(Icons.chevron_left_rounded),
          ),
        ),
      );
    }

    if (selected == null && activeTab == _CrmRightPanelTab.detail) {
      return Container(
        decoration: BoxDecoration(
          color: _waPanel,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _waBorder.withAlpha(110)),
        ),
        child: Column(
          children: [
            _RightPanelHeader(
              activeTab: activeTab,
              onTabChanged: (tab) {
                if (tabOverride != null) return;
                setState(() => _activeRightPanelTab = tab);
              },
              onClose: onClose ?? () => setState(() => _showDetailsPanel = false),
            ),
            const Expanded(
              child: Center(
                child: Text(
                  'Panel de detalle del cliente',
                  style: AppTextStyles.subtitle,
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (activeTab == _CrmRightPanelTab.ia) {
      return Container(
        decoration: BoxDecoration(
          color: _waPanel,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _waBorder.withAlpha(110)),
        ),
        child: Column(
          children: [
            _RightPanelHeader(
              activeTab: activeTab,
              onTabChanged: (tab) {
                if (tabOverride != null) return;
                setState(() => _activeRightPanelTab = tab);
              },
              onClose: onClose ?? () => setState(() => _showDetailsPanel = false),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                child: _CrmAiCommercialPanel(
                  suggestion: _commercialAiSuggestion,
                  loading: _loadingCommercialSuggestion,
                  onSuggest: () => _requestCommercialReplySuggestion(manual: true),
                  onInsert: _insertCommercialSuggestionInComposer,
                  onSend: _sendCommercialSuggestion,
                  onIgnore: _ignoreCommercialSuggestion,
                  onCreateTask: selected == null
                      ? null
                      : () => _openCreateTaskDialog(context),
                  onCreateQuote: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Creación de cotización desde IA disponible próximamente.'),
                      ),
                    );
                  },
                  onUseLocation: () async {
                    final text = await _buildGpsMessage();
                    _insertTextInComposer(text);
                  },
                  onUseHours: () async {
                    final text = await _buildStoreHoursMessage();
                    _insertTextInComposer(text);
                  },
                  onUseAccounts: () async {
                    final text = await _buildBankAccountsMessage();
                    _insertTextInComposer(text);
                  },
                  onUseCatalog: () async {
                    final text = await _buildCatalogMessage();
                    _insertTextInComposer(text);
                  },
                  statusMenu: PopupMenuButton<String>(
                    tooltip: 'Cambiar estado CRM',
                    onSelected: (value) async {
                      await _changeStatus(value);
                    },
                    itemBuilder: (context) => _crmStatuses
                        .map(
                          (status) => PopupMenuItem<String>(
                            value: status,
                            child: Text(_statusLabel(status)),
                          ),
                        )
                        .toList(growable: false),
                    child: const Chip(
                      label: Text('Cambiar estado CRM'),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (selected == null) {
      return const SizedBox.shrink();
    }
    final customer = selected;

    return Container(
      decoration: BoxDecoration(
        color: _waPanel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _waBorder.withAlpha(110)),
      ),
      child: Scrollbar(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _RightPanelHeader(
                activeTab: activeTab,
                onTabChanged: (tab) {
                  if (tabOverride != null) return;
                  setState(() => _activeRightPanelTab = tab);
                },
                onClose: onClose ?? () => setState(() => _showDetailsPanel = false),
              ),
              const SizedBox(height: 8),
              _InfoRow(label: 'Telefono', value: customer.telefono),
              _InfoRow(
                label: 'Ciudad',
                value: customer.ciudad ?? 'No definida',
              ),
              _InfoRow(
                label: 'Direccion',
                value: customer.direccion ?? 'No definida',
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                key: ValueKey(
                  'responsable-${customer.id}-${customer.responsable?.id ?? ''}',
                ),
                initialValue: customer.responsable?.id,
                decoration: const InputDecoration(
                  labelText: 'Responsable',
                  isDense: true,
                  filled: true,
                  fillColor: Color(0xFFF6F7F7),
                  border: OutlineInputBorder(
                    borderSide: BorderSide(color: _waBorder),
                  ),
                ),
                items: _users
                    .map(
                      (user) => DropdownMenuItem<String>(
                        value: user.id,
                        child: Text(user.nombreCompleto),
                      ),
                    )
                    .toList(growable: false),
                onChanged: _saving ? null : _assignResponsible,
              ),
              const SizedBox(height: 8),
              const Text(
                'Estado comercial',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: _waTextMuted,
                ),
              ),
              const SizedBox(height: 5),
              Wrap(
                spacing: 5,
                runSpacing: 5,
                children: _crmStatuses
                    .map(
                      (status) => ChoiceChip(
                        label: Text(
                          _statusLabel(status),
                          style: const TextStyle(fontSize: 11),
                        ),
                        selected: customer.estadoActual == status,
                        selectedColor: _statusAccentColor(status).withAlpha(26),
                        side: BorderSide(color: _waBorder.withAlpha(100)),
                        visualDensity: VisualDensity.compact,
                        onSelected: _saving
                            ? null
                            : (_) => _changeStatus(status),
                      ),
                    )
                    .toList(growable: false),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _nextActionCtrl,
                minLines: 1,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Proxima accion',
                  isDense: true,
                  filled: true,
                  fillColor: Color(0xFFF6F7F7),
                  border: OutlineInputBorder(
                    borderSide: BorderSide(color: _waBorder),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: _saving ? null : _saveNextAction,
                  style: FilledButton.styleFrom(
                    backgroundColor: _waGreenDark,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Guardar'),
                ),
              ),
              Divider(height: 18, color: _waBorder.withAlpha(110)),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Tareas', style: AppTextStyles.subtitle),
                  TextButton.icon(
                    onPressed: (_saving || _loadingTasks)
                        ? null
                        : () => _openCreateTaskDialog(context),
                    icon: const Icon(Icons.add_rounded, size: 16),
                    label: const Text('Nueva'),
                  ),
                ],
              ),
              if (_loadingTasks)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else if (_selectedTasks.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 6),
                  child: Text(
                    'Sin tareas de seguimiento',
                    style: AppTextStyles.small,
                  ),
                )
              else
                ..._selectedTasks.map((task) => _buildTaskTile(task, context)),
              Divider(height: 18, color: _waBorder.withAlpha(110)),
              const Text(
                'Ventas',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: _waTextMuted,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                'Estado actual: ${_statusLabel(customer.estadoActual)}',
                style: const TextStyle(fontSize: 11, color: _waTextMuted),
              ),
              const SizedBox(height: 6),
              const Text(
                'Sin modulo adicional de ventas en este cliente.',
                style: TextStyle(fontSize: 11, color: _waTextMuted),
              ),
              Divider(height: 18, color: _waBorder.withAlpha(110)),
              const Text(
                'Historial',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: _waTextMuted,
                ),
              ),
              const SizedBox(height: 5),
              ...customer.statusHistory
                  .take(6)
                  .map(
                    (entry) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        '${_statusLabel(entry.estadoAnterior ?? 'NUEVO')} -> ${_statusLabel(entry.estadoNuevo)}\n${entry.changedBy?.nombreCompleto ?? 'Sistema'} · ${_formatDateTime(entry.createdAt)}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ),
            ],
          ),
        ),
      ),
    );
  }

  // Mapeo de estados antiguos (de 10 a 7) para compatibilidad con datos históricos
  String _mapLegacyStatus(String status) {
    switch (status) {
      case 'INTERESADO':
        // Context-dependent: NUEVO si es nuevo cliente, NEGOCIACION si ya fue contactado
        // Default: NUEVO para evitar perder clientes en embudo
        return 'NUEVO';
      case 'SEGUIMIENTO':
        return 'NEGOCIACION';
      case 'SOPORTE':
        // SOPORTE no es estado comercial, mapear a NUEVO para revisión
        return 'NUEVO';
      case 'COBRO_PENDIENTE':
        return 'PENDIENTE_PAGO';
      default:
        return status; // pass through if already valid
    }
  }

  Color _statusAccentColor(String status) {
    // Mapeo automático de estados históricos a color correspondiente
    final mappedStatus = _mapLegacyStatus(status);
    switch (mappedStatus) {
      case 'GANADO':
        return const Color(0xFF1FA855); // Verde WhatsApp
      case 'PERDIDO':
        return AppColors.error; // Rojo
      case 'NEGOCIACION':
      case 'RESERVADO':
        return const Color(0xFF5E6E75); // Gris
      case 'PENDIENTE_PAGO':
        return AppColors.warning; // Naranja
      case 'COTIZACION':
        return const Color(0xFF4B5563); // Gris oscuro
      case 'NUEVO':
      default:
        return const Color(0xFF7A8A96); // Gris azulado claro
    }
  }

  String _initials(String raw) {
    final parts = raw.trim().split(' ').where((e) => e.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return '${parts[0].substring(0, 1)}${parts[1].substring(0, 1)}'
        .toUpperCase();
  }

  String _formatDateTime(DateTime? value) {
    if (value == null) return 'Sin fecha';
    return DateFormat('dd/MM HH:mm').format(value);
  }

  bool _isSameDay(DateTime? a, DateTime? b) {
    if (a == null || b == null) return a == b;
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  String _formatDayLabel(DateTime? value) {
    if (value == null) return 'Sin fecha';
    final now = DateTime.now();
    final day = DateTime(value.year, value.month, value.day);
    final today = DateTime(now.year, now.month, now.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return 'Hoy';
    if (diff == 1) return 'Ayer';
    if (diff > 1 && diff <= 7) {
      final raw = DateFormat('EEEE', 'es').format(value);
      return raw.substring(0, 1).toUpperCase() + raw.substring(1);
    }
    return DateFormat('dd/MM/yyyy').format(value);
  }
}

class _DateSeparator extends StatelessWidget {
  const _DateSeparator({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 3.5),
        decoration: BoxDecoration(
          color: const Color(0xFFE2E8ED),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.white.withAlpha(120)),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 9.5,
            fontWeight: FontWeight.w500,
            color: _waTextMuted,
          ),
        ),
      ),
    );
  }
}

class _RightPanelHeader extends StatelessWidget {
  const _RightPanelHeader({
    required this.activeTab,
    required this.onTabChanged,
    required this.onClose,
  });

  final _CrmRightPanelTab activeTab;
  final ValueChanged<_CrmRightPanelTab> onTabChanged;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        ChoiceChip(
          label: const Text('Detalle', style: TextStyle(fontSize: 11)),
          selected: activeTab == _CrmRightPanelTab.detail,
          onSelected: (_) => onTabChanged(_CrmRightPanelTab.detail),
          visualDensity: VisualDensity.compact,
        ),
        const SizedBox(width: 6),
        ChoiceChip(
          label: const Text('IA', style: TextStyle(fontSize: 11)),
          selected: activeTab == _CrmRightPanelTab.ia,
          onSelected: (_) => onTabChanged(_CrmRightPanelTab.ia),
          visualDensity: VisualDensity.compact,
        ),
        const Spacer(),
        IconButton(
          tooltip: 'Cerrar panel',
          onPressed: onClose,
          icon: const Icon(Icons.close_rounded, size: 20),
          visualDensity: VisualDensity.compact,
        ),
      ],
    );
  }
}

class _CrmAiCommercialPanel extends StatelessWidget {
  const _CrmAiCommercialPanel({
    required this.suggestion,
    required this.loading,
    required this.onSuggest,
    required this.onInsert,
    required this.onSend,
    required this.onIgnore,
    required this.onUseLocation,
    required this.onUseHours,
    required this.onUseAccounts,
    required this.onUseCatalog,
    this.onCreateTask,
    this.onCreateQuote,
    this.statusMenu,
  });

  final CrmComercialAiReplySuggestion? suggestion;
  final bool loading;
  final VoidCallback onSuggest;
  final VoidCallback onInsert;
  final VoidCallback onSend;
  final VoidCallback onIgnore;
  final VoidCallback onUseLocation;
  final VoidCallback onUseHours;
  final VoidCallback onUseAccounts;
  final VoidCallback onUseCatalog;
  final VoidCallback? onCreateTask;
  final VoidCallback? onCreateQuote;
  final Widget? statusMenu;

  @override
  Widget build(BuildContext context) {
    final card = BoxDecoration(
      color: const Color(0xFFF6F8F9),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: _waBorder.withAlpha(120)),
    );
    return ListView(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: card,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Intención detectada',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
              ),
              const SizedBox(height: 4),
              Text(
                (suggestion?.intent ?? 'Sin sugerencia aún').replaceAll('_', ' '),
                style: const TextStyle(fontSize: 11, color: _waTextMuted),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: card,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Respuesta sugerida',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
              ),
              const SizedBox(height: 4),
              Text(
                suggestion?.suggestedReply ?? 'Pulsa "Sugerir respuesta" para generar una propuesta.',
                style: const TextStyle(fontSize: 11, color: _waTextMuted),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: card,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Datos usados y próxima acción',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
              ),
              const SizedBox(height: 4),
              Text(
                'Datos: ${suggestion?.dataUsed.join(', ') ?? 'Sin datos'}',
                style: const TextStyle(fontSize: 11, color: _waTextMuted),
              ),
              const SizedBox(height: 2),
              Text(
                'Próxima acción: ${suggestion?.nextAction ?? 'Sin recomendación'}',
                style: const TextStyle(fontSize: 11, color: _waTextMuted),
              ),
              if ((suggestion?.missingData ?? const <String>[]).isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  'Faltantes: ${suggestion!.missingData.join(', ')}',
                  style: const TextStyle(fontSize: 11, color: _waTextMuted),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 10),
        FilledButton.icon(
          onPressed: loading ? null : onSuggest,
          icon: loading
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.auto_fix_high_rounded, size: 16),
          label: const Text('Sugerir respuesta'),
        ),
        const SizedBox(height: 6),
        FilledButton.icon(
          onPressed: suggestion == null ? null : onInsert,
          icon: const Icon(Icons.input_rounded, size: 16),
          label: const Text('Insertar respuesta'),
        ),
        const SizedBox(height: 6),
        FilledButton.icon(
          onPressed: suggestion == null ? null : onSend,
          icon: const Icon(Icons.send_rounded, size: 16),
          label: const Text('Enviar sugerencia'),
          style: FilledButton.styleFrom(
            backgroundColor: _waGreenDark,
            foregroundColor: Colors.white,
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            OutlinedButton.icon(
              onPressed: suggestion == null ? null : onIgnore,
              icon: const Icon(Icons.block_rounded, size: 15),
              label: const Text('Ignorar'),
            ),
            OutlinedButton.icon(
              onPressed: onCreateTask,
              icon: const Icon(Icons.task_alt_rounded, size: 15),
              label: const Text('Crear tarea'),
            ),
            OutlinedButton.icon(
              onPressed: onCreateQuote,
              icon: const Icon(Icons.request_quote_rounded, size: 15),
              label: const Text('Crear cotización'),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            OutlinedButton(onPressed: onUseLocation, child: const Text('Usar ubicación')),
            OutlinedButton(onPressed: onUseHours, child: const Text('Usar horario')),
            OutlinedButton(onPressed: onUseAccounts, child: const Text('Usar cuentas')),
            OutlinedButton(onPressed: onUseCatalog, child: const Text('Usar catálogo')),
            if (statusMenu != null) statusMenu!,
          ],
        ),
      ],
    );
  }
}

class _SummaryChip extends StatelessWidget {
  const _SummaryChip({
    required this.label,
    required this.count,
    required this.color,
  });

  final String label;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withAlpha(count > 0 ? 22 : 12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$count',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: count > 0 ? color : _waTextMuted,
              fontSize: 11,
            ),
          ),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: count > 0 ? color : _waTextMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 78,
            child: Text(
              label,
              style: const TextStyle(fontSize: 11, color: _waTextMuted),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 11, color: _waText),
            ),
          ),
        ],
      ),
    );
  }
}

class _CrmConversationListItem extends StatelessWidget {
  const _CrmConversationListItem({
    super.key,
    required this.item,
    required this.isActive,
    required this.visibleName,
    required this.previewText,
    required this.timeLabel,
    required this.statusLabel,
    required this.statusColor,
    this.onAvatarTap,
    this.onTap,
  });

  final CrmComercialInboxConversation item;
  final bool isActive;
  final String visibleName;
  final String previewText;
  final String timeLabel;
  final String statusLabel;
  final Color statusColor;
  final VoidCallback? onAvatarTap;
  final VoidCallback? onTap;

  String _initials(String raw) {
    final parts = raw.trim().split(' ').where((e) => e.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts[0].substring(0, 1) + parts[1].substring(0, 1)).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final tileColor = isActive ? _waSelected : Colors.transparent;
    final avatarUrl = (item.remoteAvatarUrl ?? '').trim();
    final hasAvatar = _isSafePublicNetworkUrl(avatarUrl);
    // Estado visual: NUEVO si no está vinculado, estado real si está vinculado
    final showStatus = statusLabel.isNotEmpty && statusLabel != 'SIN CRM';
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        hoverColor: _waHover.withAlpha(80),
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          color: tileColor,
          padding: const EdgeInsets.fromLTRB(0, 2, 8, 2),
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                width: 3,
                height: 46,
                margin: const EdgeInsets.only(right: 7),
                decoration: BoxDecoration(
                  color: isActive ? _waGreenDark : Colors.transparent,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              GestureDetector(
                onTap: onAvatarTap,
                child: CircleAvatar(
                  radius: 18,
                  backgroundColor: statusColor.withAlpha(18),
                  backgroundImage: hasAvatar ? NetworkImage(avatarUrl) : null,
                  child: hasAvatar
                      ? null
                      : Text(
                          _initials(visibleName),
                          style: TextStyle(
                            color: statusColor,
                            fontWeight: FontWeight.w700,
                            fontSize: 11,
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            visibleName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: _waText,
                              height: 1.13,
                            ),
                          ),
                        ),
                        Text(
                          timeLabel,
                          style: TextStyle(
                            fontSize: 10,
                            color: item.unreadCount > 0 ? _waGreenDark : _waTextMuted,
                            fontWeight: item.unreadCount > 0 ? FontWeight.w600 : FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      previewText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        color: _waTextMuted,
                        height: 1.13,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        if (showStatus)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: statusColor.withAlpha(18),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              statusLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 8.5,
                                color: statusColor,
                                fontWeight: FontWeight.w600,
                                height: 1,
                              ),
                            ),
                          ),
                        const Spacer(),
                        if (item.unreadCount > 0)
                          Container(
                            constraints: const BoxConstraints(minWidth: 16),
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: _waGreenDark,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              '${item.unreadCount}',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 9,
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
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
      ),
    );
  }
}

class _CrmQuickReplyTemplate {
  const _CrmQuickReplyTemplate({
    required this.id,
    required this.label,
    required this.text,
  });

  final String id;
  final String label;
  final String text;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'label': label,
      'text': text,
    };
  }

  factory _CrmQuickReplyTemplate.fromMap(Map<String, dynamic> map) {
    return _CrmQuickReplyTemplate(
      id: (map['id'] ?? '').toString(),
      label: (map['label'] ?? '').toString(),
      text: (map['text'] ?? '').toString(),
    );
  }
}

class _CrmTimelineEntry {
  const _CrmTimelineEntry({
    required this.title,
    required this.subtitle,
    required this.author,
    required this.createdAt,
    required this.icon,
    required this.isOutgoing,
    required this.messageType,
    this.mediaUrl,
    this.caption,
    this.messageId,
    this.mediaStorageKey,
    this.mediaStatus,
    this.mediaMimeType,
    this.originalFileName,
    this.mediaFileSize,
  });

  final String title;
  final String subtitle;
  final String author;
  final DateTime? createdAt;
  final IconData icon;
  final bool isOutgoing;
  final String messageType;
  final String? mediaUrl;
  final String? caption;
  final String? messageId;
  final String? mediaStorageKey;
  final String? mediaStatus;
  final String? mediaMimeType;
  final String? originalFileName;
  final int? mediaFileSize;
}

class _CrmTimelineTile extends StatelessWidget {
  const _CrmTimelineTile({required this.entry});

  final _CrmTimelineEntry entry;

  // Builds the appropriate media widget based on messageType.
  // Wraps the entry fields back into a CrmComercialInboxMessage for the ConsumerStatefulWidgets.
  Widget _buildMediaContent() {
    final msgId = entry.messageId;
    if (msgId == null) return const SizedBox.shrink();
    final msg = CrmComercialInboxMessage(
      id: msgId,
      direction: entry.isOutgoing ? 'OUTGOING' : 'INCOMING',
      messageType: entry.messageType,
      body: entry.title,
      caption: entry.caption,
      mediaUrl: entry.mediaUrl,
      mediaMimeType: entry.mediaMimeType,
      senderName: entry.author,
      sentAt: entry.createdAt,
      mediaStorageKey: entry.mediaStorageKey,
      mediaStatus: entry.mediaStatus,
      originalFileName: entry.originalFileName,
      mediaFileSize: entry.mediaFileSize,
    );
    switch (entry.messageType.toUpperCase()) {
      case 'IMAGE':
        return _CrmImageContent(msg: msg, textColor: _waText);
      case 'AUDIO':
        return _CrmAudioContent(msg: msg, textColor: _waText);
      case 'VIDEO':
        return _CrmVideoContent(msg: msg, textColor: _waText);
      default:
        return _CrmDocumentContent(msg: msg, textColor: _waText);
    }
  }

  @override
  Widget build(BuildContext context) {
    final maxBubbleWidth = MediaQuery.of(context).size.width < 900 ? 320.0 : 760.0;
    final bubbleColor = entry.isOutgoing
        ? const Color(0xFFD9FDD3)
        : Colors.white.withAlpha(235);
    final bubbleRadius = BorderRadius.only(
      topLeft: const Radius.circular(12),
      topRight: const Radius.circular(12),
      bottomLeft: Radius.circular(entry.isOutgoing ? 12 : 4),
      bottomRight: Radius.circular(entry.isOutgoing ? 4 : 12),
    );

    return Row(
      mainAxisAlignment:
          entry.isOutgoing ? MainAxisAlignment.end : MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxBubbleWidth),
          child: Container(
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 5),
            decoration: BoxDecoration(
              color: bubbleColor,
              borderRadius: bubbleRadius,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(10),
                  blurRadius: 3,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Render multimedia if present
                if (entry.messageType.toUpperCase() != 'TEXT' && entry.messageId != null) ...[
                  _buildMediaContent(),
                  if (entry.caption?.isNotEmpty == true)
                    const SizedBox(height: 6),
                ],
                // Text content
                if (entry.messageType.toUpperCase() == 'TEXT' && entry.title.isNotEmpty)
                  Text(
                    entry.title,
                    style: const TextStyle(
                      fontSize: 13,
                      color: _waText,
                      height: 1.3,
                    ),
                  ),
                // Caption (if exists)
                if (entry.caption?.isNotEmpty == true) ...[
                  const SizedBox(height: 4),
                  Text(
                    entry.caption!,
                    style: const TextStyle(
                      fontSize: 12,
                      color: _waText,
                      fontStyle: FontStyle.italic,
                      height: 1.2,
                    ),
                  ),
                ],
                const SizedBox(height: 3),
                Align(
                  alignment: Alignment.bottomRight,
                  child: Text(
                    entry.createdAt == null
                        ? 'Sin fecha'
                        : DateFormat('HH:mm').format(entry.createdAt!),
                    style: const TextStyle(fontSize: 9.5, color: _waTextMuted),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

  // ─── CRM Comercial Media Widgets ──────────────────────────────────────────────

  class _CrmMediaUnavailable extends StatelessWidget {
    const _CrmMediaUnavailable({
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
                'Reintentar',
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

  class _CrmImageContent extends ConsumerStatefulWidget {
    const _CrmImageContent({required this.msg, required this.textColor});
    final CrmComercialInboxMessage msg;
    final Color textColor;
    @override
    ConsumerState<_CrmImageContent> createState() => _CrmImageContentState();
  }

  class _CrmImageContentState extends ConsumerState<_CrmImageContent> {
    Future<Uint8List>? _bytesFuture;
    String? _url;

    @override
    void initState() {
      super.initState();
      _setFutureIfNeeded();
    }

    @override
    void didUpdateWidget(covariant _CrmImageContent oldWidget) {
      super.didUpdateWidget(oldWidget);
      if (oldWidget.msg.id != widget.msg.id ||
          oldWidget.msg.mediaUrl != widget.msg.mediaUrl) {
        _setFutureIfNeeded();
      }
    }

    void _setFutureIfNeeded() {
      _url = _mediaUrlForCrmMsg(widget.msg);
      if (_url == null || widget.msg.mediaFailed) {
        _bytesFuture = null;
        return;
      }
      final downloadBytes =
          ref.read(crmComercialRepositoryProvider).downloadMediaBytes;
      _bytesFuture = _crmBytesFromMediaUrl(_url!, downloadBytes: downloadBytes);
    }

    @override
    Widget build(BuildContext context) {
      final downloadBytes =
          ref.read(crmComercialRepositoryProvider).downloadMediaBytes;
      if (widget.msg.mediaFailed) {
        return _CrmMediaUnavailable(
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
            _CrmMediaUnavailable(
              icon: Icons.image_not_supported_outlined,
              textColor: widget.textColor,
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
      final imageFuture = _crmBytesFromMediaUrl(url, downloadBytes: downloadBytes);
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

  class _CrmAudioContent extends ConsumerStatefulWidget {
    const _CrmAudioContent({required this.msg, required this.textColor});
    final CrmComercialInboxMessage msg;
    final Color textColor;
    @override
    ConsumerState<_CrmAudioContent> createState() => _CrmAudioContentState();
  }

  class _CrmAudioContentState extends ConsumerState<_CrmAudioContent> {
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
        final url = _mediaUrlForCrmMsg(widget.msg);
        if (url == null) throw Exception('Sin URL de audio');
        final source = await _crmMediaSourceForPlayback(
          url,
          widget.msg.mediaMimeType,
          downloadBytes: ref.read(crmComercialRepositoryProvider).downloadMediaBytes,
        );
        final player = media_kit.Player();
        await player.setVolume(100);
        _playingSub = player.stream.playing.listen((v) {
          if (mounted) setState(() => _playing = v);
        });
        _positionSub = player.stream.position.listen((v) {
          if (mounted) setState(() => _position = v);
        });
        _durationSub = player.stream.duration.listen((v) {
          if (mounted) setState(() => _duration = v);
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
      return maxWidth.clamp(_minPlayerWidth, _maxPlayerWidth);
    }

    Future<void> _seekFromLocalDx(double dx, double width) async {
      final player = _player;
      if (player == null || _duration <= Duration.zero || width <= 0) return;
      final progress = (dx / width).clamp(0.0, 1.0);
      await player.seek(
        Duration(milliseconds: (progress * _duration.inMilliseconds).round()),
      );
    }

    @override
    Widget build(BuildContext context) {
      final color = widget.textColor;
      if (_mediaUrlForCrmMsg(widget.msg) == null || widget.msg.mediaFailed) {
        return _CrmMediaUnavailable(icon: Icons.mic_off_rounded, textColor: color);
      }
      if (_error != null) {
        return _CrmMediaUnavailable(
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
                            widget.msg.originalFileName ?? 'Audio',
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
                          _CrmStaticWaveform(color: color),
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
                          final thumbTravel =
                              (barWidth - 10).clamp(0.0, barWidth);
                          return GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTapDown: (d) =>
                                _seekFromLocalDx(d.localPosition.dx, barWidth),
                            onHorizontalDragUpdate: (d) =>
                                _seekFromLocalDx(d.localPosition.dx, barWidth),
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
                                        borderRadius:
                                            BorderRadius.circular(999),
                                      ),
                                    ),
                                    FractionallySizedBox(
                                      widthFactor: progress.toDouble(),
                                      child: Container(
                                        height: 3,
                                        decoration: BoxDecoration(
                                          color: color,
                                          borderRadius:
                                              BorderRadius.circular(999),
                                        ),
                                      ),
                                    ),
                                    Positioned(
                                      left: (thumbTravel * progress).clamp(
                                          0.0, thumbTravel),
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

  class _CrmStaticWaveform extends StatelessWidget {
    const _CrmStaticWaveform({required this.color});
    final Color color;
    static const _heights = [
      4.0, 8.0, 12.0, 6.0, 14.0, 8.0, 10.0, 6.0,
      4.0, 12.0, 8.0, 14.0, 6.0, 10.0, 8.0, 4.0, 12.0, 6.0,
    ];
    @override
    Widget build(BuildContext context) {
      return LayoutBuilder(
        builder: (context, constraints) {
          final availableWidth = constraints.hasBoundedWidth
              ? constraints.maxWidth
              : _heights.length * 5.0;
          final visibleCount =
              (availableWidth / 5).floor().clamp(4, _heights.length);
          final heights = _heights.take(visibleCount).toList(growable: false);
          return SizedBox(
            height: 16,
            child: Row(
              mainAxisSize: MainAxisSize.max,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                for (var i = 0; i < heights.length; i++) ...[
                  Flexible(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        width: 3,
                        height: heights[i].clamp(3.0, 14.0),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),
                  if (i < heights.length - 1) const SizedBox(width: 2),
                ],
              ],
            ),
          );
        },
      );
    }
  }

  class _CrmVideoContent extends ConsumerStatefulWidget {
    const _CrmVideoContent({required this.msg, required this.textColor});
    final CrmComercialInboxMessage msg;
    final Color textColor;
    @override
    ConsumerState<_CrmVideoContent> createState() => _CrmVideoContentState();
  }

  class _CrmVideoContentState extends ConsumerState<_CrmVideoContent> {
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
      final mediaUrl = _mediaUrlForCrmMsg(widget.msg);
      if (mediaUrl == null) return;
      setState(() => _loading = true);
      try {
        final source = await _crmMediaSourceForPlayback(
          mediaUrl,
          widget.msg.mediaMimeType ?? 'video/mp4',
          downloadBytes: ref.read(crmComercialRepositoryProvider).downloadMediaBytes,
        );
        final player = media_kit.Player();
        await player.setVolume(100);
        final controller = media_kit_video.VideoController(player);
        _playingSub = player.stream.playing.listen((v) {
          if (mounted) setState(() => _playing = v);
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
        if (mounted) setState(() { _loading = false; _error = e.toString(); });
      }
    }

    Future<void> _togglePlayPause() async {
      final player = _player;
      if (player == null) return;
      if (_playing) { await player.pause(); } else { await player.play(); }
    }

    @override
    Widget build(BuildContext context) {
      final color = widget.textColor;
      final controller = _videoController;
      if (_mediaUrlForCrmMsg(widget.msg) == null || widget.msg.mediaFailed) {
        return _CrmMediaUnavailable(
          icon: Icons.videocam_off_outlined,
          textColor: color,
        );
      }
      return ClipRRect(
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
      );
    }
  }

  class _CrmDocumentContent extends ConsumerStatefulWidget {
    const _CrmDocumentContent({required this.msg, required this.textColor});
    final CrmComercialInboxMessage msg;
    final Color textColor;
    @override
    ConsumerState<_CrmDocumentContent> createState() => _CrmDocumentContentState();
  }

  class _CrmDocumentContentState extends ConsumerState<_CrmDocumentContent> {
    bool _loading = false;

    Future<void> _open() async {
      final mediaUrl = _mediaUrlForCrmMsg(widget.msg);
      if (mediaUrl == null) return;
      setState(() => _loading = true);
      await _crmOpenMedia(
        mediaUrl,
        widget.msg.mediaMimeType,
        downloadBytes: ref.read(crmComercialRepositoryProvider).downloadMediaBytes,
      );
      if (mounted) setState(() => _loading = false);
    }

    @override
    Widget build(BuildContext context) {
      final color = widget.textColor;
      final mediaUrl = _mediaUrlForCrmMsg(widget.msg);
      if (mediaUrl == null || widget.msg.mediaFailed) {
        return _CrmMediaUnavailable(
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
              widget.msg.originalFileName ??
                  widget.msg.body ??
                  'Documento',
              style: TextStyle(color: color, fontSize: 13),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: _open,
            child: Icon(Icons.download_rounded, color: color, size: 16),
          ),
        ],
      );
    }
  }
