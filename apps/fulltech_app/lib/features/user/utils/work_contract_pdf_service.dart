import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../../core/company/company_settings_model.dart';
import '../../../core/models/user_model.dart';

const _spanishMonths = <String>[
  'enero',
  'febrero',
  'marzo',
  'abril',
  'mayo',
  'junio',
  'julio',
  'agosto',
  'septiembre',
  'octubre',
  'noviembre',
  'diciembre',
];

String _dateToSpanishLong(DateTime date) {
  final month = _spanishMonths[(date.month - 1).clamp(0, 11)];
  return 'día ${date.day} del mes de $month del año ${date.year}';
}

String _unitsToSpanish(int n) {
  switch (n) {
    case 0:
      return 'CERO';
    case 1:
      return 'UNO';
    case 2:
      return 'DOS';
    case 3:
      return 'TRES';
    case 4:
      return 'CUATRO';
    case 5:
      return 'CINCO';
    case 6:
      return 'SEIS';
    case 7:
      return 'SIETE';
    case 8:
      return 'OCHO';
    case 9:
      return 'NUEVE';
    case 10:
      return 'DIEZ';
    case 11:
      return 'ONCE';
    case 12:
      return 'DOCE';
    case 13:
      return 'TRECE';
    case 14:
      return 'CATORCE';
    case 15:
      return 'QUINCE';
    case 16:
      return 'DIECISEIS';
    case 17:
      return 'DIECISIETE';
    case 18:
      return 'DIECIOCHO';
    case 19:
      return 'DIECINUEVE';
    case 20:
      return 'VEINTE';
    case 21:
      return 'VEINTIUNO';
    case 22:
      return 'VEINTIDOS';
    case 23:
      return 'VEINTITRES';
    case 24:
      return 'VEINTICUATRO';
    case 25:
      return 'VEINTICINCO';
    case 26:
      return 'VEINTISEIS';
    case 27:
      return 'VEINTISIETE';
    case 28:
      return 'VEINTIOCHO';
    case 29:
      return 'VEINTINUEVE';
    default:
      return '';
  }
}

String _tensToSpanish(int n) {
  if (n < 30) return _unitsToSpanish(n);
  final tens = n ~/ 10;
  final unit = n % 10;
  String tensWord;
  switch (tens) {
    case 3:
      tensWord = 'TREINTA';
      break;
    case 4:
      tensWord = 'CUARENTA';
      break;
    case 5:
      tensWord = 'CINCUENTA';
      break;
    case 6:
      tensWord = 'SESENTA';
      break;
    case 7:
      tensWord = 'SETENTA';
      break;
    case 8:
      tensWord = 'OCHENTA';
      break;
    case 9:
      tensWord = 'NOVENTA';
      break;
    default:
      tensWord = '';
  }
  if (unit == 0) return tensWord;
  return '$tensWord Y ${_unitsToSpanish(unit)}';
}

String _hundredsToSpanish(int n) {
  if (n < 100) return _tensToSpanish(n);
  if (n == 100) return 'CIEN';
  final hundreds = n ~/ 100;
  final rest = n % 100;
  String hundredsWord;
  switch (hundreds) {
    case 1:
      hundredsWord = 'CIENTO';
      break;
    case 2:
      hundredsWord = 'DOSCIENTOS';
      break;
    case 3:
      hundredsWord = 'TRESCIENTOS';
      break;
    case 4:
      hundredsWord = 'CUATROCIENTOS';
      break;
    case 5:
      hundredsWord = 'QUINIENTOS';
      break;
    case 6:
      hundredsWord = 'SEISCIENTOS';
      break;
    case 7:
      hundredsWord = 'SETECIENTOS';
      break;
    case 8:
      hundredsWord = 'OCHOCIENTOS';
      break;
    case 9:
      hundredsWord = 'NOVECIENTOS';
      break;
    default:
      hundredsWord = '';
  }
  if (rest == 0) return hundredsWord;
  return '$hundredsWord ${_tensToSpanish(rest)}';
}

