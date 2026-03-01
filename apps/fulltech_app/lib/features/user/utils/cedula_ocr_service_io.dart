import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'cedula_ocr_types.dart';

class CedulaOcrServiceImpl implements CedulaOcrService {
  @override
  Future<CedulaOcrResult> scan({
    required List<int> bytes,
    required String fileName,
  }) async {
    if (kIsWeb) {
      throw UnsupportedError('Escaneo de cédula no disponible en Web.');
    }

    if (!(Platform.isAndroid || Platform.isIOS)) {
      throw UnsupportedError(
        'Escaneo de cédula disponible sólo en Android/iOS.',
      );
    }

    final tmpDir = await getTemporaryDirectory();
    final safeName = fileName.trim().isEmpty
        ? 'cedula.jpg'
        : fileName.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    final tmpPath = p.join(
      tmpDir.path,
      'cedula_scan_${DateTime.now().millisecondsSinceEpoch}_$safeName',
    );

    final tmpFile = File(tmpPath);
    await tmpFile.writeAsBytes(bytes, flush: true);

    final textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final inputImage = InputImage.fromFilePath(tmpFile.path);
      final recognizedText = await textRecognizer.processImage(inputImage);
      final raw = recognizedText.text;
      return CedulaOcrResult(
        rawText: raw,
        cedula: _extractCedula(raw),
        nombreCompleto: _extractNombreCompleto(raw),
        fechaNacimiento: _extractFechaNacimiento(raw),
      );
    } on MissingPluginException {
      throw UnsupportedError(
        'OCR no disponible (plugin no registrado en esta plataforma).',
      );
    } finally {
      await textRecognizer.close();
      unawaited(
        tmpFile.exists().then((exists) {
          if (exists) {
            return tmpFile.delete();
          }
          return Future<void>.value();
        }),
      );
    }
  }
}

String? _extractCedula(String text) {
  final normalized = text.replaceAll('\n', ' ');

  final dashed = RegExp(r'\b(\d{3}-\d{7}-\d)\b');
  final dashedMatch = dashed.firstMatch(normalized);
  if (dashedMatch != null) return dashedMatch.group(1);

  final compact = RegExp(r'\b(\d{11})\b');
  final compactMatch = compact.firstMatch(normalized.replaceAll('-', ''));
  if (compactMatch != null) {
    final digits = compactMatch.group(1)!;
    return '${digits.substring(0, 3)}-${digits.substring(3, 10)}-${digits.substring(10)}';
  }

  return null;
}

DateTime? _extractFechaNacimiento(String text) {
  final normalized = text.replaceAll('\n', ' ');
  final dateRe = RegExp(r'\b(\d{1,2})[\/-](\d{1,2})[\/-](\d{4})\b');
  final matches = dateRe.allMatches(normalized).toList(growable: false);
  if (matches.isEmpty) return null;

  DateTime? best;
  for (final m in matches) {
    final d = int.tryParse(m.group(1)!);
    final mo = int.tryParse(m.group(2)!);
    final y = int.tryParse(m.group(3)!);
    if (d == null || mo == null || y == null) continue;
    if (y < 1930 || y > DateTime.now().year) continue;
    if (mo < 1 || mo > 12) continue;
    if (d < 1 || d > 31) continue;

    final candidate = DateTime(y, mo, d);
    final now = DateTime.now();
    if (candidate.isAfter(now)) continue;

    // Prefer older plausible DOBs (avoid capturing issue/expiry dates if present).
    if (best == null || candidate.isBefore(best)) {
      best = candidate;
    }
  }
  return best;
}

String? _extractNombreCompleto(String text) {
  final lines = text
      .split(RegExp(r'\r?\n'))
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .toList(growable: false);

  // Try label-based extraction (common Spanish IDs)
  final labelPairs = <List<String>>[
    ['APELLIDOS', 'NOMBRES'],
    ['APELLIDO', 'NOMBRE'],
  ];

  for (final pair in labelPairs) {
    final ap = _findValueAfterLabel(lines, pair[0]);
    final nom = _findValueAfterLabel(lines, pair[1]);
    if (ap != null && nom != null) {
      final full = '${nom.trim()} ${ap.trim()}'.replaceAll(RegExp(r'\s+'), ' ');
      return _normalizeName(full);
    }
  }

  final candidates = lines
      .where((l) => l.length >= 8)
      .where((l) => RegExp(r'[A-Za-zÁÉÍÓÚÜÑáéíóúüñ]').hasMatch(l))
      .where(
        (l) => !RegExp(
          r'\b(REPUBLICA|REPÚBLICA|DOMINICANA|JUNTA|CENTRAL|ELECTORAL|CEDULA|CÉDULA|IDENTIDAD|NACIONALIDAD|SEXO|NACIMIENTO|FECHA|EXPIRA|EMISION)\b',
          caseSensitive: false,
        ).hasMatch(l),
      )
      .map((l) => l.replaceAll(RegExp(r'[^A-Za-zÁÉÍÓÚÜÑáéíóúüñ\s]'), ' '))
      .map((l) => l.replaceAll(RegExp(r'\s+'), ' ').trim())
      .where((l) => l.split(' ').length >= 2)
      .toList(growable: false);

  if (candidates.isEmpty) return null;

  // Choose the longest candidate as the name.
  candidates.sort((a, b) => b.length.compareTo(a.length));
  return _normalizeName(candidates.first);
}

String? _findValueAfterLabel(List<String> lines, String label) {
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i].toUpperCase();
    if (line.contains(label)) {
      // If label and value are on same line separated by ':'
      final colonIdx = lines[i].indexOf(':');
      if (colonIdx != -1 && colonIdx + 1 < lines[i].length) {
        final value = lines[i].substring(colonIdx + 1).trim();
        if (value.isNotEmpty) return value;
      }
      // Otherwise take next line
      if (i + 1 < lines.length) {
        final value = lines[i + 1].trim();
        if (value.isNotEmpty) return value;
      }
    }
  }
  return null;
}

String _normalizeName(String value) {
  final cleaned = value.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (cleaned.isEmpty) return cleaned;

  // Title-case-ish without forcing all-caps.
  return cleaned
      .split(' ')
      .where((w) => w.trim().isNotEmpty)
      .map((w) {
        final lower = w.toLowerCase();
        if (lower.length <= 2) return lower.toUpperCase();
        return '${lower[0].toUpperCase()}${lower.substring(1)}';
      })
      .join(' ');
}
