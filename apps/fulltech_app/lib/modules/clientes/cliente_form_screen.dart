import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:validators/validators.dart' as validators;

import '../../core/auth/auth_provider.dart';
import '../../core/routing/app_navigator.dart';
import '../../core/routing/routes.dart';
import '../../core/widgets/app_drawer.dart';
import '../../core/utils/safe_url_launcher.dart';
import 'application/clientes_controller.dart';
import 'client_location_utils.dart';
import 'cliente_model.dart';

class ClienteFormScreen extends ConsumerStatefulWidget {
  final String? clienteId;

  const ClienteFormScreen({super.key, this.clienteId});

  @override
  ConsumerState<ClienteFormScreen> createState() => _ClienteFormScreenState();
}

class _ClienteFormScreenState extends ConsumerState<ClienteFormScreen> {
  final _formKey = GlobalKey<FormState>();

  final _nombreCtrl = TextEditingController();
  final _telefonoCtrl = TextEditingController();
  final _direccionCtrl = TextEditingController();
  final _locationUrlCtrl = TextEditingController();
  final _correoCtrl = TextEditingController();

  bool _loadingInitial = false;
  ClienteModel? _cliente;

  bool get _isEdit => widget.clienteId != null && widget.clienteId!.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _loadIfEdit();
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _telefonoCtrl.dispose();
    _direccionCtrl.dispose();
    _locationUrlCtrl.dispose();
    _correoCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadIfEdit() async {
    if (!_isEdit) return;
    setState(() => _loadingInitial = true);
    try {
      final cliente = await ref
          .read(clientesControllerProvider.notifier)
          .getById(widget.clienteId!);
      _cliente = cliente;
      _nombreCtrl.text = cliente.nombre;
      _telefonoCtrl.text = cliente.telefono;
      _direccionCtrl.text = cliente.direccion ?? '';
      _locationUrlCtrl.text = cliente.locationUrl ?? '';
      _correoCtrl.text = cliente.correo ?? '';
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo cargar el cliente para edición'),
        ),
      );
    } finally {
      if (mounted) setState(() => _loadingInitial = false);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    try {
      final saved = await ref
          .read(clientesControllerProvider.notifier)
          .saveCliente(
            id: _cliente?.id,
            nombre: _nombreCtrl.text,
            telefono: _telefonoCtrl.text,
            direccion: _direccionCtrl.text,
            locationUrl: _locationUrlCtrl.text,
            correo: _correoCtrl.text,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_isEdit ? 'Cliente actualizado' : 'Cliente creado'),
        ),
      );
      context.go(Routes.clienteDetail(saved.id));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(clientesControllerProvider);
    final user = ref.watch(authStateProvider).user;
    final locationPreview = parseClientLocationPreview(_locationUrlCtrl.text);
    final locationUri = Uri.tryParse(_locationUrlCtrl.text.trim());

    return Scaffold(
      drawer: buildAdaptiveDrawer(context, currentUser: user),
      appBar: AppBar(
        leading: AppNavigator.maybeBackButton(
          context,
          fallbackRoute: Routes.clientes,
        ),
        title: Text(_isEdit ? 'Editar cliente' : 'Nuevo cliente'),
      ),
      body: _loadingInitial
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      TextFormField(
                        controller: _nombreCtrl,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(
                          labelText: 'Nombre *',
                          hintText: 'Nombre completo del cliente',
                        ),
                        validator: (value) {
                          final text = (value ?? '').trim();
                          if (text.isEmpty) return 'El nombre es obligatorio';
                          if (text.length < 2) {
                            return 'Ingresa un nombre válido';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _telefonoCtrl,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(
                          labelText: 'Teléfono *',
                          hintText: 'Ej: +1 809 555 1234',
                        ),
                        validator: (value) {
                          final text = (value ?? '').trim();
                          if (text.isEmpty) return 'El teléfono es obligatorio';
                          final sanitized = text.replaceAll(
                            RegExp(r'[^0-9+]'),
                            '',
                          );
                          if (sanitized.length < 7) {
                            return 'Teléfono demasiado corto';
                          }
                          final allowed = RegExp(r'^[0-9+()\-\s]+$');
                          if (!allowed.hasMatch(text)) {
                            return 'Formato de teléfono inválido';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _direccionCtrl,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: const InputDecoration(
                          labelText: 'Dirección',
                          hintText: 'Opcional',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _locationUrlCtrl,
                        keyboardType: TextInputType.url,
                        decoration: InputDecoration(
                          labelText: 'Link de ubicación',
                          hintText: 'https://maps.google.com/...',
                          suffixIcon: IconButton(
                            tooltip: 'Abrir link',
                            onPressed: (_locationUrlCtrl.text).trim().isEmpty
                                ? null
                                : () async {
                                    final uri = locationUri;
                                    if (uri == null) return;
                                    await safeOpenUrl(context, uri);
                                  },
                            icon: const Icon(Icons.open_in_new_rounded),
                          ),
                        ),
                        onChanged: (_) => setState(() {}),
                        validator: (value) {
                          final text = (value ?? '').trim();
                          if (text.isEmpty) return null;
                          final uri = Uri.tryParse(text);
                          final looksValid =
                              uri != null &&
                              uri.hasScheme &&
                              (uri.host.isNotEmpty || uri.scheme == 'geo');
                          if (!looksValid) {
                            return 'Ingresa un link de ubicación válido';
                          }
                          return null;
                        },
                      ),
                      if ((_locationUrlCtrl.text).trim().isNotEmpty) ...[
                        const SizedBox(height: 12),
                        _LocationPreviewCard(
                          locationUrl: _locationUrlCtrl.text.trim(),
                          latitude: locationPreview.latitude,
                          longitude: locationPreview.longitude,
                        ),
                      ],
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _correoCtrl,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(
                          labelText: 'Correo',
                          hintText: 'Opcional',
                        ),
                        validator: (value) {
                          final text = (value ?? '').trim();
                          if (text.isEmpty) return null;
                          if (!validators.isEmail(text)) {
                            return 'Correo inválido';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: state.saving
                                  ? null
                                  : () => Navigator.pop(context),
                              child: const Text('Cancelar'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: state.saving ? null : _save,
                              icon: state.saving
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.save_outlined),
                              label: const Text('Guardar'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}

class _LocationPreviewCard extends StatelessWidget {
  const _LocationPreviewCard({
    required this.locationUrl,
    this.latitude,
    this.longitude,
  });

  final String locationUrl;
  final double? latitude;
  final double? longitude;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final uri = Uri.tryParse(locationUrl);
    final hasCoords =
        latitude != null &&
        longitude != null &&
        latitude!.isFinite &&
        longitude!.isFinite;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Vista previa de ubicación',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            if (hasCoords) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  height: 180,
                  child: FlutterMap(
                    options: MapOptions(
                      initialCenter: LatLng(latitude!, longitude!),
                      initialZoom: 15,
                      interactionOptions: const InteractionOptions(
                        flags: InteractiveFlag.none,
                      ),
                    ),
                    children: [
                      TileLayer(
                        urlTemplate:
                            'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.fulltech.app',
                      ),
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: LatLng(latitude!, longitude!),
                            width: 40,
                            height: 40,
                            child: Icon(
                              Icons.location_pin,
                              color: theme.colorScheme.error,
                              size: 40,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '${latitude!.toStringAsFixed(6)}, ${longitude!.toStringAsFixed(6)}',
                style: theme.textTheme.bodySmall,
              ),
            ] else
              Text(
                'El enlace se guardará, pero no se pudieron extraer coordenadas para mostrar el mapa aquí.',
                style: theme.textTheme.bodyMedium,
              ),
            if (uri != null) ...[
              const SizedBox(height: 8),
              FilledButton.tonalIcon(
                onPressed: () => safeOpenUrl(context, uri),
                icon: const Icon(Icons.open_in_new_rounded, size: 18),
                label: const Text('Abrir enlace'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
