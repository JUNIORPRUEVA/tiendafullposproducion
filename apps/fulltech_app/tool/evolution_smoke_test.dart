import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:http_parser/http_parser.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

void main(List<String> args) async {
  final parsed = _parseArgs(args);

  final baseUrl =
      (parsed['baseUrl'] ?? Platform.environment['EVOLUTION_BASE_URL'] ?? '')
          .trim();
  final instance =
      (parsed['instance'] ?? Platform.environment['EVOLUTION_INSTANCE'] ?? '')
          .trim();
  final apiKey =
      (parsed['apiKey'] ?? Platform.environment['EVOLUTION_API_KEY'] ?? '')
          .trim();
  final to = (parsed['to'] ?? Platform.environment['EVOLUTION_TO'] ?? '')
      .trim();
  final mode = (parsed['mode'] ?? 'text').trim().toLowerCase();
  final text = (parsed['text'] ?? 'Prueba de envío (FULLTECH)').trim();

  if (baseUrl.isEmpty || instance.isEmpty || apiKey.isEmpty || to.isEmpty) {
    stderr.writeln('Missing args. Usage:');
    stderr.writeln(
      '  flutter pub run tool/evolution_smoke_test.dart --baseUrl <url> --instance <name> --apiKey <key> --to <phone> --mode text',
    );
    stderr.writeln(
      '  flutter pub run tool/evolution_smoke_test.dart --baseUrl <url> --instance <name> --apiKey <key> --to <phone> --mode pdf',
    );
    stderr.writeln(
      'Or set env vars: EVOLUTION_BASE_URL, EVOLUTION_INSTANCE, EVOLUTION_API_KEY, EVOLUTION_TO',
    );
    exitCode = 2;
    return;
  }

  final normalizedBaseUrl = baseUrl.endsWith('/')
      ? baseUrl.substring(0, baseUrl.length - 1)
      : baseUrl;
  final number = _normalizeWhatsAppNumber(to);
  if (number.isEmpty) {
    stderr.writeln('Invalid --to number.');
    exitCode = 2;
    return;
  }

  final dio = Dio(
    BaseOptions(
      baseUrl: normalizedBaseUrl,
      headers: {'apikey': apiKey},
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      sendTimeout: const Duration(seconds: 60),
      validateStatus: (_) => true,
    ),
  );

  final endpoint = mode == 'pdf'
      ? '/message/sendMedia/${Uri.encodeComponent(instance)}'
      : '/message/sendText/${Uri.encodeComponent(instance)}';

  if (mode == 'pdf') {
    final bytes = await _buildTestPdf();
    final b64 = base64Encode(bytes);
    final fileName = parsed['fileName'] ?? 'test_fulltech.pdf';
    final caption = parsed['caption'] ?? 'Prueba PDF desde FULLTECH';

    final numbersToTry = <String>{
      number,
      '$number@s.whatsapp.net',
      '$number@c.us',
    }.toList();

    final attempts = <({String label, Object data, Options? options})>[];

    for (final n in numbersToTry) {
      attempts.addAll([
        (
          label: 'flat:media+fileName:$n',
          data: {
            'number': n,
            'mediatype': 'document',
            'mimetype': 'application/pdf',
            'caption': caption,
            'media': b64,
            'fileName': fileName,
          },
          options: null,
        ),
        (
          label: 'nested:mediaMessage:$n',
          data: {
            'number': n,
            'mediaMessage': {
              'mediatype': 'document',
              'mimetype': 'application/pdf',
              'caption': caption,
              'media': b64,
              'fileName': fileName,
            },
          },
          options: null,
        ),
      ]);
    }

    // Multipart fallback.
    attempts.add((
      label: 'multipart:media',
      data: FormData.fromMap({
        'number': number,
        'caption': caption,
        'mediatype': 'document',
        'mimetype': 'application/pdf',
        'fileName': fileName,
        'media': MultipartFile.fromBytes(
          bytes,
          filename: fileName,
          contentType: MediaType('application', 'pdf'),
        ),
      }),
      options: Options(contentType: 'multipart/form-data'),
    ));

    Response<dynamic>? last;
    for (final attempt in attempts) {
      final res = await dio.post(
        endpoint,
        data: attempt.data,
        options: attempt.options,
      );
      stdout.writeln('--- Attempt: ${attempt.label}');
      stdout.writeln('Status: ${res.statusCode}');
      stdout.writeln('Data  : ${_stringify(res.data)}');
      last = res;
      if ((res.statusCode ?? 0) >= 200 && (res.statusCode ?? 0) < 300) {
        break;
      }
    }

    stdout.writeln('=== Evolution Smoke Test (final) ===');
    stdout.writeln('Status   : ${last?.statusCode}');
    stdout.writeln('Data     : ${_stringify(last?.data)}');

    if ((last?.statusCode ?? 0) < 200 || (last?.statusCode ?? 0) >= 300) {
      exitCode = 1;
    }
  } else {
    final res = await dio.post(
      endpoint,
      data: {'number': number, 'text': text},
    );

    stdout.writeln('=== Evolution Smoke Test ===');
    stdout.writeln('Base URL : $normalizedBaseUrl');
    stdout.writeln('Instance : $instance');
    stdout.writeln('Endpoint : $endpoint');
    stdout.writeln('To       : $to');
    stdout.writeln('Normalized: $number');
    stdout.writeln('Status   : ${res.statusCode}');
    stdout.writeln('Data     : ${_stringify(res.data)}');

    if ((res.statusCode ?? 0) < 200 || (res.statusCode ?? 0) >= 300) {
      exitCode = 1;
    }
  }
}

Future<Uint8List> _buildTestPdf() async {
  final doc = pw.Document();
  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      build: (context) {
        return pw.Center(
          child: pw.Text(
            'FULLTECH – PDF de prueba',
            style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold),
          ),
        );
      },
    ),
  );
  final bytes = await doc.save();
  return Uint8List.fromList(bytes);
}

String _stringify(dynamic data) {
  if (data == null) return 'null';
  if (data is String) return data;
  try {
    return const JsonEncoder.withIndent('  ').convert(data);
  } catch (_) {
    return data.toString();
  }
}

Map<String, String> _parseArgs(List<String> args) {
  final out = <String, String>{};
  for (var i = 0; i < args.length; i++) {
    final a = args[i];
    if (!a.startsWith('--')) continue;
    final key = a.substring(2);
    final value = (i + 1 < args.length && !args[i + 1].startsWith('--'))
        ? args[++i]
        : 'true';
    out[key] = value;
  }
  return out;
}

String _normalizeWhatsAppNumber(String raw) {
  var input = raw.trim();
  if (input.isEmpty) return '';

  final waMeMatch = RegExp(
    r'wa\.me/([0-9]+)',
    caseSensitive: false,
  ).firstMatch(input);
  if (waMeMatch != null) {
    input = waMeMatch.group(1) ?? input;
  }

  input = input.replaceAll(
    RegExp(r'(@c\.us|@s\.whatsapp\.net)$', caseSensitive: false),
    '',
  );

  var digits = input.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.isEmpty) return '';

  if (digits.startsWith('00')) {
    digits = digits.replaceFirst(RegExp(r'^00+'), '');
    if (digits.isEmpty) return '';
  }

  final isDominicanLocal =
      digits.length == 10 && RegExp(r'^(809|829|849)').hasMatch(digits);
  if (isDominicanLocal) return '1$digits';

  if (digits.length == 11 && digits.startsWith('1')) return digits;

  return digits;
}
