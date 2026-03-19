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
    rnc?: string | null;
    phone?: string | null;
    address?: string | null;
  };
  certificate: {
    number: string;
    dateIso: string;
  };
  clientName: string;
  serviceTypeLabel: string;
  serviceLabel?: string | null;
  scopeLabel?: string | null;
  equipmentInstalledText?: string | null;
  installationDateIso?: string | null;
  hasWarranty?: boolean;
  warrantyDurationValue?: number | null;
  warrantyDurationUnit?: 'DAYS' | 'MONTHS' | 'YEARS' | null;
  warrantySummary?: string | null;
  coverageSummary?: string | null;
  exclusionsSummary?: string | null;
  notes?: string | null;
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

function fmtWarrantyDuration(value?: number | null, unit?: string | null) {
  if (!value || !Number.isFinite(value) || value <= 0) return '';
  switch ((unit ?? '').toUpperCase()) {
    case 'DAYS':
      return `${value} dia${value === 1 ? '' : 's'}`;
    case 'YEARS':
      return `${value} ano${value === 1 ? '' : 's'}`;
    case 'MONTHS':
    default:
      return `${value} mes${value === 1 ? '' : 'es'}`;
  }
}

const INVOICE_COLORS = {
  brand: '#0F4C81',
  brandDark: '#0A2F4E',
  brandSoft: '#EAF3FB',
  border: '#D6E3F0',
  text: '#17212B',
  muted: '#5B6773',
  line: '#E4EAF0',
  card: '#F8FBFE',
  white: '#FFFFFF',
};

function cleanText(value?: string | null) {
  return (value ?? '').trim();
}

function hasText(value?: string | null) {
  return cleanText(value).length > 0;
}

function moneyOrZero(value?: number | null) {
  return Number.isFinite(value) ? Number(value) : 0;
}

function safeDivide(total: number, qty?: number | null) {
  if (!qty || !Number.isFinite(qty) || qty <= 0) return total;
  return total / qty;
}

type InvoiceRow = {
  index: number;
  description: string;
  qtyText: string;
  unitPrice: number;
  total: number;
};

type InfoField = {
  label: string;
  value: string;
};

function collectInvoiceRows(data: InvoiceDraftData): InvoiceRow[] {
  const rows: InvoiceRow[] = [];
  const baseAmount = moneyOrZero(data.initialQuoteAmount);

  if (baseAmount > 0) {
    rows.push({
      index: rows.length + 1,
      description: 'Servicio base',
      qtyText: '1',
      unitPrice: baseAmount,
      total: baseAmount,
    });
  }

  for (const extra of data.extras) {
    const descriptionParts = [cleanText(extra.description), cleanText(extra.note)].filter(Boolean);
    const amount = moneyOrZero(extra.amount);
    if (!descriptionParts.length && amount <= 0) continue;
    const qty = extra.qty ?? null;
    rows.push({
      index: rows.length + 1,
      description: descriptionParts.join(' · '),
      qtyText: qty != null && Number.isFinite(qty) ? String(qty) : '1',
      unitPrice: safeDivide(amount, qty),
      total: amount,
    });
  }

  if (!rows.length) {
    rows.push({
      index: 1,
      description: cleanText(data.service.title) || cleanText(data.service.typeLabel) || 'Servicio',
      qtyText: '1',
      unitPrice: moneyOrZero(data.totals.total),
      total: moneyOrZero(data.totals.total),
    });
  }

  return rows;
}

function pageMetrics(doc: PdfDoc) {
  return {
    pageWidth: doc.page.width,
    pageHeight: doc.page.height,
    left: doc.page.margins.left,
    right: doc.page.width - doc.page.margins.right,
    top: doc.page.margins.top,
    bottom: doc.page.height - doc.page.margins.bottom,
    contentWidth: doc.page.width - doc.page.margins.left - doc.page.margins.right,
  };
}

