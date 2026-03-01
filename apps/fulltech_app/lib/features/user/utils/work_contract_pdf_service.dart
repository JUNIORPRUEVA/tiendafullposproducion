import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../../core/company/company_settings_model.dart';
import '../../../core/models/user_model.dart';

Future<Uint8List> buildWorkContractPdf({
  required UserModel employee,
  CompanySettings? company,
}) async {
  final dateFmt = DateFormat('dd/MM/yyyy');
  final today = DateTime.now();

  final companyName = (company?.companyName ?? '').trim().isNotEmpty
      ? company!.companyName.trim()
      : 'FULLTECH';
  final rnc = (company?.rnc ?? '').trim();
  final phone = (company?.phone ?? '').trim();
  final address = (company?.address ?? '').trim();

  final nombre = employee.nombreCompleto.trim().isNotEmpty
      ? employee.nombreCompleto.trim()
      : '________________';
  final cedula = (employee.cedula ?? '').trim().isNotEmpty
      ? employee.cedula!.trim()
      : '________________';
  final telefono = employee.telefono.trim().isNotEmpty
      ? employee.telefono.trim()
      : '________________';
  final email = employee.email.trim().isNotEmpty
      ? employee.email.trim()
      : '________________';

  final fechaIngreso = employee.fechaIngreso != null
      ? dateFmt.format(employee.fechaIngreso!)
      : '________________';

  final cuentaNomina = (employee.cuentaNominaPreferencial ?? '').trim().isNotEmpty
      ? employee.cuentaNominaPreferencial!.trim()
      : '________________';

  final habilidades = employee.habilidades.isNotEmpty
      ? employee.habilidades.join(', ')
      : '________________';

  final rol = (employee.role ?? '').trim().isNotEmpty
      ? (employee.role ?? '').trim()
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
              if (address.isNotEmpty) pw.Text(address),
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
              pw.Text('Fecha: ${dateFmt.format(today)}'),
            ],
          ),
        ),
        pw.SizedBox(height: 14),
        pw.Divider(),

        sectionTitle('1) Partes'),
        pw.Text(
          'Entre $companyName (en lo adelante “EL EMPLEADOR”) y $nombre (en lo adelante “EL EMPLEADO”), se acuerda el presente contrato de trabajo bajo los términos y condiciones descritos a continuación.',
        ),

        sectionTitle('2) Datos del empleado'),
        labelValue('Nombre completo:', nombre),
        labelValue('Cédula:', cedula),
        labelValue('Teléfono:', telefono),
        labelValue('Correo:', email),
        labelValue('Rol/Puesto:', rol),
        labelValue('Fecha de ingreso:', fechaIngreso),
        labelValue('Cuenta nómina preferencial:', cuentaNomina),
        labelValue('Habilidades:', habilidades),

        sectionTitle('3) Condiciones principales'),
        pw.Bullet(text: 'Tipo de contrato: ______________________________'),
        pw.Bullet(text: 'Período de prueba (si aplica): ________________'),
        pw.Bullet(text: 'Horario de trabajo: __________________________'),
        pw.Bullet(text: 'Remuneración y forma de pago: ________________'),
        pw.Bullet(text: 'Lugar de trabajo: ____________________________'),

        sectionTitle('4) Obligaciones y políticas'),
        pw.Text(
          'EL EMPLEADO se compromete a cumplir con las políticas internas, normas de seguridad, confidencialidad y lineamientos operativos del EMPLEADOR. Cualquier incumplimiento podrá conllevar medidas disciplinarias según el reglamento interno y la legislación aplicable.',
        ),

        sectionTitle('5) Confidencialidad'),
        pw.Text(
          'EL EMPLEADO reconoce que durante su relación laboral puede tener acceso a información confidencial. Se obliga a no divulgar dicha información durante la vigencia del contrato ni con posterioridad, salvo autorización expresa del EMPLEADOR.',
        ),

        sectionTitle('6) Firma'),
        pw.SizedBox(height: 16),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Expanded(
              child: pw.Column(
                children: [
                  pw.Divider(thickness: 1),
                  pw.Text('Firma EL EMPLEADOR'),
                ],
              ),
            ),
            pw.SizedBox(width: 24),
            pw.Expanded(
              child: pw.Column(
                children: [
                  pw.Divider(thickness: 1),
                  pw.Text('Firma EL EMPLEADO'),
                ],
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 10),
        pw.Text(
          'Nota: Este documento es una plantilla generada automáticamente. Revísalo y ajústalo con tu asesor legal según tus políticas internas y la legislación aplicable.',
          style: pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
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
