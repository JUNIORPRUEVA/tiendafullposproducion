import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_error_reporter.dart';

class AppErrorOverlay extends StatefulWidget {
  const AppErrorOverlay({super.key});

  @override
  State<AppErrorOverlay> createState() => _AppErrorOverlayState();
}

class _AppErrorOverlayState extends State<AppErrorOverlay> {
  int? _lastShownEventId;
  bool _dialogOpen = false;

  @override
  void initState() {
    super.initState();
    AppErrorReporter.instance.lastError.addListener(_handleErrorChanged);
  }

  @override
  void dispose() {
    AppErrorReporter.instance.lastError.removeListener(_handleErrorChanged);
    super.dispose();
  }

  void _handleErrorChanged() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _showLatestErrorIfNeeded();
    });
  }

  Future<void> _showLatestErrorIfNeeded() async {
    final error = AppErrorReporter.instance.lastError.value;
    if (error == null) return;
    if (_dialogOpen) return;
    if (_lastShownEventId == error.eventId) return;

    _dialogOpen = true;
    _lastShownEventId = error.eventId;
    await _showDetails(context, error);
    _dialogOpen = false;

    final latest = AppErrorReporter.instance.lastError.value;
    if (!mounted || latest == null) return;
    if (latest.eventId != _lastShownEventId) {
      unawaited(_showLatestErrorIfNeeded());
    }
  }

  Future<void> _showDetails(BuildContext context, AppErrorDetails error) async {
    final full = error.toClipboardString();
    final sections = <Widget>[
      _Section(label: 'Error', value: error.message),
      if ((error.endpointUrl ?? '').trim().isNotEmpty)
        _Section(label: 'Endpoint', value: error.endpointUrl!),
      if ((error.method ?? '').trim().isNotEmpty)
        _Section(label: 'Método', value: error.method!),
      if ((error.apiResponse ?? '').trim().isNotEmpty)
        _Section(label: 'Respuesta API', value: error.apiResponse!),
      if ((error.technicalDetails ?? '').trim().isNotEmpty)
        _Section(label: 'Detalle técnico', value: error.technicalDetails!),
      if (error.stackTrace.trim().isNotEmpty)
        _Section(label: 'Stack trace', value: error.stackTrace),
    ];

    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Error detectado'),
          content: SizedBox(
            width: 720,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: sections,
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: full));
                if (!dialogContext.mounted) return;
              },
              child: const Text('Copiar error'),
            ),
            TextButton(
              onPressed: () {
                AppErrorReporter.instance.clear();
                Navigator.pop(dialogContext);
              },
              child: const Text('Cerrar'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}

class _Section extends StatelessWidget {
  final String label;
  final String value;

  const _Section({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withValues(
                alpha: 0.45,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: SelectableText(value),
          ),
        ],
      ),
    );
  }
}
