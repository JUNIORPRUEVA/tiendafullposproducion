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
import 'marketing_models.dart';

class PublicidadCampanasScreen extends ConsumerStatefulWidget {
  const PublicidadCampanasScreen({super.key});

  @override
  ConsumerState<PublicidadCampanasScreen> createState() =>
      _PublicidadCampanasScreenState();
}

class _PublicidadCampanasScreenState
    extends ConsumerState<PublicidadCampanasScreen> {
  bool _loading = true;
  bool _busy = false;
  String? _error;
  List<MarketingCampaign> _campaigns = const [];
  List<MarketingMediaAsset> _assets = const [];
  MetaAdsConfigDebug? _metaConfig;
  String? _selectedId;

  final _dailyBudgetCtrl = TextEditingController();
  final _totalBudgetCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _destinationCtrl = TextEditingController();
  final _headlineCtrl = TextEditingController();
  final _primaryTextCtrl = TextEditingController();
  final _descriptionCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _radiusCtrl = TextEditingController(text: '15');
  final _ageMinCtrl = TextEditingController(text: '24');
  final _ageMaxCtrl = TextEditingController(text: '60');
  final _interestsCtrl = TextEditingController();
  final _objectiveCtrl = TextEditingController(text: 'OUTCOME_TRAFFIC');

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _dailyBudgetCtrl.dispose();
    _totalBudgetCtrl.dispose();
    _phoneCtrl.dispose();
    _destinationCtrl.dispose();
    _headlineCtrl.dispose();
    _primaryTextCtrl.dispose();
    _descriptionCtrl.dispose();
    _cityCtrl.dispose();
    _radiusCtrl.dispose();
    _ageMinCtrl.dispose();
    _ageMaxCtrl.dispose();
    _interestsCtrl.dispose();
    _objectiveCtrl.dispose();
    super.dispose();
  }

  MarketingCampaign? get _selectedCampaign {
    for (final item in _campaigns) {
      if (item.id == _selectedId) return item;
    }
    return _campaigns.isEmpty ? null : _campaigns.first;
  }

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
      _syncEditors(_selectedCampaign);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is ApiException ? e.message : '$e';
        _loading = false;
      });
    }
  }

  void _syncEditors(MarketingCampaign? campaign) {
    if (campaign == null) return;
    _dailyBudgetCtrl.text = campaign.dailyBudget?.toStringAsFixed(2) ?? '';
    _totalBudgetCtrl.text = campaign.totalBudget?.toStringAsFixed(2) ?? '';
    _phoneCtrl.text = campaign.whatsappPhone ?? '';
    _destinationCtrl.text = campaign.destinationUrl ?? '';
    _headlineCtrl.text = campaign.headline ?? '';
    _primaryTextCtrl.text = campaign.primaryText ?? '';
    _descriptionCtrl.text = campaign.description ?? '';

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

  Future<void> _runBusy(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _createDraft() async {
    await _runBusy(() async {
      final api = ref.read(marketingApiProvider);
      final created = await api.generateCampaignDraft();
      if (!mounted) return;
      await _load();
      setState(() => _selectedId = created.id);
      _syncEditors(created);
    });
  }

  Future<void> _changeBaseImage(String mediaAssetId) async {
    final campaign = _selectedCampaign;
    if (campaign == null) return;
    await _runBusy(() async {
      final updated = await ref
          .read(marketingApiProvider)
          .changeCampaignBaseImage(campaign.id, mediaAssetId);
      if (!mounted) return;
      await _load();
      _syncEditors(updated);
    });
  }

  Future<void> _confirmBaseImage() async {
    final campaign = _selectedCampaign;
    if (campaign == null) return;
    await _runBusy(() async {
      final updated = await ref
          .read(marketingApiProvider)
          .confirmCampaignBaseImage(campaign.id);
      if (!mounted) return;
      await _load();
      _syncEditors(updated);
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
        SnackBar(content: Text('No se pudo abrir el explorador: $e')),
      );
      return;
    }

    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null || bytes.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Archivo inválido.')),
      );
      return;
    }

    await _runBusy(() async {
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
      if (!mounted) return;
      await _load();
    });
  }

  Future<void> _saveDraft() async {
    final campaign = _selectedCampaign;
    if (campaign == null) return;

    final dailyBudget = double.tryParse(_dailyBudgetCtrl.text.trim()) ?? 0;
    if (dailyBudget <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('El presupuesto diario debe ser mayor a 0.')),
      );
      return;
    }

    final interests = _interestsCtrl.text
        .split(',')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);

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

    await _runBusy(() async {
      final updated = await ref.read(marketingApiProvider).updateCampaign(
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
      if (!mounted) return;
      await _load();
      _syncEditors(updated);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Borrador guardado.')),
      );
    });
  }

  Future<void> _createMetaCampaign() async {
    final campaign = _selectedCampaign;
    if (campaign == null) return;
    await _runBusy(() async {
      await _saveDraft();
      await ref.read(marketingApiProvider).createMetaCampaign(campaign.id);
      if (!mounted) return;
      await _load();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Campaña creada en Meta en estado PAUSED.')),
      );
    });
  }

  Future<void> _activateCampaign() async {
    final campaign = _selectedCampaign;
    if (campaign == null) return;
    await _runBusy(() async {
      await ref.read(marketingApiProvider).activateCampaign(campaign.id);
      if (!mounted) return;
      await _load();
    });
  }

  Future<void> _pauseCampaign() async {
    final campaign = _selectedCampaign;
    if (campaign == null) return;
    await _runBusy(() async {
      await ref.read(marketingApiProvider).pauseCampaign(campaign.id);
      if (!mounted) return;
      await _load();
    });
  }

  Future<void> _duplicateCampaign() async {
    final campaign = _selectedCampaign;
    if (campaign == null) return;
    await _runBusy(() async {
      final duplicate =
          await ref.read(marketingApiProvider).duplicateCampaign(campaign.id);
      if (!mounted) return;
      await _load();
      setState(() => _selectedId = duplicate.id);
      _syncEditors(duplicate);
    });
  }

  Future<void> _rejectCampaign() async {
    final campaign = _selectedCampaign;
    if (campaign == null) return;
    await _runBusy(() async {
      await ref.read(marketingApiProvider).rejectCampaign(campaign.id);
      if (!mounted) return;
      await _load();
    });
  }

  String _statusLabel(MarketingCampaignStatus status) {
    switch (status) {
      case MarketingCampaignStatus.ready:
        return 'Lista para publicitar';
      case MarketingCampaignStatus.publishing:
        return 'Publicando';
      case MarketingCampaignStatus.active:
        return 'Activa';
      case MarketingCampaignStatus.paused:
        return 'Pausada';
      case MarketingCampaignStatus.error:
        return 'Error';
      case MarketingCampaignStatus.rejected:
        return 'Rechazada';
      case MarketingCampaignStatus.draft:
        return 'Borrador';
    }
  }

  String _phaseLabel(MarketingCampaignPhase phase) {
    switch (phase) {
      case MarketingCampaignPhase.design:
        return 'Fase 1: Crear diseño';
      case MarketingCampaignPhase.copySegmentation:
        return 'Fase 2: Copy + segmentación';
      case MarketingCampaignPhase.publish:
        return 'Fase 3: Publicitar';
    }
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
        onPressed: _busy ? null : _createDraft,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Nueva campaña'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Text(
                    _error!.trim().isEmpty
                        ? 'No se pudo cargar campañas. Intenta recargar.'
                        : _error!,
                  ),
                )
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final isCompact = constraints.maxWidth < 900;
                    final detail = selected == null
                        ? const Center(
                            child: Text('No hay campañas. Crea una para iniciar.'),
                          )
                        : _buildCampaignDetail(selected);

                    if (isCompact) {
                      return Column(
                        children: [
                          SizedBox(
                            height: 240,
                            child: _buildCampaignList(selected),
                          ),
                          const Divider(height: 1),
                          Expanded(child: detail),
                        ],
                      );
                    }

                    return Row(
                      children: [
                        SizedBox(
                          width: 340,
                          child: _buildCampaignList(selected),
                        ),
                        const VerticalDivider(width: 1),
                        Expanded(child: detail),
                      ],
                    );
                  },
                ),
    );
  }

  Widget _buildCampaignList(MarketingCampaign? selected) {
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: _campaigns.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final item = _campaigns[index];
        final active = selected?.id == item.id;

        return InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () {
            setState(() => _selectedId = item.id);
            _syncEditors(item);
          },
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: active
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.headline ?? 'Campaña sin headline',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 6),
                Text(_statusLabel(item.status)),
                const SizedBox(height: 4),
                Text(_phaseLabel(item.phase)),
                const SizedBox(height: 6),
                Text(
                  'Presupuesto diario: ${item.dailyBudget?.toStringAsFixed(2) ?? '-'} ${item.currency == MarketingCampaignCurrency.usd ? 'USD' : 'DOP'}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 4),
                Text(
                  'WhatsApp: ${item.whatsappPhone ?? '-'}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildCampaignDetail(MarketingCampaign campaign) {
    final metaConfig = _metaConfig;
    final isMetaIncomplete =
        metaConfig != null && (!metaConfig.hasAdAccountId || !metaConfig.tokenValid);
    final validGalleryAssetId = _assets.any((item) => item.id == campaign.galleryAssetId)
      ? campaign.galleryAssetId
      : null;

    final prompt = _buildDesignPrompt(campaign);

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (isMetaIncomplete)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'Configuración incompleta de Meta Ads: falta META_AD_ACCOUNT_ID o token inválido. Estados orgánicos no se afectan.',
              ),
            ),
          _buildPhaseCard(
            title: 'Fase 1: Crear diseño',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if ((campaign.baseImageUrl ?? '').isNotEmpty)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.network(
                      campaign.baseImageUrl!,
                      height: 180,
                      width: double.infinity,
                      fit: BoxFit.cover,
                    ),
                  ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: validGalleryAssetId,
                  isExpanded: true,
                  items: _assets
                      .map(
                        (item) => DropdownMenuItem(
                          value: item.id,
                          child: Text(
                            item.fileName,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: _busy
                      ? null
                      : (value) {
                          if (value == null) return;
                          _changeBaseImage(value);
                        },
                  decoration: const InputDecoration(
                    labelText: 'Imagen base desde Galería de contenido',
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Prompt para diseño',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 6),
                SelectableText(prompt),
                const SizedBox(height: 8),
                Row(
                  children: [
                    OutlinedButton.icon(
                      onPressed: _busy
                          ? null
                          : () {
                              _confirmBaseImage();
                            },
                      icon: const Icon(Icons.check_circle_outline_rounded),
                      label: const Text('Confirmar imagen base'),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: () {
                        final messenger = ScaffoldMessenger.of(context);
                        Clipboard.setData(ClipboardData(text: prompt));
                        messenger.showSnackBar(
                          const SnackBar(content: Text('Prompt copiado.')),
                        );
                      },
                      icon: const Icon(Icons.copy_rounded),
                      label: const Text('Copiar prompt'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _buildPhaseCard(
            title: 'Fase 2: Copy + segmentación',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    ElevatedButton.icon(
                      onPressed: _busy ? null : _uploadDesign,
                      icon: const Icon(Icons.upload_file_rounded),
                      label: const Text('Subir diseño final'),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: _busy
                          ? null
                          : () =>
                                ref.read(marketingApiProvider).regenerateCampaignCopy(campaign.id).then((_) => _load()),
                      icon: const Icon(Icons.auto_fix_high_rounded),
                      label: const Text('Regenerar copy'),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if ((campaign.finalDesignUrl ?? '').isNotEmpty)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.network(
                      campaign.finalDesignUrl!,
                      height: 180,
                      width: double.infinity,
                      fit: BoxFit.cover,
                    ),
                  ),
                const SizedBox(height: 12),
                TextField(
                  controller: _headlineCtrl,
                  decoration: const InputDecoration(labelText: 'Headline'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _primaryTextCtrl,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Texto principal corto',
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _descriptionCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'Descripción'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _interestsCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Intereses sugeridos (coma separada)',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _buildPhaseCard(
            title: 'Fase 3: Publicitar',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _dailyBudgetCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(
                          labelText: 'Presupuesto diario',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _totalBudgetCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(
                          labelText: 'Presupuesto total opcional',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _phoneCtrl,
                  decoration: const InputDecoration(
                    labelText: 'WhatsApp destino',
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _destinationCtrl,
                  decoration: const InputDecoration(
                    labelText: 'URL destino (opcional)',
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _cityCtrl,
                        decoration: const InputDecoration(labelText: 'Ciudad'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _radiusCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Radio (km)'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _ageMinCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Edad mínima'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _ageMaxCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Edad máxima'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _objectiveCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Objetivo publicitario',
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: _busy ? null : _saveDraft,
                      icon: const Icon(Icons.save_rounded),
                      label: const Text('Guardar borrador'),
                    ),
                    FilledButton.icon(
                      onPressed: _busy ? null : _createMetaCampaign,
                      icon: const Icon(Icons.campaign_rounded),
                      label: const Text('Crear campaña'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _activateCampaign,
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: const Text('Activar campaña'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _pauseCampaign,
                      icon: const Icon(Icons.pause_rounded),
                      label: const Text('Pausar campaña'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _duplicateCampaign,
                      icon: const Icon(Icons.copy_rounded),
                      label: const Text('Duplicar'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _rejectCampaign,
                      icon: const Icon(Icons.cancel_rounded),
                      label: const Text('Rechazar'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: const Text('Detalles técnicos'),
                  children: [
                    _kv('Campaign ID', campaign.metaCampaignId),
                    _kv('Ad Set ID', campaign.metaAdSetId),
                    _kv('Creative ID', campaign.metaCreativeId),
                    _kv('Ad ID', campaign.metaAdId),
                    _kv('Meta status', campaign.metaStatus),
                    _kv('Meta error', campaign.metaError),
                    _kv('Error code', campaign.metaErrorCode),
                    _kv('Error subcode', campaign.metaErrorSubcode),
                    _kv('fbtrace_id', campaign.fbtraceId),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _kv(String key, String? value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(width: 140, child: Text(key)),
          Expanded(child: SelectableText(value?.trim().isEmpty ?? true ? '-' : value!)),
        ],
      ),
    );
  }

  Widget _buildPhaseCard({required String title, required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }

  String _buildDesignPrompt(MarketingCampaign campaign) {
    final image = campaign.baseImageUrl ?? '';
    final focus = campaign.aiAngle ?? 'producto principal';
    return '''Diseña una pieza publicitaria pagada para Meta Ads.

Usa esta imagen base pública: $image
No cambies el producto principal ni su proporción visual.
Mantén estilo comercial limpio y legible para móvil.

Objetivo del anuncio: ${_objectiveCtrl.text.trim().isEmpty ? 'OUTCOME_TRAFFIC' : _objectiveCtrl.text.trim()}
Ángulo sugerido: $focus
Salida: versión 1080x1350 y 1080x1920.''';
  }
}
