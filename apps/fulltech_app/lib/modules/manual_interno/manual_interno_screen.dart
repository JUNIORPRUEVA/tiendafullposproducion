import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/app_permissions.dart';
import '../../core/auth/app_role.dart';
import '../../core/auth/auth_provider.dart';
import '../../core/widgets/app_drawer.dart';
import '../../core/errors/api_exception.dart';
import 'company_manual_models.dart';
import 'company_manual_repository.dart';

class ManualInternoScreen extends ConsumerStatefulWidget {
  const ManualInternoScreen({super.key});

  @override
  ConsumerState<ManualInternoScreen> createState() =>
      _ManualInternoScreenState();
}

class _ManualInternoScreenState extends ConsumerState<ManualInternoScreen> {
  final TextEditingController _searchCtrl = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  String? _error;
  List<CompanyManualEntry> _entries = const [];
  CompanyManualEntryKind? _kindFilter;
  String? _selectedEntryId;

  @override
  void initState() {
    super.initState();
    _loadEntries();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadEntries() async {
    final user = ref.read(authStateProvider).user;
    final canManage =
        user != null &&
        hasPermission(user.appRole, AppPermission.manageCompanyManual);

    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final repo = ref.read(companyManualRepositoryProvider);
      final items = await repo.listEntries(
        kind: _kindFilter,
        includeHidden: canManage,
      );

      DateTime? latest;
      for (final item in items) {
        final updatedAt = item.updatedAt ?? item.createdAt;
        if (updatedAt == null) continue;
        if (latest == null || updatedAt.isAfter(latest)) {
          latest = updatedAt;
        }
      }
      if (latest != null) {
        await repo.markSeen(latest);
        ref.invalidate(companyManualSummaryProvider);
      }

      final selectedId = items.any((item) => item.id == _selectedEntryId)
          ? _selectedEntryId
          : (items.isEmpty ? null : items.first.id);

      if (!mounted) return;
      setState(() {
        _entries = items;
        _loading = false;
        _selectedEntryId = selectedId;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is ApiException ? e.message : '$e';
        _loading = false;
      });
    }
  }

  List<CompanyManualEntry> get _visibleEntries {
    final query = _searchCtrl.text.trim().toLowerCase();
    if (query.isEmpty) return _entries;
    return _entries
        .where((item) {
          return item.title.toLowerCase().contains(query) ||
              (item.summary ?? '').toLowerCase().contains(query) ||
              item.content.toLowerCase().contains(query) ||
              (item.moduleKey ?? '').toLowerCase().contains(query);
        })
        .toList(growable: false);
  }

