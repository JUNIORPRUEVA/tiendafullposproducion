import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:signature/signature.dart';

class SignatureScreen extends StatefulWidget {
  final Future<void> Function(Uint8List pngBytes) onSave;

  const SignatureScreen({super.key, required this.onSave});

  @override
  State<SignatureScreen> createState() => _SignatureScreenState();
}

class _SignatureScreenState extends State<SignatureScreen> {
  late final SignatureController _controller;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _controller = SignatureController(
      penStrokeWidth: 3,
      exportBackgroundColor: Colors.white,
    );
    unawaited(
      SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    unawaited(
      SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]),
    );
    super.dispose();
  }

  Future<void> _save() async {
    if (_submitting) return;

    setState(() => _submitting = true);

    final bytes = await _controller.toPngBytes();
    if (!mounted) return;
    if (bytes == null || bytes.isEmpty) {
      setState(() => _submitting = false);
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text('Debes capturar una firma antes de guardar.'),
        ),
      );
      return;
    }

    try {
      await widget.onSave(bytes);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text('No se pudo guardar la firma: $e')),
      );
      setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return PopScope(
      canPop: !_submitting,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Firma del cliente',
                            style: theme.textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w900,
                              color: cs.onSurface,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Firma en horizontal y guarda para finalizar el cierre.',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: cs.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    TextButton(
                      onPressed: _submitting
                          ? null
                          : () => Navigator.of(context).pop(),
                      child: const Text('Cancelar'),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: _submitting ? null : _controller.clear,
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Limpiar'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: _submitting ? null : _save,
                      icon: const Icon(Icons.save_outlined),
                      label: const Text('Guardar firma'),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Expanded(
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: cs.outlineVariant.withValues(alpha: 0.60),
                      ),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x14000000),
                          blurRadius: 18,
                          offset: Offset(0, 8),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: ColoredBox(
                        color: Colors.white,
                        child: Signature(
                          controller: _controller,
                          backgroundColor: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
