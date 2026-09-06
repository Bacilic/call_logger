/// Γράφει την εξαγωγή των Στατιστικών σε αρχείο PDF.
///
/// Σελίδα Α4 με την ταυτότητα της εξαγωγής στην κορυφή και τους πίνακες από
/// κάτω, όπως τους δίνει το [DashboardExportDocument]. Χωρίς διαγράμματα: ένα
/// διάγραμμα σε χαρτί χωρίς υποδείξεις χάνει τα μισά του, ενώ οι πίνακες
/// κρατούν κάθε νούμερο.
///
/// **Η γραμματοσειρά περνά ως δεδομένα, όχι ως όνομα.** Οι ενσωματωμένες
/// γραμματοσειρές του PDF δεν έχουν ελληνικούς χαρακτήρες: χωρίς αρχείο
/// γραμματοσειράς κάθε ελληνική λέξη θα γινόταν κουτάκια.
library;

import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'dashboard_export_document.dart';

/// Τα bytes ενός `.pdf` με το περιεχόμενο του [document].
///
/// Το [fontData] είναι ένα TrueType αρχείο με ελληνική κάλυψη.
Future<Uint8List> buildDashboardPdf(
  DashboardExportDocument document, {
  required Uint8List fontData,
}) async {
  final font = pw.Font.ttf(fontData.buffer.asByteData());
  final theme = pw.ThemeData.withFont(base: font, bold: font, italic: font);

  final pdf = pw.Document(title: document.title);

  pdf.addPage(
    pw.MultiPage(
      theme: theme,
      pageFormat: PdfPageFormat.a4,
      // Το προεπιλεγμένο όριο των 20 σελίδων πετάει εξαίρεση αντί να κόψει, και
      // μια πλήρης χρονιά κλήσεων το ξεπερνά άνετα.
      maxPages: 500,
      margin: const pw.EdgeInsets.fromLTRB(32, 32, 32, 40),
      header: (context) => context.pageNumber == 1
          ? pw.SizedBox()
          : pw.Container(
              alignment: pw.Alignment.centerRight,
              margin: const pw.EdgeInsets.only(bottom: 12),
              child: pw.Text(
                document.title,
                style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
              ),
            ),
      footer: (context) => pw.Container(
        alignment: pw.Alignment.centerRight,
        margin: const pw.EdgeInsets.only(top: 10),
        child: pw.Text(
          'Σελίδα ${context.pageNumber} από ${context.pagesCount}',
          style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
        ),
      ),
      // **Επίπεδη λίστα, όχι φωλιασμένες στήλες.** Ένα `Column` του πακέτου δεν
      // σπάει σε σελίδες: όταν ο πίνακας «Ανά ημέρα» ξεπερνούσε τη μία σελίδα,
      // το έγγραφο δεν μπορούσε να τον τοποθετήσει πουθενά και γεννούσε κενές
      // σελίδες μέχρι να σκάσει. Δίνοντας τον πίνακα κατευθείαν στο έγγραφο, το
      // ίδιο τον μοιράζει σε όσες σελίδες χρειάζεται.
      build: (context) => [
        _documentHeader(document),
        pw.SizedBox(height: 18),
        for (final table in document.tables) ..._tableBlock(table),
      ],
    ),
  );

  return pdf.save();
}

pw.Widget _documentHeader(DashboardExportDocument document) {
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text(
        document.title,
        style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
      ),
      pw.SizedBox(height: 4),
      pw.Text(
        document.rangeLabel,
        style: const pw.TextStyle(fontSize: 12, color: PdfColors.grey800),
      ),
      pw.SizedBox(height: 10),
      pw.Container(
        padding: const pw.EdgeInsets.all(8),
        decoration: const pw.BoxDecoration(color: PdfColors.grey100),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              'Ενεργά φίλτρα: ${document.activeFilterLabels.join(' · ')}',
              style: const pw.TextStyle(fontSize: 10),
            ),
            pw.SizedBox(height: 3),
            pw.Text(
              'Δημιουργήθηκε: ${document.generatedAtLabel}',
              style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
            ),
          ],
        ),
      ),
    ],
  );
}

/// Ο τίτλος και ο πίνακας ως **χωριστά** στοιχεία του εγγράφου.
///
/// Ο τίτλος μένει κολλημένος στον πίνακά του με `pw.Header`, που ξέρει να μη
/// μείνει μόνος του στο τέλος μιας σελίδας.
List<pw.Widget> _tableBlock(DashboardExportTable table) {
  return [
    pw.Header(
      level: 1,
      text: table.title,
      textStyle: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
    ),
    if (table.isEmpty)
      pw.Text(
        'Δεν υπάρχουν δεδομένα.',
        style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
      )
    else
      pw.TableHelper.fromTextArray(
        headers: table.columns,
        data: table.rows,
        cellStyle: const pw.TextStyle(fontSize: 9),
        headerStyle: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
        headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
        cellHeight: 16,
        headerAlignment: pw.Alignment.centerLeft,
        cellAlignment: pw.Alignment.centerLeft,
        border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
      ),
    pw.SizedBox(height: 16),
  ];
}