function ensureSpace(doc: PdfDoc, heightNeeded: number) {
  const { top, bottom } = pageMetrics(doc);
  if (doc.y + heightNeeded <= bottom) return;
  doc.addPage();
  doc.y = top;
}

function drawRoundedCard(doc: PdfDoc, x: number, y: number, width: number, height: number, options?: {
  fillColor?: string;
  strokeColor?: string;
  radius?: number;
  lineWidth?: number;
}) {
  const radius = options?.radius ?? 12;
  doc.save();
  doc.lineWidth(options?.lineWidth ?? 1);
  doc.roundedRect(x, y, width, height, radius);
  doc.fillAndStroke(options?.fillColor ?? INVOICE_COLORS.white, options?.strokeColor ?? INVOICE_COLORS.border);
  doc.restore();
}

function drawSectionTitle(doc: PdfDoc, label: string, x: number, y: number, width: number) {
  doc
    .fillColor(INVOICE_COLORS.brand)
    .fontSize(10)
    .font('Helvetica-Bold')
    .text(label.toUpperCase(), x, y, { width, lineBreak: false });
}

function drawInfoCard(doc: PdfDoc, title: string, fields: InfoField[], x: number, y: number, width: number) {
  const visibleFields = fields.filter((field) => hasText(field.value));
  if (!visibleFields.length) return 0;

  const innerX = x + 16;
  const innerWidth = width - 32;
  const rowGap = 12;
  let contentHeight = 18;

  for (const field of visibleFields) {
    const valueHeight = doc.heightOfString(field.value, {
      width: innerWidth,
      align: 'left',
    });
    contentHeight += 12 + valueHeight + rowGap;
  }

  const height = Math.max(110, contentHeight + 10);
  drawRoundedCard(doc, x, y, width, height, {
    fillColor: INVOICE_COLORS.card,
    strokeColor: INVOICE_COLORS.border,
  });

  drawSectionTitle(doc, title, innerX, y + 16, innerWidth);

  let cursorY = y + 36;
  for (const field of visibleFields) {
    doc
      .fillColor(INVOICE_COLORS.muted)
      .font('Helvetica-Bold')
      .fontSize(8.5)
      .text(field.label, innerX, cursorY, { width: innerWidth, lineBreak: false });
    cursorY += 12;
    doc
      .fillColor(INVOICE_COLORS.text)
      .font('Helvetica')
      .fontSize(10.5)
      .text(field.value, innerX, cursorY, { width: innerWidth, align: 'left' });
    cursorY = doc.y + rowGap;
  }

  return height;
}