String _numberToSpanishWords(int n) {
  if (n < 0) return '';
  if (n < 1000) return _hundredsToSpanish(n);
  if (n < 1000000) {
    final thousands = n ~/ 1000;
    final rest = n % 1000;
    final thousandsWord = thousands == 1
        ? 'MIL'
        : '${_hundredsToSpanish(thousands)} MIL';
    if (rest == 0) return thousandsWord;
    return '$thousandsWord ${_hundredsToSpanish(rest)}';
  }
  // Out of supported range for now.
  return '';
}

String _salaryToContractText(String salario) {
  // If salary is already a formatted string from upstream, try to extract
  // numeric value. Otherwise, fallback to the provided string.
  final numeric = salario.replaceAll(RegExp(r'[^0-9.,]'), '');
  final normalized = numeric.replaceAll(',', '');
  final value = double.tryParse(normalized);
  if (value == null) return salario.trim();

  final pesos = value.floor();
  final cents = ((value - pesos) * 100).round().clamp(0, 99);
  final words = _numberToSpanishWords(pesos);
  final centsText = cents.toString().padLeft(2, '0');
  final fmt = NumberFormat.currency(symbol: 'RD\$', decimalDigits: 2);
  return '${words.isEmpty ? '________________' : words} PESOS DOMINICANOS CON $centsText/100 (${fmt.format(value)})';
}

DateTime _addMonths(DateTime date, int monthsToAdd) {
  final year = date.year + ((date.month - 1 + monthsToAdd) ~/ 12);
  final month = ((date.month - 1 + monthsToAdd) % 12) + 1;

  final lastDayOfTargetMonth = DateTime(year, month + 1, 0).day;
  final day = date.day <= lastDayOfTargetMonth
      ? date.day
      : lastDayOfTargetMonth;
  return DateTime(year, month, day);
}

