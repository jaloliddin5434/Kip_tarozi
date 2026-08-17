import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../i18n/strings.dart';
import '../models/dashboard.dart';
import '../models/statistika.dart';

/// Statistika ekranida tanlangan filtrlarga (davr + mahsulot + smena/jami)
/// mos hisobotni PDF sifatida yasaydi — [Printing.layoutPdf] orqali OS chop
/// etish/saqlash oynasiga uzatiladi.
pw.Document statistikaHujjatiQur({
  required DavrJamlanmasi jamlanma,
  required String mahsulotNomi,
  required String? smena,
  required List<SmenaJamlanmasi> smenalar,
  required int soni,
  required double jamiKg,
  required double ortachaOgirlik,
  required Lokalizatsiya lok,
}) {
  final doc = pw.Document();

  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      build: (context) {
        return pw.Padding(
          padding: const pw.EdgeInsets.all(32),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('Kip Tarozi', style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 4),
              pw.Text(lok.t('statistika_hujjati'), style: const pw.TextStyle(fontSize: 13, color: PdfColors.grey700)),
              pw.Divider(height: 24),
              _qator(lok.t('davr'), '${jamlanma.boshlanishSanasi} — ${jamlanma.tugashSanasi}'),
              _qator(lok.t('mahsulot'), mahsulotNomi),
              _qator(lok.t('smena'), smena ?? lok.t('jami')),
              pw.SizedBox(height: 16),
              _qator(lok.t('jami'), '$soni ${lok.t("soni")}'),
              _qator('${lok.t("jami")} kg', '${jamiKg.toStringAsFixed(1)} kg'),
              _qator(lok.t('ortacha_ogirlik'), '${ortachaOgirlik.toStringAsFixed(1)} kg'),
              if (smenalar.isNotEmpty) ...[
                pw.SizedBox(height: 20),
                pw.Text(lok.t('smenalar_taqqoslash'), style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 8),
                pw.Table(
                  border: pw.TableBorder.all(color: PdfColors.grey400),
                  children: [
                    pw.TableRow(
                      decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                      children: [
                        _katak(lok.t('smena'), bold: true),
                        _katak(lok.t('soni'), bold: true),
                        _katak('kg', bold: true),
                      ],
                    ),
                    for (final s in smenalar)
                      pw.TableRow(
                        children: [_katak(s.smena), _katak('${s.soni}'), _katak(s.jamiKg.toStringAsFixed(1))],
                      ),
                  ],
                ),
              ],
              pw.SizedBox(height: 24),
              pw.Text(
                DateTime.now().toString().substring(0, 16),
                style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey500),
              ),
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
        pw.SizedBox(width: 140, child: pw.Text(belgi, style: const pw.TextStyle(color: PdfColors.grey700))),
        pw.Text(qiymat, style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
      ],
    ),
  );
}

pw.Widget _katak(String matn, {bool bold = false}) {
  return pw.Padding(
    padding: const pw.EdgeInsets.all(6),
    child: pw.Text(matn, style: pw.TextStyle(fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
  );
}