function drawHeader(doc: PdfDoc, data: InvoiceDraftData, documentType: string) {
  const { left, top, contentWidth } = pageMetrics(doc);
  const rightWidth = 200;
  const leftWidth = contentWidth - rightWidth - 18;
  const headerTop = top;
  const rightX = left + leftWidth + 18;
  const cardHeight = 132;

  drawRoundedCard(doc, left, headerTop, leftWidth, cardHeight, {
    fillColor: INVOICE_COLORS.white,
    strokeColor: INVOICE_COLORS.border,
  });
  drawRoundedCard(doc, rightX, headerTop, rightWidth, cardHeight, {
    fillColor: INVOICE_COLORS.brandDark,
    strokeColor: INVOICE_COLORS.brandDark,
  });

  const companyX = left + 18;
  let companyY = headerTop + 18;
  doc.fillColor(INVOICE_COLORS.brand).font('Helvetica-Bold').fontSize(18).text(cleanText(data.company.name) || 'Fulltech SRL', companyX, companyY, {
    width: leftWidth - 36,
  });
  companyY = doc.y + 8;

  const companyLines = [
    hasText(data.company.rnc) ? `RNC: ${cleanText(data.company.rnc)}` : '',
    hasText(data.company.phone) ? `Tel: ${cleanText(data.company.phone)}` : '',
    cleanText(data.company.address),
  ].filter(Boolean);

  for (const line of companyLines) {
    doc.fillColor(INVOICE_COLORS.muted).font('Helvetica').fontSize(10).text(line, companyX, companyY, {
      width: leftWidth - 36,
    });
    companyY = doc.y + 5;
  }

  const metaX = rightX + 18;
  let metaY = headerTop + 18;
  doc.fillColor(INVOICE_COLORS.white).font('Helvetica-Bold').fontSize(22).text('FACTURA', metaX, metaY, {
    width: rightWidth - 36,
    align: 'right',
  });
  metaY = doc.y + 12;

  const metaLines = [
    ['Numero', cleanText(data.invoice.number)],
    ['Fecha', fmtDate(data.invoice.dateIso)],
    ['Documento', cleanText(documentType) || 'Servicio'],
  ].filter(([, value]) => hasText(value));

  for (const [label, value] of metaLines) {
    doc.fillColor('#BFD3E5').font('Helvetica-Bold').fontSize(8.5).text(label.toUpperCase(), metaX, metaY, {
      width: rightWidth - 36,
      align: 'right',
      lineBreak: false,
    });
    metaY += 11;
    doc.fillColor(INVOICE_COLORS.white).font('Helvetica').fontSize(10.5).text(value, metaX, metaY, {
      width: rightWidth - 36,
      align: 'right',
    });
    metaY = doc.y + 8;
  }

  const dividerY = headerTop + cardHeight + 18;
  doc.save();
  doc.moveTo(left, dividerY).lineTo(left + contentWidth, dividerY).lineWidth(1).strokeColor(INVOICE_COLORS.line).stroke();
  doc.restore();

  doc.y = dividerY + 16;
}

function drawItemsTable(doc: PdfDoc, rows: InvoiceRow[]) {
  const { left, contentWidth } = pageMetrics(doc);
  const tableTop = doc.y;
  const rowHeightBase = 24;
  const colPositions = {
    index: left,
    description: left + 34,
    qty: left + 318,
    price: left + 390,
    total: left + 474,
  };
  const colWidths = {
    index: 26,
    description: 274,
    qty: 50,
    price: 70,
    total: 78,
  };

  ensureSpace(doc, 90);
  drawSectionTitle(doc, 'Detalle', left, tableTop, contentWidth);

  const headerY = doc.y + 10;
  drawRoundedCard(doc, left, headerY, contentWidth, 28, {
    fillColor: INVOICE_COLORS.brand,
    strokeColor: INVOICE_COLORS.brand,
    radius: 10,
  });

  doc.fillColor(INVOICE_COLORS.white).font('Helvetica-Bold').fontSize(9.5);
  doc.text('#', colPositions.index + 8, headerY + 9, { width: colWidths.index, align: 'center', lineBreak: false });
  doc.text('Descripcion', colPositions.description + 8, headerY + 9, { width: colWidths.description - 16, lineBreak: false });
  doc.text('Cantidad', colPositions.qty, headerY + 9, { width: colWidths.qty, align: 'right', lineBreak: false });
  doc.text('Precio', colPositions.price, headerY + 9, { width: colWidths.price, align: 'right', lineBreak: false });
  doc.text('Total', colPositions.total, headerY + 9, { width: colWidths.total, align: 'right', lineBreak: false });

  let rowY = headerY + 36;
  rows.forEach((row, rowIndex) => {
    const descHeight = doc.heightOfString(row.description, {
      width: colWidths.description - 16,
      align: 'left',
    });
    const rowHeight = Math.max(rowHeightBase, descHeight + 14);
    ensureSpace(doc, rowHeight + 12);

    drawRoundedCard(doc, left, rowY, contentWidth, rowHeight, {
      fillColor: rowIndex % 2 === 0 ? INVOICE_COLORS.white : '#FDFEFF',
      strokeColor: INVOICE_COLORS.line,
      radius: 8,
      lineWidth: 0.8,
    });

    doc.fillColor(INVOICE_COLORS.text).font('Helvetica').fontSize(9.5);
    doc.text(String(row.index), colPositions.index + 8, rowY + 8, { width: colWidths.index, align: 'center' });
    doc.text(row.description, colPositions.description + 8, rowY + 8, { width: colWidths.description - 16 });
    doc.text(row.qtyText, colPositions.qty, rowY + 8, { width: colWidths.qty, align: 'right' });
    doc.text(fmtMoney(row.unitPrice), colPositions.price, rowY + 8, { width: colWidths.price, align: 'right' });
    doc.text(fmtMoney(row.total), colPositions.total, rowY + 8, { width: colWidths.total, align: 'right' });

    rowY += rowHeight + 8;
  });

  doc.y = rowY;
}

