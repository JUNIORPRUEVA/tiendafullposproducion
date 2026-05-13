import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/app_permissions.dart';
import '../../core/auth/auth_provider.dart';
import '../../core/errors/api_exception.dart';
import '../../core/widgets/app_drawer.dart';
import '../../core/widgets/custom_app_bar.dart';
import 'marketing_api.dart';
import 'marketing_campaign_models.dart';
import 'marketing_models.dart';
import 'providers/campaign_autosave_provider.dart';
import 'widgets/autosave_indicator.dart';

class PublicidadCampanasScreenV2 extends ConsumerStatefulWidget {
  const PublicidadCampanasScreenV2({super.key});

  @override
  ConsumerState<PublicidadCampanasScreenV2> createState() =>
      _PublicidadCampanasScreenV2State();
}

class _PublicidadCampanasScreenV2State
    extends ConsumerState<PublicidadCampanasScreenV2> {
  static const String _defaultCity = 'Higuey, La Altagracia';
  static const int _defaultRadiusKm = 10;
  static const double _defaultMinAge = 25;
  static const double _defaultMaxAge = 60;
  static const String _fixedObjective = 'OUTCOME_ENGAGEMENT';

  bool _loading = true;
  bool _busyAction = false;
  String? _error;

  List<MarketingCampaign> _campaigns = const [];
  List<MarketingMediaAsset> _assets = const [];
  String? _selectedId;

  final _phoneCtrl = TextEditingController();
  final _dailyBudgetCtrl = TextEditingController(text: '500');
  final _cityCtrl = TextEditingController(text: _defaultCity);

  RangeValues _ageRange = const RangeValues(_defaultMinAge, _defaultMaxAge);
  int _radiusKm = _defaultRadiusKm;
  final Set<String> _selectedInterests = <String>{};

  Timer? _autosaveTimer;
  AutosaveState _autosaveState = AutosaveState();

  static const List<int> _radiusPresets = [5, 10, 15, 30];
  static const List<int> _budgetPresets = [300, 500, 1000, 3000];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _autosaveTimer?.cancel();
    _phoneCtrl.dispose();
    _dailyBudgetCtrl.dispose();
    _cityCtrl.dispose();
    super.dispose();
  }

  MarketingCampaign? get _selectedCampaign {
    try {
      return _campaigns.firstWhere((c) => c.id == _selectedId);
    } catch (_) {
      return _campaigns.isNotEmpty ? _campaigns.first : null;
    }
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
        _selectedId = selected;
        _loading = false;
      });

      if (selected != null) {
        final campaign = _campaigns.firstWhere((c) => c.id == selected);
        _syncFormFromCampaign(campaign);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is ApiException ? e.message : '$e';
        _loading = false;
      });
    }
  }

  void _syncFormFromCampaign(MarketingCampaign campaign) {
    final audience = campaign.finalAudience ?? campaign.recommendedAudience ?? {};
    final knownWhatsapp = _whatsappOptions(campaign);
    final campaignPhone = (campaign.whatsappPhone ?? '').trim();
    _phoneCtrl.text = campaignPhone.isNotEmpty
      ? campaignPhone
      : (knownWhatsapp.isNotEmpty ? knownWhatsapp.first : '');
    _dailyBudgetCtrl.text = (campaign.dailyBudget ?? 500).toStringAsFixed(0);
    final city = '${audience['city'] ?? ''}'.trim();
    _cityCtrl.text = city.isEmpty ? _defaultCity : city;

    final radius = (audience['radiusKm'] as num?)?.toInt() ?? _defaultRadiusKm;
    _radiusKm = _radiusPresets.contains(radius) ? radius : _defaultRadiusKm;

    final minAge =
      (((audience['ageMin'] as num?)?.toDouble() ?? _defaultMinAge).clamp(18, 65))
        .toDouble();
    final maxAge =
      (((audience['ageMax'] as num?)?.toDouble() ?? _defaultMaxAge).clamp(18, 65))
        .toDouble();
    _ageRange = RangeValues(
      minAge <= maxAge ? minAge : _defaultMinAge,
      minAge <= maxAge ? maxAge : _defaultMaxAge,
    );

    _selectedInterests
      ..clear()
      ..addAll(_extractSuggestedInterests(campaign));

    _autosaveState = AutosaveState();
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
      final created = await ref.read(marketingApiProvider).generateCampaignDraft();
      await _load();
      if (!mounted) return;
      setState(() => _selectedId = created.id);
    });
  }

  Future<void> _applyMediaAndAutoGenerate(String mediaAssetId) async {
    final campaign = _selectedCampaign;
    if (campaign == null) return;

    await _runAction('Media aplicada y copy generado', () async {
      final api = ref.read(marketingApiProvider);
      await api.changeCampaignBaseImage(campaign.id, mediaAssetId);
      await api.confirmCampaignBaseImage(campaign.id);
      await api.regenerateCampaignCopy(campaign.id);
      await _load();
    });
  }

  void _scheduleAutosave() {
    final campaign = _selectedCampaign;
    if (campaign == null) return;

    _autosaveTimer?.cancel();
    setState(() {
      _autosaveState = _autosaveState.copyWith(
        hasUnsavedChanges: true,
        error: null,
      );
    });

    _autosaveTimer = Timer(const Duration(milliseconds: 850), () async {
      await _saveDraftSilently(campaign.id);
    });
  }

  Future<void> _saveDraftSilently(String campaignId) async {
    if (!mounted) return;

    setState(() {
      _autosaveState = _autosaveState.copyWith(
        isLoading: true,
        error: null,
      );
    });

    try {
      await ref.read(marketingApiProvider).updateCampaign(
            campaignId,
            cta: 'WHATSAPP_MESSAGE',
            dailyBudget: _dailyBudget,
            whatsappPhone: _phoneCtrl.text.trim(),
            finalAudience: _buildAudience(),
          );

      if (!mounted) return;
      setState(() {
        _autosaveState = _autosaveState.copyWith(
          isLoading: false,
          hasUnsavedChanges: false,
          lastSavedAt: DateTime.now().toIso8601String(),
          error: null,
        );
      });
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _autosaveState = _autosaveState.copyWith(
          isLoading: false,
          hasUnsavedChanges: true,
          error: '$e',
        );
      });
    }
  }

  Future<void> _publishCampaign() async {
    final campaign = _selectedCampaign;
    if (campaign == null) return;

    await _runAction('Campaña publicada', () async {
      await _saveDraftSilently(campaign.id);
      await ref.read(marketingApiProvider).createMetaCampaign(
            campaign.id,
            objective: _fixedObjective,
          );
      await _load();
    });
  }

  double get _dailyBudget => double.tryParse(_dailyBudgetCtrl.text.trim()) ?? 0;

  Map<String, dynamic> _buildAudience() {
    return {
      'city': _cityCtrl.text.trim(),
      'radiusKm': _radiusKm,
      'ageMin': _ageRange.start.round(),
      'ageMax': _ageRange.end.round(),
      'interests': _selectedInterests.toList(growable: false),
      'objective': _fixedObjective,
      'gender': 'ALL',
    };
  }

  List<String> _extractSuggestedInterests(MarketingCampaign campaign) {
    final source = campaign.recommendedAudience ?? campaign.finalAudience ?? {};
    final raw = source['interests'];
    if (raw is! List) return const <String>[];
    return raw
        .map((item) => '$item'.trim())
        .where((item) => item.isNotEmpty)
        .take(8)
        .toList(growable: false);
  }

  String _detectMediaType(MarketingCampaign campaign) {
    final selected = _assets.where((item) => item.id == campaign.galleryAssetId);
    if (selected.isEmpty) return 'Media';
    return _isVideo(selected.first) ? 'Video' : 'Imagen';
  }

  bool _isVideo(MarketingMediaAsset asset) {
    return asset.mimeType.toLowerCase().contains('video');
  }

  String _estimateReachText(double budget) {
    if (budget <= 0) return 'Ingresa presupuesto para estimar alcance';
    final min = (budget * 22).round();
    final max = (budget * 41).round();
    return 'Alcance estimado: $min - $max personas/dia';
  }

  List<String> _cityOptions(MarketingCampaign campaign) {
    final options = <String>{
      _defaultCity,
      'Higuey',
      'Punta Cana',
      'Bavaro',
    };
    final source = campaign.recommendedAudience ?? campaign.finalAudience ?? {};
    final city = '${source['city'] ?? ''}'.trim();
    if (city.isNotEmpty) options.add(city);
    final current = _cityCtrl.text.trim();
    if (current.isNotEmpty) options.add(current);
    return options.toList(growable: false)..sort();
  }

  List<String> _whatsappOptions(MarketingCampaign campaign) {
    final options = <String>{};
    final selected = (campaign.whatsappPhone ?? '').trim();
    if (selected.isNotEmpty) options.add(selected);
    for (final item in _campaigns) {
      final phone = (item.whatsappPhone ?? '').trim();
      if (phone.isNotEmpty) options.add(phone);
    }
    final current = _phoneCtrl.text.trim();
    if (current.isNotEmpty) options.add(current);
    return options.toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authStateProvider).user;
    final canView =
        user != null && hasPermission(user.appRole, AppPermission.viewPublicidad);

    if (!canView) {
      return Scaffold(
        appBar: const CustomAppBar(title: 'Publicidad / Campanas'),
        body: const Center(
          child: Text('Acceso denegado. Solo ADMIN puede usar Publicidad.'),
        ),
      );
    }

    final campaign = _selectedCampaign;

    return Scaffold(
      drawer: buildAdaptiveDrawer(context, currentUser: user),
      appBar: const CustomAppBar(title: 'Publicidad / Campanas'),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _busyAction || _loading ? null : _createDraft,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Nueva campana'),
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
              : campaign == null
                  ? _buildEmptyState()
                  : Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                          child: _buildSimpleSteps(campaign),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Todo fijo a WhatsApp Messages: selecciona media, presupuesto, WhatsApp y publica.',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant,
                                      ),
                                ),
                              ),
                              AutosaveStatusIndicator(state: _autosaveState),
                            ],
                          ),
                        ),
                        Expanded(
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              final isWide = constraints.maxWidth >= 1180;
                              if (isWide) {
                                return Row(
                                  children: [
                                    SizedBox(
                                      width: 290,
                                      child: _buildCampaignList(campaign),
                                    ),
                                    const VerticalDivider(width: 1),
                                    Expanded(
                                      child: _buildEditorAndPreview(
                                        campaign,
                                        isWide: true,
                                      ),
                                    ),
                                  ],
                                );
                              }

                              return Column(
                                children: [
                                  SizedBox(
                                    height: 170,
                                    child: _buildCampaignList(campaign),
                                  ),
                                  const Divider(height: 1),
                                  Expanded(
                                    child: _buildEditorAndPreview(
                                      campaign,
                                      isWide: false,
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                      ],
                    ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.campaign_rounded,
            size: 52,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 12),
          Text(
            'No hay campanas todavia',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Crea una campana y publica en minutos.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildSimpleSteps(MarketingCampaign campaign) {
    final hasMedia = (campaign.baseImageUrl ?? '').isNotEmpty;
    final hasBudget = _dailyBudget > 0;
    final hasWhatsapp = _phoneCtrl.text.trim().isNotEmpty;
    final hasPreview =
        (campaign.baseImageUrl ?? campaign.finalDesignUrl ?? '').trim().isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
        gradient: LinearGradient(
          colors: [
            Theme.of(context).colorScheme.surface,
            Theme.of(context).colorScheme.surfaceContainer,
          ],
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: _StepChip(
              index: 1,
              label: 'Media',
              icon: Icons.perm_media_rounded,
              isDone: hasMedia,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _StepChip(
              index: 2,
              label: 'Presupuesto',
              icon: Icons.payments_rounded,
              isDone: hasBudget,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _StepChip(
              index: 3,
              label: 'WhatsApp',
              icon: Icons.chat_rounded,
              isDone: hasWhatsapp,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _StepChip(
              index: 4,
              label: 'Preview',
              icon: Icons.preview_rounded,
              isDone: hasPreview,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _StepChip(
              index: 5,
              label: 'Publicar',
              icon: Icons.send_rounded,
              isDone: campaign.status == MarketingCampaignStatus.active ||
                  campaign.status == MarketingCampaignStatus.publishing,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCampaignList(MarketingCampaign selected) {
    return ListView.separated(
      padding: const EdgeInsets.all(8),
      itemCount: _campaigns.length,
      separatorBuilder: (_, _) => const SizedBox(height: 6),
      itemBuilder: (context, index) {
        final item = _campaigns[index];
        return _CampaignListItem(
          campaign: item,
          isActive: selected.id == item.id,
          onTap: () {
            setState(() => _selectedId = item.id);
            _syncFormFromCampaign(item);
          },
        );
      },
    );
  }

  Widget _buildEditorAndPreview(MarketingCampaign campaign, {required bool isWide}) {
    if (isWide) {
      return Row(
        children: [
          Expanded(
            flex: 3,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: _buildSimplifiedForm(campaign),
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(
            flex: 2,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: _buildLargePreview(campaign),
            ),
          ),
        ],
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildLargePreview(campaign),
          const SizedBox(height: 12),
          _buildSimplifiedForm(campaign),
        ],
      ),
    );
  }

  Widget _buildSimplifiedForm(MarketingCampaign campaign) {
    final cityOptions = _cityOptions(campaign);
    final whatsappOptions = _whatsappOptions(campaign);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _StepCard(
          title: '1. Imagen o video',
          subtitle: 'Selecciona la media. El sistema genera copy automaticamente.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_assets.isEmpty)
                const Text('No hay media disponible en galeria.')
              else
                SizedBox(
                  height: 116,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _assets.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 10),
                    itemBuilder: (context, index) {
                      final asset = _assets[index];
                      final selected = campaign.galleryAssetId == asset.id;
                      final thumb = (asset.thumbnailUrl ?? asset.imageUrl).trim();
                      return GestureDetector(
                        onTap: _busyAction
                            ? null
                            : () => _applyMediaAndAutoGenerate(asset.id),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          width: 170,
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: selected
                                  ? Theme.of(context).colorScheme.primary
                                  : Theme.of(context)
                                      .colorScheme
                                      .outlineVariant
                                      .withValues(alpha: 0.6),
                              width: selected ? 2 : 1,
                            ),
                            color: selected
                                ? Theme.of(context)
                                    .colorScheme
                                    .primaryContainer
                                    .withValues(alpha: 0.35)
                                : Theme.of(context).colorScheme.surface,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: thumb.isEmpty
                                      ? Container(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .surfaceContainer,
                                        )
                                      : Image.network(
                                          thumb,
                                          fit: BoxFit.cover,
                                          width: double.infinity,
                                        ),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                asset.fileName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.labelMedium,
                              ),
                              const SizedBox(height: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: _isVideo(asset)
                                      ? Theme.of(context)
                                          .colorScheme
                                          .tertiaryContainer
                                      : Theme.of(context)
                                          .colorScheme
                                          .secondaryContainer,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  _isVideo(asset) ? 'Video' : 'Imagen',
                                  style: Theme.of(context).textTheme.labelSmall,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _StepCard(
          title: '2. Presupuesto',
          subtitle: 'Presupuesto rapido. Segmentacion automatica con defaults de Higuey + 10km.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _dailyBudgetCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                ],
                decoration: const InputDecoration(
                  prefixText: 'DOP ',
                  labelText: 'Presupuesto diario',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) {
                  setState(() {});
                  _scheduleAutosave();
                },
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _budgetPresets
                    .map(
                      (preset) => ChoiceChip(
                        selected: _dailyBudget.round() == preset,
                        label: Text('$preset'),
                        onSelected: _busyAction
                            ? null
                            : (_) {
                                setState(() {
                                  _dailyBudgetCtrl.text = '$preset';
                                });
                                _scheduleAutosave();
                              },
                      ),
                    )
                    .toList(growable: false),
              ),
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  color: Theme.of(context)
                      .colorScheme
                      .tertiaryContainer
                      .withValues(alpha: 0.45),
                ),
                child: Text(
                  _estimateReachText(_dailyBudget),
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
              const SizedBox(height: 12),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(bottom: 4),
                title: Text(
                  'Ajustar ubicacion y edades (opcional)',
                  style: Theme.of(context).textTheme.labelMedium,
                ),
                subtitle: Text(
                  'Default activo: Higuey, La Altagracia · 10 km · 25-60',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: _cityCtrl.text.trim().isEmpty
                        ? null
                        : _cityCtrl.text.trim(),
                    items: cityOptions
                        .map(
                          (city) => DropdownMenuItem<String>(
                            value: city,
                            child: Text(city),
                          ),
                        )
                        .toList(growable: false),
                    onChanged: _busyAction
                        ? null
                        : (value) {
                            if (value == null) return;
                            setState(() => _cityCtrl.text = value);
                            _scheduleAutosave();
                          },
                    decoration: const InputDecoration(
                      labelText: 'Ciudad',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Radio',
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _radiusPresets
                        .map(
                          (preset) => ChoiceChip(
                            selected: _radiusKm == preset,
                            label: Text('$preset km'),
                            onSelected: _busyAction
                                ? null
                                : (_) {
                                    setState(() => _radiusKm = preset);
                                    _scheduleAutosave();
                                  },
                          ),
                        )
                        .toList(growable: false),
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Edades: ${_ageRange.start.round()} - ${_ageRange.end.round()}',
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                  ),
                  RangeSlider(
                    min: 18,
                    max: 65,
                    divisions: 47,
                    labels: RangeLabels(
                      _ageRange.start.round().toString(),
                      _ageRange.end.round().toString(),
                    ),
                    values: _ageRange,
                    onChanged: _busyAction
                        ? null
                        : (value) {
                            setState(() => _ageRange = value);
                            _scheduleAutosave();
                          },
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _StepCard(
          title: '3. WhatsApp destino',
          subtitle: 'Objetivo fijo: Mensajes/Interaccion. CTA fijo: Enviar mensaje.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DropdownButtonFormField<String>(
                initialValue:
                    _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim(),
                items: whatsappOptions
                    .map(
                      (phone) => DropdownMenuItem<String>(
                        value: phone,
                        child: Text(phone),
                      ),
                    )
                    .toList(growable: false),
                onChanged: _busyAction
                    ? null
                    : (value) {
                        if (value == null) return;
                        setState(() => _phoneCtrl.text = value);
                        _scheduleAutosave();
                      },
                decoration: const InputDecoration(
                  labelText: 'Numero WhatsApp',
                  border: OutlineInputBorder(),
                ),
              ),
              if (whatsappOptions.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'No hay numeros disponibles aun. Configura uno en una campana y luego selecciona aqui.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: const [
                  _Pill(label: 'Objetivo: Mensajes/Interaccion'),
                  _Pill(label: 'Destino: WhatsApp'),
                  _Pill(label: 'CTA: Enviar mensaje'),
                  _Pill(label: 'Advantage+ Multi Advertiser: Off'),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _StepCard(
          title: '5. Publicar',
          subtitle: 'Preview se actualiza solo cuando cambia media o ajustes.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: double.infinity,
                height: 46,
                child: FilledButton.icon(
                  onPressed: _busyAction ? null : _publishCampaign,
                  icon: const Icon(Icons.send_rounded),
                  label: const Text('Publicar campana'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLargePreview(MarketingCampaign campaign) {
    final image = campaign.finalDesignUrl ?? campaign.baseImageUrl ?? '';
    final mediaType = _detectMediaType(campaign);
    final description = (campaign.description ?? '').trim().isEmpty
        ? 'Descripcion automatica para generar conversaciones en WhatsApp.'
        : campaign.description!;
    final ctaLabel = 'Enviar mensaje por WhatsApp';

    Widget previewCard(String label, double height, {bool story = false}) {
      return Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
          color: Theme.of(context).colorScheme.surface,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
              child: Row(
                children: [
                  Text(
                    label,
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const Spacer(),
                  _Pill(label: mediaType),
                ],
              ),
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(story ? 18 : 0),
              child: image.trim().isEmpty
                  ? Container(
                      height: height,
                      color: Theme.of(context).colorScheme.surfaceContainer,
                      child: const Center(child: Text('Sin preview')),
                    )
                  : Image.network(
                      image,
                      height: height,
                      width: double.infinity,
                      fit: BoxFit.cover,
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    campaign.headline ?? 'Headline automatico',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    campaign.primaryText ?? 'Texto principal generado automaticamente.',
                    maxLines: story ? 2 : 3,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: null,
                      icon: const Icon(Icons.chat_bubble_rounded, size: 16),
                      label: Text(ctaLabel),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '4. Preview Meta Ads',
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        previewCard('Facebook Feed', 240),
        previewCard('Instagram Feed', 260),
        previewCard('Instagram Story', 340, story: true),
      ],
    );
  }
}

class _StepChip extends StatelessWidget {
  const _StepChip({
    required this.index,
    required this.label,
    required this.icon,
    required this.isDone,
  });

  final int index;
  final String label;
  final IconData icon;
  final bool isDone;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: isDone
            ? scheme.primaryContainer.withValues(alpha: 0.55)
            : scheme.surface,
        border: Border.all(
          color: isDone ? scheme.primary : scheme.outlineVariant,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            isDone ? Icons.check_circle_rounded : icon,
            size: 14,
            color: isDone ? scheme.primary : scheme.onSurfaceVariant,
          ),
          const SizedBox(width: 6),
          Text(
            '$index. $label',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      ),
    );
  }
}

class _StepCard extends StatelessWidget {
  const _StepCard({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
        color: Theme.of(context).colorScheme.surface,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: Theme.of(context).colorScheme.secondaryContainer,
      ),
      child: Text(label, style: Theme.of(context).textTheme.labelSmall),
    );
  }
}

class _CampaignListItem extends StatefulWidget {
  const _CampaignListItem({
    required this.campaign,
    required this.isActive,
    required this.onTap,
  });

  final MarketingCampaign campaign;
  final bool isActive;
  final VoidCallback onTap;

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
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: widget.isActive
                  ? scheme.primary
                  : (_hovered
                      ? scheme.primary.withValues(alpha: 0.3)
                      : scheme.outlineVariant.withValues(alpha: 0.4)),
              width: widget.isActive ? 1.6 : 1,
            ),
            color: widget.isActive
                ? scheme.primaryContainer.withValues(alpha: 0.3)
                : (_hovered ? scheme.surfaceContainer : Colors.transparent),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.campaign.headline ?? 'Sin headline',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context)
                    .textTheme
                    .labelLarge
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                _statusLabel(widget.campaign.status),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: _statusColor(context, widget.campaign.status),
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                '${widget.campaign.dailyBudget?.toStringAsFixed(0) ?? '-'} DOP/dia',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _statusLabel(MarketingCampaignStatus status) {
    switch (status) {
      case MarketingCampaignStatus.draft:
        return 'Borrador';
      case MarketingCampaignStatus.ready:
        return 'Lista';
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
      case MarketingCampaignStatus.paused:
      case MarketingCampaignStatus.draft:
        return scheme.onSurfaceVariant;
    }
  }
}
