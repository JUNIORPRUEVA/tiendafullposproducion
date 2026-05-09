import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api/env.dart';
import 'image_analysis_models.dart';
import 'marketing_api.dart';
import 'marketing_models.dart';

/// ============================================================
/// NUEVO FLUJO DE ESTADOS - CONTROLADO Y PROFESIONAL
/// ============================================================
///
/// Paso 1: Selección de imagen (usuario elige)
/// Paso 2: Análisis IA (análisis + recomendaciones)
/// Paso 3: Confirmación (preview + generar)
/// Paso 4: Generación (SOLO después de confirmar)
///

class EstadosNuevoFlujoScreen extends ConsumerStatefulWidget {
  const EstadosNuevoFlujoScreen({
    required this.initialStoryType,
    required this.onGenerateConfirmed,
    super.key,
  });

  final String initialStoryType;
  final Future<void> Function(String selectedImageId) onGenerateConfirmed;

  @override
  ConsumerState<EstadosNuevoFlujoScreen> createState() =>
      _EstadosNuevoFlujoScreenState();
}

class _EstadosNuevoFlujoScreenState
    extends ConsumerState<EstadosNuevoFlujoScreen> {
  // State
  late String _selectedStoryType;
  String? _selectedImageId;
  ImageAnalysisResult? _selectedImageAnalysis;
  bool _analyzing = false;
  bool _generating = false;
  String? _filterCategory;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _selectedStoryType = widget.initialStoryType;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: scheme.surfaceContainerLowest,
      appBar: AppBar(
        title: const Text('Generar Estado'),
        elevation: 0,
        backgroundColor: scheme.surface,
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Story type selector bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              color: scheme.surface,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _buildStoryTypeButton('sales', 'Ventas', Icons.shopping_cart_rounded),
                    const SizedBox(width: 8),
                    _buildStoryTypeButton('trust', 'Confianza', Icons.verified_rounded),
                    const SizedBox(width: 8),
                    _buildStoryTypeButton('educational', 'Educativo', Icons.school_rounded),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            // Main content: Gallery + AI Panel
            Expanded(
              child: Row(
                children: [
                  // LEFT: Gallery
                  Expanded(
                    flex: 60,
                    child: _buildGalleryPanel(),
                  ),
                  Container(
                    width: 1,
                    color: scheme.outlineVariant.withValues(alpha: 0.2),
                  ),
                  // RIGHT: AI Analysis Panel
                  Expanded(
                    flex: 40,
                    child: _buildAnalysisPanel(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStoryTypeButton(String type, String label, IconData icon) {
    final isSelected = _selectedStoryType == type;
    final scheme = Theme.of(context).colorScheme;

    return FilterChip(
      selected: isSelected,
      onSelected: (_) => setState(() => _selectedStoryType = type),
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16),
          const SizedBox(width: 6),
          Text(label),
        ],
      ),
      backgroundColor: isSelected ? scheme.primaryContainer : scheme.surfaceVariant,
      selectedColor: scheme.primary,
      labelStyle: TextStyle(
        color: isSelected ? scheme.onPrimary : scheme.onSurface,
        fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
      ),
    );
  }

  Widget _buildGalleryPanel() {
    return Column(
      children: [
        // Filters & Search
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Search
              TextField(
                onChanged: (value) => setState(() => _searchQuery = value),
                decoration: InputDecoration(
                  hintText: 'Buscar imagen...',
                  prefixIcon: const Icon(Icons.search_rounded),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
              ),
              const SizedBox(height: 12),
              // Category chips
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _buildCategoryChip(null, 'Todas'),
                    const SizedBox(width: 8),
                    _buildCategoryChip('camara', 'Cámaras'),
                    const SizedBox(width: 8),
                    _buildCategoryChip('motor', 'Motores'),
                    const SizedBox(width: 8),
                    _buildCategoryChip('cerco', 'Cercos'),
                    const SizedBox(width: 8),
                    _buildCategoryChip('pos', 'POS'),
                  ],
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        // Gallery Grid
        Expanded(
          child: Consumer(
            builder: (context, ref, child) {
              final mediaAssets = ref.watch(
                _mediaAssetsFutureProvider(
                  category: _filterCategory,
                  searchQuery: _searchQuery,
                ),
              );

              return mediaAssets.when(
                loading: () => const Center(
                  child: CircularProgressIndicator(),
                ),
                error: (error, stack) => Center(
                  child: Text('Error: $error'),
                ),
                data: (assets) {
                  if (assets.isEmpty) {
                    return Center(
                      child: Text(
                        'No hay imágenes disponibles',
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                    );
                  }

                  return GridView.builder(
                    padding: const EdgeInsets.all(12),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      childAspectRatio: 0.75,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                    ),
                    itemCount: assets.length,
                    itemBuilder: (context, index) {
                      final asset = assets[index];
                      final isSelected = _selectedImageId == asset.id;

                      return _buildGalleryItem(asset, isSelected);
                    },
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildCategoryChip(String? value, String label) {
    final isSelected = _filterCategory == value;
    final scheme = Theme.of(context).colorScheme;

    return FilterChip(
      selected: isSelected,
      onSelected: (_) => setState(() => _filterCategory = value),
      label: Text(label),
      backgroundColor: scheme.surfaceVariant,
      selectedColor: scheme.primaryContainer,
      labelStyle: TextStyle(
        fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
      ),
    );
  }

  Widget _buildGalleryItem(MarketingMediaAsset asset, bool isSelected) {
    final scheme = Theme.of(context).colorScheme;

    return InkWell(
      onTap: () => _onImageSelected(asset),
      borderRadius: BorderRadius.circular(12),
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Container(
              color: scheme.surfaceVariant,
              child: Image.network(
                asset.fileUrl,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => Center(
                  child: Icon(
                    Icons.image_not_supported_rounded,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ),
          // Selection overlay
          if (isSelected)
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: scheme.primary.withValues(alpha: 0.2),
                border: Border.all(
                  color: scheme.primary,
                  width: 3,
                ),
              ),
              child: Center(
                child: Icon(
                  Icons.check_circle_rounded,
                  color: scheme.primary,
                  size: 40,
                ),
              ),
            ),
          // Product label
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.8),
                    Colors.transparent,
                  ],
                ),
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(12),
                  bottomRight: Radius.circular(12),
                ),
              ),
              padding: const EdgeInsets.all(8),
              child: Text(
                asset.relatedService ?? asset.category ?? 'Producto',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAnalysisPanel() {
    final scheme = Theme.of(context).colorScheme;

    if (_selectedImageId == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.image_search_rounded,
              size: 64,
              color: scheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              'Selecciona una imagen',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Elige una imagen de la galería\npara ver recomendaciones IA',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    if (_analyzing) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text('Analizando imagen...'),
          ],
        ),
      );
    }

    if (_selectedImageAnalysis == null) {
      return const SizedBox.shrink();
    }

    final analysis = _selectedImageAnalysis!;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Image preview
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: AspectRatio(
              aspectRatio: 1,
              child: Image.network(
                analysis.fileUrl,
                fit: BoxFit.cover,
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Quality score
          _buildQualityScore(analysis),
          const SizedBox(height: 16),
          // Recommendation
          _buildRecommendationCard(analysis),
          const SizedBox(height: 16),
          // Suggested angle
          _buildSuggestedAngle(analysis),
          const SizedBox(height: 16),
          // Usage history
          if (analysis.usageHistory.timesUsed > 0)
            _buildUsageHistory(analysis),
          const SizedBox(height: 20),
          // Generate button
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _generating ? null : () => _onConfirmAndGenerate(analysis),
              icon: _generating
                  ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation(scheme.onPrimary),
                    ),
                  )
                  : const Icon(Icons.auto_awesome_rounded),
              label: Text(_generating ? 'Generando...' : 'GENERAR CONTENIDO'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQualityScore(ImageAnalysisResult analysis) {
    final scheme = Theme.of(context).colorScheme;
    final qualityColor = _getQualityColor(analysis.qualityScore);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceVariant,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Calidad Visual',
            style: Theme.of(context).textTheme.labelMedium,
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: analysis.qualityScore / 100,
              minHeight: 8,
              backgroundColor: scheme.outlineVariant.withValues(alpha: 0.2),
              valueColor: AlwaysStoppedAnimation(qualityColor),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${analysis.qualityScore}/100',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: qualityColor,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                analysis.visualQuality.toUpperCase(),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: qualityColor,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRecommendationCard(ImageAnalysisResult analysis) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: scheme.primary.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.lightbulb_rounded,
                color: scheme.primary,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  analysis.recommendation,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...analysis.recommendationReason.map((reason) => Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              children: [
                Icon(
                  Icons.check_circle_rounded,
                  color: scheme.primary,
                  size: 14,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    reason,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          )),
          const SizedBox(height: 8),
          if (analysis.estimatedConversionLift > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '+${analysis.estimatedConversionLift}% conversión estimada',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: scheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSuggestedAngle(ImageAnalysisResult analysis) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceVariant,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Ángulo Sugerido',
            style: Theme.of(context).textTheme.labelMedium,
          ),
          const SizedBox(height: 8),
          Text(
            analysis.suggestedAngle,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _buildUsageHistory(ImageAnalysisResult analysis) {
    final scheme = Theme.of(context).colorScheme;
    final metrics = analysis.usageHistory.conversionMetrics;
    final ctr = metrics.clicks > 0 ? (metrics.conversions / metrics.clicks * 100).toStringAsFixed(1) : 'N/A';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceVariant,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Historial de Uso',
            style: Theme.of(context).textTheme.labelMedium,
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildMetricBadge('${analysis.usageHistory.timesUsed}', 'Usos'),
              _buildMetricBadge('${metrics.impressions}', 'Impresiones'),
              _buildMetricBadge('$ctr%', 'Conv.'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetricBadge(String value, String label) {
    final scheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        Text(
          value,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Color _getQualityColor(int score) {
    if (score >= 85) return Colors.green;
    if (score >= 70) return Colors.orange;
    return Colors.red;
  }

  Future<void> _onImageSelected(MarketingMediaAsset asset) async {
    setState(() {
      _selectedImageId = asset.id;
      _analyzing = true;
      _selectedImageAnalysis = null;
    });

    try {
      final api = ref.read(marketingApiProvider);
      final result = await api.analyzeMediaAssets(
        mediaAssetIds: [asset.id],
        storyType: _selectedStoryType,
      );

      final ranked = (result['ranked'] as List?)
          ?.whereType<Map>()
          .map((item) => ImageAnalysisResult.fromJson(item.cast<String, dynamic>()))
          .toList(growable: false) ??
          const [];

      setState(() {
        _selectedImageAnalysis = ranked.isNotEmpty ? ranked.first : null;
        _analyzing = false;
      });
    } catch (e) {
      setState(() => _analyzing = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al analizar imagen: $e')),
        );
      }
    }
  }

  Future<void> _onConfirmAndGenerate(ImageAnalysisResult analysis) async {
    if (_selectedImageId == null) return;

    setState(() => _generating = true);

    try {
      await widget.onGenerateConfirmed(_selectedImageId!);
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      setState(() => _generating = false);
    }
  }
}

// ============================================================
// PROVIDERS
// ============================================================

final _mediaAssetsFutureProvider =
    FutureProvider.family<List<MarketingMediaAsset>, Map<String, String?>>((
  ref,
  params,
) async {
  final api = ref.watch(marketingApiProvider);
  final assets = await api.loadMediaAssets(
    category: params['category'],
  );

  // Filter by search query
  final searchQuery = (params['searchQuery'] ?? '').toLowerCase();
  if (searchQuery.isEmpty) return assets;

  return assets
      .where((asset) =>
          (asset.relatedService?.toLowerCase().contains(searchQuery) ?? false) ||
          (asset.category?.toLowerCase().contains(searchQuery) ?? false))
      .toList();
});
