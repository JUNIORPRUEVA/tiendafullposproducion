import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/ai_assistant/domain/models/ai_chat_context.dart';
import '../../core/ai_assistant/domain/services/ai_assistant_service.dart';
import '../../core/auth/app_role.dart';
import '../../core/routing/routes.dart';
import '../../core/theme/role_branding.dart';
import 'company_manual_models.dart';

final companyManualExecutivePresentationServiceProvider =
    Provider<CompanyManualExecutivePresentationService>((ref) {
      return CompanyManualExecutivePresentationService(
        ref.watch(aiAssistantServiceProvider),
      );
    });

class CompanyManualExecutivePresentationBundle {
  const CompanyManualExecutivePresentationBundle({
    required this.presentation,
    required this.pdfBytes,
    required this.fileName,
  });

  final CompanyManualExecutivePresentation presentation;
  final Uint8List pdfBytes;
  final String fileName;
}

class CompanyManualExecutivePresentation {
  const CompanyManualExecutivePresentation({
    required this.title,
    required this.subtitle,
    required this.coverStatement,
    required this.themeLabel,
    required this.slides,
    required this.generatedWithAi,
  });

  final String title;
  final String subtitle;
  final String coverStatement;
  final String themeLabel;
  final List<CompanyManualExecutiveSlide> slides;
  final bool generatedWithAi;
}

class CompanyManualExecutiveSlide {
  const CompanyManualExecutiveSlide({
    required this.title,
    required this.subtitle,
    required this.bullets,
    required this.highlight,
    required this.presenterNote,
  });

  final String title;
  final String subtitle;
  final List<String> bullets;
  final String highlight;
  final String presenterNote;
}

class CompanyManualExecutivePresentationService {
  CompanyManualExecutivePresentationService(this._aiAssistantService);

  final AiAssistantService _aiAssistantService;

  Future<CompanyManualExecutivePresentationBundle> generateBundle({
    required CompanyManualEntry entry,
    required AppRole role,
  }) async {
    final presentation = await _generatePresentation(entry);
    final pdfBytes = await _buildPdf(
      entry: entry,
      role: role,
      presentation: presentation,
    );
    return CompanyManualExecutivePresentationBundle(
      presentation: presentation,
      pdfBytes: pdfBytes,
      fileName: _buildFileName(entry),
    );
  }

  Future<CompanyManualExecutivePresentation> _generatePresentation(
    CompanyManualEntry entry,
  ) async {
    try {
      final result = await _aiAssistantService.chat(
        context: AiChatContext(
          module: 'manual-interno',
          screenName: 'Manual Interno',
          route: Routes.manualInterno,
          entityType: 'company-manual-entry',
          entityId: entry.id,
        ),
        message: _buildPrompt(entry),
        history: const [],
      );
      if (!result.denied) {
        final parsed = _tryParseAiPresentation(result.content);
        if (parsed != null && parsed.slides.isNotEmpty) {
          return parsed;
        }
      }
    } catch (_) {
      // Fallback handled below so admins can always present the rule.
    }

    return _buildFallbackPresentation(entry);
  }

  String _buildPrompt(CompanyManualEntry entry) {
    final audience = entry.audience.label;
    final roles = entry.targetRoles.map((role) => role.label).join(', ');
    final module = (entry.moduleKey ?? '').trim();

    return '''
Genera una presentacion ejecutiva en ESPANOL para una reunion interna de equipo sobre una regla o norma del Manual Interno de FullTech.

Debes responder SOLO con JSON valido, sin markdown, sin comentarios y sin texto adicional.

Formato exacto:
{
  "title": "string",
  "subtitle": "string",
  "coverStatement": "string",
  "themeLabel": "string",
  "slides": [
    {
      "title": "string",
      "subtitle": "string",
      "highlight": "string",
      "presenterNote": "string",
      "bullets": ["string", "string", "string"]
    }
  ]
}

Reglas estrictas:
- Entre 4 y 6 slides.
- Maximo 4 bullets por slide.
- Cada bullet debe ser breve, clara y ejecutiva.
- No inventes politicas ni datos que no existan en el texto fuente.
- Si algo no esta explicito en el texto, reformulalo sin agregar informacion nueva.
- Debe verse como una presentacion elegante tipo PowerPoint para explicar al equipo.
- Enfoca el tono segun el tema real de la regla.
- Usa un estilo corporativo serio, claro y moderno, acorde con colores azul petroleo, turquesa y cian profesional.

Datos de la regla:
Titulo: ${entry.title}
Tipo: ${entry.kind.label}
Audiencia: $audience
${roles.isEmpty ? '' : 'Roles objetivo: $roles'}
${module.isEmpty ? '' : 'Modulo relacionado: $module'}
Resumen: ${entry.summary ?? 'Sin resumen'}
Contenido fuente:
${entry.content}
''';
  }

