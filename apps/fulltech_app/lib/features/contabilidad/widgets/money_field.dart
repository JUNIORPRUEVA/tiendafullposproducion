import 'package:flutter/material.dart';

class MoneyField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final bool enabled;
  final String? helperText;
  final String? Function(String?)? validator;

  const MoneyField({
    super.key,
    required this.controller,
    required this.label,
    this.enabled = true,
    this.helperText,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      enabled: enabled,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: label,
        helperText: helperText,
        prefixText: '\$ ',
      ),
      validator: validator,
    );
  }
}
