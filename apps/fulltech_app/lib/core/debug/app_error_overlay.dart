import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_error_reporter.dart';
import '../routing/app_router.dart';

class AppErrorOverlay extends StatefulWidget {
  const AppErrorOverlay({super.key});

  @override
  State<AppErrorOverlay> createState() => _AppErrorOverlayState();
}

class _AppErrorOverlayState extends State<AppErrorOverlay> {
  int? _lastShownEventId;
  bool _dialogOpen = false;
  bool _retrying = false;

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

    final dialogContext = _resolveDialogContext();
    if (dialogContext == null) return;

    _dialogOpen = true;
    _lastShownEventId = error.eventId;
    await _showDetails(dialogContext, error);
    _dialogOpen = false;

    final latest = AppErrorReporter.instance.lastError.value;
    if (!mounted || latest == null) return;
    if (latest.eventId != _lastShownEventId) {
      unawaited(_showLatestErrorIfNeeded());
    }
  }

  BuildContext? _resolveDialogContext() {
    return appRootNavigatorKey.currentState?.overlay?.context ??
        appRootNavigatorKey.currentContext;
  }

  Future<void> _showDetails(BuildContext context, AppErrorDetails error) async {
    final full = error.toClipboardString();
    final technicalSections = <Widget>[
      _Section(label: 'Error real', value: error.primaryTechnicalMessage),
      if (error.message.trim().isNotEmpty &&
          error.message.trim() != error.primaryTechnicalMessage)
        _Section(label: 'Resumen tecnico', value: error.message),
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
    final severityColor = _severityColor(context, error.severity);
    final severityIcon = _severityIcon(error.severity);
    final canRetry = error.onRetry != null;

    await showDialog<void>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: true,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        final scheme = theme.colorScheme;
        final mediaQuery = MediaQuery.of(dialogContext);
        final maxDialogHeight =
            mediaQuery.size.height - mediaQuery.viewInsets.bottom - 32;
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return Dialog(
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 24,
              ),
              backgroundColor: Colors.transparent,
              elevation: 0,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: 500,
                  maxHeight: maxDialogHeight.clamp(280.0, 760.0),
                ),
                child: Container(
                  decoration: BoxDecoration(
                    color: scheme.surface.withValues(alpha: 0.985),
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.18),
                        blurRadius: 32,
                        offset: const Offset(0, 18),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(28),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Flexible(
                          child: SingleChildScrollView(
                            padding: EdgeInsets.zero,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Container(
                                  padding: const EdgeInsets.fromLTRB(
                                    22,
                                    20,
                                    22,
                                    18,
                                  ),
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [
                                        severityColor.withValues(alpha: 0.14),
                                        scheme.surface,
                                      ],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                  ),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Container(
                                        width: 54,
                                        height: 54,
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            colors: [
                                              severityColor.withValues(
                                                alpha: 0.22,
                                              ),
                                              severityColor.withValues(
                                                alpha: 0.08,
                                              ),
                                            ],
                                            begin: Alignment.topLeft,
                                            end: Alignment.bottomRight,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            18,
                                          ),
                                        ),
                                        child: Icon(
                                          severityIcon,
                                          color: severityColor,
                                          size: 28,
                                        ),
                                      ),
                                      const SizedBox(width: 14),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              error.title,
                                              style: theme.textTheme.titleLarge
                                                  ?.copyWith(
                                                    fontWeight: FontWeight.w800,
                                                    letterSpacing: -0.2,
                                                  ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              _subtitleFor(error),
                                              style: theme.textTheme.bodyMedium
                                                  ?.copyWith(
                                                    color:
                                                        scheme.onSurfaceVariant,
                                                  ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      IconButton(
                                        onPressed: () {
                                          AppErrorReporter.instance.clear();
                                          Navigator.of(
                                            dialogContext,
                                            rootNavigator: true,
                                          ).pop();
                                        },
                                        tooltip: 'Cerrar',
                                        icon: const Icon(Icons.close_rounded),
                                      ),
                                    ],
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    22,
                                    18,
                                    22,
                                    10,
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        error.userMessage,
                                        style: theme.textTheme.bodyLarge
                                            ?.copyWith(
                                              height: 1.45,
                                              color: scheme.onSurface
                                                  .withValues(alpha: 0.92),
                                            ),
                                      ),
                                      const SizedBox(height: 16),
                                      _Section(
                                        label: 'Error real para copiar',
                                        value: error.primaryTechnicalMessage,
                                        dense: true,
                                      ),
                                      const SizedBox(height: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 14,
                                          vertical: 12,
                                        ),
                                        decoration: BoxDecoration(
                                          color: scheme.surfaceContainerHighest
                                              .withValues(alpha: 0.55),
                                          borderRadius: BorderRadius.circular(
                                            18,
                                          ),
                                        ),
                                        child: Row(
                                          children: [
                                            Icon(
                                              Icons.shield_outlined,
                                              size: 18,
                                              color: severityColor,
                                            ),
                                            const SizedBox(width: 10),
                                            Expanded(
                                              child: Text(
                                                canRetry
                                                    ? 'Puedes intentar nuevamente sin salir de la pantalla.'
                                                    : 'Tu informacion sigue protegida y ya puedes copiar el error completo para revisarlo.',
                                                style: theme
                                                    .textTheme
                                                    .bodyMedium
                                                    ?.copyWith(
                                                      color: scheme
                                                          .onSurfaceVariant,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                    ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(height: 10),
                                      ...technicalSections,
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                          child: Wrap(
                            alignment: WrapAlignment.end,
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              TextButton.icon(
                                onPressed: () async {
                                  await Clipboard.setData(
                                    ClipboardData(text: full),
                                  );
                                  if (!dialogContext.mounted) return;
                                  ScaffoldMessenger.maybeOf(
                                    dialogContext,
                                  )?.showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Reporte copiado al portapapeles',
                                      ),
                                    ),
                                  );
                                },
                                icon: const Icon(Icons.copy_all_rounded),
                                label: const Text('Copiar reporte'),
                              ),
                              if (canRetry)
                                OutlinedButton.icon(
                                  onPressed: _retrying
                                      ? null
                                      : () async {
                                          setDialogState(
                                            () => _retrying = true,
                                          );
                                          try {
                                            await error.onRetry!.call();
                                            AppErrorReporter.instance.clear();
                                            if (!dialogContext.mounted) return;
                                            Navigator.of(
                                              dialogContext,
                                              rootNavigator: true,
                                            ).pop();
                                          } catch (retryError, retryStack) {
                                            AppErrorReporter.instance.record(
                                              retryError,
                                              retryStack,
                                              context: error.context,
                                              title: error.title,
                                              userMessage: error.userMessage,
                                              technicalDetails:
                                                  error.technicalDetails,
                                              severity: error.severity,
                                              dedupeKey:
                                                  'retry-${error.eventId}',
                                              retryLabel: error.retryLabel,
                                              onRetry: error.onRetry,
                                            );
                                          } finally {
                                            if (dialogContext.mounted) {
                                              setDialogState(
                                                () => _retrying = false,
                                              );
                                            } else {
                                              _retrying = false;
                                            }
                                          }
                                        },
                                  icon: _retrying
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(Icons.refresh_rounded),
                                  label: Text(error.retryLabel ?? 'Reintentar'),
                                ),
                              FilledButton.icon(
                                onPressed: () {
                                  AppErrorReporter.instance.clear();
                                  Navigator.of(
                                    dialogContext,
                                    rootNavigator: true,
                                  ).pop();
                                },
                                icon: const Icon(Icons.check_rounded),
                                label: Text(
                                  canRetry ? 'Ahora no' : 'Entendido',
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Color _severityColor(BuildContext context, AppErrorSeverity severity) {
    final scheme = Theme.of(context).colorScheme;
    switch (severity) {
      case AppErrorSeverity.warning:
        return Colors.orange.shade700;
      case AppErrorSeverity.fatal:
        return scheme.error;
      case AppErrorSeverity.error:
        return scheme.error;
    }
  }

  IconData _severityIcon(AppErrorSeverity severity) {
    switch (severity) {
      case AppErrorSeverity.warning:
        return Icons.warning_amber_rounded;
      case AppErrorSeverity.fatal:
        return Icons.dangerous_rounded;
      case AppErrorSeverity.error:
        return Icons.error_outline_rounded;
    }
  }

  String _subtitleFor(AppErrorDetails error) {
    if (error.onRetry != null) {
      return 'Puedes intentar nuevamente ahora.';
    }

    switch (error.severity) {
      case AppErrorSeverity.warning:
        return 'La aplicacion puede seguir funcionando.';
      case AppErrorSeverity.fatal:
        return 'Necesita atencion antes de continuar.';
      case AppErrorSeverity.error:
        return 'El sistema detecto una incidencia controlada.';
    }
  }

  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}

class _Section extends StatelessWidget {
  final String label;
  final String value;
  final bool dense;

  const _Section({
    required this.label,
    required this.value,
    this.dense = false,
  });

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
            padding: EdgeInsets.all(dense ? 10 : 12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withValues(
                alpha: 0.45,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              value,
              softWrap: true,
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}
