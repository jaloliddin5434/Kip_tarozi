import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../i18n/strings.dart';
import '../models/hujjat.dart';

/// Bitta kip yozuvi uchun oddiy, bir sahifalik chop etiladigan hujjat —
/// Hujjatlar bo'limidagi "Chop etish" tugmasi shu PDF'ni generatsiya qilib,
/// [Printing.layoutPdf] orqali OS chop etish oynasiga uzatadi.
pw.Document kipHujjatiQur(HujjatKip kip, Lokalizatsiya lok) {
  final doc = pw.Document();

  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a5,
      build: (context) {
        return pw.Padding(
          padding: const pw.EdgeInsets.all(24),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('Kip Tarozi', style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 4),
              pw.Text(lok.t('hujjat'), style: const pw.TextStyle(fontSize: 12, color: PdfColors.grey700)),
              pw.Divider(height: 24),
              _qator(lok.t('mahsulot'), kip.mahsulotNomi),
              _qator(lok.t('partiya'), '#${kip.partiyaRaqami}'),
              _qator(lok.t('kip_qisqa'), '${kip.kipRaqami}'),
              _qator(lok.t('ogirlik'), '${kip.ogirlik.toStringAsFixed(1)} kg'),
              _qator(lok.t('smena'), kip.smena),
              _qator(lok.t('operator'), kip.operatorIsm),
              _qator(lok.t('vaqt'), kip.vaqt.toLocal().toString().substring(0, 16)),
              _qator(lok.t('holati'), kip.holati),
              pw.SizedBox(height: 24),
              pw.Text('ID: ${kip.id}', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey500)),
            ],
          ),
        );
      },
    ),
  );

  return doc;
}

pw.Widget _qator(String belgi, String qiymat) {
  return pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 4),
    child: pw.Row(
      children: [
        pw.SizedBox(width: 130, child: pw.Text(belgi, style: const pw.TextStyle(color: PdfColors.grey700))),
        pw.Text(qiymat, style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
      ],
    ),
  );
}