  CompanyManualExecutivePresentation? _tryParseAiPresentation(String raw) {
    final normalized = raw.trim();
    if (normalized.isEmpty) return null;

    final jsonCandidate = _extractJsonObject(normalized);
    if (jsonCandidate == null) return null;

    final dynamic decoded;
    try {
      decoded = jsonDecode(jsonCandidate);
    } catch (_) {
      return null;
    }
    if (decoded is! Map) return null;
    final map = decoded.cast<String, dynamic>();
    final slidesRaw = map['slides'];
    if (slidesRaw is! List) return null;

    final slides = slidesRaw
        .whereType<Map>()
        .map((item) => item.cast<String, dynamic>())
        .map(_slideFromMap)
        .whereType<CompanyManualExecutiveSlide>()
        .toList();
    if (slides.isEmpty) return null;

    return CompanyManualExecutivePresentation(
      title: _nonEmptyOr(map['title'], 'Presentacion ejecutiva'),
      subtitle: _nonEmptyOr(map['subtitle'], 'Resumen clave para reunion'),
      coverStatement: _nonEmptyOr(
        map['coverStatement'],
        'Alineemos el criterio operativo del equipo.',
      ),
      themeLabel: _nonEmptyOr(map['themeLabel'], 'Manual Interno'),
      slides: slides,
      generatedWithAi: true,
    );
  }

  CompanyManualExecutiveSlide? _slideFromMap(Map<String, dynamic> map) {
    final bulletsRaw = map['bullets'];
    final bullets = bulletsRaw is List
        ? bulletsRaw
              .whereType<String>()
              .map((item) => item.trim())
              .where((item) => item.isNotEmpty)
              .take(4)
              .toList()
        : const <String>[];
    if (bullets.isEmpty) return null;

    return CompanyManualExecutiveSlide(
      title: _nonEmptyOr(map['title'], 'Punto clave'),
      subtitle: _nonEmptyOr(map['subtitle'], 'Guia de aplicacion'),
      highlight: _nonEmptyOr(map['highlight'], 'Alineacion operativa'),
      presenterNote: _nonEmptyOr(
        map['presenterNote'],
        'Explica por que este punto importa para la operacion diaria.',
      ),
      bullets: bullets,
    );
  }