  Future<bool> _openEditor({CompanyManualEntry? entry}) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _CompanyManualEntryDialog(entry: entry),
    );
    if (saved == true) {
      await _loadEntries();
      return true;
    }
    return false;
  }

  Future<bool> _deleteEntry(CompanyManualEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar entrada'),
        content: Text('¿Deseas eliminar "${entry.title}"?'),
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
    if (confirmed != true) return false;

    setState(() => _saving = true);
    try {
      await ref.read(companyManualRepositoryProvider).deleteEntry(entry.id);
      await _loadEntries();
      return true;
    } catch (e) {
      if (!mounted) return false;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('No se pudo eliminar: $e')));
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  CompanyManualEntry? _resolveSelectedEntry(List<CompanyManualEntry> entries) {
    if (entries.isEmpty) return null;
    for (final entry in entries) {
      if (entry.id == _selectedEntryId) return entry;
    }
    return entries.first;
  }

  List<_ManualSectionData> _buildSections(List<CompanyManualEntry> entries) {
    final sections = <_ManualSectionData>[];
    for (final kind in CompanyManualEntryKind.values) {
      final items = entries.where((entry) => entry.kind == kind).toList();
      if (items.isEmpty) continue;
      items.sort((a, b) {
        final byOrder = a.sortOrder.compareTo(b.sortOrder);
        if (byOrder != 0) return byOrder;
        return a.title.toLowerCase().compareTo(b.title.toLowerCase());
      });
      sections.add(_ManualSectionData(kind: kind, entries: items));
    }
    return sections;
  }

  void _openEntryDetail(CompanyManualEntry entry, bool canManage) {
    final width = MediaQuery.of(context).size.width;
    if (width >= 980) {
      setState(() => _selectedEntryId = entry.id);
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _ManualEntryDetailScreen(
          entry: entry,
          canManage: canManage,
          onEdit: canManage
              ? () async {
                  final saved = await _openEditor(entry: entry);
                  if (saved && mounted && context.mounted) {
                    Navigator.of(context).pop();
                  }
                }
              : null,
          onDelete: canManage
              ? () async {
                  final deleted = await _deleteEntry(entry);
                  if (deleted && mounted && context.mounted) {
                    Navigator.of(context).pop();
                  }
                }
              : null,
        ),
      ),
    );
  }

  String _formatDate(DateTime? value) {
    if (value == null) return 'Sin fecha';
    final day = value.day.toString().padLeft(2, '0');
    final month = value.month.toString().padLeft(2, '0');
    final year = value.year.toString();
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '$day/$month/$year $hour:$minute';
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authStateProvider).user;
    final canManage =
        user != null &&
        hasPermission(user.appRole, AppPermission.manageCompanyManual);
    final entries = _visibleEntries;
    final sections = _buildSections(entries);
    final selectedEntry = _resolveSelectedEntry(entries);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Manual Interno'),
        actions: [
          IconButton(
            tooltip: 'Recargar',
            onPressed: _loading ? null : _loadEntries,
            icon: const Icon(Icons.refresh),
          ),
          if (canManage)
            IconButton(
              tooltip: 'Nueva entrada',
              onPressed: () => _openEditor(),
              icon: const Icon(Icons.add),
            ),
        ],
      ),
      drawer: buildAdaptiveDrawer(context, currentUser: user),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Theme.of(context).colorScheme.primary.withValues(alpha: 0.07),
              Theme.of(context).scaffoldBackgroundColor,
              Theme.of(context).colorScheme.surface,
            ],
          ),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: _ManualOverviewHeader(
                totalTopics: entries.length,
                totalSections: sections.length,
                selectedFilter: _kindFilter?.label ?? 'Todo el manual',
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                controller: _searchCtrl,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'Buscar reglas, políticas, guías o módulos...',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searchCtrl.text.isEmpty
                      ? null
                      : IconButton(
                          onPressed: () {
                            _searchCtrl.clear();
                            setState(() {});
                          },
                          icon: const Icon(Icons.close),
                        ),
                ),
              ),
            ),
            SizedBox(
              height: 52,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: const Text('Todo'),
                      selected: _kindFilter == null,
                      onSelected: (_) {
                        setState(() => _kindFilter = null);
                        _loadEntries();
                      },
                    ),
                  ),
                  for (final kind in CompanyManualEntryKind.values)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(kind.label),
                        selected: _kindFilter == kind,
                        onSelected: (_) {
                          setState(() => _kindFilter = kind);
                          _loadEntries();
                        },
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                  ? Center(child: Text(_error!))
                  : entries.isEmpty
                  ? const Center(child: Text('No hay temas para mostrar'))
                  : RefreshIndicator(
                      onRefresh: _loadEntries,
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final isWide = constraints.maxWidth >= 980;
                          final listPane = _ManualSectionsList(
                            sections: sections,
                            selectedEntryId: selectedEntry?.id,
                            canManage: canManage,
                            onOpenEntry: (entry) =>
                                _openEntryDetail(entry, canManage),
                            onEditEntry: (entry) => _openEditor(entry: entry),
                            onDeleteEntry: _deleteEntry,
                            formatDate: _formatDate,
                          );

                          if (!isWide) {
                            return listPane;
                          }

                          return Padding(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                            child: _ManualDesktopSplitView(
                              entries: entries,
                              selectedEntry: selectedEntry,
                              selectedFilter:
                                  _kindFilter?.label ?? 'Todo el manual',
                              canManage: canManage,
                              onOpenEntry: (entry) =>
                                  _openEntryDetail(entry, canManage),
                              onEditEntry: (entry) => _openEditor(entry: entry),
                              onDeleteEntry: _deleteEntry,
                              formatDate: _formatDate,
                            ),
                          );
                        },
                      ),
                    ),
            ),
          ],
        ),
      ),
      floatingActionButton: canManage
          ? FloatingActionButton.extended(
              onPressed: _saving ? null : () => _openEditor(),
              icon: const Icon(Icons.add),
              label: const Text('Nueva entrada'),
            )
          : null,
    );
  }
}

class _ManualOverviewHeader extends StatelessWidget {
  const _ManualOverviewHeader({
    required this.totalTopics,
    required this.totalSections,
    required this.selectedFilter,
  });

