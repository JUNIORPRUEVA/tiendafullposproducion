import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;

import '../../core/auth/auth_provider.dart';
import '../../core/company/company_settings_model.dart';
import '../../core/company/company_settings_repository.dart';
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

  bool _loading = true;
  bool _saving = false;
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

  Future<void> _save() async {
    if (_saving) return;
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
    } catch (e) {
      _showMessage('$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authStateProvider).user;
    final isAdmin = user?.role == 'ADMIN';

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
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_saving)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
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
                  ),
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
                        TextField(
                          controller: _nameCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Nombre empresa',
                          ),
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
                          decoration: const InputDecoration(
                            labelText: 'Teléfono',
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _addressCtrl,
                          maxLines: 2,
                          decoration: const InputDecoration(
                            labelText: 'Dirección',
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Divider(),
                        const SizedBox(height: 12),
                        const Text(
                          'Datos legales para contrato laboral',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _legalRepresentativeNameCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Representante legal',
                          ),
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
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            OutlinedButton.icon(
                              onPressed: _pickLogo,
                              icon: const Icon(Icons.upload_file_outlined),
                              label: const Text('Subir logo'),
                            ),
                            const SizedBox(width: 8),
                            if (_logoBase64 != null)
                              OutlinedButton.icon(
                                onPressed: () {
                                  setState(() => _logoBase64 = null);
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
                                color: Theme.of(
                                  context,
                                ).colorScheme.outlineVariant,
                              ),
                            ),
                            child: Image.memory(
                              _logoBytes()!,
                              fit: BoxFit.cover,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
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
                              tooltip: _showApiKey
                                  ? 'Ocultar clave'
                                  : 'Mostrar clave',
                              onPressed: () =>
                                  setState(() => _showApiKey = !_showApiKey),
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
                            },
                            icon: const Icon(Icons.delete_outline),
                            label: const Text('Limpiar API key'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
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
                              tooltip: _showEvolutionApiKey
                                  ? 'Ocultar clave'
                                  : 'Mostrar clave',
                              onPressed: () => setState(
                                () => _showEvolutionApiKey =
                                    !_showEvolutionApiKey,
                              ),
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
                            },
                            icon: const Icon(Icons.delete_outline),
                            label: const Text('Limpiar Evolution API'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
      bottomNavigationBar: SafeArea(
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
