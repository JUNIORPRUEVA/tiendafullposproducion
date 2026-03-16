import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;

import '../../core/auth/auth_provider.dart';
import '../../core/company/company_settings_model.dart';
import '../../core/company/company_settings_repository.dart';
import '../../core/evolution/evolution_api_repository.dart';
import '../../core/errors/api_exception.dart';
import '../../core/widgets/app_drawer.dart';

class ConfiguracionScreen extends ConsumerStatefulWidget {
  const ConfiguracionScreen({super.key});

  @override
  ConsumerState<ConfiguracionScreen> createState() =>
      _ConfiguracionScreenState();
}

class _ConfiguracionScreenState extends ConsumerState<ConfiguracionScreen> {
  static const int _maxLogoBytes = 2 * 1024 * 1024;
  static const int _maxLogoDimension = 1200;

  final _nameCtrl = TextEditingController();
  final _rncCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _legalRepresentativeNameCtrl = TextEditingController();
  final _legalRepresentativeCedulaCtrl = TextEditingController();
  final _legalRepresentativeRoleCtrl = TextEditingController();
  final _legalRepresentativeNationalityCtrl = TextEditingController();
  final _legalRepresentativeCivilStatusCtrl = TextEditingController();
  final _openAiApiKeyCtrl = TextEditingController();
  final _evolutionApiBaseUrlCtrl = TextEditingController();
  final _evolutionApiInstanceNameCtrl = TextEditingController();
  final _evolutionApiApiKeyCtrl = TextEditingController();
  final _evolutionTestNumberCtrl = TextEditingController();
  final _evolutionTestMessageCtrl = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  bool _sendingEvolutionTest = false;
  bool _showApiKey = false;
  bool _showEvolutionApiKey = false;
  String? _logoBase64;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _rncCtrl.dispose();
    _phoneCtrl.dispose();
    _addressCtrl.dispose();
    _legalRepresentativeNameCtrl.dispose();
    _legalRepresentativeCedulaCtrl.dispose();
    _legalRepresentativeRoleCtrl.dispose();
    _legalRepresentativeNationalityCtrl.dispose();
    _legalRepresentativeCivilStatusCtrl.dispose();
    _openAiApiKeyCtrl.dispose();
    _evolutionApiBaseUrlCtrl.dispose();
    _evolutionApiInstanceNameCtrl.dispose();
    _evolutionApiApiKeyCtrl.dispose();
    _evolutionTestNumberCtrl.dispose();
    _evolutionTestMessageCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final settings = await ref
          .read(companySettingsRepositoryProvider)
          .getSettings();
      if (!mounted) return;
      _nameCtrl.text = settings.companyName;
      _rncCtrl.text = settings.rnc;
      _phoneCtrl.text = settings.phone;
      _addressCtrl.text = settings.address;
      _legalRepresentativeNameCtrl.text = settings.legalRepresentativeName;
      _legalRepresentativeCedulaCtrl.text = settings.legalRepresentativeCedula;
      _legalRepresentativeRoleCtrl.text = settings.legalRepresentativeRole;
      _legalRepresentativeNationalityCtrl.text =
          settings.legalRepresentativeNationality;
      _legalRepresentativeCivilStatusCtrl.text =
          settings.legalRepresentativeCivilStatus;
      _logoBase64 = settings.logoBase64;
      _openAiApiKeyCtrl.text = settings.openAiApiKey;
      _evolutionApiBaseUrlCtrl.text = settings.evolutionApiBaseUrl;
      _evolutionApiInstanceNameCtrl.text = settings.evolutionApiInstanceName;
      _evolutionApiApiKeyCtrl.text = settings.evolutionApiApiKey;
    } catch (e) {
      _showMessage('$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickLogo() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
      withData: true,
    );

    if (!mounted) return;
    final file = result?.files.firstOrNull;
    if (file == null || file.bytes == null) return;

    try {
      final preparedBytes = _prepareLogoBytes(file.bytes!);
      setState(() => _logoBase64 = base64Encode(preparedBytes));
      _showMessage('Logo cargado correctamente.');
    } catch (e) {
      _showMessage('$e');
    }
  }

  Uint8List? _logoBytes() {
    final raw = _logoBase64;
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      return base64Decode(raw);
    } catch (_) {
      return null;
    }
  }

  Uint8List _prepareLogoBytes(Uint8List rawBytes) {
    final decoded = img.decodeImage(rawBytes);
    if (decoded == null) {
      throw Exception('La imagen seleccionada no es valida.');
    }

    var current = img.bakeOrientation(decoded);
    current = _resizeToFit(current, _maxLogoDimension);

    for (var attempt = 0; attempt < 5; attempt++) {
      final quality = (88 - (attempt * 10)).clamp(50, 88).toInt();
      final pngBytes = Uint8List.fromList(img.encodePng(current, level: 6));
      final jpgBytes = Uint8List.fromList(
        img.encodeJpg(current, quality: quality),
      );

      if (current.hasAlpha && pngBytes.length <= _maxLogoBytes) {
        return pngBytes;
      }
      if (jpgBytes.length <= _maxLogoBytes) {
        return jpgBytes;
      }
      if (!current.hasAlpha && pngBytes.length <= _maxLogoBytes) {
        return pngBytes;
      }

      if (current.width <= 320 && current.height <= 320) {
        break;
      }

      current = img.copyResize(
        current,
        width: (current.width * 0.82).round(),
        height: (current.height * 0.82).round(),
        interpolation: img.Interpolation.average,
      );
    }

    throw Exception(
      'El logo sigue siendo demasiado pesado. Usa una imagen menor de 2 MB o con menos resolucion.',
    );
  }

  img.Image _resizeToFit(img.Image image, int maxDimension) {
    if (image.width <= maxDimension && image.height <= maxDimension) {
      return image;
    }

    final aspectRatio = image.width / image.height;
    final width = image.width >= image.height
        ? maxDimension
        : (maxDimension * aspectRatio).round();
    final height = image.height > image.width
        ? maxDimension
        : (maxDimension / aspectRatio).round();

    return img.copyResize(
      image,
      width: width,
      height: height,
      interpolation: img.Interpolation.average,
    );
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text(message)));
  }

  Future<bool> _save() async {
    if (_saving) return false;
    setState(() => _saving = true);
    final settings = CompanySettings(
      companyName: _nameCtrl.text.trim(),
      rnc: _rncCtrl.text.trim(),
      phone: _phoneCtrl.text.trim(),
      address: _addressCtrl.text.trim(),
      legalRepresentativeName: _legalRepresentativeNameCtrl.text.trim(),
      legalRepresentativeCedula: _legalRepresentativeCedulaCtrl.text.trim(),
      legalRepresentativeRole: _legalRepresentativeRoleCtrl.text.trim(),
      legalRepresentativeNationality: _legalRepresentativeNationalityCtrl.text
          .trim(),
      legalRepresentativeCivilStatus: _legalRepresentativeCivilStatusCtrl.text
          .trim(),
      logoBase64: _logoBase64,
      openAiApiKey: _openAiApiKeyCtrl.text.trim(),
      openAiModel: '',
      hasOpenAiApiKey: _openAiApiKeyCtrl.text.trim().isNotEmpty,
      evolutionApiBaseUrl: _evolutionApiBaseUrlCtrl.text.trim(),
      evolutionApiInstanceName: _evolutionApiInstanceNameCtrl.text.trim(),
      evolutionApiApiKey: _evolutionApiApiKeyCtrl.text.trim(),
      hasEvolutionApiApiKey: _evolutionApiApiKeyCtrl.text.trim().isNotEmpty,
    );

    try {
      await ref.read(companySettingsRepositoryProvider).saveSettings(settings);
      ref.invalidate(companySettingsProvider);
      _showMessage('Configuracion guardada');
      return true;
    } catch (e) {
      _showMessage('$e');
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _buildSavingBanner({EdgeInsetsGeometry? margin}) {
    return Padding(
      padding: margin ?? const EdgeInsets.only(bottom: 10),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Text(
                'Guardando configuración...',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              SizedBox(height: 8),
              LinearProgressIndicator(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCompanyFields({VoidCallback? refreshUi}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _nameCtrl,
          decoration: const InputDecoration(labelText: 'Nombre empresa'),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _rncCtrl,
          decoration: const InputDecoration(labelText: 'RNC'),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _phoneCtrl,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(labelText: 'Teléfono'),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _addressCtrl,
          maxLines: 2,
          decoration: const InputDecoration(labelText: 'Dirección'),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: () async {
                await _pickLogo();
                refreshUi?.call();
              },
              icon: const Icon(Icons.upload_file_outlined),
              label: const Text('Subir logo'),
            ),
            if (_logoBase64 != null)
              OutlinedButton.icon(
                onPressed: () {
                  setState(() => _logoBase64 = null);
                  refreshUi?.call();
                  _showMessage('Logo eliminado.');
                },
                icon: const Icon(Icons.delete_outline),
                label: const Text('Quitar logo'),
              ),
          ],
        ),
        const SizedBox(height: 10),
        if (_logoBytes() != null)
          Container(
            width: 90,
            height: 90,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
            child: Image.memory(_logoBytes()!, fit: BoxFit.cover),
          ),
      ],
    );
  }

  Widget _buildLegalFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _legalRepresentativeNameCtrl,
          decoration: const InputDecoration(labelText: 'Representante legal'),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _legalRepresentativeCedulaCtrl,
          decoration: const InputDecoration(
            labelText: 'Cédula del representante',
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _legalRepresentativeRoleCtrl,
          decoration: const InputDecoration(
            labelText: 'Cargo del representante',
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _legalRepresentativeNationalityCtrl,
          decoration: const InputDecoration(
            labelText: 'Nacionalidad del representante',
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _legalRepresentativeCivilStatusCtrl,
          decoration: const InputDecoration(
            labelText: 'Estado civil del representante',
          ),
        ),
      ],
    );
  }

  Widget _buildOpenAiFields({VoidCallback? refreshUi}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Configuración de API (ChatGPT)',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        const Text(
          'Solo coloca tu API key. El sistema selecciona automáticamente el mejor modelo disponible según la necesidad.',
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _openAiApiKeyCtrl,
          obscureText: !_showApiKey,
          autocorrect: false,
          enableSuggestions: false,
          decoration: InputDecoration(
            labelText: 'OpenAI API Key',
            hintText: 'sk-...',
            suffixIcon: IconButton(
              tooltip: _showApiKey ? 'Ocultar clave' : 'Mostrar clave',
              onPressed: () {
                setState(() => _showApiKey = !_showApiKey);
                refreshUi?.call();
              },
              icon: Icon(
                _showApiKey
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: () {
              setState(() {
                _openAiApiKeyCtrl.clear();
              });
              refreshUi?.call();
            },
            icon: const Icon(Icons.delete_outline),
            label: const Text('Limpiar API key'),
          ),
        ),
      ],
    );
  }

  Widget _buildEvolutionFields({VoidCallback? refreshUi}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Configuración de API (Evolution)',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        const Text(
          'Configura tu instancia de Evolution API para enviar notificaciones y mensajes.',
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _evolutionApiBaseUrlCtrl,
          autocorrect: false,
          enableSuggestions: false,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(
            labelText: 'Base URL',
            hintText: 'https://tu-evolution-api.com',
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _evolutionApiInstanceNameCtrl,
          autocorrect: false,
          enableSuggestions: false,
          decoration: const InputDecoration(
            labelText: 'Instance name',
            hintText: 'fulltech',
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _evolutionApiApiKeyCtrl,
          obscureText: !_showEvolutionApiKey,
          autocorrect: false,
          enableSuggestions: false,
          decoration: InputDecoration(
            labelText: 'API Key',
            hintText: 'ev-...',
            suffixIcon: IconButton(
              tooltip: _showEvolutionApiKey ? 'Ocultar clave' : 'Mostrar clave',
              onPressed: () {
                setState(() => _showEvolutionApiKey = !_showEvolutionApiKey);
                refreshUi?.call();
              },
              icon: Icon(
                _showEvolutionApiKey
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: () {
              setState(() {
                _evolutionApiBaseUrlCtrl.clear();
                _evolutionApiInstanceNameCtrl.clear();
                _evolutionApiApiKeyCtrl.clear();
              });
              refreshUi?.call();
            },
            icon: const Icon(Icons.delete_outline),
            label: const Text('Limpiar Evolution API'),
          ),
        ),
        const SizedBox(height: 16),
        const Divider(),
        const SizedBox(height: 16),
        const Text(
          'Prueba',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        const Text(
          'Coloca un número y un mensaje para validar que Evolution puede enviar WhatsApp (texto).',
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _evolutionTestNumberCtrl,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(
            labelText: 'Número (WhatsApp)',
            hintText: '1829XXXXXXX',
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _evolutionTestMessageCtrl,
          maxLines: 2,
          decoration: const InputDecoration(
            labelText: 'Mensaje',
            hintText: 'Hola, esto es una prueba…',
          ),
        ),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            onPressed: (_saving || _sendingEvolutionTest)
                ? null
                : () async {
                    final numberRaw = _evolutionTestNumberCtrl.text.trim();
                    final messageRaw = _evolutionTestMessageCtrl.text.trim();
                    final evolution = ref.read(evolutionApiRepositoryProvider);
                    final normalized = evolution.normalizeWhatsAppNumber(
                      numberRaw,
                    );

                    if (normalized.isEmpty) {
                      _showMessage('Número inválido para WhatsApp.');
                      return;
                    }

                    setState(() => _sendingEvolutionTest = true);
                    refreshUi?.call();
                    try {
                      final saved = await _save();
                      if (!saved) return;

                      await evolution.sendTextMessage(
                        toNumber: normalized,
                        message: messageRaw.isEmpty
                            ? 'Prueba FULLTECH'
                            : messageRaw,
                      );
                      _showMessage('Mensaje de prueba enviado.');
                    } on ApiException catch (e) {
                      _showMessage(e.message);
                    } catch (e) {
                      _showMessage('No se pudo enviar: $e');
                    } finally {
                      if (mounted) {
                        setState(() => _sendingEvolutionTest = false);
                      }
                      refreshUi?.call();
                    }
                  },
            icon: _sendingEvolutionTest
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.send_outlined),
            label: Text(
              _sendingEvolutionTest ? 'Enviando...' : 'Enviar prueba',
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMobileBody() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_saving) _buildSavingBanner(),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Datos de la empresa',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                _buildCompanyFields(),
                const SizedBox(height: 12),
                const Divider(),
                const SizedBox(height: 12),
                const Text(
                  'Datos legales para contrato laboral',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                _buildLegalFields(),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: _buildOpenAiFields(),
          ),
        ),
        const SizedBox(height: 10),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: _buildEvolutionFields(),
          ),
        ),
      ],
    );
  }

  List<_SettingsCardData> _buildDesktopCards() {
    final companyTitle = _nameCtrl.text.trim().isEmpty
        ? 'Empresa pendiente de configurar'
        : _nameCtrl.text.trim();
    final legalTitle = _legalRepresentativeNameCtrl.text.trim().isEmpty
        ? 'Representante legal pendiente'
        : _legalRepresentativeNameCtrl.text.trim();
    final openAiReady = _openAiApiKeyCtrl.text.trim().isNotEmpty;
    final evolutionReady =
        _evolutionApiBaseUrlCtrl.text.trim().isNotEmpty &&
        _evolutionApiInstanceNameCtrl.text.trim().isNotEmpty &&
        _evolutionApiApiKeyCtrl.text.trim().isNotEmpty;

    return [
      _SettingsCardData(
        icon: Icons.business_outlined,
        title: 'Datos de la empresa',
        description: 'Nombre, RNC, teléfono, dirección y logo institucional.',
        actionLabel: 'Editar empresa',
        highlights: [
          companyTitle,
          _phoneCtrl.text.trim().isEmpty
              ? 'Sin teléfono configurado'
              : _phoneCtrl.text.trim(),
        ],
        onTap: _openCompanyDialog,
      ),
      _SettingsCardData(
        icon: Icons.gavel_outlined,
        title: 'Datos legales',
        description:
            'Información del representante legal utilizada en contratos laborales.',
        actionLabel: 'Editar datos legales',
        highlights: [
          legalTitle,
          _legalRepresentativeRoleCtrl.text.trim().isEmpty
              ? 'Sin cargo definido'
              : _legalRepresentativeRoleCtrl.text.trim(),
        ],
        onTap: _openLegalDialog,
      ),
      _SettingsCardData(
        icon: Icons.hub_outlined,
        title: 'API del sistema',
        description: 'OpenAI, Evolution API y servicios externos del sistema.',
        actionLabel: 'Editar integraciones',
        highlights: [
          openAiReady ? 'OpenAI configurada' : 'OpenAI pendiente',
          evolutionReady ? 'Evolution activa' : 'Evolution pendiente',
        ],
        onTap: _openApiDialog,
      ),
    ];
  }

  Future<void> _openCompanyDialog() async {
    await _openDesktopDialog(
      title: 'Editar datos de empresa',
      subtitle:
          'Actualiza la identidad comercial y la información base usada en documentos y procesos internos.',
      maxWidth: 680,
      contentBuilder: (refreshUi) => _buildCompanyFields(refreshUi: refreshUi),
    );
  }

  Future<void> _openLegalDialog() async {
    await _openDesktopDialog(
      title: 'Editar datos legales',
      subtitle:
          'Mantén al día la información legal utilizada en contratos y plantillas administrativas.',
      maxWidth: 640,
      contentBuilder: (_) => _buildLegalFields(),
    );
  }

  Future<void> _openApiDialog() async {
    await _openDesktopDialog(
      title: 'Editar API del sistema',
      subtitle:
          'Gestiona las credenciales de OpenAI y las integraciones externas necesarias para automatizaciones.',
      maxWidth: 760,
      contentBuilder: (refreshUi) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildOpenAiFields(refreshUi: refreshUi),
          const SizedBox(height: 20),
          const Divider(),
          const SizedBox(height: 20),
          _buildEvolutionFields(refreshUi: refreshUi),
        ],
      ),
    );
  }

  Future<void> _openDesktopDialog({
    required String title,
    required String subtitle,
    required double maxWidth,
    required Widget Function(VoidCallback refreshUi) contentBuilder,
  }) async {
    var isSubmitting = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: !isSubmitting,
      builder: (dialogContext) {
        final screenSize = MediaQuery.sizeOf(dialogContext);

        return StatefulBuilder(
          builder: (dialogContext, setStateDialog) {
            Future<void> submit() async {
              if (isSubmitting) return;
              setStateDialog(() => isSubmitting = true);
              final success = await _save();
              if (!dialogContext.mounted) return;
              if (success) {
                Navigator.of(dialogContext).pop();
                return;
              }
              setStateDialog(() => isSubmitting = false);
            }

            return Dialog(
              insetPadding: const EdgeInsets.all(24),
              clipBehavior: Clip.antiAlias,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: maxWidth,
                  maxHeight: screenSize.height * 0.84,
                ),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(28, 28, 28, 24),
                  decoration: BoxDecoration(
                    color: Theme.of(dialogContext).colorScheme.surface,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
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
                                  title,
                                  style: Theme.of(dialogContext)
                                      .textTheme
                                      .headlineSmall
                                      ?.copyWith(fontWeight: FontWeight.w800),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  subtitle,
                                  style: Theme.of(dialogContext)
                                      .textTheme
                                      .bodyMedium
                                      ?.copyWith(
                                        color: Theme.of(
                                          dialogContext,
                                        ).colorScheme.onSurfaceVariant,
                                      ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'Cerrar',
                            onPressed: isSubmitting
                                ? null
                                : () => Navigator.of(dialogContext).pop(),
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      if (isSubmitting) ...[
                        const LinearProgressIndicator(),
                        const SizedBox(height: 18),
                      ],
                      Flexible(
                        child: SingleChildScrollView(
                          child: contentBuilder(() => setStateDialog(() {})),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: isSubmitting
                                ? null
                                : () => Navigator.of(dialogContext).pop(),
                            child: const Text('Cancelar'),
                          ),
                          const SizedBox(width: 12),
                          FilledButton.icon(
                            onPressed: isSubmitting ? null : submit,
                            icon: const Icon(Icons.save_outlined),
                            label: Text(
                              isSubmitting ? 'Guardando...' : 'Guardar',
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildDesktopBody(BuildContext context) {
    final cards = _buildDesktopCards();

    return SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1400),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_saving)
                  _buildSavingBanner(margin: const EdgeInsets.only(bottom: 18)),
                _SettingsHeader(
                  title: 'Configuración del sistema',
                  subtitle:
                      'Administra los datos de la empresa y los parámetros del sistema.',
                ),
                const SizedBox(height: 24),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final width = constraints.maxWidth;
                    final columns = width >= 1280
                        ? 3
                        : width >= 980
                        ? 2
                        : 1;
                    const spacing = 20.0;
                    final cardWidth =
                        (width - (spacing * (columns - 1))) / columns;

                    return Wrap(
                      spacing: spacing,
                      runSpacing: spacing,
                      children: [
                        for (final card in cards)
                          SizedBox(
                            width: cardWidth,
                            child: _SettingsCard(card: card),
                          ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authStateProvider).user;
    final isAdmin = user?.role == 'ADMIN';
    final isDesktop = MediaQuery.sizeOf(context).width >= 900;

    if (!isAdmin) {
      return Scaffold(
        appBar: AppBar(title: const Text('Configuración')),
        drawer: buildAdaptiveDrawer(context, currentUser: user),
        body: const Center(
          child: Text('Solo administradores pueden acceder a configuración'),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Configuración')),
      drawer: buildAdaptiveDrawer(context, currentUser: user),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : isDesktop
          ? _buildDesktopBody(context)
          : _buildMobileBody(),
      bottomNavigationBar: isDesktop
          ? null
          : SafeArea(
              minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: const Icon(Icons.save_outlined),
                label: Text(_saving ? 'Guardando...' : 'Guardar configuración'),
              ),
            ),
    );
  }
}

class _SettingsHeader extends StatelessWidget {
  const _SettingsHeader({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          colors: [scheme.surface, scheme.surfaceContainerHighest],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withValues(alpha: 0.06),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  subtitle,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 20),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.desktop_windows_outlined, color: scheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Vista desktop',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: scheme.primary,
                    fontWeight: FontWeight.w700,
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

class _SettingsCardData {
  const _SettingsCardData({
    required this.icon,
    required this.title,
    required this.description,
    required this.actionLabel,
    required this.highlights,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String description;
  final String actionLabel;
  final List<String> highlights;
  final Future<void> Function() onTap;
}

class _SettingsCard extends StatefulWidget {
  const _SettingsCard({required this.card});

  final _SettingsCardData card;

  @override
  State<_SettingsCard> createState() => _SettingsCardState();
}

class _SettingsCardState extends State<_SettingsCard> {
  bool _hovered = false;

  void _setHovered(bool value) {
    if (_hovered == value) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_hovered == value) return;
      setState(() => _hovered = value);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return MouseRegion(
      onEnter: (_) => _setHovered(true),
      onExit: (_) => _setHovered(false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        transform: Matrix4.translationValues(0, _hovered ? -4.0 : 0.0, 0),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: scheme.shadow.withValues(alpha: _hovered ? 0.12 : 0.06),
              blurRadius: _hovered ? 28 : 18,
              offset: Offset(0, _hovered ? 14 : 10),
            ),
          ],
        ),
        child: Material(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(20),
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: widget.card.onTap,
            child: Ink(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: _hovered
                      ? scheme.primary.withValues(alpha: 0.28)
                      : scheme.outlineVariant.withValues(alpha: 0.7),
                ),
                gradient: LinearGradient(
                  colors: [scheme.surface, scheme.surfaceContainerLowest],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: scheme.primary.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Icon(
                          widget.card.icon,
                          color: scheme.primary,
                          size: 28,
                        ),
                      ),
                      const Spacer(),
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerHighest,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.arrow_outward_rounded,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Text(
                    widget.card.title,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.card.description,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 18),
                  for (final highlight in widget.card.highlights) ...[
                    Row(
                      children: [
                        Icon(
                          Icons.check_circle_outline_rounded,
                          size: 18,
                          color: scheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            highlight,
                            style: theme.textTheme.bodyMedium,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                  ],
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: scheme.primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      widget.card.actionLabel,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: scheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
