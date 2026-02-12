import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/client_model.dart';
import '../application/clients_controller.dart';

class ClientsView extends ConsumerStatefulWidget {
  const ClientsView({super.key});

  @override
  ConsumerState<ClientsView> createState() => _ClientsViewState();
}

class _ClientsViewState extends ConsumerState<ClientsView> {
  String search = '';

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(clientsControllerProvider);
    final ctrl = ref.watch(clientsControllerProvider.notifier);

    final filtered = state.items
        .where((c) => c.nombre.toLowerCase().contains(search.toLowerCase()))
        .toList();

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(context, ctrl),
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('Nuevo cliente'),
      ),
      body: RefreshIndicator(
        onRefresh: () => ctrl.load(search: search),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Buscar cliente',
              ),
              onChanged: (v) => setState(() => search = v),
            ),
            const SizedBox(height: 12),
            if (state.loading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: CircularProgressIndicator(),
                ),
              ),
            if (state.error != null)
              Text(
                state.error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ...filtered.map(
              (c) => Card(
                child: ListTile(
                  leading: const CircleAvatar(
                    child: Icon(Icons.person_outline),
                  ),
                  title: Text(c.nombre),
                  subtitle: Text(
                    [c.telefono, c.email]
                        .whereType<String>()
                        .where((e) => e.isNotEmpty)
                        .join(' · '),
                  ),
                  trailing: PopupMenuButton<String>(
                    onSelected: (value) {
                      if (value == 'edit') {
                        _openForm(context, ctrl, client: c);
                      } else if (value == 'delete') {
                        ctrl.remove(c.id);
                      }
                    },
                    itemBuilder: (context) => const [
                      PopupMenuItem(value: 'edit', child: Text('Editar')),
                      PopupMenuItem(value: 'delete', child: Text('Borrar')),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openForm(
    BuildContext context,
    ClientsController ctrl, {
    ClientModel? client,
  }) async {
    final nombre = TextEditingController(text: client?.nombre ?? '');
    final telefono = TextEditingController(text: client?.telefono ?? '');
    final email = TextEditingController(text: client?.email ?? '');
    final direccion = TextEditingController(text: client?.direccion ?? '');
    final notas = TextEditingController(text: client?.notas ?? '');

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(client == null ? 'Nuevo cliente' : 'Editar cliente'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nombre,
                decoration: const InputDecoration(labelText: 'Nombre'),
              ),
              TextField(
                controller: telefono,
                decoration: const InputDecoration(labelText: 'Teléfono'),
              ),
              TextField(
                controller: email,
                decoration: const InputDecoration(labelText: 'Email'),
              ),
              TextField(
                controller: direccion,
                decoration: const InputDecoration(labelText: 'Dirección'),
              ),
              TextField(
                controller: notas,
                decoration: const InputDecoration(labelText: 'Notas'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );

    if (result == true) {
      if (client == null) {
        await ctrl.create(
          nombre: nombre.text.trim(),
          telefono: telefono.text.trim(),
          email: email.text.trim(),
          direccion: direccion.text.trim(),
          notas: notas.text.trim(),
        );
      } else {
        await ctrl.update(
          client.id,
          nombre: nombre.text.trim(),
          telefono: telefono.text.trim(),
          email: email.text.trim(),
          direccion: direccion.text.trim(),
          notas: notas.text.trim(),
        );
      }
    }
  }
}
