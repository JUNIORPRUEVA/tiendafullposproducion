import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
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

class CrmComercialScreen extends ConsumerStatefulWidget {
  const CrmComercialScreen({super.key});

  @override
  ConsumerState<CrmComercialScreen> createState() => _CrmComercialScreenState();
}

class _CrmComercialScreenState extends ConsumerState<CrmComercialScreen> {
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
  bool _showDetailsPanel = true;
  bool _mobileConversationMode = false;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _noteCtrl.dispose();
    _nextActionCtrl.dispose();
    _activityTypeCtrl.dispose();
    _activityDescriptionCtrl.dispose();
    _taskTitleCtrl.dispose();
    _taskDescCtrl.dispose();
    super.dispose();
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

  String _crmInstanceStatusText() {
    final settings = _crmSettings;
    if (settings == null) return 'Cargando configuracion de instancia...';
    if ((settings.selectedWhatsappInstanceId ?? '').trim().isEmpty) {
      return 'Selecciona una instancia para recibir mensajes reales.';
    }
    if (settings.selectedInstanceExists == false) {
      return 'La instancia seleccionada ya no existe. Configura una nueva instancia.';
    }
    final name = (settings.selectedWhatsappInstanceName ?? '').trim();
    if (name.isEmpty) {
      return settings.enabled
          ? 'Instancia activa configurada.'
          : 'Instancia configurada (mensajes reales desactivados).';
    }
    if (!settings.enabled) {
      return 'Instancia activa: $name (desactivada)';
    }
    return 'Instancia activa: $name';
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

  void _showConvertPlaceholder() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Proximamente: convertir contacto WhatsApp a cliente CRM comercial.',
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
    final selected = _selected;
    return Scaffold(
      backgroundColor: _waBg,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _buildCrmShell(context, selected),
    );
  }