  CompanyManualExecutivePresentation _buildFallbackPresentation(
    CompanyManualEntry entry,
  ) {
    final summaryBullets = _extractBullets(
      '${entry.summary ?? ''}\n${entry.content}',
      maxItems: 4,
    );
    final detailBullets = _extractBullets(entry.content, maxItems: 4);
    final actionBullets = _buildActionBullets(entry);
    final riskBullets = _buildRiskBullets(entry);

    return CompanyManualExecutivePresentation(
      title: entry.title,
      subtitle: '${entry.kind.label} · ${entry.audience.label}',
      coverStatement:
          'Presentacion ejecutiva para explicar la norma con claridad, contexto y criterio operativo.',
      themeLabel: entry.moduleKey?.trim().isNotEmpty == true
          ? 'Modulo ${entry.moduleKey!.trim()}'
          : 'Manual Interno FullTech',
      slides: [
        CompanyManualExecutiveSlide(
          title: 'Idea central',
          subtitle: 'Que debe entender el equipo desde el inicio',
          highlight: 'Alineacion inmediata',
          presenterNote:
              'Abre la reunion explicando el objetivo de la norma y por que existe.',
          bullets: summaryBullets,
        ),
        CompanyManualExecutiveSlide(
          title: 'Puntos que no se pueden perder',
          subtitle: 'Resumen ejecutivo de la regla',
          highlight: 'Criterio compartido',
          presenterNote:
              'Usa este slide para validar que todos interpretan la regla igual.',
          bullets: detailBullets,
        ),
        CompanyManualExecutiveSlide(
          title: 'Como aplicarlo en la operacion',
          subtitle: 'Traduccion practica al trabajo diario',
          highlight: 'Ejecucion diaria',
          presenterNote:
              'Conecta la norma con comportamientos concretos del equipo.',
          bullets: actionBullets,
        ),
        CompanyManualExecutiveSlide(
          title: 'Errores que debemos evitar',
          subtitle: 'Riesgos mas comunes al incumplir o interpretar mal',
          highlight: 'Prevencion',
          presenterNote:
              'Cierra este tramo mostrando el costo operativo de no alinearse.',
          bullets: riskBullets,
        ),
      ],
      generatedWithAi: false,
    );
  }

  List<String> _buildActionBullets(CompanyManualEntry entry) {
    final bullets = <String>[];
    bullets.add('Aplicar la norma de forma consistente en cada caso similar.');
    if (entry.audience == CompanyManualAudience.roleSpecific &&
        entry.targetRoles.isNotEmpty) {
      bullets.add(
        'Confirmar responsabilidades del rol: ${entry.targetRoles.map((role) => role.label).join(', ')}.',
      );
    } else {
      bullets.add('Alinear a todo el equipo con el mismo criterio operativo.');
    }
    if ((entry.moduleKey ?? '').trim().isNotEmpty) {
      bullets.add('Usar la regla dentro del flujo del modulo ${entry.moduleKey!.trim()}.');
    }
    bullets.add('Resolver dudas antes de ejecutar para evitar retrabajo.');
    return bullets.take(4).toList();
  }

  List<String> _buildRiskBullets(CompanyManualEntry entry) {
    final extracted = _extractBullets(entry.content, maxItems: 6)
        .map((item) => 'Evitar: $item')
        .take(2)
        .toList();
    final bullets = <String>[
      ...extracted,
      'Evitar interpretaciones distintas de una misma norma.',
      'Evitar decisiones improvisadas fuera del criterio definido.',
      'Evitar impactos en servicio, tiempos o confianza del cliente.',
    ];
    return bullets.take(4).toList();
  }

  List<String> _extractBullets(String text, {required int maxItems}) {
    final normalized = text
        .replaceAll('\r', '\n')
        .replaceAll('•', '\n')
        .replaceAll(RegExp(r'\n+'), '\n')
        .trim();
    if (normalized.isEmpty) {
      return const ['Mantener criterio claro y comunicacion simple.'];
    }

    final bulletLike = normalized
        .split('\n')
        .map((line) => line.replaceFirst(RegExp(r'^[-*\d\.)\s]+'), '').trim())
        .where((line) => line.isNotEmpty)
        .toList();

    final source = bulletLike.length >= maxItems
        ? bulletLike
        : normalized
              .split(RegExp(r'(?<=[\.!?])\s+'))
              .map((line) => line.trim())
              .where((line) => line.isNotEmpty)
              .toList();

    final cleaned = <String>[];
    for (final item in source) {
      final compact = item.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (compact.isEmpty) continue;
      cleaned.add(_limitWords(compact, 16));
      if (cleaned.length >= maxItems) break;
    }
    if (cleaned.isEmpty) {
      return const ['Mantener criterio claro y comunicacion simple.'];
    }
    return cleaned;
  }

  String _limitWords(String text, int maxWords) {
    final words = text.split(' ');
    if (words.length <= maxWords) return text;
    return '${words.take(maxWords).join(' ')}...';
  }

  String _nonEmptyOr(dynamic value, String fallback) {
    final normalized = value?.toString().trim() ?? '';
    return normalized.isEmpty ? fallback : normalized;
  }