function drawTotalsCard(doc: PdfDoc, data: InvoiceDraftData) {
  const { left, contentWidth } = pageMetrics(doc);
  const subtotal = moneyOrZero(data.totals.total);
  const totalsWidth = 220;
  const x = left + contentWidth - totalsWidth;
  const y = doc.y + 6;
  const lines = [
    { label: 'Subtotal', value: fmtMoney(subtotal), highlight: false },
    { label: 'Total', value: fmtMoney(moneyOrZero(data.totals.total)), highlight: true },
  ];

  drawRoundedCard(doc, x, y, totalsWidth, 96, {
    fillColor: INVOICE_COLORS.card,
    strokeColor: INVOICE_COLORS.border,
  });

  doc.fillColor(INVOICE_COLORS.brand).font('Helvetica-Bold').fontSize(10).text('RESUMEN', x + 16, y + 14, {
    width: totalsWidth - 32,
    align: 'left',
    lineBreak: false,
  });

  let cursorY = y + 38;
  for (const line of lines) {
    doc.fillColor(line.highlight ? INVOICE_COLORS.brandDark : INVOICE_COLORS.muted).font(line.highlight ? 'Helvetica-Bold' : 'Helvetica').fontSize(line.highlight ? 12.5 : 10).text(line.label, x + 16, cursorY, {
      width: 90,
      lineBreak: false,
    });
    doc.text(line.value, x + 100, cursorY, {
      width: totalsWidth - 116,
      align: 'right',
      lineBreak: false,
    });
    cursorY += line.highlight ? 26 : 18;
    if (!line.highlight) {
      doc.save();
      doc.moveTo(x + 16, cursorY - 6).lineTo(x + totalsWidth - 16, cursorY - 6).lineWidth(0.7).strokeColor(INVOICE_COLORS.line).stroke();
      doc.restore();
    }
  }

  doc.y = y + 108;
}

function drawNotes(doc: PdfDoc, notes?: string | null) {
  if (!hasText(notes)) return;
  const { left, contentWidth } = pageMetrics(doc);
  ensureSpace(doc, 90);
  drawSectionTitle(doc, 'Observaciones', left, doc.y, contentWidth);
  const cardY = doc.y + 10;
  const text = cleanText(notes);
  const height = Math.max(74, doc.heightOfString(text, { width: contentWidth - 32, align: 'left' }) + 28);
  drawRoundedCard(doc, left, cardY, contentWidth, height, {
    fillColor: INVOICE_COLORS.white,
    strokeColor: INVOICE_COLORS.border,
  });
  doc.fillColor(INVOICE_COLORS.text).font('Helvetica').fontSize(10).text(text, left + 16, cardY + 14, {
    width: contentWidth - 32,
    align: 'left',
  });
  doc.y = cardY + height + 8;
}

type ApprovalCarrier = {
  approvalRecord?: {
    approvedByName?: string | null;
    approvedAtIso?: string | null;
  } | null;
};

type SignatureCarrier = ApprovalCarrier & {
  signature?: {
    pngBytes: Buffer;
    signedAtIso?: string | null;
  } | null;
  client?: { name: string };
  clientName?: string;
};