Future<Uint8List> buildWorkContractPdf({
  required UserModel employee,
  CompanySettings? company,
  String? lugar,
  DateTime? fechaInicio,
  String? salario,
  String? moneda,
  String? periodicidadPago,
  String? metodoPago,
}) async {
  final today = DateTime.now();

  final companyName = (company?.companyName ?? '').trim().isNotEmpty
      ? company!.companyName.trim()
      : 'FULLTECH, SRL';

  // Datos fijos como aparecen en el contrato oficial provisto.
  const employerRncLine = '133 08020 6';
  const representativeName = 'YÚNIOR LÓPEZ DE LA ROSA';
  const representativeNationality = 'dominicano';
  const representativeCivil = 'soltero';
  const representativeCedula = '40238377333';
  const representativeRole = 'gerente';

  final companyAddress = (company?.address ?? '').trim().isNotEmpty
      ? company!.address!.trim()
      : 'la calle beller numero 9 centro, en la ciudad de Higüey, Provincia la Altagracia, República Dominicana';

  final nombreEmpleado = employee.nombreCompleto.trim().isNotEmpty
      ? employee.nombreCompleto.trim()
      : '____________________________';
  final cedulaEmpleado = (employee.cedula ?? '').trim().isNotEmpty
      ? employee.cedula!.trim()
      : '____________________________';

  final startDate = fechaInicio ?? employee.fechaIngreso ?? today;

  final salarioRaw = (salario ?? '').trim();
  final salarioText = salarioRaw.isNotEmpty
      ? _salaryToContractText(salarioRaw)
      : '____________________________';

  final doc = pw.Document(title: 'Contrato de trabajo', author: companyName);

  pw.Widget spacedText(String text) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 8),
      child: pw.Text(
        text,
        style: const pw.TextStyle(fontSize: 11, height: 1.25),
      ),
    );
  }

  pw.Widget richLabel(String label, String rest) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 8),
      child: pw.RichText(
        text: pw.TextSpan(
          style: const pw.TextStyle(fontSize: 11, height: 1.25),
          children: [
            pw.TextSpan(
              text: label,
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            ),
            pw.TextSpan(text: rest),
          ],
        ),
      ),
    );
  }

  pw.Widget centeredTitle(String text) {
    return pw.Center(
      child: pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 8),
        child: pw.Text(
          text,
          textAlign: pw.TextAlign.center,
          style: pw.TextStyle(
            fontSize: 14,
            fontWeight: pw.FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }

  pw.Widget signatureBlock(String leftLabel, String rightLabel) {
    return pw.Column(
      children: [
        pw.SizedBox(height: 18),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Expanded(
              child: pw.Column(
                children: [
                  pw.Container(height: 1, color: PdfColors.black),
                  pw.SizedBox(height: 4),
                  pw.Text(leftLabel, style: const pw.TextStyle(fontSize: 10)),
                ],
              ),
            ),
            pw.SizedBox(width: 28),
            pw.Expanded(
              child: pw.Column(
                children: [
                  pw.Container(height: 1, color: PdfColors.black),
                  pw.SizedBox(height: 4),
                  pw.Text(rightLabel, style: const pw.TextStyle(fontSize: 10)),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(28),
      build: (context) => [
        pw.Text(
          companyName,
          style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
        ),
        pw.Text(employerRncLine, style: const pw.TextStyle(fontSize: 11)),
        pw.SizedBox(height: 10),
        centeredTitle('C O N T R A T O   D E    T R A B A J O'),
        pw.SizedBox(height: 8),
        pw.Text('ENTRE:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 10),

        spacedText(
          'De una parte, $companyName., sociedad constituida, organizada y existente de conformidad con las leyes de la República Dominicana, con domicilio social en $companyAddress, en su calidad de administradora y operadora de negocios de elaboración de alimentos (comida rápida) en lo adelante, “LA EMPRESA”, representado para todos los fines del presente documento por $representativeName, $representativeNationality, mayor de edad, $representativeCivil, provisto de la Cédula de Identidad y Electoral No. $representativeCedula, en su calidad de $representativeRole, que a los fines del presente contrato se denominará: EL EMPLEADOR;',
        ),

        spacedText(
          'Y, de la otra parte, $nombreEmpleado, de nacionalidad dominicana, mayor de edad, provisto de la Cédula de Identidad y Electoral No. $cedulaEmpleado, con domicilio y residencia en la ciudad de Higüey, Provincia la Altagracia, República Dominicana, quien en lo adelante se denominará: EL EMPLEADO.',
        ),

        spacedText(
          'Ambas partes conjuntamente denominadas en lo adelante, Las Partes:',
        ),

        pw.SizedBox(height: 6),
        pw.Text(
          'HAN CONVENIDO LO SIGUIENTE:',
          style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 12),

        richLabel(
          'PRIMERO: ',
          'Objeto del Contrato: EL EMPLEADOR por medio del presente documento contrata los servicios de EL EMPLEADO, quien acepta trabajar para el LA EMPRESA, en horario 9:00 am A 6:00 pm. Con una hora de almuerzo entre la 1:00pm a 2:00pm. de lunes a domingo, teniendo un día libre semanal y devengará por dicho concepto un salario mensual de $salarioText.',
        ),

        richLabel(
          'SEGUNDO: ',
          'Duración del Contrato: El presente contrato será por tiempo indefinido y comenzará a partir del ${_dateToSpanishLong(startDate)}.',
        ),

        richLabel(
          'TERCERO: ',
          'EL EMPLEADOR proveerá a EL EMPLEADO de seguro de salud durante la vigencia del presente contrato, así como los beneficios otorgados por el Código de Trabajo de la República Dominicana.',
        ),

        pw.SizedBox(height: 4),
        spacedText(
          'PÁRRAFO I: En caso de que el presente contrato sea rescindido por cualquiera de las partes, antes de los 3 meses, EL EMPLEADO automáticamente perderá los beneficios anteriormente señalados.',
        ),

        richLabel(
          'CUARTO: ',
          'EL EMPLEADO se compromete a cumplir el horario regular de trabajo establecido por EL EMPLEADOR, el cual puede ser modificado dependiendo de las necesidades de LA EMPRESA, lo que le será avisado previamente a EL EMPLEADO; en el entendido que en caso de que EL EMPLEADO no pueda asistir a su jornada de trabajo por cualquier causa, aún esta sea justificada, EL EMPLEADO deberá hacer los arreglos necesarios y deberá notificarlo a LA EMPRESA con antelación.',
        ),

        richLabel(
          'QUINTO: ',
          'EL EMPLEADO, se compromete a asistir y a participar en las actividades y actos que celebre EL EMPLEADOR, tales como: Reuniones laborales, eventos que queden contratados fuera del local comercial.',
        ),

        richLabel(
          'SEXTO: ',
          'A EL EMPLEADO, sin perjuicio de cualquier período, determinado por EL EMPLEADOR, le corresponderá, un periodo de vacaciones cada año, en la fecha que establezcan por mutuo acuerdo según calendario del equipo.',
        ),

        richLabel(
          'NOVENO: ',
          'El incumplimiento de cualquiera de las obligaciones contraídas por EL EMPLEADO establecidas en este contrato y/o por las causas enunciadas por el Código de Trabajo de la República Dominicana dará lugar a la rescisión del presente contrato.',
        ),

        richLabel(
          'DECIMO: ',
          'El presente contrato deja sin ningún valor y efecto jurídico cualquier acuerdo suscrito con anterioridad.',
        ),

        richLabel(
          'DECIMO PRIMERO: ',
          'Las partes aceptan todas y cada una de las estipulaciones pactadas por el presente documento y para lo no previsto en el mismo se remiten al Código de Trabajo de la República Dominicana y al Derecho Común que regirá a título supletorio sus relaciones.',
        ),

        pw.SizedBox(height: 14),
        spacedText(
          'HECHO Y FIRMADO DE BUENA FE ENTRE LAS PARTES, en la calle Padre Bellini N°6, Higüey, sector Cambelen, en la ciudad de Higüey, Provincia la Altagracia, República Dominicana, el ${_dateToSpanishLong(startDate)}.',
        ),

        signatureBlock('POR EL EMPLEADOR:', 'POR EL EMPLEADO:'),
        pw.SizedBox(height: 14),

        pw.SizedBox(height: 16),
        pw.Text(
          'CERTIFICACION DE FIRMAS',
          style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 10),
        spacedText(
          'Yo, ANATACIO GUERRERO, Abogado Notario Público de los del Número de los del municipio Higüey de la provincia La Altagracia con Colegiatura del Colegio de Notarios de la República Dominicana Número 7065, CERTIFICO Y DOY FE: Que las firmas que anteceden en el presente documento, fueron puestas y escritas en mi presencia por los SEÑORES: x,x,x,x,x,x Y x,x,x,x,x,x,x,x de generales que constan la cual me han manifestado bajo fe del juramento que con esas firmas es con la que ellos acostumbran a usar en todos los actos de su vida pública y privada.  En la Calle Dionicio Arturo Troncoso N°16 Esq. Gaspar Hernández de la Ciudad de Higüey, provincia La Altagracia, República Dominicana, a los QUINCE (15) días del mes de Enero del año Dos mil Veinte y Dos (2022). DE TODO LO QUE CERTIFICO Y DOY FE-',
        ),
        pw.SizedBox(height: 18),
        pw.Container(height: 1, color: PdfColors.black),
        pw.SizedBox(height: 6),
        pw.Text(
          'DR. ANATACIO GUERRERO\nAbogado Notario Público',
          style: const pw.TextStyle(fontSize: 10),
        ),
      ],
    ),
  );

  return doc.save();
}

Future<void> shareWorkContractPdf({
  required Uint8List bytes,
  required UserModel employee,
}) async {
  final safeName = employee.nombreCompleto.trim().isEmpty
      ? 'empleado'
      : employee.nombreCompleto.trim().replaceAll(RegExp(r'\s+'), '_');
  final dateFmt = DateFormat('yyyyMMdd');
  final fileName = 'contrato_${safeName}_${dateFmt.format(DateTime.now())}.pdf';
  await Printing.sharePdf(bytes: bytes, filename: fileName);
}
