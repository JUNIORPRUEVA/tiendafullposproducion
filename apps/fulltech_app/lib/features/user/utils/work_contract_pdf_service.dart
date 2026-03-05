import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../../core/company/company_settings_model.dart';
import '../../../core/models/user_model.dart';

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
  final dateFmt = DateFormat('dd/MM/yyyy');
  final today = DateTime.now();

  final companyName = (company?.companyName ?? '').trim().isNotEmpty
      ? company!.companyName.trim()
      : 'FULLTECH SRL';
  const representativeName = 'Yunior López de la Rosa';
  final rnc = (company?.rnc ?? '').trim();
  final phone = (company?.phone ?? '').trim();
  final companyAddress = (company?.address ?? '').trim();

  final placeText = (lugar ?? '').trim().isNotEmpty
      ? lugar!.trim()
      : (companyAddress.isNotEmpty ? companyAddress : '________________');

  final nombre = employee.nombreCompleto.trim().isNotEmpty
      ? employee.nombreCompleto.trim()
      : '________________';
  final cedula = (employee.cedula ?? '').trim().isNotEmpty
      ? employee.cedula!.trim()
      : '________________';
  final telefono = employee.telefono.trim().isNotEmpty
      ? employee.telefono.trim()
      : '________________';
  final cargo = (employee.role ?? '').trim().isNotEmpty
      ? (employee.role ?? '').trim()
      : '________________';
  final direccionEmpleado = '________________';

  final startDate = fechaInicio ?? employee.fechaIngreso ?? today;
  final endDate = _addMonths(startDate, 3);

  final salarioText = (salario ?? '').trim().isNotEmpty
      ? salario!.trim()
      : '________________';
  final monedaText = (moneda ?? '').trim().isNotEmpty ? moneda!.trim() : 'DOP';
  final periodicidadText = (periodicidadPago ?? '').trim().isNotEmpty
      ? periodicidadPago!.trim()
      : '________________';
  final metodoPagoText = (metodoPago ?? '').trim().isNotEmpty
      ? metodoPago!.trim()
      : '________________';

  final doc = pw.Document(title: 'Contrato de trabajo', author: companyName);

  pw.Widget labelValue(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 6),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: 160,
            child: pw.Text(
              label,
              style: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.grey800,
              ),
            ),
          ),
          pw.Expanded(child: pw.Text(value)),
        ],
      ),
    );
  }

  pw.Widget sectionTitle(String text) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(top: 12, bottom: 8),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: 12,
          fontWeight: pw.FontWeight.bold,
          color: PdfColors.blue900,
        ),
      ),
    );
  }

  pw.Widget clauseTitle(String text) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(top: 10, bottom: 4),
      child: pw.Text(text, style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
    );
  }

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(28),
      build: (context) => [
        pw.Center(
          child: pw.Column(
            children: [
              pw.Text(
                companyName,
                style: pw.TextStyle(
                  fontSize: 16,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              if (rnc.isNotEmpty) pw.Text('RNC: $rnc'),
              if (phone.isNotEmpty) pw.Text('Tel: $phone'),
              if (companyAddress.isNotEmpty) pw.Text(companyAddress),
              pw.SizedBox(height: 10),
              pw.Text(
                'CONTRATO DE TRABAJO',
                style: pw.TextStyle(
                  fontSize: 14,
                  fontWeight: pw.FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                'Lugar y fecha: $placeText, a fecha ${dateFmt.format(today)}',
              ),
            ],
          ),
        ),
        pw.SizedBox(height: 14),
        pw.Divider(),

        sectionTitle('I. Identificación de las partes'),
        pw.Text(
          'Entre, de una parte, la sociedad comercial $companyName (en lo adelante, “LA EMPRESA”), debidamente representada por su Gerente y Representante Legal $representativeName; y, de la otra parte, el(la) Sr(a). $nombre (en lo adelante, “EL(la) EMPLEADO(a)”), portador(a) de la Cédula de Identidad y Electoral No. $cedula, con domicilio en $direccionEmpleado, teléfono $telefono, quien desempeñará el cargo de $cargo; se ha convenido y pactado el presente Contrato de Trabajo, el cual se regirá por las disposiciones del Código de Trabajo de la República Dominicana y por las siguientes cláusulas:',
        ),

        sectionTitle('Datos del empleado'),
        labelValue('Nombre completo:', nombre),
        labelValue('Número de cédula:', cedula),
        labelValue('Dirección:', direccionEmpleado),
        labelValue('Teléfono:', telefono),
        labelValue('Cargo o función:', cargo),

        sectionTitle('II. Objeto del contrato'),
        clauseTitle('Primera (Objeto y funciones).'),
        pw.Text(
          'EL(la) EMPLEADO(a) se obliga a prestar servicios personales a favor de LA EMPRESA en el área asignada, desempeñando las funciones propias del cargo indicado y aquellas tareas razonables y compatibles con su puesto que le sean asignadas conforme a las necesidades operativas de LA EMPRESA.',
        ),

        sectionTitle('III. Duración del contrato'),
        clauseTitle('Segunda (Contrato temporal por 3 meses).'),
        pw.Text(
          'El presente contrato es de naturaleza temporal por un período inicial de tres (3) meses, iniciando en fecha ${dateFmt.format(startDate)} y concluyendo en fecha ${dateFmt.format(endDate)}, salvo terminación anticipada por las causas previstas por la ley y/o por lo pactado en este contrato.',
        ),
        clauseTitle('Tercera (Renovación o contrato indefinido).'),
        pw.Text(
          'Al vencimiento del plazo indicado, LA EMPRESA podrá, según desempeño y necesidades operativas, renovar el presente contrato o acordar con EL(la) EMPLEADO(a) su continuidad bajo un contrato de duración indefinida, conforme a la normativa aplicable.',
        ),

        sectionTitle('IV. Horario de trabajo'),
        clauseTitle('Cuarta (Jornada y horario).'),
        pw.Text(
          'La jornada laboral ordinaria será de ocho (8) horas diarias. El horario específico será definido por LA EMPRESA según las necesidades operativas, comunicándose oportunamente a EL(la) EMPLEADO(a), quien se compromete a cumplirlo. Cualquier variación, descansos y horas extraordinarias se regirán por lo dispuesto en la legislación laboral vigente.',
        ),

        sectionTitle('V. Remuneración'),
        clauseTitle('Quinta (Salario y forma de pago).'),
        pw.Text(
          'LA EMPRESA pagará a EL(la) EMPLEADO(a) un salario de $salarioText (moneda: $monedaText), pagadero con periodicidad $periodicidadText mediante $metodoPagoText. Los descuentos y retenciones que correspondan se efectuarán conforme a la legislación aplicable.',
        ),

        sectionTitle('VI. Obligaciones del empleado'),
        clauseTitle('Sexta (Compromisos de EL(la) EMPLEADO(a)).'),
        pw.Bullet(
          text:
              'Cumplir diligentemente las tareas asignadas y responsabilidades propias del puesto.',
        ),
        pw.Bullet(
          text:
              'Respetar el horario laboral y mantener puntualidad y asistencia.',
        ),
        pw.Bullet(text: 'Mantener una conducta profesional y respetuosa.'),
        pw.Bullet(
          text:
              'Cumplir con las políticas internas y procedimientos de LA EMPRESA.',
        ),
        pw.Bullet(
          text:
              'Cuidar los equipos, herramientas y bienes de trabajo que le sean entregados.',
        ),
        pw.Bullet(
          text:
              'Mantener confidencialidad sobre la información y operaciones de LA EMPRESA.',
        ),

        sectionTitle('VII. Obligaciones de la empresa'),
        clauseTitle('Séptima (Compromisos de LA EMPRESA).'),
        pw.Bullet(
          text: 'Pagar el salario acordado en la forma y plazo convenidos.',
        ),
        pw.Bullet(
          text:
              'Proveer las herramientas necesarias para la ejecución de las labores.',
        ),
        pw.Bullet(
          text:
              'Cumplir con las leyes laborales vigentes en la República Dominicana.',
        ),

        sectionTitle('VIII. Normas y reglamento interno'),
        clauseTitle('Octava (Normas internas).'),
        pw.Text(
          'EL(la) EMPLEADO(a) declara conocer y aceptar el cumplimiento de las normas internas, políticas y procedimientos de FULLTECH SRL, incluyendo políticas de seguridad, uso de sistemas, manejo de información y medidas disciplinarias conforme a ley.',
        ),

        sectionTitle('IX. Terminación del contrato'),
        clauseTitle('Novena (Causas de terminación).'),
        pw.Text(
          'El presente contrato podrá finalizar: (a) por vencimiento del período de tres (3) meses; (b) por incumplimiento de las obligaciones; o (c) por decisión de una o ambas partes conforme al Código de Trabajo de la República Dominicana y demás disposiciones aplicables.',
        ),

        sectionTitle('X. Aceptación del contrato'),
        clauseTitle('Décima (Declaración de conformidad).'),
        pw.Text(
          'Leído que fue el presente contrato y enteradas las partes de su contenido y alcance, lo aceptan en todas sus partes y lo firman en dos (2) ejemplares de un mismo tenor y efecto, en el lugar y fecha indicados al inicio.',
        ),

        sectionTitle('Firmas'),
        pw.SizedBox(height: 16),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Expanded(
              child: pw.Column(
                children: [
                  pw.Divider(thickness: 1),
                  pw.Text('Firma del representante de LA EMPRESA'),
                  pw.SizedBox(height: 4),
                  pw.Text(representativeName),
                  pw.Text('Gerente – FULLTECH SRL'),
                ],
              ),
            ),
            pw.SizedBox(width: 24),
            pw.Expanded(
              child: pw.Column(
                children: [
                  pw.Divider(thickness: 1),
                  pw.Text('Firma del(la) EMPLEADO(a)'),
                  pw.SizedBox(height: 4),
                  pw.Text('Nombre: $nombre'),
                  pw.Text('Cédula: $cedula'),
                ],
              ),
            ),
          ],
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