function drawApproval(doc: PdfDoc, data: ApprovalCarrier) {
  const approvalBits = [
    hasText(data.approvalRecord?.approvedByName) ? `Aprobado por ${cleanText(data.approvalRecord?.approvedByName)}` : '',
    hasText(data.approvalRecord?.approvedAtIso) ? fmtDate(data.approvalRecord?.approvedAtIso) : '',
  ].filter(Boolean);
  if (!approvalBits.length) return;
  doc.fillColor(INVOICE_COLORS.muted).font('Helvetica').fontSize(8.5).text(approvalBits.join(' · '), {
    align: 'left',
  });
  doc.moveDown(0.5);
}

function drawSignature(doc: PdfDoc, data: SignatureCarrier) {
  if (!data.signature?.pngBytes) return;
  const { left, contentWidth } = pageMetrics(doc);
  const signerName = cleanText(data.client?.name) || cleanText(data.clientName) || 'Cliente';
  ensureSpace(doc, 150);
  drawSectionTitle(doc, 'Aceptacion del cliente', left, doc.y, contentWidth);
  const cardY = doc.y + 10;
  drawRoundedCard(doc, left, cardY, contentWidth, 122, {
    fillColor: INVOICE_COLORS.white,
    strokeColor: INVOICE_COLORS.border,
  });

  doc.fillColor(INVOICE_COLORS.text).font('Helvetica-Bold').fontSize(10).text(signerName, left + 16, cardY + 14, {
    width: 220,
  });
  if (hasText(data.signature.signedAtIso)) {
    doc.fillColor(INVOICE_COLORS.muted).font('Helvetica').fontSize(8.5).text(`Firmado el ${fmtDate(data.signature.signedAtIso)}`, left + 16, cardY + 30, {
      width: 220,
    });
  }

  doc.save();
  doc.roundedRect(left + 16, cardY + 48, 250, 52, 8).lineWidth(0.8).strokeColor(INVOICE_COLORS.line).stroke();
  doc.restore();
  doc.image(data.signature.pngBytes, left + 24, cardY + 54, { fit: [234, 38], valign: 'center' });
  doc.save();
  doc.moveTo(left + 16, cardY + 106).lineTo(left + 266, cardY + 106).lineWidth(0.8).strokeColor(INVOICE_COLORS.muted).stroke();
  doc.restore();
  doc.fillColor(INVOICE_COLORS.muted).font('Helvetica').fontSize(8.5).text('Firma del cliente', left + 16, cardY + 109, {
    width: 250,
    align: 'center',
  });

  doc.y = cardY + 134;
}

function drawWarrantyHeader(doc: PdfDoc, data: WarrantyDraftData) {
  const { left, contentWidth, top } = pageMetrics(doc);
  const headerY = top;
  const companyWidth = contentWidth - 196;
  drawRoundedCard(doc, left, headerY, companyWidth, 112, {
    fillColor: INVOICE_COLORS.white,
    strokeColor: INVOICE_COLORS.border,
    radius: 16,
  });
  drawRoundedCard(doc, left + companyWidth + 16, headerY, 180, 112, {
    fillColor: INVOICE_COLORS.brandDark,
    strokeColor: INVOICE_COLORS.brandDark,
    radius: 16,
  });

  doc.fillColor(INVOICE_COLORS.brand).font('Helvetica-Bold').fontSize(20).text(cleanText(data.company.name) || 'FULLTECH', left + 18, headerY + 18, {
    width: companyWidth - 36,
  });
  doc.fillColor(INVOICE_COLORS.muted).font('Helvetica').fontSize(9.2);
  let metaY = headerY + 48;
  for (const line of [
    hasText(data.company.rnc) ? `RNC: ${cleanText(data.company.rnc)}` : '',
    hasText(data.company.phone) ? `Tel: ${cleanText(data.company.phone)}` : '',
    cleanText(data.company.address),
  ].filter(Boolean)) {
    doc.text(line, left + 18, metaY, { width: companyWidth - 36 });
    metaY += 14;
  }

  doc.fillColor(INVOICE_COLORS.white).font('Helvetica-Bold').fontSize(18).text('GARANTIA', left + companyWidth + 32, headerY + 18, {
    width: 116,
    align: 'right',
  });
  doc.font('Helvetica').fontSize(9.2);
  doc.text(`Certificado: ${cleanText(data.certificate.number)}`, left + companyWidth + 24, headerY + 52, {
    width: 132,
    align: 'right',
  });
  doc.text(`Fecha: ${fmtDate(data.certificate.dateIso)}`, left + companyWidth + 24, headerY + 68, {
    width: 132,
    align: 'right',
  });
  doc.text('Carta de cobertura y condiciones', left + companyWidth + 24, headerY + 86, {
    width: 132,
    align: 'right',
  });

  doc.y = headerY + 128;
}

