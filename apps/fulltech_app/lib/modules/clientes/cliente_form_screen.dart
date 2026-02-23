import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:validators/validators.dart' as validators;

import 'application/clientes_controller.dart';
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
    _correoCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadIfEdit() async {
    if (!_isEdit) return;
    setState(() => _loadingInitial = true);
    try {
      final cliente = await ref.read(clientesControllerProvider.notifier).getById(widget.clienteId!);
      _cliente = cliente;
      _nombreCtrl.text = cliente.nombre;
      _telefonoCtrl.text = cliente.telefono;
      _direccionCtrl.text = cliente.direccion ?? '';
      _correoCtrl.text = cliente.correo ?? '';
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo cargar el cliente para edición')),
      );
    } finally {
      if (mounted) setState(() => _loadingInitial = false);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    try {
      await ref.read(clientesControllerProvider.notifier).saveCliente(
            id: _cliente?.id,
            nombre: _nombreCtrl.text,
            telefono: _telefonoCtrl.text,
            direccion: _direccionCtrl.text,
            correo: _correoCtrl.text,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_isEdit ? 'Cliente actualizado' : 'Cliente creado')),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(clientesControllerProvider);

    return Scaffold(
      appBar: AppBar(
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
                          if (text.length < 2) return 'Ingresa un nombre válido';
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
                          final sanitized = text.replaceAll(RegExp(r'[^0-9+]'), '');
                          if (sanitized.length < 7) return 'Teléfono demasiado corto';
                          final allowed = RegExp(r'^[0-9+()\-\s]+$');
                          if (!allowed.hasMatch(text)) return 'Formato de teléfono inválido';
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
                        controller: _correoCtrl,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(
                          labelText: 'Correo',
                          hintText: 'Opcional',
                        ),
                        validator: (value) {
                          final text = (value ?? '').trim();
                          if (text.isEmpty) return null;
                          if (!validators.isEmail(text)) return 'Correo inválido';
                          return null;
                        },
                      ),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: state.saving ? null : () => Navigator.pop(context),
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
                                      child: CircularProgressIndicator(strokeWidth: 2),
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
