import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
  final _nameCtrl = TextEditingController();
  final _rncCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _openAiApiKeyCtrl = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  bool _showApiKey = false;
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
    _openAiApiKeyCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final settings = await ref.read(companySettingsRepositoryProvider).getSettings();
      if (!mounted) return;
      _nameCtrl.text = settings.companyName;
      _rncCtrl.text = settings.rnc;
      _phoneCtrl.text = settings.phone;
      _addressCtrl.text = settings.address;
      _logoBase64 = settings.logoBase64;
      _openAiApiKeyCtrl.text = settings.openAiApiKey;
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e')),
      );
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

    final file = result?.files.firstOrNull;
    if (file == null || file.bytes == null) return;

    setState(() => _logoBase64 = base64Encode(file.bytes!));
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

  Future<void> _save() async {
    setState(() => _saving = true);
    final settings = CompanySettings(
      companyName: _nameCtrl.text.trim(),
      rnc: _rncCtrl.text.trim(),
      phone: _phoneCtrl.text.trim(),
      address: _addressCtrl.text.trim(),
      logoBase64: _logoBase64,
      openAiApiKey: _openAiApiKeyCtrl.text.trim(),
      openAiModel: '',
      hasOpenAiApiKey: _openAiApiKeyCtrl.text.trim().isNotEmpty,
    );

    try {
      await ref.read(companySettingsRepositoryProvider).saveSettings(settings);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Configuración guardada')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e')),
      );
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
        drawer: AppDrawer(currentUser: user),
        body: const Center(
          child: Text('Solo administradores pueden acceder a configuración'),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Configuración')),
      drawer: AppDrawer(currentUser: user),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
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
                                onPressed: () =>
                                    setState(() => _logoBase64 = null),
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