function drawWarrantyTextCard(doc: PdfDoc, title: string, text: string, options?: { fillColor?: string; minHeight?: number }) {
  if (!hasText(text)) return;
  const { left, contentWidth } = pageMetrics(doc);
  ensureSpace(doc, 110);
  drawSectionTitle(doc, title, left, doc.y, contentWidth);
  const cardY = doc.y + 10;
  const height = Math.max(options?.minHeight ?? 78, doc.heightOfString(text, { width: contentWidth - 32, align: 'left' }) + 28);
  drawRoundedCard(doc, left, cardY, contentWidth, height, {
    fillColor: options?.fillColor ?? INVOICE_COLORS.white,
    strokeColor: INVOICE_COLORS.border,
  });
  doc.fillColor(INVOICE_COLORS.text).font('Helvetica').fontSize(10).text(text, left + 16, cardY + 14, {
    width: contentWidth - 32,
    align: 'left',
  });
  doc.y = cardY + height + 10;
}

function drawFooter(doc: PdfDoc) {
  const { left, bottom, contentWidth } = pageMetrics(doc);
  const footerY = bottom - 36;
  doc.save();
  doc.moveTo(left, footerY).lineTo(left + contentWidth, footerY).lineWidth(0.8).strokeColor(INVOICE_COLORS.line).stroke();
  doc.restore();
  doc.fillColor(INVOICE_COLORS.muted).font('Helvetica-Bold').fontSize(9).text('Gracias por su preferencia', left, footerY + 10, {
    width: contentWidth,
    align: 'center',
  });
  doc.font('Helvetica').fontSize(8.5).text('Documento emitido por Fulltech SRL para uso comercial y atencion al cliente.', left, footerY + 22, {
    width: contentWidth,
    align: 'center',
  });
}

export async function buildInvoicePdf(data: InvoiceDraftData): Promise<Buffer> {
  return bufferFromPdf((doc) => {
    const rows = collectInvoiceRows(data);
    const clientFields: InfoField[] = [
      { label: 'Nombre', value: cleanText(data.client.name) || 'Cliente' },
      { label: 'Telefono', value: cleanText(data.client.phone) },
      { label: 'Direccion', value: cleanText(data.client.address) },
    ];
    const serviceFields: InfoField[] = [
      { label: 'Tipo', value: cleanText(data.service.typeLabel) || 'Servicio' },
      { label: 'Servicio', value: cleanText(data.service.title) },
      { label: 'Tecnico', value: cleanText(data.service.technicianName) },
      { label: 'Fecha servicio', value: fmtDate(data.service.serviceDateIso) },
    ];

    drawHeader(doc, data, cleanText(data.service.typeLabel) || 'Servicio');

    const { left, contentWidth } = pageMetrics(doc);
    const cardGap = 16;
    const cardWidth = (contentWidth - cardGap) / 2;
    const infoTop = doc.y;
    const clientHeight = drawInfoCard(doc, 'Cliente', clientFields, left, infoTop, cardWidth);
    const serviceHeight = drawInfoCard(doc, 'Servicio', serviceFields, left + cardWidth + cardGap, infoTop, cardWidth);
    doc.y = infoTop + Math.max(clientHeight, serviceHeight) + 18;

    drawItemsTable(doc, rows);
    drawTotalsCard(doc, data);
    drawNotes(doc, data.notes);
    drawApproval(doc, data);
    drawSignature(doc, data);
    drawFooter(doc);
  });
}