  final int totalTopics;
  final int totalSections;
  final String selectedFilter;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          colors: [scheme.primary, const Color(0xFF0F172A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: scheme.primary.withValues(alpha: 0.18),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Wrap(
        runSpacing: 16,
        spacing: 16,
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Manual interno por secciones',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Explora los temas por tarjetas, entra al detalle y consulta cada regla o guía con más claridad.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: Colors.white.withValues(alpha: 0.82),
                  ),
                ),
              ],
            ),
          ),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _ManualMetricChip(
                icon: Icons.layers_outlined,
                label: 'Secciones',
                value: '$totalSections',
              ),
              _ManualMetricChip(
                icon: Icons.article_outlined,
                label: 'Temas',
                value: '$totalTopics',
              ),
              _ManualMetricChip(
                icon: Icons.tune_outlined,
                label: 'Filtro',
                value: selectedFilter,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ManualMetricChip extends StatelessWidget {
  const _ManualMetricChip({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 18),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Colors.white.withValues(alpha: 0.75),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ManualDesktopSplitView extends StatelessWidget {
  const _ManualDesktopSplitView({
    required this.entries,
    required this.selectedEntry,
    required this.selectedFilter,
    required this.canManage,
    required this.onOpenEntry,
    required this.onEditEntry,
    required this.onDeleteEntry,
    required this.formatDate,
  });

  final List<CompanyManualEntry> entries;
  final CompanyManualEntry? selectedEntry;
  final String selectedFilter;
  final bool canManage;
  final ValueChanged<CompanyManualEntry> onOpenEntry;
  final Future<bool> Function(CompanyManualEntry entry) onEditEntry;
  final Future<bool> Function(CompanyManualEntry entry) onDeleteEntry;
  final String Function(DateTime? value) formatDate;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 430,
          child: Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 20,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Normas y guias',
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Selecciona una tarjeta para abrir automaticamente el detalle completo.',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      _ManualMetricChip(
                        icon: Icons.article_outlined,
                        label: 'Visibles',
                        value: '${entries.length}',
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: _ManualDesktopBadge(label: selectedFilter),
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    itemCount: entries.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final entry = entries[index];
                      return _ManualDesktopEntryTile(
                        entry: entry,
                        selected: entry.id == selectedEntry?.id,
                        canManage: canManage,
                        onTap: () => onOpenEntry(entry),
                        onEdit: () => onEditEntry(entry),
                        onDelete: () => onDeleteEntry(entry),
                        formatDate: formatDate,
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 18),
        Expanded(
          child: Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 16,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        selectedEntry?.title ?? 'Detalle de la norma',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ),
                    if (selectedEntry != null) ...[
                      _ManualDesktopBadge(label: selectedEntry!.kind.label),
                      const SizedBox(width: 8),
                      _ManualDesktopBadge(label: selectedEntry!.audience.label),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: _ManualEntryDetailPane(
                  entry: selectedEntry,
                  canManage: canManage,
                  onEdit: selectedEntry == null
                      ? null
                      : () => onEditEntry(selectedEntry!),
                  onDelete: selectedEntry == null
                      ? null
                      : () => onDeleteEntry(selectedEntry!),
                  formatDate: formatDate,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ManualDesktopEntryTile extends StatelessWidget {
  const _ManualDesktopEntryTile({
    required this.entry,
    required this.selected,
    required this.canManage,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
    required this.formatDate,
  });

  final CompanyManualEntry entry;
  final bool selected;
  final bool canManage;
  final VoidCallback onTap;
  final Future<bool> Function() onEdit;
  final Future<bool> Function() onDelete;
  final String Function(DateTime? value) formatDate;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final updatedAt = entry.updatedAt ?? entry.createdAt;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            color: selected
                ? scheme.primary.withValues(alpha: 0.08)
                : scheme.surfaceContainerLowest,
            border: Border.all(
              color: selected
                  ? scheme.primary.withValues(alpha: 0.45)
                  : scheme.outlineVariant,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _ManualDesktopBadge(label: entry.kind.label),
                            if (entry.moduleKey != null &&
                                entry.moduleKey!.isNotEmpty)
                              _ManualDesktopBadge(
                                label: 'Modulo ${entry.moduleKey}',
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (canManage)
                    PopupMenuButton<String>(
                      onSelected: (value) async {
                        if (value == 'edit') {
                          await onEdit();
                        } else if (value == 'delete') {
                          await onDelete();
                        }
                      },
                      itemBuilder: (context) => const [
                        PopupMenuItem(value: 'edit', child: Text('Editar')),
                        PopupMenuItem(value: 'delete', child: Text('Eliminar')),
                      ],
                    ),
                ],
              ),
              if (entry.summary != null && entry.summary!.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  entry.summary!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurface.withValues(alpha: 0.74),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Actualizado ${formatDate(updatedAt)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    selected
                        ? Icons.visibility_outlined
                        : Icons.arrow_forward_rounded,
                    color: scheme.primary,
                    size: 18,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ManualDesktopBadge extends StatelessWidget {
  const _ManualDesktopBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: scheme.primary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _ManualSectionsList extends StatelessWidget {
  const _ManualSectionsList({
    required this.sections,
    required this.selectedEntryId,
    required this.canManage,
    required this.onOpenEntry,
    required this.onEditEntry,
    required this.onDeleteEntry,
    required this.formatDate,
  });

  final List<_ManualSectionData> sections;
  final String? selectedEntryId;
  final bool canManage;
  final ValueChanged<CompanyManualEntry> onOpenEntry;
  final Future<bool> Function(CompanyManualEntry entry) onEditEntry;
  final Future<bool> Function(CompanyManualEntry entry) onDeleteEntry;
  final String Function(DateTime? value) formatDate;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      itemCount: sections.length,
      itemBuilder: (context, index) {
        final section = sections[index];
        return Padding(
          padding: EdgeInsets.only(
            bottom: index == sections.length - 1 ? 0 : 20,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ManualSectionHeader(section: section),
              const SizedBox(height: 12),
              for (final entry in section.entries)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _ManualTopicCard(
                    entry: entry,
                    isSelected: entry.id == selectedEntryId,
                    canManage: canManage,
                    onTap: () => onOpenEntry(entry),
                    onEdit: () => onEditEntry(entry),
                    onDelete: () => onDeleteEntry(entry),
                    formatDate: formatDate,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _ManualSectionHeader extends StatelessWidget {
  const _ManualSectionHeader({required this.section});

  final _ManualSectionData section;

  @override
  Widget build(BuildContext context) {
    final color = section.accentColor;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(section.icon, color: color),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                section.title,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text(
                '${section.entries.length} temas. ${section.description}',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ManualTopicCard extends StatelessWidget {
  const _ManualTopicCard({
    required this.entry,
    required this.isSelected,
    required this.canManage,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
    required this.formatDate,
  });

  final CompanyManualEntry entry;
  final bool isSelected;
  final bool canManage;
  final VoidCallback onTap;
  final Future<bool> Function() onEdit;
  final Future<bool> Function() onDelete;
  final String Function(DateTime? value) formatDate;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final roles = entry.targetRoles.map((role) => role.label).join(', ');
    final updatedAt = entry.updatedAt ?? entry.createdAt;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isSelected
                ? scheme.primary.withValues(alpha: 0.08)
                : scheme.surface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: isSelected
                  ? scheme.primary.withValues(alpha: 0.45)
                  : scheme.outlineVariant,
              width: isSelected ? 1.4 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 18,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _ManualTag(label: entry.kind.label),
                            _ManualTag(label: entry.audience.label),
                            if (entry.moduleKey != null &&
                                entry.moduleKey!.isNotEmpty)
                              _ManualTag(label: 'Módulo ${entry.moduleKey}'),
                            if (!entry.published)
                              const _ManualTag(label: 'Oculto'),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (canManage)
                    PopupMenuButton<String>(
                      tooltip: 'Opciones',
                      onSelected: (value) async {
                        if (value == 'edit') {
                          await onEdit();
                        } else if (value == 'delete') {
                          await onDelete();
                        }
                      },
                      itemBuilder: (context) => const [
                        PopupMenuItem(value: 'edit', child: Text('Editar')),
                        PopupMenuItem(value: 'delete', child: Text('Eliminar')),
                      ],
                    ),
                ],
              ),
              if (entry.summary != null && entry.summary!.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  entry.summary!,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurface.withValues(alpha: 0.72),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              if (roles.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  'Aplica a: $roles',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Actualizado ${formatDate(updatedAt)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Ver detalle',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: scheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.arrow_forward_rounded,
                    color: scheme.primary,
                    size: 18,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ManualTag extends StatelessWidget {
  const _ManualTag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _ManualEntryDetailPane extends StatelessWidget {
  const _ManualEntryDetailPane({
    required this.entry,
    required this.canManage,
    required this.onEdit,
    required this.onDelete,
    required this.formatDate,
  });

  final CompanyManualEntry? entry;
  final bool canManage;
  final Future<bool> Function()? onEdit;
  final Future<bool> Function()? onDelete;
  final String Function(DateTime? value) formatDate;

  @override
  Widget build(BuildContext context) {
    final selectedEntry = entry;
    if (selectedEntry == null) {
      return const _ManualEmptyDetail();
    }

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 24,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        children: [
          _ManualDetailHeader(
            entry: selectedEntry,
            canManage: canManage,
            onEdit: onEdit,
            onDelete: onDelete,
            formatDate: formatDate,
          ),
          const Divider(height: 1),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: _ManualEntryBody(entry: selectedEntry),
            ),
          ),
        ],
      ),
    );
  }
}

class _ManualDetailHeader extends StatelessWidget {
  const _ManualDetailHeader({
    required this.entry,
    required this.canManage,
    required this.onEdit,
    required this.onDelete,
    required this.formatDate,
  });

  final CompanyManualEntry entry;
  final bool canManage;
  final Future<bool> Function()? onEdit;
  final Future<bool> Function()? onDelete;
  final String Function(DateTime? value) formatDate;

  @override
  Widget build(BuildContext context) {
    final roles = entry.targetRoles.map((role) => role.label).join(', ');
    final updatedAt = entry.updatedAt ?? entry.createdAt;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.title,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _ManualTag(label: entry.kind.label),
                        _ManualTag(label: entry.audience.label),
                        if (entry.moduleKey != null &&
                            entry.moduleKey!.isNotEmpty)
                          _ManualTag(label: 'Módulo ${entry.moduleKey}'),
                        if (roles.isNotEmpty) _ManualTag(label: 'Roles $roles'),
                        if (!entry.published) const _ManualTag(label: 'Oculto'),
                      ],
                    ),
                  ],
                ),
              ),
              if (canManage)
                Wrap(
                  spacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: onEdit == null
                          ? null
                          : () async {
                              await onEdit!.call();
                            },
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('Editar'),
                    ),
                    FilledButton.icon(
                      onPressed: onDelete == null
                          ? null
                          : () async {
                              await onDelete!.call();
                            },
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Eliminar'),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            'Última actualización ${formatDate(updatedAt)}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _ManualEntryBody extends StatelessWidget {
  const _ManualEntryBody({required this.entry});

  final CompanyManualEntry entry;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (entry.summary != null && entry.summary!.isNotEmpty) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Theme.of(
                context,
              ).colorScheme.primary.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              entry.summary!,
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 18),
        ],
        SelectableText(
          entry.content,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.65),
        ),
      ],
    );
  }
}

class _ManualEmptyDetail extends StatelessWidget {
  const _ManualEmptyDetail();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.menu_book_outlined,
                size: 48,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 12),
              Text(
                'Selecciona un tema',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
                'Abre una tarjeta del panel izquierdo para leer el contenido completo aquí.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ManualEntryDetailScreen extends StatelessWidget {
  const _ManualEntryDetailScreen({
    required this.entry,
    required this.canManage,
    required this.onEdit,
    required this.onDelete,
  });

  final CompanyManualEntry entry;
  final bool canManage;
  final Future<void> Function()? onEdit;
  final Future<void> Function()? onDelete;

  String _formatDate(DateTime? value) {
    if (value == null) return 'Sin fecha';
    final day = value.day.toString().padLeft(2, '0');
    final month = value.month.toString().padLeft(2, '0');
    final year = value.year.toString();
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '$day/$month/$year $hour:$minute';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Detalle del manual'),
        actions: [
          if (canManage && onEdit != null)
            IconButton(
              tooltip: 'Editar',
              onPressed: () async => onEdit!.call(),
              icon: const Icon(Icons.edit_outlined),
            ),
          if (canManage && onDelete != null)
            IconButton(
              tooltip: 'Eliminar',
              onPressed: () async => onDelete!.call(),
              icon: const Icon(Icons.delete_outline),
            ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: _ManualEntryDetailPane(
            entry: entry,
            canManage: false,
            onEdit: null,
            onDelete: null,
            formatDate: _formatDate,
          ),
        ),
      ),
    );
  }
}

class _ManualSectionData {
  const _ManualSectionData({required this.kind, required this.entries});

  final CompanyManualEntryKind kind;
  final List<CompanyManualEntry> entries;

  String get title => kind.label;

  String get description {
    switch (kind) {
      case CompanyManualEntryKind.generalRule:
        return 'Reglas base para la operación diaria.';
      case CompanyManualEntryKind.roleRule:
        return 'Lineamientos específicos según el rol.';
      case CompanyManualEntryKind.policy:
        return 'Políticas internas y criterios formales.';
      case CompanyManualEntryKind.warrantyPolicy:
        return 'Condiciones y manejo de garantías.';
      case CompanyManualEntryKind.responsibility:
        return 'Responsabilidades y compromisos del equipo.';
      case CompanyManualEntryKind.productService:
        return 'Información comercial de productos y servicios.';
      case CompanyManualEntryKind.priceRule:
        return 'Reglas para cotizar y fijar precios.';
      case CompanyManualEntryKind.serviceRule:
        return 'Estándares para la ejecución del servicio.';
      case CompanyManualEntryKind.moduleGuide:
        return 'Guías rápidas para usar módulos del sistema.';
    }
  }

  IconData get icon {
    switch (kind) {
      case CompanyManualEntryKind.generalRule:
        return Icons.rule_folder_outlined;
      case CompanyManualEntryKind.roleRule:
        return Icons.badge_outlined;
      case CompanyManualEntryKind.policy:
        return Icons.policy_outlined;
      case CompanyManualEntryKind.warrantyPolicy:
        return Icons.verified_user_outlined;
      case CompanyManualEntryKind.responsibility:
        return Icons.assignment_turned_in_outlined;
      case CompanyManualEntryKind.productService:
        return Icons.inventory_2_outlined;
      case CompanyManualEntryKind.priceRule:
        return Icons.sell_outlined;
      case CompanyManualEntryKind.serviceRule:
        return Icons.handyman_outlined;
      case CompanyManualEntryKind.moduleGuide:
        return Icons.menu_book_outlined;
    }
  }

  Color get accentColor {
    switch (kind) {
      case CompanyManualEntryKind.generalRule:
        return const Color(0xFF1D4ED8);
      case CompanyManualEntryKind.roleRule:
        return const Color(0xFF0F766E);
      case CompanyManualEntryKind.policy:
        return const Color(0xFF7C3AED);
      case CompanyManualEntryKind.warrantyPolicy:
        return const Color(0xFFEA580C);
      case CompanyManualEntryKind.responsibility:
        return const Color(0xFFBE123C);
      case CompanyManualEntryKind.productService:
        return const Color(0xFF0284C7);
      case CompanyManualEntryKind.priceRule:
        return const Color(0xFFCA8A04);
      case CompanyManualEntryKind.serviceRule:
        return const Color(0xFF15803D);
      case CompanyManualEntryKind.moduleGuide:
        return const Color(0xFF4338CA);
    }
  }
}

class _CompanyManualEntryDialog extends ConsumerStatefulWidget {
  const _CompanyManualEntryDialog({this.entry});

  final CompanyManualEntry? entry;

  @override
  ConsumerState<_CompanyManualEntryDialog> createState() =>
      _CompanyManualEntryDialogState();
}

class _CompanyManualEntryDialogState
    extends ConsumerState<_CompanyManualEntryDialog> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _summaryCtrl;
  late final TextEditingController _contentCtrl;
  late final TextEditingController _moduleCtrl;
  late final TextEditingController _sortCtrl;

  late CompanyManualEntryKind _kind;
  late CompanyManualAudience _audience;
  late bool _published;
  late Set<AppRole> _targetRoles;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(text: widget.entry?.title ?? '');
    _summaryCtrl = TextEditingController(text: widget.entry?.summary ?? '');
    _contentCtrl = TextEditingController(text: widget.entry?.content ?? '');
    _moduleCtrl = TextEditingController(text: widget.entry?.moduleKey ?? '');
    _sortCtrl = TextEditingController(
      text: (widget.entry?.sortOrder ?? 0).toString(),
    );
    _kind = widget.entry?.kind ?? CompanyManualEntryKind.generalRule;
    _audience = widget.entry?.audience ?? CompanyManualAudience.general;
    _published = widget.entry?.published ?? true;
    _targetRoles = {...?widget.entry?.targetRoles};
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _summaryCtrl.dispose();
    _contentCtrl.dispose();
    _moduleCtrl.dispose();
    _sortCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    final title = _titleCtrl.text.trim();
    final content = _contentCtrl.text.trim();
    final sortOrder = int.tryParse(_sortCtrl.text.trim()) ?? 0;
    if (title.isEmpty || content.isEmpty) {
      setState(() => _error = 'Título y contenido son obligatorios');
      return;
    }
    if (_audience == CompanyManualAudience.roleSpecific &&
        _targetRoles.isEmpty) {
      setState(
        () => _error = 'Selecciona al menos un rol para una entrada por rol',
      );
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    final entry = CompanyManualEntry(
      id: widget.entry?.id ?? '',
      ownerId: widget.entry?.ownerId ?? '',
      title: title,
      summary: _summaryCtrl.text.trim().isEmpty
          ? null
          : _summaryCtrl.text.trim(),
      content: content,
      kind: _kind,
      audience: _audience,
      targetRoles: _targetRoles.toList()
        ..sort((a, b) => a.label.compareTo(b.label)),
      moduleKey: _moduleCtrl.text.trim().isEmpty
          ? null
          : _moduleCtrl.text.trim(),
      published: _published,
      sortOrder: sortOrder,
      createdByUserId: widget.entry?.createdByUserId ?? '',
      updatedByUserId: widget.entry?.updatedByUserId,
      createdAt: widget.entry?.createdAt,
      updatedAt: widget.entry?.updatedAt,
    );

    try {
      final repo = ref.read(companyManualRepositoryProvider);
      if (widget.entry == null) {
        await repo.createEntry(entry);
      } else {
        await repo.updateEntry(entry);
      }
      ref.invalidate(companyManualSummaryProvider);
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.entry == null ? 'Nueva entrada' : 'Editar entrada'),
      content: SizedBox(
        width: 560,
        child: ListView(
          shrinkWrap: true,
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            if (_error != null) ...[
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              const SizedBox(height: 10),
            ],
            TextField(
              controller: _titleCtrl,
              decoration: const InputDecoration(labelText: 'Título'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _summaryCtrl,
              decoration: const InputDecoration(
                labelText: 'Resumen breve (opcional)',
              ),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<CompanyManualEntryKind>(
              initialValue: _kind,
              items: CompanyManualEntryKind.values
                  .map(
                    (kind) =>
                        DropdownMenuItem(value: kind, child: Text(kind.label)),
                  )
                  .toList(),
              onChanged: _saving
                  ? null
                  : (value) {
                      if (value == null) return;
                      setState(() => _kind = value);
                    },
              decoration: const InputDecoration(labelText: 'Tipo de entrada'),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<CompanyManualAudience>(
              initialValue: _audience,
              items: CompanyManualAudience.values
                  .map(
                    (audience) => DropdownMenuItem(
                      value: audience,
                      child: Text(audience.label),
                    ),
                  )
                  .toList(),
              onChanged: _saving
                  ? null
                  : (value) {
                      if (value == null) return;
                      setState(() {
                        _audience = value;
                        if (_audience == CompanyManualAudience.general) {
                          _targetRoles.clear();
                        }
                      });
                    },
              decoration: const InputDecoration(labelText: 'Alcance'),
            ),
            if (_audience == CompanyManualAudience.roleSpecific) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final role in [
                    AppRole.asistente,
                    AppRole.vendedor,
                    AppRole.marketing,
                    AppRole.tecnico,
                    AppRole.admin,
                  ])
                    FilterChip(
                      label: Text(role.label),
                      selected: _targetRoles.contains(role),
                      onSelected: _saving
                          ? null
                          : (selected) {
                              setState(() {
                                if (selected) {
                                  _targetRoles.add(role);
                                } else {
                                  _targetRoles.remove(role);
                                }
                              });
                            },
                    ),
                ],
              ),
            ],
            const SizedBox(height: 10),
            TextField(
              controller: _moduleCtrl,
              decoration: const InputDecoration(
                labelText: 'Módulo relacionado (opcional)',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _sortCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Orden'),
            ),
            const SizedBox(height: 10),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: _published,
              onChanged: _saving
                  ? null
                  : (value) => setState(() => _published = value),
              title: const Text('Visible para usuarios'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _contentCtrl,
              minLines: 8,
              maxLines: 14,
              decoration: const InputDecoration(
                labelText: 'Contenido',
                alignLabelWithHint: true,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Guardar'),
        ),
      ],
    );
  }
}