  Widget _buildCrmShell(BuildContext context, CrmComercialCustomer? selected) {
    final activeTaskCountByCustomer = <String, int>{};
    for (final task in _allTasks) {
      if (!task.isActive) continue;
      activeTaskCountByCustomer[task.customerId] =
          (activeTaskCountByCustomer[task.customerId] ?? 0) + 1;
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final isMobile = width < 900;
          final isTablet = width >= 900 && width < 1280;

          if (isMobile) {
            if (!_mobileConversationMode || _selectedConversation == null) {
              return _buildSidebarPanel(
                context,
                selected: selected,
                activeTaskCountByCustomer: activeTaskCountByCustomer,
                isMobile: true,
              );
            }
            return _buildConversationPanel(
              context,
              selected,
              _selectedConversation,
              allowDetailToggle: true,
              isMobile: true,
              onBackToList: () {
                setState(() => _mobileConversationMode = false);
              },
            );
          }

          final leftWidth = isTablet ? 320.0 : 360.0;
          final rightWidth = _showDetailsPanel
              ? (isTablet ? 320.0 : 360.0)
              : 56.0;

          return Row(
            children: [
              SizedBox(
                width: leftWidth,
                child: _buildSidebarPanel(
                  context,
                  selected: selected,
                  activeTaskCountByCustomer: activeTaskCountByCustomer,
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
                  isMobile: false,
                ),
              ),
              const SizedBox(width: 8),
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                width: rightWidth,
                child: _buildDetailsPanel(
                  context,
                  selected,
                  compact: !_showDetailsPanel,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSidebarPanel(
    BuildContext context, {
    required CrmComercialCustomer? selected,
    required Map<String, int> activeTaskCountByCustomer,
    required bool isMobile,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: _waSidebar,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _waBorder.withAlpha(120)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: BoxDecoration(
              color: const Color(0xFFF7F8F8),
              border: Border(
                bottom: BorderSide(color: _waBorder.withAlpha(110)),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: _waGreen.withAlpha(26),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: const Icon(
                    Icons.business_rounded,
                    color: _waGreenDark,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text(
                        'FULLTECH Comercial',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: _waText,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'CRM en tiempo real',
                        style: TextStyle(fontSize: 11, color: _waTextMuted),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Configurar instancia WhatsApp CRM',
                  onPressed: _saving ? null : _openCrmSettingsDialog,
                  icon: const Icon(Icons.tune_rounded, size: 20),
                ),
                IconButton(
                  tooltip: 'Actualizar',
                  onPressed: _saving ? null : _loadAll,
                  icon: const Icon(Icons.refresh_rounded, size: 20),
                ),
              ],
            ),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
            decoration: BoxDecoration(
              color: _crmInstanceWarning
                  ? Colors.amber.withAlpha(24)
                  : _waGreen.withAlpha(12),
              border: Border(
                bottom: BorderSide(color: _waBorder.withAlpha(90)),
              ),
            ),
            child: Text(
              _crmInstanceStatusText(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: _crmInstanceWarning ? const Color(0xFF8A5800) : _waGreenDark,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
            child: Column(
              children: [
                TextField(
                  controller: _searchCtrl,
                  onSubmitted: (_) => _loadAll(),
                  decoration: InputDecoration(
                    hintText: 'Buscar cliente o telefono',
                    prefixIcon: const Icon(Icons.search_rounded, size: 20),
                    isDense: true,
                    filled: true,
                    fillColor: const Color(0xFFF6F7F7),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: _waBorder.withAlpha(110)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: _waBorder.withAlpha(110)),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        key: ValueKey('status-filter-$_statusFilter'),
                        initialValue: _statusFilter,
                        decoration: InputDecoration(
                          labelText: 'Estado',
                          isDense: true,
                          filled: true,
                          fillColor: const Color(0xFFF6F7F7),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(
                              color: _waBorder.withAlpha(110),
                            ),
                          ),
                        ),
                        items: [
                          const DropdownMenuItem<String>(
                            value: '',
                            child: Text('Todos'),
                          ),
                          ..._crmStatuses.map(
                            (status) => DropdownMenuItem<String>(
                              value: status,
                              child: Text(_statusLabel(status)),
                            ),
                          ),
                        ],
                        onChanged: (value) {
                          setState(() {
                            _statusFilter = (value ?? '').trim();
                          });
                          _loadAll();
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilterChip(
                      selected: _onlyMine,
                      showCheckmark: false,
                      side: BorderSide(color: _waBorder.withAlpha(100)),
                      backgroundColor: const Color(0xFFF6F7F7),
                      selectedColor: _waGreen.withAlpha(20),
                      visualDensity: VisualDensity.compact,
                      label: const Text('Mio'),
                      onSelected: (value) {
                        setState(() => _onlyMine = value);
                        _loadAll();
                      },
                    ),
                  ],
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
            child: _conversations.isEmpty
                ? Center(
                    child: Text(
                      _conversationWarning ??
                          'Sin conversaciones para la instancia seleccionada.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 12, color: _waTextMuted),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.only(bottom: 8),
                    itemCount: _conversations.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 1),
                    itemBuilder: (context, index) {
                      final item = _conversations[index];
                      final isActive = _selectedConversation?.id == item.id;
                      final taskCount = item.crmCustomerId == null
                          ? 0
                          : (activeTaskCountByCustomer[item.crmCustomerId!] ?? 0);
                      return _CrmConversationListItem(
                        item: item,
                        isActive: isActive,
                        taskCount: taskCount,
                        statusLabel: item.crmCustomerStatus == null
                            ? 'SIN CRM'
                            : _statusLabel(item.crmCustomerStatus!),
                        statusColor: item.crmCustomerStatus == null
                            ? const Color(0xFF7A8A96)
                            : _statusAccentColor(item.crmCustomerStatus!),
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
        ],
      ),
    );
  }

  Widget _buildConversationPanel(
    BuildContext context,
    CrmComercialCustomer? selected,
    CrmComercialInboxConversation? selectedConversation, {
    required bool allowDetailToggle,
    required bool isMobile,
    VoidCallback? onBackToList,
  }) {
    final hasSelection = selected != null;
    final hasConversation = selectedConversation != null;
    final timeline =
        _messages
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
              ),
            )
            .toList(growable: false);

    return Container(
      decoration: BoxDecoration(
        color: _waPanel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _waBorder.withAlpha(110)),
      ),
      child: Column(
        children: [
          Container(
            height: 68,
            padding: const EdgeInsets.symmetric(horizontal: 12),
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
                CircleAvatar(
                  radius: 18,
                  backgroundColor: _waGreen.withAlpha(24),
                  child: Text(
                    _initials(selectedConversation?.contactName ?? 'CRM'),
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: _waGreenDark,
                      fontSize: 12,
                    ),
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
                      Text(
                        hasConversation
                            ? '${selectedConversation.remotePhone ?? selectedConversation.remoteJid ?? 'Sin telefono'}  |  ${selectedConversation.crmCustomerName ?? 'Nuevo contacto'}'
                            : 'Selecciona una conversacion para ver mensajes reales',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          color: _waTextMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                if (selectedConversation?.isNewContact == true)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.orange.withAlpha(22),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'Nuevo contacto',
                      style: TextStyle(fontSize: 10, color: Color(0xFF9A5C00)),
                    ),
                  ),
                const SizedBox(width: 6),
                if (selectedConversation?.canConvertToCrm == true)
                  TextButton.icon(
                    onPressed: _saving ? null : _showConvertPlaceholder,
                    icon: const Icon(Icons.person_add_alt_1_rounded, size: 16),
                    label: const Text('Convertir en cliente CRM'),
                  ),
                IconButton(
                  tooltip: 'Actualizar conversacion',
                  onPressed: !hasConversation || _saving
                      ? null
                      : () => _openConversation(selectedConversation.id),
                  icon: const Icon(Icons.refresh_rounded, size: 20),
                ),
                if (allowDetailToggle)
                  IconButton(
                    tooltip: _showDetailsPanel
                        ? 'Ocultar panel derecho'
                        : 'Mostrar panel derecho',
                    onPressed: () {
                      setState(() => _showDetailsPanel = !_showDetailsPanel);
                    },
                    icon: Icon(
                      _showDetailsPanel
                          ? Icons.view_sidebar_rounded
                          : Icons.dashboard_customize_rounded,
                      size: 20,
                    ),
                  ),
              ],
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
                        child: SvgPicture.asset(
                          'assets/image/wa_bg_light.svg',
                          fit: BoxFit.cover,
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
                  ListView.builder(
                    padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
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
                          const SizedBox(height: 8),
                        ],
                      );
                    },
                  ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            decoration: BoxDecoration(
              color: const Color(0xFFF7F8F8),
              border: Border(top: BorderSide(color: _waBorder.withAlpha(110))),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _noteCtrl,
                        minLines: 1,
                        maxLines: 2,
                        decoration: const InputDecoration(
                          hintText: 'Escribir nota interna',
                          isDense: true,
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(
                            borderSide: BorderSide(color: _waBorder),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: !hasSelection || _saving ? null : _addNote,
                      icon: const Icon(Icons.send_rounded, size: 16),
                      label: const Text('Nota'),
                      style: FilledButton.styleFrom(
                        backgroundColor: _waGreenDark,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    SizedBox(
                      width: 140,
                      child: TextField(
                        controller: _activityTypeCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Tipo',
                          isDense: true,
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(
                            borderSide: BorderSide(color: _waBorder),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _activityDescriptionCtrl,
                        minLines: 1,
                        maxLines: 2,
                        decoration: const InputDecoration(
                          hintText: 'Agregar actividad comercial',
                          isDense: true,
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(
                            borderSide: BorderSide(color: _waBorder),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: !hasSelection || _saving ? null : _addActivity,
                      style: FilledButton.styleFrom(
                        backgroundColor: _waGreenDark,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Actividad'),
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
  }) {
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
            onPressed: () => setState(() => _showDetailsPanel = true),
            icon: const Icon(Icons.chevron_left_rounded),
          ),
        ),
      );
    }

    if (selected == null) {
      return Container(
        decoration: BoxDecoration(
          color: _waPanel,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _waBorder.withAlpha(110)),
        ),
        child: const Center(
          child: Text(
            'Panel de detalle del cliente',
            style: AppTextStyles.subtitle,
          ),
        ),
      );
    }

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
              Row(
                children: [
                  const Text(
                    'Informacion del contacto',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: _waText,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Colapsar panel',
                    onPressed: () => setState(() => _showDetailsPanel = false),
                    icon: const Icon(Icons.chevron_right_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _InfoRow(label: 'Telefono', value: selected.telefono),
              _InfoRow(
                label: 'Ciudad',
                value: selected.ciudad ?? 'No definida',
              ),
              _InfoRow(
                label: 'Direccion',
                value: selected.direccion ?? 'No definida',
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                key: ValueKey(
                  'responsable-${selected.id}-${selected.responsable?.id ?? ''}',
                ),
                initialValue: selected.responsable?.id,
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
                        selected: selected.estadoActual == status,
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
                'Estado actual: ${_statusLabel(selected.estadoActual)}',
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
              ...selected.statusHistory
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
    return DateFormat('dd MMM yyyy').format(value);
  }
}

class _DateSeparator extends StatelessWidget {
  const _DateSeparator({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.white.withAlpha(180),
          borderRadius: BorderRadius.circular(7),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w500,
            color: _waTextMuted,
          ),
        ),
      ),
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

class _CrmConversationListItem extends StatefulWidget {
  const _CrmConversationListItem({
    required this.item,
    required this.isActive,
    required this.taskCount,
    required this.statusLabel,
    required this.statusColor,
    this.onTap,
  });

  final CrmComercialInboxConversation item;
  final bool isActive;
  final int taskCount;
  final String statusLabel;
  final Color statusColor;
  final VoidCallback? onTap;

  @override
  State<_CrmConversationListItem> createState() =>
      _CrmConversationListItemState();
}

class _CrmConversationListItemState extends State<_CrmConversationListItem> {
  bool _hover = false;

  String _initials(String raw) {
    final parts = raw.trim().split(' ').where((e) => e.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return '${parts[0].substring(0, 1)}${parts[1].substring(0, 1)}'
        .toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final tileColor = widget.isActive
        ? _waSelected
        : _hover
        ? _waHover
        : Colors.transparent;

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            color: tileColor,
            child: Row(
              children: [
                if (widget.isActive)
                  Container(
                    width: 3,
                    height: 44,
                    margin: const EdgeInsets.only(right: 7),
                    decoration: BoxDecoration(
                      color: _waGreenDark,
                      borderRadius: BorderRadius.circular(8),
                    ),
                  )
                else
                  const SizedBox(width: 10),
                CircleAvatar(
                  radius: 18,
                  backgroundColor: widget.statusColor.withAlpha(26),
                  child: Text(
                    _initials(widget.item.contactName),
                    style: TextStyle(
                      color: widget.statusColor,
                      fontWeight: FontWeight.w700,
                      fontSize: 11,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              widget.item.contactName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: _waText,
                              ),
                            ),
                          ),
                          Text(
                            widget.item.lastMessageAt == null
                                ? '--:--'
                                : DateFormat(
                                    'HH:mm',
                                  ).format(widget.item.lastMessageAt!),
                            style: const TextStyle(
                              fontSize: 10,
                              color: _waTextMuted,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 1),
                      Text(
                        widget.item.lastMessagePreview?.isNotEmpty == true
                            ? widget.item.lastMessagePreview!
                            : (widget.item.remotePhone ?? 'Sin contenido'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          color: _waTextMuted,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: widget.statusColor.withAlpha(22),
                              borderRadius: BorderRadius.circular(7),
                            ),
                            child: Text(
                              widget.statusLabel,
                              style: TextStyle(
                                fontSize: 9,
                                color: widget.statusColor,
                              ),
                            ),
                          ),
                          if (widget.taskCount > 0) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.warning.withAlpha(20),
                                borderRadius: BorderRadius.circular(7),
                              ),
                              child: Text(
                                '${widget.taskCount} tarea${widget.taskCount == 1 ? '' : 's'}',
                                style: const TextStyle(
                                  fontSize: 9,
                                  color: AppColors.warning,
                                ),
                              ),
                            ),
                          ],
                          const Spacer(),
                          Text(
                            widget.item.crmCustomerName ??
                                (widget.item.isNewContact
                                    ? 'Nuevo contacto'
                                    : 'Sin vincular'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 9,
                              color: _waTextMuted,
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
      ),
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
  });

  final String title;
  final String subtitle;
  final String author;
  final DateTime? createdAt;
  final IconData icon;
  final bool isOutgoing;
  final String messageType;
}

class _CrmTimelineTile extends StatelessWidget {
  const _CrmTimelineTile({required this.entry});

  final _CrmTimelineEntry entry;

  @override
  Widget build(BuildContext context) {
    final bubbleColor = entry.isOutgoing
        ? const Color(0xFFD9FDD3)
        : Colors.white.withAlpha(220);

    return Row(
      mainAxisAlignment:
          entry.isOutgoing ? MainAxisAlignment.end : MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!entry.isOutgoing) ...[
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: _waGreen.withAlpha(16),
              borderRadius: BorderRadius.circular(7),
            ),
            child: Icon(entry.icon, size: 14, color: _waGreenDark),
          ),
          const SizedBox(width: 7),
        ],
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Container(
            padding: const EdgeInsets.fromLTRB(10, 7, 10, 7),
            decoration: BoxDecoration(
              color: bubbleColor,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${entry.subtitle} · ${entry.messageType}',
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: _waTextMuted,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  entry.title,
                  style: const TextStyle(fontSize: 12, color: _waText),
                ),
                const SizedBox(height: 5),
                Text(
                  '${entry.author} · ${entry.createdAt == null ? 'Sin fecha' : DateFormat('dd/MM HH:mm').format(entry.createdAt!)}',
                  style: const TextStyle(fontSize: 10, color: _waTextMuted),
                ),
              ],
            ),
          ),
        ),
        if (entry.isOutgoing) ...[
          const SizedBox(width: 7),
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: _waGreen.withAlpha(16),
              borderRadius: BorderRadius.circular(7),
            ),
            child: Icon(entry.icon, size: 14, color: _waGreenDark),
          ),
        ],
      ],
    );
  }
}