export async function buildWarrantyPdf(data: WarrantyDraftData): Promise<Buffer> {
  return bufferFromPdf((doc) => {
    const durationText = fmtWarrantyDuration(data.warrantyDurationValue, data.warrantyDurationUnit);
    const clientFields: InfoField[] = [
      { label: 'Cliente', value: cleanText(data.clientName) || 'Cliente' },
      { label: 'Servicio', value: cleanText(data.serviceTypeLabel) || 'Servicio' },
      { label: 'Cobertura', value: cleanText(data.scopeLabel) },
      { label: 'Fecha servicio', value: fmtDate(data.serviceDateIso) },
    ];
    const warrantyFields: InfoField[] = [
      { label: 'Duracion', value: durationText || (data.hasWarranty === false ? 'Sin garantia comercial adicional' : '') },
      { label: 'Tecnico', value: cleanText(data.technicianName) },
      { label: 'Fecha instalacion', value: fmtDate(data.installationDateIso) },
      { label: 'Referencia', value: cleanText(data.serviceLabel) },
    ];
    const summaryText = cleanText(data.warrantySummary) || (
      data.hasWarranty === false
        ? 'El trabajo realizado queda documentado sin garantia comercial adicional. La cobertura solo aplica a observaciones reportadas al momento de la entrega.'
        : `FULLTECH deja constancia de la garantia aplicable${hasText(data.scopeLabel) ? ` para ${cleanText(data.scopeLabel)}` : ''} segun la configuracion vigente y la fecha de ejecucion del servicio.`
    );
    const coverageText = cleanText(data.coverageSummary) || 'Incluye revision tecnica del componente o servicio reportado, verificacion del defecto reclamado y ejecucion de la correccion cuando la falla este dentro del alcance aprobado.';
    const exclusionsText = cleanText(data.exclusionsSummary) || 'No cubre danos por manipulacion externa, golpes, humedad, descargas electricas, variaciones de voltaje, uso indebido, modificaciones de terceros ni condiciones fuera de especificacion.';
    const notesText = [cleanText(data.equipmentInstalledText), cleanText(data.notes)].filter(Boolean).join('\n\n');

    drawWarrantyHeader(doc, data);

    const { left, contentWidth } = pageMetrics(doc);
    const gap = 16;
    const cardWidth = (contentWidth - gap) / 2;
    const infoTop = doc.y;
    const clientHeight = drawInfoCard(doc, 'Cliente y servicio', clientFields, left, infoTop, cardWidth);
    const warrantyHeight = drawInfoCard(doc, 'Cobertura', warrantyFields, left + cardWidth + gap, infoTop, cardWidth);
    doc.y = infoTop + Math.max(clientHeight, warrantyHeight) + 18;

    drawWarrantyTextCard(doc, 'Resumen ejecutivo', summaryText, { fillColor: INVOICE_COLORS.card, minHeight: 84 });
    drawWarrantyTextCard(doc, 'Cobertura incluida', coverageText);
    drawWarrantyTextCard(doc, 'Exclusiones y limites', exclusionsText);
    drawWarrantyTextCard(doc, 'Notas del servicio', notesText, { minHeight: 72 });
    drawApproval(doc, data);
    drawSignature(doc, data);
    drawFooter(doc);
  });
}
