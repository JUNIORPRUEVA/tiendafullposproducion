import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/app_permissions.dart';
import '../../core/auth/app_role.dart';
import '../../core/auth/auth_provider.dart';
import '../../core/widgets/app_drawer.dart';
import '../../core/widgets/custom_app_bar.dart';
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
  String _searchQuery = '';

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

  Future<void> _loadEntries() async {
    final user = ref.read(authStateProvider).user;
    final canManage =
        user != null &&
        hasPermission(user.appRole, AppPermission.manageCompanyManual);

    final repo = ref.read(companyManualRepositoryProvider);
    final cachedItems = await repo.getCachedEntries(includeHidden: canManage);

    if (mounted && cachedItems.isNotEmpty) {
      final cachedSelectedId =
          cachedItems.any((item) => item.id == _selectedEntryId)
          ? _selectedEntryId
          : cachedItems.first.id;
      setState(() {
        _entries = cachedItems;
        _loading = false;
        _error = null;
        _selectedEntryId = cachedSelectedId;
      });
    }

    if (mounted) {
      setState(() {
        _loading = _entries.isEmpty;
        _error = null;
      });
    }

    try {
      final items = await repo.listEntriesAndCache(includeHidden: canManage);

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
    final filteredByKind = (_kindFilter == null
        ? _entries
        : _entries.where((item) => item.kind == _kindFilter))
      .toList();
    final query = _searchQuery.trim().toLowerCase();
    final filtered = (query.isEmpty
        ? filteredByKind
        : filteredByKind.where((item) {
          return item.title.toLowerCase().contains(query) ||
            (item.summary ?? '').toLowerCase().contains(query) ||
            item.content.toLowerCase().contains(query) ||
            (item.moduleKey ?? '').toLowerCase().contains(query);
          }))
      .toList();
    filtered.sort((left, right) {
      final byOrder = left.sortOrder.compareTo(right.sortOrder);
      if (byOrder != 0) return byOrder;
      return left.title.toLowerCase().compareTo(right.title.toLowerCase());
    });
    return filtered;
  }

  Future<void> _openSearch(bool canManage) async {
    final result = await showSearch<_ManualSearchResult?>(
      context: context,
      delegate: _ManualSearchDelegate(
        entries: _kindFilter == null
            ? _entries
            : _entries
                  .where((entry) => entry.kind == _kindFilter)
                  .toList(growable: false),
        initialQuery: _searchQuery,
      ),
    );
    if (!mounted || result == null) return;

    setState(() {
      _searchQuery = result.query.trim();
    });

    final selectedEntry = result.selectedEntry;
    if (selectedEntry != null) {
      _openEntryDetail(selectedEntry, canManage);
    }
  }

  void _clearSearch() {
    if (_searchQuery.isEmpty) return;
    setState(() {
      _searchQuery = '';
    });
  }

  String _searchSummaryLabel() {
    final query = _searchQuery.trim();
    if (query.isEmpty) return '';
    return 'Busqueda: "$query"';
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
    final selectedEntry = _resolveSelectedEntry(entries);

    return Scaffold(
      appBar: CustomAppBar(
        title: 'Manual Interno',
        showLogo: false,
        darkerTone: true,
        actions: [
          IconButton(
            tooltip: 'Buscar',
            onPressed: _entries.isEmpty && _loading
                ? null
                : () => _openSearch(canManage),
            icon: const Icon(Icons.search_rounded),
          ),
          PopupMenuButton<CompanyManualEntryKind?>(
            tooltip: 'Filtrar',
            initialValue: _kindFilter,
            onSelected: (kind) {
              setState(() {
                _kindFilter = kind;
              });
            },
            itemBuilder: (context) => [
              const PopupMenuItem<CompanyManualEntryKind?>(
                value: null,
                child: Text('Todo'),
              ),
              ...CompanyManualEntryKind.values.map(
                (kind) => PopupMenuItem<CompanyManualEntryKind?>(
                  value: kind,
                  child: Text(kind.label),
                ),
              ),
            ],
            icon: const Icon(Icons.tune_rounded),
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
              Theme.of(context).colorScheme.primary.withValues(alpha: 0.05),
              Theme.of(context).scaffoldBackgroundColor,
              Theme.of(context).colorScheme.surface,
            ],
          ),
        ),
        child: Column(
          children: [
            if (_searchQuery.isNotEmpty || _kindFilter != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                child: _ManualActiveFiltersBar(
                  searchLabel: _searchSummaryLabel(),
                  filterLabel: _kindFilter?.label,
                  onClearSearch: _searchQuery.isEmpty ? null : _clearSearch,
                  onClearFilter: _kindFilter == null
                      ? null
                      : () {
                          setState(() {
                            _kindFilter = null;
                          });
                        },
                ),
              ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                  ? Center(child: Text(_error!))
                  : entries.isEmpty
                  ? const Center(child: Text('No hay reglas para mostrar'))
                  : RefreshIndicator(
                      onRefresh: _loadEntries,
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final isWide = constraints.maxWidth >= 980;
                          final listPane = _ManualEntriesList(
                            entries: entries,
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

class _ManualActiveFiltersBar extends StatelessWidget {
  const _ManualActiveFiltersBar({
    required this.searchLabel,
    required this.filterLabel,
    required this.onClearSearch,
    required this.onClearFilter,
  });

  final String searchLabel;
  final String? filterLabel;
  final VoidCallback? onClearSearch;
  final VoidCallback? onClearFilter;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          if (searchLabel.isNotEmpty)
            _ManualRemovableChip(
              icon: Icons.search_rounded,
              label: searchLabel,
              onRemove: onClearSearch,
            ),
          if (filterLabel != null)
            _ManualRemovableChip(
              icon: Icons.tune_rounded,
              label: filterLabel!,
              onRemove: onClearFilter,
            ),
        ],
      ),
    );
  }
}

class _ManualRemovableChip extends StatelessWidget {
  const _ManualRemovableChip({
    required this.icon,
    required this.label,
    required this.onRemove,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: scheme.primary),
          const SizedBox(width: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 220),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (onRemove != null) ...[
            const SizedBox(width: 4),
            InkWell(
              onTap: onRemove,
              borderRadius: BorderRadius.circular(999),
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: Icon(
                  Icons.close_rounded,
                  size: 16,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ManualSummaryPill extends StatelessWidget {
  const _ManualSummaryPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.14)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: scheme.primary, size: 15),
          const SizedBox(width: 7),
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: scheme.primary,
              fontWeight: FontWeight.w700,
              height: 1,
            ),
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
                      _ManualSummaryPill(
                        icon: Icons.article_outlined,
                        label: '${entries.length} visibles',
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

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            color: selected
                ? scheme.primary.withValues(alpha: 0.08)
                : scheme.surfaceContainerLowest,
            border: Border.all(
              color: selected
                  ? scheme.primary.withValues(alpha: 0.45)
                  : scheme.outlineVariant,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: selected ? scheme.primary : scheme.outline,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _ManualCompactEntryBody(
                  entry: entry,
                  dense: true,
                  emphasizeTitle: true,
                ),
              ),
              const SizedBox(width: 10),
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
                )
              else
                Icon(
                  selected ? Icons.visibility_outlined : Icons.arrow_forward_rounded,
                  color: scheme.primary,
                  size: 18,
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

class _ManualEntriesList extends StatelessWidget {
  const _ManualEntriesList({
    required this.entries,
    required this.selectedEntryId,
    required this.canManage,
    required this.onOpenEntry,
    required this.onEditEntry,
    required this.onDeleteEntry,
    required this.formatDate,
  });

  final List<CompanyManualEntry> entries;
  final String? selectedEntryId;
  final bool canManage;
  final ValueChanged<CompanyManualEntry> onOpenEntry;
  final Future<bool> Function(CompanyManualEntry entry) onEditEntry;
  final Future<bool> Function(CompanyManualEntry entry) onDeleteEntry;
  final String Function(DateTime? value) formatDate;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
      itemCount: entries.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final entry = entries[index];
        return _ManualTopicCard(
          entry: entry,
          isSelected: entry.id == selectedEntryId,
          canManage: canManage,
          onTap: () => onOpenEntry(entry),
          onEdit: () => onEditEntry(entry),
          onDelete: () => onDeleteEntry(entry),
          formatDate: formatDate,
        );
      },
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

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            color: isSelected
                ? scheme.primary.withValues(alpha: 0.08)
                : scheme.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isSelected
                  ? scheme.primary.withValues(alpha: 0.45)
                  : scheme.outlineVariant,
              width: isSelected ? 1.4 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.035),
                blurRadius: 10,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: isSelected ? scheme.primary : scheme.outline,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _ManualCompactEntryBody(entry: entry, dense: false),
              ),
              const SizedBox(width: 8),
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
                )
              else
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 15,
                  color: scheme.primary,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ManualCompactEntryBody extends StatelessWidget {
  const _ManualCompactEntryBody({
    required this.entry,
    required this.dense,
    this.emphasizeTitle = false,
  });

  final CompanyManualEntry entry;
  final bool dense;
  final bool emphasizeTitle;

  String _headline() {
    final audienceLabel = _audienceLabel(entry);
    return 'Tipo: ${entry.kind.label}  •  Dirigido a: $audienceLabel';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          entry.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: (dense ? theme.textTheme.titleSmall : theme.textTheme.bodyLarge)
              ?.copyWith(
                fontWeight: emphasizeTitle ? FontWeight.w800 : FontWeight.w700,
                fontSize: dense ? 14 : 13.6,
              ),
        ),
        const SizedBox(height: 4),
        Text(
          _headline(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
            height: 1.15,
            fontSize: dense ? 11.9 : 11.6,
          ),
        ),
      ],
    );
  }
}

String _audienceLabel(CompanyManualEntry entry) {
  if (entry.targetRoles.isNotEmpty) {
    return entry.targetRoles.map((role) => role.label).join(', ');
  }

  if (entry.audience == CompanyManualAudience.roleSpecific) {
    return 'Roles definidos';
  }

  return 'Todo el equipo';
}

class _ManualSearchResult {
  const _ManualSearchResult({required this.query, this.selectedEntry});

  final String query;
  final CompanyManualEntry? selectedEntry;
}

class _ManualSearchDelegate extends SearchDelegate<_ManualSearchResult?> {
  _ManualSearchDelegate({required this.entries, required String initialQuery})
    : super(searchFieldLabel: 'Buscar reglas y políticas') {
    query = initialQuery;
  }

  final List<CompanyManualEntry> entries;

  List<CompanyManualEntry> get _filteredEntries {
    final normalizedQuery = query.trim().toLowerCase();
    final filtered = entries.where((entry) {
      if (normalizedQuery.isEmpty) return true;
      return entry.title.toLowerCase().contains(normalizedQuery) ||
          (entry.summary ?? '').toLowerCase().contains(normalizedQuery) ||
          entry.content.toLowerCase().contains(normalizedQuery) ||
          (entry.moduleKey ?? '').toLowerCase().contains(normalizedQuery) ||
          _audienceLabel(entry).toLowerCase().contains(normalizedQuery);
    }).toList();

    filtered.sort(
      (left, right) => left.title.toLowerCase().compareTo(right.title.toLowerCase()),
    );
    return filtered;
  }

  @override
  ThemeData appBarTheme(BuildContext context) {
    final theme = Theme.of(context);
    return theme.copyWith(
      appBarTheme: theme.appBarTheme.copyWith(toolbarHeight: 64),
      inputDecorationTheme: theme.inputDecorationTheme.copyWith(
        filled: false,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
      ),
    );
  }

  @override
  List<Widget>? buildActions(BuildContext context) {
    return [
      if (query.trim().isNotEmpty)
        IconButton(
          tooltip: 'Limpiar búsqueda',
          onPressed: () {
            query = '';
            showSuggestions(context);
          },
          icon: const Icon(Icons.close_rounded),
        ),
      IconButton(
        tooltip: 'Aplicar búsqueda',
        onPressed: () => close(context, _ManualSearchResult(query: query.trim())),
        icon: const Icon(Icons.check_rounded),
      ),
    ];
  }

  @override
  Widget? buildLeading(BuildContext context) {
    return IconButton(
      tooltip: 'Cerrar',
      onPressed: () => close(context, null),
      icon: const Icon(Icons.arrow_back_rounded),
    );
  }

  @override
  Widget buildResults(BuildContext context) => _buildList(context);

  @override
  Widget buildSuggestions(BuildContext context) => _buildList(context);

  Widget _buildList(BuildContext context) {
    final filtered = _filteredEntries;
    if (entries.isEmpty) {
      return const Center(child: Text('No hay reglas disponibles'));
    }
    if (filtered.isEmpty) {
      return const Center(child: Text('No se encontraron coincidencias'));
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
      itemCount: filtered.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final entry = filtered[index];
        return ListTile(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          tileColor: Theme.of(context).colorScheme.surfaceContainerLowest,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          title: Text(
            entry.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          subtitle: Text(
            'Tipo: ${entry.kind.label} • ${_audienceLabel(entry)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: const Icon(Icons.arrow_forward_rounded),
          onTap: () => close(
            context,
            _ManualSearchResult(query: query.trim(), selectedEntry: entry),
          ),
        );
      },
    );
  }
}

class _ManualTag extends StatelessWidget {
  const _ManualTag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.w700,
          fontSize: 11,
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
    this.scrollableBody = true,
  });

  final CompanyManualEntry? entry;
  final bool canManage;
  final Future<bool> Function()? onEdit;
  final Future<bool> Function()? onDelete;
  final String Function(DateTime? value) formatDate;
  final bool scrollableBody;

  @override
  Widget build(BuildContext context) {
    final selectedEntry = entry;
    final isCompact = MediaQuery.sizeOf(context).width < 700;
    if (selectedEntry == null) {
      return const _ManualEmptyDetail();
    }

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
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
            compact: isCompact,
          ),
          const Divider(height: 1),
          if (scrollableBody)
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(isCompact ? 18 : 24),
                child: _ManualEntryBody(entry: selectedEntry),
              ),
            )
          else
            Padding(
              padding: EdgeInsets.all(isCompact ? 18 : 24),
              child: _ManualEntryBody(entry: selectedEntry),
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
    required this.compact,
  });

  final CompanyManualEntry entry;
  final bool canManage;
  final Future<bool> Function()? onEdit;
  final Future<bool> Function()? onDelete;
  final String Function(DateTime? value) formatDate;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final roles = entry.targetRoles.map((role) => role.label).join(', ');
    final updatedAt = entry.updatedAt ?? entry.createdAt;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        compact ? 18 : 20,
        20,
        compact ? 14 : 16,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  entry.title,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.2,
                    fontSize: compact ? 21 : null,
                  ),
                ),
              ),
              if (canManage)
                PopupMenuButton<String>(
                  onSelected: (value) async {
                    if (value == 'edit' && onEdit != null) {
                      await onEdit!.call();
                    }
                    if (value == 'delete' && onDelete != null) {
                      await onDelete!.call();
                    }
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(value: 'edit', child: Text('Editar')),
                    PopupMenuItem(value: 'delete', child: Text('Eliminar')),
                  ],
                ),
            ],
          ),
          SizedBox(height: compact ? 8 : 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _ManualTag(label: entry.kind.label),
              _ManualTag(label: entry.audience.label),
              if (entry.moduleKey != null && entry.moduleKey!.isNotEmpty)
                _ManualTag(label: 'Módulo ${entry.moduleKey}'),
              if (roles.isNotEmpty) _ManualTag(label: 'Roles $roles'),
              if (!entry.published) const _ManualTag(label: 'Oculto'),
            ],
          ),
          SizedBox(height: compact ? 10 : 12),
          Text(
            'Última actualización ${formatDate(updatedAt)}',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
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
    final isCompact = MediaQuery.sizeOf(context).width < 700;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (entry.summary != null && entry.summary!.isNotEmpty) ...[
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(isCompact ? 14 : 16),
            decoration: BoxDecoration(
              color: Theme.of(
                context,
              ).colorScheme.primary.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Text(
              entry.summary!,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
                fontSize: isCompact ? 13 : 13.4,
                height: 1.45,
              ),
            ),
          ),
          SizedBox(height: isCompact ? 14 : 16),
        ],
        SelectableText(
          entry.content,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            height: 1.72,
            fontSize: isCompact ? 13 : 13.4,
            color: Theme.of(context).colorScheme.onSurface,
          ),
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
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
                  Theme.of(context).colorScheme.surface,
                  Theme.of(context).colorScheme.surfaceContainerLowest,
                ],
              ),
            ),
          ),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 72, 16, 20),
              child: _ManualEntryDetailPane(
                entry: entry,
                canManage: false,
                onEdit: null,
                onDelete: null,
                formatDate: _formatDate,
                scrollableBody: false,
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: Row(
                children: [
                  _FloatingDetailAction(
                    icon: Icons.arrow_back_rounded,
                    tooltip: 'Regresar',
                    onTap: () => Navigator.of(context).maybePop(),
                  ),
                  const Spacer(),
                  if (canManage && onEdit != null)
                    _FloatingDetailAction(
                      icon: Icons.edit_outlined,
                      tooltip: 'Editar',
                      onTap: () async => onEdit!.call(),
                    ),
                  if (canManage && onDelete != null) ...[
                    const SizedBox(width: 8),
                    _FloatingDetailAction(
                      icon: Icons.delete_outline,
                      tooltip: 'Eliminar',
                      onTap: () async => onDelete!.call(),
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

class _FloatingDetailAction extends StatelessWidget {
  const _FloatingDetailAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: scheme.surface.withValues(alpha: 0.92),
        elevation: 6,
        shadowColor: Colors.black.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: Icon(icon, size: 20, color: scheme.onSurface),
          ),
        ),
      ),
    );
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