  String? _extractJsonObject(String raw) {
    final fenceMatch = RegExp(r'```(?:json)?\s*([\s\S]*?)```', caseSensitive: false)
        .firstMatch(raw);
    final candidate = fenceMatch != null ? fenceMatch.group(1)!.trim() : raw;
    final start = candidate.indexOf('{');
    final end = candidate.lastIndexOf('}');
    if (start == -1 || end == -1 || end <= start) return null;
    return candidate.substring(start, end + 1);
  }

  Future<Uint8List> _buildPdf({
    required CompanyManualEntry entry,
    required AppRole role,
    required CompanyManualExecutivePresentation presentation,
  }) async {
    final branding = resolveRoleBranding(role);
    final doc = pw.Document(
      title: presentation.title,
      author: 'FullTech',
      subject: 'Presentacion ejecutiva del Manual Interno',
    );
    final pageTheme = pw.PageTheme(
      pageFormat: PdfPageFormat.a4.landscape,
      margin: const pw.EdgeInsets.all(22),
    );

    doc.addPage(
      pw.Page(
        pageTheme: pageTheme,
        build: (context) => _buildCoverSlide(
          entry: entry,
          branding: branding,
          presentation: presentation,
        ),
      ),
    );

    for (var index = 0; index < presentation.slides.length; index++) {
      doc.addPage(
        pw.Page(
          pageTheme: pageTheme,
          build: (context) => _buildContentSlide(
            branding: branding,
            entry: entry,
            slide: presentation.slides[index],
            pageNumber: index + 2,
            totalPages: presentation.slides.length + 1,
            generatedWithAi: presentation.generatedWithAi,
          ),
        ),
      );
    }

    return doc.save();
  }

