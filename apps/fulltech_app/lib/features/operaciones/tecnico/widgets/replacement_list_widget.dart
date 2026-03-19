import 'package:flutter/material.dart';

import '../technical_visit_models.dart';

class ReplacementListWidget extends StatefulWidget {
  final List<ReplacementItemModel> items;
  final ValueChanged<String> onAdd;
  final ValueChanged<int> onRemove;
  final bool enabled;

  const ReplacementListWidget({
    super.key,
    required this.items,
    required this.onAdd,
    required this.onRemove,
    this.enabled = true,
  });

  @override
  State<ReplacementListWidget> createState() => _ReplacementListWidgetState();
}

class _ReplacementListWidgetState extends State<ReplacementListWidget> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _controller.text.trim();
    if (value.isEmpty) return;
    widget.onAdd(value);
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Reemplazos realizados',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Registra piezas cambiadas o trabajos cubiertos por garantía.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: const Color(0xFF607287),
          ),
        ),
        const SizedBox(height: 12),
        if (widget.items.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Text(
              'Aún no hay reemplazos registrados.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: const Color(0xFF64748B),
                fontWeight: FontWeight.w600,
              ),
            ),
          )
        else
          Column(
            children: [
              for (var index = 0; index < widget.items.length; index++)
                Container(
                  margin: EdgeInsets.only(
                    bottom: index == widget.items.length - 1 ? 0 : 10,
                  ),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: const Color(0xFFE8F3FF),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.build_outlined,
                          size: 16,
                          color: Color(0xFF0B6BDE),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          widget.items[index].description,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF1E293B),
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Eliminar',
                        onPressed: widget.enabled
                            ? () => widget.onRemove(index)
                            : null,
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                enabled: widget.enabled,
                decoration: InputDecoration(
                  labelText: 'Pieza o trabajo realizado',
                  hintText:
                      'Ej. Reemplazo de fuente, ajuste de motor, cambio de sensor',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                onSubmitted: (_) => _submit(),
              ),
            ),
            const SizedBox(width: 10),
            FilledButton.icon(
              onPressed: widget.enabled ? _submit : null,
              icon: const Icon(Icons.add),
              label: const Text('Agregar'),
            ),
          ],
        ),
      ],
    );
  }
}
