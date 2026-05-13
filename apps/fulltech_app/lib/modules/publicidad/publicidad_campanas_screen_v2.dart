import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/app_permissions.dart';
import '../../core/auth/auth_provider.dart';
import '../../core/errors/api_exception.dart';
import '../../core/widgets/app_drawer.dart';
import '../../core/widgets/custom_app_bar.dart';
import '../service_orders/data/upload_repository.dart';
import 'marketing_api.dart';
import 'marketing_campaign_models.dart';
import 'providers/campaign_autosave_provider.dart';
import 'widgets/autosave_indicator.dart';
import 'widgets/campaign_collapsible_section.dart';
import 'widgets/campaign_preview_panel.dart';
import 'widgets/campaign_wizard_header.dart';

/// Premium campaign management screen - SaaS style (Meta Ads / Linear / Stripe)
class PublicidadCampanasScreenV2 extends ConsumerStatefulWidget {
  const PublicidadCampanasScreenV2({super.key});

  @override
  ConsumerState<PublicidadCampanasScreenV2> createState() =>
      _PublicidadCampanasScreenV2State();
}

class _PublicidadCampanasScreenV2State
    extends ConsumerState<PublicidadCampanasScreenV2> {
  bool _loading = true;
  String? _error;
  List<MarketingCampaign> _campaigns = const [];
  List<MarketingMediaAsset> _assets = const [];
  MetaAdsConfigDebug? _metaConfig;
  String? _selectedId;

  // Form controllers
  final _headlineCtrl = TextEditingController();
  final _primaryTextCtrl = TextEditingController();
  final _descriptionCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _destinationCtrl = TextEditingController();
  final _dailyBudgetCtrl = TextEditingController();
  final _totalBudgetCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _radiusCtrl = TextEditingController(text: '15');
  final _ageMinCtrl = TextEditingController(text: '24');
  final _ageMaxCtrl = TextEditingController(text: '60');
  final _interestsCtrl = TextEditingController();
  final _objectiveCtrl = TextEditingController(text: 'OUTCOME_TRAFFIC');

  bool _busyAction = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _headlineCtrl.dispose();
    _primaryTextCtrl.dispose();
    _descriptionCtrl.dispose();
    _phoneCtrl.dispose();
    _destinationCtrl.dispose();
    _dailyBudgetCtrl.dispose();
    _totalBudgetCtrl.dispose();
    _cityCtrl.dispose();
    _radiusCtrl.dispose();
    _ageMinCtrl.dispose();
    _ageMaxCtrl.dispose();
    _interestsCtrl.dispose();
    _objectiveCtrl.dispose();
    super.dispose();
  }

  MarketingCampaign? get _selectedCampaign =>
      _campaigns.firstWhere((c) => c.id == _selectedId, orElse: () => null) ??
      (_campaigns.isNotEmpty ? _campaigns.first : null);

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final api = ref.read(marketingApiProvider);
      final tuple = await api.loadCampaigns();
      final assets = await api.loadContentGallery();
      final selected = tuple.$1.any((item) => item.id == _selectedId)
          ? _selectedId
          : (tuple.$1.isNotEmpty ? tuple.$1.first.id : null);

      if (!mounted) return;
      setState(() {
        _campaigns = tuple.$1;
        _assets = assets;
        _metaConfig = tuple.$2;
        _selectedId = selected;
        _loading = false;
      });

      if (selected != null) {
        final campaign = _campaigns.firstWhere((c) => c.id == selected);
        _syncFormFields(campaign);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is ApiException ? e.message : '$e';
        _loading = false;
      });
    }
  }

  void _syncFormFields(MarketingCampaign campaign) {
    _headlineCtrl.text = campaign.headline ?? '';
    _primaryTextCtrl.text = campaign.primaryText ?? '';
    _descriptionCtrl.text = campaign.description ?? '';
    _phoneCtrl.text = campaign.whatsappPhone ?? '';
    _destinationCtrl.text = campaign.destinationUrl ?? '';
    _dailyBudgetCtrl.text = campaign.dailyBudget?.toStringAsFixed(2) ?? '';
    _totalBudgetCtrl.text = campaign.totalBudget?.toStringAsFixed(2) ?? '';

    final audience = campaign.finalAudience ?? campaign.recommendedAudience ?? {};
    _cityCtrl.text = '${audience['city'] ?? ''}';
    _radiusCtrl.text = '${audience['radiusKm'] ?? 15}';
    _ageMinCtrl.text = '${audience['ageMin'] ?? 24}';
    _ageMaxCtrl.text = '${audience['ageMax'] ?? 60}';
    final interests = audience['interests'];
    if (interests is List) {
      _interestsCtrl.text = interests.map((e) => '$e').join(', ');
    }
    _objectiveCtrl.text = '${audience['objective'] ?? 'OUTCOME_TRAFFIC'}';
  }

  Future<void> _runAction(String label, Future<void> Function() action) async {
    if (_busyAction) return;
    setState(() => _busyAction = true);
    try {
      await action();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$label completado')),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: ${e.message}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      if (mounted) setState(() => _busyAction = false);
    }
  }

  Future<void> _createDraft() async {
    await _runAction('Campaña creada', () async {
      final api = ref.read(marketingApiProvider);
      final created = await api.generateCampaignDraft();
      await _load();
      setState(() => _selectedId = created.id);
    });
  }

  Future<void> _changeBaseImage(String mediaAssetId) async {
    final campaign = _selectedCampaign;
    if (campaign == null) return;
    await _runAction('Imagen actualizada', () async {
      await ref
          .read(marketingApiProvider)
          .changeCampaignBaseImage(campaign.id, mediaAssetId);
      await _load();
    });
  }

  Future<void> _confirmBaseImage() async {
    final campaign = _selectedCampaign;
    if (campaign == null) return;
    await _runAction('Imagen confirmada', () async {
      await ref
          .read(marketingApiProvider)
          .confirmCampaignBaseImage(campaign.id);
      await _load();
    });
  }

  Future<void> _uploadDesign() async {
    final campaign = _selectedCampaign;
    if (campaign == null) return;

    FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        withData: true,
        allowMultiple: false,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
      return;
    }

    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null || bytes.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Archivo inválido')),
      );
      return;
    }

    await _runAction('Diseño subido', () async {
      final uploadRepo = ref.read(uploadRepositoryProvider);
      final uploaded = await uploadRepo.uploadImage(
        fileName: file.name,
        bytes: bytes,
      );
      await ref.read(marketingApiProvider).uploadCampaignDesign(
            campaign.id,
            finalDesignUrl: uploaded.url,
            fileName: file.name,
            mimeType: 'image/jpeg',
          );
      await ref.read(marketingApiProvider).regenerateCampaignCopy(campaign.id);
      await _load();
    });
  }

  Future<void> _saveDraft() async {
    final campaign = _selectedCampaign;
    if (campaign == null) return;

    final dailyBudget = double.tryParse(_dailyBudgetCtrl.text.trim()) ?? 0;
    if (dailyBudget <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Presupuesto diario debe ser mayor a 0')),
      );
      return;
    }

    final interests = _interestsCtrl.text
        .split(',')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();

    final audience = {
      'city': _cityCtrl.text.trim(),
      'radiusKm': int.tryParse(_radiusCtrl.text.trim()) ?? 15,
      'ageMin': int.tryParse(_ageMinCtrl.text.trim()) ?? 24,
      'ageMax': int.tryParse(_ageMaxCtrl.text.trim()) ?? 60,
      'interests': interests,
      'objective': _objectiveCtrl.text.trim().isEmpty
          ? 'OUTCOME_TRAFFIC'
          : _objectiveCtrl.text.trim(),
      'gender': 'ALL',
    };

    await _runAction('Borrador guardado', () async {
      await ref.read(marketingApiProvider).updateCampaign(
            campaign.id,
            headline: _headlineCtrl.text.trim(),
            primaryText: _primaryTextCtrl.text.trim(),
            description: _descriptionCtrl.text.trim(),
            cta: 'WHATSAPP_MESSAGE',
            dailyBudget: dailyBudget,
            totalBudget: double.tryParse(_totalBudgetCtrl.text.trim()),
            whatsappPhone: _phoneCtrl.text.trim(),
            destinationUrl: _destinationCtrl.text.trim(),
            finalAudience: audience,
            keepRunningUntilPaused: true,
          );
      await _load();
    });
  }

  Future<void> _publishCampaign() async {
    final campaign = _selectedCampaign;
    if (campaign == null) return;
    await _runAction('Campaña publicada', () async {
      await _saveDraft();
      await ref.read(marketingApiProvider).createMetaCampaign(campaign.id);
      await _load();
    });
  }

  Future<void> _activateCampaign() async {
    final campaign = _selectedCampaign;
    if (campaign == null) return;
    await _runAction('Campaña activada', () async {
      await ref.read(marketingApiProvider).activateCampaign(campaign.id);
      await _load();
    });
  }

  Future<void> _pauseCampaign() async {
    final campaign = _selectedCampaign;
    if (campaign == null) return;
    await _runAction('Campaña pausada', () async {
      await ref.read(marketingApiProvider).pauseCampaign(campaign.id);
      await _load();
    });
  }

  Future<void> _duplicateCampaign() async {
    final campaign = _selectedCampaign;
    if (campaign == null) return;
    await _runAction('Campaña duplicada', () async {
      final dup = await ref.read(marketingApiProvider).duplicateCampaign(campaign.id);
      await _load();
      setState(() => _selectedId = dup.id);
    });
  }

  Future<void> _rejectCampaign() async {
    final campaign = _selectedCampaign;
    if (campaign == null) return;
    await _runAction('Campaña rechazada', () async {
      await ref.read(marketingApiProvider).rejectCampaign(campaign.id);
      await _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authStateProvider).user;
    final canView =
        user != null && hasPermission(user.appRole, AppPermission.viewPublicidad);

    if (!canView) {
      return Scaffold(
        appBar: const CustomAppBar(title: 'Publicidad / Campañas'),
        body: const Center(
          child: Text('Acceso denegado. Solo ADMIN puede usar Publicidad.'),
        ),
      );
    }

    final selected = _selectedCampaign;

    return Scaffold(
      drawer: buildAdaptiveDrawer(context, currentUser: user),
      appBar: const CustomAppBar(title: 'Publicidad / Campañas'),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _busyAction || _loading ? null : _createDraft,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Nueva campaña'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(_error!),
                        const SizedBox(height: 16),
                        OutlinedButton.icon(
                          onPressed: _load,
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('Reintentar'),
                        ),
                      ],
                    ),
                  ),
                )
              : Column(
                  children: [
                    // Wizard header
                    if (selected != null)
                      CampaignWizardHeader(
                        currentPhase: selected.phase,
                        status: selected.status,
                        hasError: selected.status == MarketingCampaignStatus.error ||
                            selected.status == MarketingCampaignStatus.rejected,
                      ),
                    // Main content
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final isCompact = constraints.maxWidth < 1100;

                          if (isCompact) {
                            return _buildCompactLayout(selected);
                          }
                          return _buildDesktopLayout(selected);
                        },
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _buildCompactLayout(MarketingCampaign? selected) {
    return Column(
      children: [
        if (selected == null)
          Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.add_rounded,
                    size: 48,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No hay campañas',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Crea una nueva campaña para comenzar',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
          )
        else ...[
          // Campaign list
          SizedBox(
            height: 200,
            child: _buildCampaignList(selected),
          ),
          const Divider(height: 1),
          // Content
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: _buildFormContent(selected),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildDesktopLayout(MarketingCampaign? selected) {
    if (selected == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.add_rounded,
              size: 48,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              'No hay campañas',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Crea una nueva campaña para comenzar',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      );
    }

    return Row(
      children: [
        // Left: Campaign list
        SizedBox(
          width: 320,
          child: _buildCampaignList(selected),
        ),
        const VerticalDivider(width: 1),
        // Middle: Preview
        SizedBox(
          width: 350,
          child: CampaignPreviewPanel(campaign: selected),
        ),
        const VerticalDivider(width: 1),
        // Right: Form + Actions
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: _buildFormContent(selected),
          ),
        ),
      ],
    );
  }

  Widget _buildCampaignList(MarketingCampaign selected) {
    return ListView.separated(
      padding: const EdgeInsets.all(8),
      itemCount: _campaigns.length,
      separatorBuilder: (_, _) => const SizedBox(height: 6),
      itemBuilder: (context, index) {
        final item = _campaigns[index];
        final isActive = selected.id == item.id;

        return _CampaignListItem(
          campaign: item,
          isActive: isActive,
          onTap: () {
            setState(() => _selectedId = item.id);
            _syncFormFields(item);
          },
        );
      },
    );
  }

  Widget _buildFormContent(MarketingCampaign campaign) {
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Phase 1: Image
        CampaignCollapsibleSection(
          title: '1. Diseño',
          subtitle: 'Imagen base de la campaña',
          icon: Icons.image_rounded,
          initiallyExpanded: campaign.phase == MarketingCampaignPhase.design,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if ((campaign.baseImageUrl ?? '').isNotEmpty)
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    campaign.baseImageUrl!,
                    height: 140,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) =>
                        Container(
                          height: 140,
                          color: scheme.surfaceContainer,
                          child: const Center(
                            child: Text('Error cargando imagen'),
                          ),
                        ),
                  ),
                ),
              if ((campaign.baseImageUrl ?? '').isNotEmpty)
                const SizedBox(height: 10),
              if (_assets.isNotEmpty)
                DropdownButtonFormField<String>(
                  value: _assets.any((a) => a.id == campaign.galleryAssetId)
                      ? campaign.galleryAssetId
                      : null,
                  items: _assets
                      .map((item) =>
                          DropdownMenuItem(
                            value: item.id,
                            child: Text(item.fileName,
                                overflow: TextOverflow.ellipsis),
                          ))
                      .toList(),
                  onChanged: _busyAction
                      ? null
                      : (value) {
                          if (value != null) _changeBaseImage(value);
                        },
                  decoration: const InputDecoration(
                    labelText: 'Seleccionar imagen',
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(
                        horizontal: 10, vertical: 8),
                  ),
                ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                height: 36,
                child: OutlinedButton.icon(
                  onPressed: _busyAction ? null : _confirmBaseImage,
                  icon: const Icon(Icons.check_circle_outline_rounded, size: 16),
                  label: const Text('Confirmar imagen'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        // Phase 2: Copy
        CampaignCollapsibleSection(
          title: '2. Copy',
          subtitle: 'Redacción y textos del anuncio',
          icon: Icons.edit_rounded,
          initiallyExpanded: campaign.phase == MarketingCampaignPhase.copySegmentation,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _busyAction ? null : _uploadDesign,
                      icon: const Icon(Icons.upload_file_rounded, size: 14),
                      label: const Text('Subir diseño'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _busyAction
                          ? null
                          : () => ref
                              .read(marketingApiProvider)
                              .regenerateCampaignCopy(campaign.id)
                              .then((_) => _load()),
                      icon: const Icon(Icons.auto_fix_high_rounded, size: 14),
                      label: const Text('Regenerar'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if ((campaign.finalDesignUrl ?? '').isNotEmpty)
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    campaign.finalDesignUrl!,
                    height: 120,
                    width: double.infinity,
                    fit: BoxFit.cover,
                  ),
                ),
              if ((campaign.finalDesignUrl ?? '').isNotEmpty)
                const SizedBox(height: 10),
              CompactFormField(
                label: 'Headline',
                controller: _headlineCtrl,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 8),
              CompactFormField(
                label: 'Texto principal',
                controller: _primaryTextCtrl,
                maxLines: 2,
                minLines: 2,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 8),
              CompactFormField(
                label: 'Descripción',
                controller: _descriptionCtrl,
                maxLines: 2,
                minLines: 1,
                onChanged: (_) => setState(() {}),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        // Phase 3: Segmentation + Budget
        CampaignCollapsibleSection(
          title: '3. Segmentación',
          subtitle: 'Audiencia y presupuesto',
          icon: Icons.people_rounded,
          initiallyExpanded: campaign.phase == MarketingCampaignPhase.copySegmentation,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CompactFieldRow(
                field1: CompactFormField(
                  label: 'Presupuesto diario',
                  controller: _dailyBudgetCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                field2: CompactFormField(
                  label: 'Presupuesto total',
                  controller: _totalBudgetCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(height: 8),
              CompactFormField(
                label: 'WhatsApp destino',
                controller: _phoneCtrl,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 8),
              CompactFormField(
                label: 'URL destino (opcional)',
                controller: _destinationCtrl,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 8),
              CompactFieldRow(
                field1: CompactFormField(
                  label: 'Ciudad',
                  controller: _cityCtrl,
                  onChanged: (_) => setState(() {}),
                ),
                field2: CompactFormField(
                  label: 'Radio (km)',
                  controller: _radiusCtrl,
                  keyboardType: TextInputType.number,
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(height: 8),
              CompactFieldRow(
                field1: CompactFormField(
                  label: 'Edad mínima',
                  controller: _ageMinCtrl,
                  keyboardType: TextInputType.number,
                  onChanged: (_) => setState(() {}),
                ),
                field2: CompactFormField(
                  label: 'Edad máxima',
                  controller: _ageMaxCtrl,
                  keyboardType: TextInputType.number,
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(height: 8),
              CompactFormField(
                label: 'Intereses (coma separados)',
                controller: _interestsCtrl,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 8),
              CompactFormField(
                label: 'Objetivo Meta Ads',
                controller: _objectiveCtrl,
                onChanged: (_) => setState(() {}),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        // Actions
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            FilledButton.icon(
              onPressed: _busyAction ? null : _saveDraft,
              icon: const Icon(Icons.save_rounded, size: 14),
              label: const Text('Guardar', style: TextStyle(fontSize: 12)),
            ),
            FilledButton.icon(
              onPressed: _busyAction ? null : _publishCampaign,
              icon: const Icon(Icons.send_rounded, size: 14),
              label: const Text('Publicar', style: TextStyle(fontSize: 12)),
            ),
            OutlinedButton.icon(
              onPressed: _busyAction ? null : _activateCampaign,
              icon: const Icon(Icons.play_arrow_rounded, size: 14),
              label: const Text('Activar', style: TextStyle(fontSize: 12)),
            ),
            OutlinedButton.icon(
              onPressed: _busyAction ? null : _pauseCampaign,
              icon: const Icon(Icons.pause_rounded, size: 14),
              label: const Text('Pausar', style: TextStyle(fontSize: 12)),
            ),
            OutlinedButton.icon(
              onPressed: _busyAction ? null : _duplicateCampaign,
              icon: const Icon(Icons.copy_rounded, size: 14),
              label: const Text('Duplicar', style: TextStyle(fontSize: 12)),
            ),
            OutlinedButton.icon(
              onPressed: _busyAction ? null : _rejectCampaign,
              icon: const Icon(Icons.close_rounded, size: 14),
              label: const Text('Rechazar', style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
        const SizedBox(height: 10),
        // Debug info
        CampaignCollapsibleSection(
          title: 'Detalles técnicos',
          subtitle: 'Meta Ads y configuración',
          icon: Icons.settings_rounded,
          initiallyExpanded: false,
          isDense: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildKeyValue('Campaign ID', campaign.metaCampaignId),
              _buildKeyValue('Ad Set ID', campaign.metaAdSetId),
              _buildKeyValue('Creative ID', campaign.metaCreativeId),
              _buildKeyValue('Ad ID', campaign.metaAdId),
              _buildKeyValue('Meta Status', campaign.metaStatus),
              _buildKeyValue('Meta Error', campaign.metaError),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildKeyValue(String key, String? value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(
              key,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value?.trim().isEmpty ?? true ? '-' : value!,
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ),
        ],
      ),
    );
  }
}

/// Campaign list item - compact and efficient
class _CampaignListItem extends StatefulWidget {
  final MarketingCampaign campaign;
  final bool isActive;
  final VoidCallback onTap;

  const _CampaignListItem({
    required this.campaign,
    required this.isActive,
    required this.onTap,
  });

  @override
  State<_CampaignListItem> createState() => _CampaignListItemState();
}

class _CampaignListItemState extends State<_CampaignListItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(8),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: widget.isActive
                    ? scheme.primary
                    : (_hovered
                        ? scheme.primary.withValues(alpha: 0.3)
                        : scheme.outlineVariant.withValues(alpha: 0.2)),
                width: widget.isActive ? 1.5 : 1,
              ),
              color: widget.isActive
                  ? scheme.primaryContainer.withValues(alpha: 0.3)
                  : (_hovered
                      ? scheme.surfaceContainer
                      : Colors.transparent),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.campaign.headline ?? 'Sin headline',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 3),
                Text(
                  _statusLabel(widget.campaign.status),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        fontSize: 10,
                        color: _statusColor(context, widget.campaign.status),
                      ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${widget.campaign.dailyBudget?.toStringAsFixed(2) ?? '-'} ${widget.campaign.currency == MarketingCampaignCurrency.usd ? 'USD' : 'DOP'}/día',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        fontSize: 10,
                        color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
                      ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _statusLabel(MarketingCampaignStatus status) {
    switch (status) {
      case MarketingCampaignStatus.draft:
        return '● Borrador';
      case MarketingCampaignStatus.ready:
        return '● Lista';
      case MarketingCampaignStatus.publishing:
        return '◐ Publicando...';
      case MarketingCampaignStatus.active:
        return '● Activa';
      case MarketingCampaignStatus.paused:
        return '⏸ Pausada';
      case MarketingCampaignStatus.error:
        return '✗ Error';
      case MarketingCampaignStatus.rejected:
        return '✗ Rechazada';
    }
  }

  Color _statusColor(BuildContext context, MarketingCampaignStatus status) {
    final scheme = Theme.of(context).colorScheme;
    switch (status) {
      case MarketingCampaignStatus.active:
        return scheme.tertiary;
      case MarketingCampaignStatus.publishing:
      case MarketingCampaignStatus.ready:
        return scheme.primary;
      case MarketingCampaignStatus.error:
      case MarketingCampaignStatus.rejected:
        return scheme.error;
      default:
        return scheme.onSurfaceVariant.withValues(alpha: 0.6);
    }
  }
}
