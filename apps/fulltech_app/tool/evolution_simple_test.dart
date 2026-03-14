import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:http_parser/http_parser.dart';

String _argValue(List<String> args, String name) {
  final idx = args.indexOf(name);
  if (idx == -1) return '';
  if (idx + 1 >= args.length) return '';
  return args[idx + 1].trim();
}

bool _hasFlag(List<String> args, String name) => args.contains(name);

String _env(String key) => (Platform.environment[key] ?? '').trim();

String _normalizeBaseUrl(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return '';
  return trimmed.endsWith('/')
      ? trimmed.substring(0, trimmed.length - 1)
      : trimmed;
}

String normalizeWhatsAppNumber(String raw) {
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

void _printUsage() {
  stdout.writeln('Evolution simple test');
  stdout.writeln('');
  stdout.writeln('Required (args or env):');
  stdout.writeln('  --baseUrl <url>        env: EVOLUTION_BASE_URL');
  stdout.writeln('  --instance <name>      env: EVOLUTION_INSTANCE');
  stdout.writeln('  --apiKey <key>         env: EVOLUTION_APIKEY');
  stdout.writeln('  --to <number>          env: EVOLUTION_TO');
  stdout.writeln('');
  stdout.writeln('Optional:');
  stdout.writeln(
    '  --text <message>       env: EVOLUTION_TEXT (default: "Prueba FULLTECH")',
  );
  stdout.writeln(
    '  --media                also tries sendMedia with a tiny PDF',
  );
  stdout.writeln('');
  stdout.writeln('Example:');
  stdout.writeln(
    '  dart run tool/evolution_simple_test.dart --baseUrl https://evo.tu-dominio.com --instance miinstancia --apiKey xxx --to 1829XXXXXXX --text "hola"',
  );
}

Uint8List _tinyPdfBytes() {
  // A minimal valid PDF file (very small). Enough for upload plumbing tests.
  const pdf =
      '%PDF-1.4\n'
      '1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n'
      '2 0 obj\n<< /Type /Pages /Kids [3 0 R] /Count 1 >>\nendobj\n'
      '3 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] /Contents 4 0 R >>\nendobj\n'
      '4 0 obj\n<< /Length 44 >>\nstream\nBT /F1 18 Tf 20 100 Td (FULLTECH) Tj ET\nendstream\nendobj\n'
      'xref\n0 5\n0000000000 65535 f \n'
      '0000000009 00000 n \n'
      '0000000058 00000 n \n'
      '0000000115 00000 n \n'
      '0000000213 00000 n \n'
      'trailer\n<< /Size 5 /Root 1 0 R >>\n'
      'startxref\n330\n%%EOF\n';
  return Uint8List.fromList(utf8.encode(pdf));
}

Future<void> _printResponse(Response<dynamic> res) async {
  stdout.writeln('HTTP ${res.statusCode} ${res.statusMessage ?? ''}');
  final data = res.data;
  if (data == null) {
    stdout.writeln('<no body>');
    return;
  }

  if (data is String) {
    stdout.writeln(data);
    return;
  }

  try {
    stdout.writeln(const JsonEncoder.withIndent('  ').convert(data));
  } catch (_) {
    stdout.writeln(data.toString());
  }
}

Future<void> main(List<String> args) async {
  if (_hasFlag(args, '--help') || _hasFlag(args, '-h')) {
    _printUsage();
    exit(0);
  }

  final baseUrl = _normalizeBaseUrl(
    _argValue(args, '--baseUrl').isNotEmpty
        ? _argValue(args, '--baseUrl')
        : _env('EVOLUTION_BASE_URL'),
  );
  final instance =
      (_argValue(args, '--instance').isNotEmpty
              ? _argValue(args, '--instance')
              : _env('EVOLUTION_INSTANCE'))
          .trim();
  final apiKey =
      (_argValue(args, '--apiKey').isNotEmpty
              ? _argValue(args, '--apiKey')
              : _env('EVOLUTION_APIKEY'))
          .trim();
  final toRaw =
      (_argValue(args, '--to').isNotEmpty
              ? _argValue(args, '--to')
              : _env('EVOLUTION_TO'))
          .trim();
  final text =
      (_argValue(args, '--text').isNotEmpty
              ? _argValue(args, '--text')
              : _env('EVOLUTION_TEXT'))
          .trim();

  if (baseUrl.isEmpty || instance.isEmpty || apiKey.isEmpty || toRaw.isEmpty) {
    _printUsage();
    stderr.writeln('Missing required config.');
    stderr.writeln(
      'baseUrl="$baseUrl" instance="$instance" apiKey=${apiKey.isEmpty ? '(empty)' : '(present)'} to="$toRaw"',
    );
    exit(2);
  }

  final toNumber = normalizeWhatsAppNumber(toRaw);
  if (toNumber.isEmpty) {
    stderr.writeln('Invalid WhatsApp number: "$toRaw"');
    exit(2);
  }

  final dio = Dio(
    BaseOptions(
      baseUrl: baseUrl,
      headers: {'apikey': apiKey, 'content-type': 'application/json'},
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 45),
      sendTimeout: const Duration(seconds: 60),
      validateStatus: (code) => true,
    ),
  );

  final sendTextPath = '/message/sendText/${Uri.encodeComponent(instance)}';
  final sendMediaPath = '/message/sendMedia/${Uri.encodeComponent(instance)}';

  stdout.writeln('BaseURL: $baseUrl');
  stdout.writeln('Instance: $instance');
  stdout.writeln('To: $toNumber');

  stdout.writeln('\n== 1) sendText ==');
  try {
    final res = await dio.post(
      sendTextPath,
      data: {
        'number': toNumber,
        'text': text.isEmpty ? 'Prueba FULLTECH' : text,
      },
    );
    await _printResponse(res);
  } catch (e) {
    stderr.writeln('sendText threw: $e');
    exit(1);
  }

  if (!_hasFlag(args, '--media')) {
    stdout.writeln('\nDone (text-only).');
    return;
  }

  stdout.writeln('\n== 2) sendMedia (tiny PDF) ==');
  final bytes = _tinyPdfBytes();
  final b64 = base64Encode(bytes);
  final fileName = 'prueba_fulltech.pdf';

  final attempts = <({String label, Object data, Options? options})>[
    (
      label: 'flat:base64',
      data: {
        'number': toNumber,
        'mediatype': 'document',
        'mimetype': 'application/pdf',
        'caption': 'Prueba FULLTECH (PDF)',
        'media': b64,
        'fileName': fileName,
      },
      options: null,
    ),
    (
      label: 'nested:mediaMessage',
      data: {
        'number': toNumber,
        'mediaMessage': {
          'mediatype': 'document',
          'mimetype': 'application/pdf',
          'caption': 'Prueba FULLTECH (PDF)',
          'media': b64,
          'fileName': fileName,
        },
      },
      options: null,
    ),
    (
      label: 'multipart:media',
      data: FormData.fromMap({
        'number': toNumber,
        'caption': 'Prueba FULLTECH (PDF)',
        'media': MultipartFile.fromBytes(
          bytes,
          filename: fileName,
          contentType: MediaType('application', 'pdf'),
        ),
      }),
      options: Options(contentType: 'multipart/form-data'),
    ),
  ];

  for (final attempt in attempts) {
    stdout.writeln('\n-- Attempt: ${attempt.label}');
    try {
      final res = await dio.post(
        sendMediaPath,
        data: attempt.data,
        options: attempt.options,
      );
      await _printResponse(res);
      if ((res.statusCode ?? 0) >= 200 && (res.statusCode ?? 0) < 300) {
        stdout.writeln('OK');
        return;
      }
    } catch (e) {
      stderr.writeln('Attempt ${attempt.label} threw: $e');
    }
  }

  stdout.writeln('\nDone (media attempts finished).');
}