  pw.Widget _buildCoverSlide({
    required CompanyManualEntry entry,
    required RoleBranding branding,
    required CompanyManualExecutivePresentation presentation,
  }) {
    final darkColor = branding.tertiary;
    final primaryColor = branding.primary;
    final secondaryColor = branding.secondary;
    final backgroundColor = branding.backgroundMiddle;
    final dark = _pdfColor(darkColor);
    final primary = _pdfColor(primaryColor);
    final secondary = _pdfColor(secondaryColor);
    final background = _pdfColor(backgroundColor);

    return pw.Container(
      decoration: pw.BoxDecoration(
        color: background,
        borderRadius: pw.BorderRadius.circular(26),
      ),
      child: pw.Stack(
        children: [
          pw.Positioned(
            right: -36,
            top: -28,
            child: pw.Container(
              width: 190,
              height: 190,
              decoration: pw.BoxDecoration(
                shape: pw.BoxShape.circle,
                color: _pdfColor(secondaryColor.withValues(alpha: 0.14)),
              ),
            ),
          ),
          pw.Positioned(
            left: -24,
            bottom: -60,
            child: pw.Container(
              width: 240,
              height: 240,
              decoration: pw.BoxDecoration(
                shape: pw.BoxShape.circle,
                color: _pdfColor(primaryColor.withValues(alpha: 0.12)),
              ),
            ),
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.all(34),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Row(
                  children: [
                    _coverPill('FULLTECH', dark, PdfColors.white),
                    pw.SizedBox(width: 10),
                    _coverPill('MANUAL INTERNO', PdfColors.white, dark),
                  ],
                ),
                pw.Spacer(),
                pw.Container(
                  width: 96,
                  height: 6,
                  decoration: pw.BoxDecoration(
                    color: primary,
                    borderRadius: pw.BorderRadius.circular(999),
                  ),
                ),
                pw.SizedBox(height: 22),
                pw.Text(
                  presentation.title,
                  style: pw.TextStyle(
                    color: dark,
                    fontSize: 28,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 10),
                pw.Text(
                  presentation.subtitle,
                  style: pw.TextStyle(
                    color: _pdfColor(darkColor.withValues(alpha: 0.78)),
                    fontSize: 15,
                  ),
                ),
                pw.SizedBox(height: 18),
                pw.Container(
                  width: 430,
                  padding: const pw.EdgeInsets.all(18),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.white,
                    borderRadius: pw.BorderRadius.circular(18),
                    border: pw.Border.all(
                      color: _pdfColor(primaryColor.withValues(alpha: 0.25)),
                    ),
                  ),
                  child: pw.Text(
                    presentation.coverStatement,
                    style: pw.TextStyle(
                      color: dark,
                      fontSize: 14,
                      lineSpacing: 3,
                    ),
                  ),
                ),
                pw.SizedBox(height: 20),
                pw.Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _metaChip(entry.kind.label, primary),
                    _metaChip(entry.audience.label, secondary),
                    _metaChip(presentation.themeLabel, dark),
                    if ((entry.moduleKey ?? '').trim().isNotEmpty)
                      _metaChip('Modulo ${entry.moduleKey!.trim()}', primary),
                  ],
                ),
                pw.Spacer(),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      branding.departmentName,
                      style: pw.TextStyle(
                        color: _pdfColor(darkColor.withValues(alpha: 0.7)),
                        fontSize: 11,
                      ),
                    ),
                    pw.Text(
                      presentation.generatedWithAi
                          ? 'Diseñado con apoyo de IA'
                          : 'Diseño ejecutivo generado localmente',
                      style: pw.TextStyle(
                        color: _pdfColor(darkColor.withValues(alpha: 0.7)),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _buildContentSlide({
    required RoleBranding branding,
    required CompanyManualEntry entry,
    required CompanyManualExecutiveSlide slide,
    required int pageNumber,
    required int totalPages,
    required bool generatedWithAi,
  }) {
    final primaryColor = branding.primary;
    final secondaryColor = branding.secondary;
    final darkColor = branding.tertiary;
    final lightColor = branding.backgroundMiddle;
    final primary = _pdfColor(primaryColor);
    final secondary = _pdfColor(secondaryColor);
    final dark = _pdfColor(darkColor);
    final light = _pdfColor(lightColor);

    return pw.Container(
      decoration: pw.BoxDecoration(
        color: light,
        borderRadius: pw.BorderRadius.circular(26),
      ),
      child: pw.Row(
        children: [
          pw.Container(
            width: 172,
            padding: const pw.EdgeInsets.fromLTRB(20, 24, 20, 24),
            decoration: pw.BoxDecoration(
              color: dark,
              borderRadius: const pw.BorderRadius.only(
                topLeft: pw.Radius.circular(26),
                bottomLeft: pw.Radius.circular(26),
              ),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'SLIDE ${pageNumber - 1}',
                  style: pw.TextStyle(
                    color: PdfColors.white,
                    fontSize: 11,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 16),
                pw.Container(
                  width: 44,
                  height: 4,
                  decoration: pw.BoxDecoration(
                    color: secondary,
                    borderRadius: pw.BorderRadius.circular(999),
                  ),
                ),
                pw.SizedBox(height: 18),
                pw.Text(
                  slide.highlight,
                  style: pw.TextStyle(
                    color: PdfColors.white,
                    fontSize: 22,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 14),
                pw.Text(
                  entry.title,
                  style: pw.TextStyle(
                    color: _pdfColor(
                      const Color(0xFFFFFFFF).withValues(alpha: 0.84),
                    ),
                    fontSize: 11,
                    lineSpacing: 2,
                  ),
                ),
                pw.Spacer(),
                pw.Text(
                  generatedWithAi ? 'IA + FullTech' : 'FullTech',
                  style: pw.TextStyle(
                    color: _pdfColor(
                      const Color(0xFFFFFFFF).withValues(alpha: 0.7),
                    ),
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
          pw.Expanded(
            child: pw.Padding(
              padding: const pw.EdgeInsets.fromLTRB(26, 24, 26, 18),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Expanded(
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text(
                              slide.title,
                              style: pw.TextStyle(
                                color: dark,
                                fontSize: 22,
                                fontWeight: pw.FontWeight.bold,
                              ),
                            ),
                            pw.SizedBox(height: 8),
                            pw.Text(
                              slide.subtitle,
                              style: pw.TextStyle(
                                color: _pdfColor(
                                  darkColor.withValues(alpha: 0.74),
                                ),
                                fontSize: 12.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      pw.Container(
                        padding: const pw.EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: pw.BoxDecoration(
                          color: _pdfColor(
                            primaryColor.withValues(alpha: 0.10),
                          ),
                          borderRadius: pw.BorderRadius.circular(999),
                        ),
                        child: pw.Text(
                          '$pageNumber/$totalPages',
                          style: pw.TextStyle(
                            color: primary,
                            fontWeight: pw.FontWeight.bold,
                            fontSize: 10.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 20),
                  pw.Expanded(
                    child: pw.Column(
                      children: [
                        for (final bullet in slide.bullets)
                          pw.Container(
                            width: double.infinity,
                            margin: const pw.EdgeInsets.only(bottom: 12),
                            padding: const pw.EdgeInsets.fromLTRB(14, 14, 14, 14),
                            decoration: pw.BoxDecoration(
                              color: PdfColors.white,
                              borderRadius: pw.BorderRadius.circular(16),
                              border: pw.Border.all(
                                color: _pdfColor(
                                  secondaryColor.withValues(alpha: 0.20),
                                ),
                              ),
                            ),
                            child: pw.Row(
                              crossAxisAlignment: pw.CrossAxisAlignment.start,
                              children: [
                                pw.Container(
                                  width: 22,
                                  height: 22,
                                  decoration: pw.BoxDecoration(
                                    color: primary,
                                    shape: pw.BoxShape.circle,
                                  ),
                                  child: pw.Center(
                                    child: pw.Text(
                                      '•',
                                      style: pw.TextStyle(
                                        color: PdfColors.white,
                                        fontSize: 16,
                                        fontWeight: pw.FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                                pw.SizedBox(width: 12),
                                pw.Expanded(
                                  child: pw.Text(
                                    bullet,
                                    style: pw.TextStyle(
                                      color: dark,
                                      fontSize: 13,
                                      lineSpacing: 3,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                  pw.Container(
                    width: double.infinity,
                    padding: const pw.EdgeInsets.all(14),
                    decoration: pw.BoxDecoration(
                      color: _pdfColor(
                        secondaryColor.withValues(alpha: 0.10),
                      ),
                      borderRadius: pw.BorderRadius.circular(16),
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          'Guion sugerido del presentador',
                          style: pw.TextStyle(
                            color: dark,
                            fontSize: 10.5,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                        pw.SizedBox(height: 6),
                        pw.Text(
                          slide.presenterNote,
                          style: pw.TextStyle(
                            color: _pdfColor(
                              darkColor.withValues(alpha: 0.84),
                            ),
                            fontSize: 11,
                            lineSpacing: 2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _coverPill(String label, PdfColor background, PdfColor foreground) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: pw.BoxDecoration(
        color: background,
        borderRadius: pw.BorderRadius.circular(999),
      ),
      child: pw.Text(
        label,
        style: pw.TextStyle(
          color: foreground,
          fontSize: 10.5,
          fontWeight: pw.FontWeight.bold,
        ),
      ),
    );
  }

  pw.Widget _metaChip(String label, PdfColor color) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: pw.BoxDecoration(
        color: _pdfColorFromChannels(color, 0.10),
        borderRadius: pw.BorderRadius.circular(999),
        border: pw.Border.all(color: _pdfColorFromChannels(color, 0.22)),
      ),
      child: pw.Text(
        label,
        style: pw.TextStyle(
          color: color,
          fontSize: 10.5,
          fontWeight: pw.FontWeight.bold,
        ),
      ),
    );
  }

  PdfColor _pdfColor(Color color) {
    return PdfColor.fromInt(color.toARGB32());
  }

  PdfColor _pdfColorFromChannels(PdfColor color, double alpha) {
    return PdfColor(color.red, color.green, color.blue, alpha);
  }

  String _buildFileName(CompanyManualEntry entry) {
    final slug = entry.title
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
    return 'manual-interno-${slug.isEmpty ? 'presentacion' : slug}.pdf';
  }
}