import PDFDocument = require('pdfkit');

export type InvoiceDraftData = {
  company: {
    name: string;
    rnc?: string | null;
    phone?: string | null;
    address?: string | null;
  };
  invoice: {
    number: string;
    dateIso: string;
  };
  client: {
    name: string;
    phone?: string | null;
    address?: string | null;
  };
  service: {
    id: string;
    title: string;
    typeLabel: string;
    technicianName?: string | null;
    serviceDateIso?: string | null;
  };
  initialQuoteAmount: number;
  extras: Array<{ description: string; qty?: number | null; amount: number; note?: string | null }>;
  notes?: string | null;
  totals: {
    extrasTotal: number;
    total: number;
  };
  approvalRecord?: {
    approvedByName?: string | null;
    approvedAtIso?: string | null;
  } | null;
  signature?: {
    pngBytes: Buffer;
    signedAtIso?: string | null;
  } | null;
};

export type WarrantyDraftData = {
  company: {
    name: string;
  };
  certificate: {
    number: string;
    dateIso: string;
  };
  clientName: string;
  serviceTypeLabel: string;
  equipmentInstalledText?: string | null;
  installationDateIso?: string | null;
  warrantyDurationMonths: number;
  technicianName?: string | null;
  serviceDateIso?: string | null;
  approvalRecord?: {
    approvedByName?: string | null;
    approvedAtIso?: string | null;
  } | null;
  signature?: {
    pngBytes: Buffer;
    signedAtIso?: string | null;
  } | null;
};

type PdfDoc = InstanceType<typeof PDFDocument>;

function bufferFromPdf(build: (doc: PdfDoc) => void): Promise<Buffer> {
  return new Promise((resolve, reject) => {
    const doc = new PDFDocument({ size: 'A4', margin: 48 });
    const chunks: Buffer[] = [];

    doc.on('data', (c) => chunks.push(Buffer.isBuffer(c) ? c : Buffer.from(c)));
    doc.on('error', reject);
    doc.on('end', () => resolve(Buffer.concat(chunks)));

    build(doc);
    doc.end();
  });
}

function fmtMoney(n: number) {
  const safe = Number.isFinite(n) ? n : 0;
  return safe.toLocaleString('es-DO', { style: 'currency', currency: 'DOP' });
}

function fmtDate(iso?: string | null) {
  const raw = (iso ?? '').trim();
  if (!raw) return '';
  const d = new Date(raw);
  if (Number.isNaN(d.getTime())) return raw;
  const pad = (x: number) => `${x}`.padStart(2, '0');
  return `${pad(d.getDate())}/${pad(d.getMonth() + 1)}/${d.getFullYear()}`;
}

export async function buildInvoicePdf(data: InvoiceDraftData): Promise<Buffer> {
  return bufferFromPdf((doc) => {
    doc.fontSize(16).text(data.company.name || 'FULLTECH', { align: 'left' });
    doc.moveDown(0.2);
    if (data.company.rnc) doc.fontSize(9).fillColor('#444').text(`RNC: ${data.company.rnc}`);
    if (data.company.phone) doc.fontSize(9).fillColor('#444').text(`Tel: ${data.company.phone}`);
    if (data.company.address) doc.fontSize(9).fillColor('#444').text(`Dirección: ${data.company.address}`);

    doc.moveDown(0.8);
    doc.fillColor('#000').fontSize(14).text('FACTURA', { align: 'right' });
    doc.fontSize(10).text(`No.: ${data.invoice.number}`, { align: 'right' });
    doc.fontSize(10).text(`Fecha: ${fmtDate(data.invoice.dateIso)}`, { align: 'right' });

    doc.moveDown(1);
    doc.fontSize(11).text('Cliente', { underline: true });
    doc.fontSize(10).text(`Nombre: ${data.client.name}`);
    if (data.client.phone) doc.fontSize(10).text(`Teléfono: ${data.client.phone}`);
    if (data.client.address) doc.fontSize(10).text(`Dirección: ${data.client.address}`);

    doc.moveDown(0.6);
    doc.fontSize(11).text('Servicio', { underline: true });
    doc.fontSize(10).text(`Tipo: ${data.service.typeLabel}`);
    doc.fontSize(10).text(`Técnico: ${data.service.technicianName ?? 'N/D'}`);
    doc.fontSize(10).text(`Fecha del servicio: ${fmtDate(data.service.serviceDateIso)}`);
    doc.fontSize(9).fillColor('#666').text(`ID: ${data.service.id}`);
    doc.fillColor('#000');

    doc.moveDown(1);
    doc.fontSize(11).text('Detalle', { underline: true });

    const startX = doc.x;
    const colDesc = startX;
    const colQty = startX + 330;
    const colAmt = startX + 420;

    doc.fontSize(9).fillColor('#444').text('Descripción', colDesc, doc.y);
    doc.text('Cant.', colQty, doc.y, { width: 60, align: 'right' });
    doc.text('Monto', colAmt, doc.y, { width: 90, align: 'right' });
    doc.fillColor('#000');
    doc.moveDown(0.3);

    doc.fontSize(10).text('Cotización inicial', colDesc, doc.y);
    doc.text('-', colQty, doc.y, { width: 60, align: 'right' });
    doc.text(fmtMoney(data.initialQuoteAmount), colAmt, doc.y, { width: 90, align: 'right' });
    doc.moveDown(0.2);

    for (const item of data.extras) {
      const desc = item.note ? `${item.description} (${item.note})` : item.description;
      doc.fontSize(10).text(desc, colDesc, doc.y, { width: 320 });
      doc.text(item.qty != null ? String(item.qty) : '-', colQty, doc.y, { width: 60, align: 'right' });
      doc.text(fmtMoney(item.amount), colAmt, doc.y, { width: 90, align: 'right' });
      doc.moveDown(0.2);
    }

    doc.moveDown(0.6);
    doc.fontSize(10).text(`Extras: ${fmtMoney(data.totals.extrasTotal)}`, { align: 'right' });
    doc.fontSize(12).text(`Total: ${fmtMoney(data.totals.total)}`, { align: 'right' });

    if (data.notes?.trim()) {
      doc.moveDown(0.8);
      doc.fontSize(10).text('Notas', { underline: true });
      doc.fontSize(9).text(data.notes.trim());
    }

    if (data.approvalRecord?.approvedAtIso || data.approvalRecord?.approvedByName) {
      doc.moveDown(0.8);
      doc.fontSize(9).fillColor('#444').text(
        `Aprobado por: ${data.approvalRecord?.approvedByName ?? 'N/D'} · ${fmtDate(data.approvalRecord?.approvedAtIso)}`,
      );
      doc.fillColor('#000');
    }

    if (data.signature?.pngBytes) {
      doc.moveDown(1);
      doc.fontSize(10).text('Firma del cliente', { underline: true });
      const y = doc.y + 8;
      doc.image(data.signature.pngBytes, startX, y, { fit: [240, 90] });
      doc.moveDown(6);
      if (data.signature.signedAtIso) {
        doc.fontSize(9).fillColor('#444').text(`Firmado el: ${fmtDate(data.signature.signedAtIso)}`);
        doc.fillColor('#000');
      }
    }
  });
}

