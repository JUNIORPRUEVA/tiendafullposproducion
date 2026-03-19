import 'package:flutter/material.dart';

class NotesInput extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final String label;
  final String hintText;
  final int minLines;
  final int maxLines;
  final bool enabled;

  const NotesInput({
    super.key,
    required this.controller,
    required this.onChanged,
    this.label = 'Notas técnicas',
    this.hintText =
        'Escribe aquí los hallazgos, observaciones y próximos pasos.',
    this.minLines = 5,
    this.maxLines = 10,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      enabled: enabled,
      minLines: minLines,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        hintText: hintText,
        alignLabelWithHint: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
        filled: true,
        fillColor: const Color(0xFFF8FBFF),
      ),
      onChanged: onChanged,
    );
  }
}