export async function buildWarrantyPdf(data: WarrantyDraftData): Promise<Buffer> {
  return bufferFromPdf((doc) => {
    doc.fontSize(16).text(data.company.name || 'FULLTECH', { align: 'left' });
    doc.moveDown(0.6);
    doc.fontSize(14).text('CARTA DE GARANTÍA', { align: 'center' });

    doc.moveDown(0.6);
    doc.fontSize(10).text(`No.: ${data.certificate.number}`);
    doc.fontSize(10).text(`Fecha: ${fmtDate(data.certificate.dateIso)}`);

    doc.moveDown(1);
    doc.fontSize(11).text('Detalles', { underline: true });
    doc.fontSize(10).text(`Cliente: ${data.clientName}`);
    doc.fontSize(10).text(`Tipo de servicio: ${data.serviceTypeLabel}`);
    if (data.equipmentInstalledText?.trim()) {
      doc.fontSize(10).text(`Equipos instalados: ${data.equipmentInstalledText.trim()}`);
    }
    if (data.installationDateIso) {
      doc.fontSize(10).text(`Fecha de instalación: ${fmtDate(data.installationDateIso)}`);
    }
    doc.fontSize(10).text(`Duración de garantía: ${data.warrantyDurationMonths} meses`);

    doc.moveDown(0.9);
    doc.fontSize(10).text(
      'FULLTECH SRL certifica que los equipos instalados en este servicio cuentan con garantía según las condiciones establecidas por la empresa.',
      { align: 'justify' },
    );

    doc.moveDown(0.9);
    doc.fontSize(11).text('Condiciones de garantía', { underline: true });
    doc.fontSize(9).text(
      [
        '1) Cobertura (12 meses): cámaras, DVR/NVR, discos duros (HDD) y mano de obra de instalación, a partir de la fecha del servicio/instalación indicada en este documento.',
        '2) Cobertura (6 meses): motores y otros equipos no incluidos en el punto 1, a partir de la fecha del servicio/instalación indicada en este documento.',
        '3) Exclusiones: daños por golpes, manipulación indebida, humedad/inundación, descargas eléctricas, variaciones de voltaje, uso fuera de especificación, instalación/modificación por terceros, o falta de mantenimiento recomendado.',
        '4) Procedimiento: para activar la garantía se requiere validación del caso y, cuando aplique, revisión técnica del equipo/instalación.',
        '5) Tiempos de respuesta: la atención se coordina según agenda y disponibilidad, priorizando los casos que afecten la operación del cliente.',
      ].join('\n'),
      { align: 'justify' },
    );

    doc.moveDown(0.9);
    doc.fontSize(10).text(`Técnico: ${data.technicianName ?? 'N/D'}`);
    doc.fontSize(10).text(`Fecha del servicio: ${fmtDate(data.serviceDateIso)}`);

    if (data.approvalRecord?.approvedAtIso || data.approvalRecord?.approvedByName) {
      doc.moveDown(0.8);
      doc.fontSize(9).fillColor('#444').text(
        `Aprobado por: ${data.approvalRecord?.approvedByName ?? 'N/D'} · ${fmtDate(data.approvalRecord?.approvedAtIso)}`,
      );
      doc.fillColor('#000');
    }

    if (data.signature?.pngBytes) {
      doc.moveDown(1);
      doc.fontSize(10).text('Firma del cliente', { underline: true });
      const y = doc.y + 8;
      doc.image(data.signature.pngBytes, doc.x, y, { fit: [240, 90] });
      doc.moveDown(6);
      if (data.signature.signedAtIso) {
        doc.fontSize(9).fillColor('#444').text(`Firmado el: ${fmtDate(data.signature.signedAtIso)}`);
        doc.fillColor('#000');
      }
    }
  });
}
