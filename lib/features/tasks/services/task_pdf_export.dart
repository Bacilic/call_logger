/// Γράφει το φύλλο μιας εκκρεμότητας σε PDF.
///
/// Μία σελίδα Α4 που ξεκινά με τη δουλειά και τελειώνει με κενές γραμμές για
/// σημειώσεις επί τόπου. Η διάταξη είναι φτιαγμένη για **το χέρι του τεχνικού**,
/// όχι για αρχείο: το τηλέφωνο τυπώνεται μεγάλο, και ό,τι δεν υπάρχει απλώς
/// λείπει αντί να αφήνει ετικέτα με παύλα.
///
/// **Η γραμματοσειρά περνά ως δεδομένα, όχι ως όνομα.** Οι ενσωματωμένες
/// γραμματοσειρές του PDF δεν έχουν ελληνικούς χαρακτήρες: χωρίς αρχείο
/// γραμματοσειράς κάθε ελληνική λέξη θα γινόταν κουτάκια.
library;

import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'task_print_document.dart';

/// Τα bytes ενός `.pdf` με το περιεχόμενο του [document].
///
/// Το [fontData] είναι ένα TrueType αρχείο με ελληνική κάλυψη.
Future<Uint8List> buildTaskPdf(
  TaskPrintDocument document, {
  required Uint8List fontData,
}) async {
  final font = pw.Font.ttf(fontData.buffer.asByteData());
  final theme = pw.ThemeData.withFont(base: font, bold: font, italic: font);

  final pdf = pw.Document(title: document.heading);

  pdf.addPage(
    // MultiPage και όχι Page: το ιστορικό αναβολών δεν έχει άνω όριο, και μια
    // εκκρεμότητα που μετακινήθηκε δεκαπέντε φορές δεν επιτρέπεται να κοπεί
    // σιωπηλά στο κάτω περιθώριο.
    pw.MultiPage(
      theme: theme,
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(40, 38, 40, 40),
      footer: (context) => context.pagesCount == 1
          ? pw.SizedBox()
          : pw.Container(
              alignment: pw.Alignment.centerRight,
              margin: const pw.EdgeInsets.only(top: 10),
              child: pw.Text(
                'Σελίδα ${context.pageNumber} από ${context.pagesCount}',
                style: const pw.TextStyle(
                  fontSize: 9,
                  color: PdfColors.grey600,
                ),
              ),
            ),
      build: (context) => [
        _header(document),
        pw.SizedBox(height: 14),
        pw.Text(
          document.title,
          style: pw.TextStyle(fontSize: 17, fontWeight: pw.FontWeight.bold),
        ),
        if (document.dueLabel.isNotEmpty) ...[
          pw.SizedBox(height: 3),
          pw.Text(
            document.dueLabel,
            style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey700),
          ),
        ],
        if (document.description.isNotEmpty) ...[
          pw.SizedBox(height: 14),
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.all(10),
            decoration: const pw.BoxDecoration(color: PdfColors.grey100),
            child: pw.Text(
              document.description,
              style: const pw.TextStyle(fontSize: 11, lineSpacing: 3),
            ),
          ),
        ],
        if (document.fields.isNotEmpty) ...[
          pw.SizedBox(height: 14),
          ...document.fields.map(_field),
        ],
        if (document.linkLine != null) ...[
          pw.SizedBox(height: 8),
          pw.Text(
            document.linkLine!,
            style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
          ),
        ],
        if (document.hasSnoozes) ..._snoozeSection(document),
        if (document.hasClosure) ..._closureSection(document),
        ..._notesSection(),
      ],
    ),
  );

  return pdf.save();
}

pw.Widget _header(TaskPrintDocument document) {
  return pw.Container(
    padding: const pw.EdgeInsets.only(bottom: 6),
    decoration: const pw.BoxDecoration(
      border: pw.Border(bottom: pw.BorderSide(width: 1.4)),
    ),
    child: pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      crossAxisAlignment: pw.CrossAxisAlignment.end,
      children: [
        pw.Text(
          document.heading,
          style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
        ),
        pw.Text(
          document.createdAtLabel,
          style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
        ),
      ],
    ),
  );
}

pw.Widget _field(TaskPrintField field) {
  return pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 4),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.SizedBox(
          width: 90,
          child: pw.Text(
            field.label,
            style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey700),
          ),
        ),
        pw.Expanded(
          child: pw.Text(
            field.value,
            style: pw.TextStyle(
              fontSize: field.emphasized ? 15 : 11,
              fontWeight: field.emphasized
                  ? pw.FontWeight.bold
                  : pw.FontWeight.normal,
            ),
          ),
        ),
      ],
    ),
  );
}

List<pw.Widget> _snoozeSection(TaskPrintDocument document) {
  return [
    pw.SizedBox(height: 16),
    _sectionTitle('ΑΝΑΒΟΛΕΣ (${document.snoozes.length})'),
    pw.SizedBox(height: 5),
    for (final snooze in document.snoozes)
      pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 3),
        child: pw.Text(
          [
            '${snooze.order}. ${snooze.movedAt}',
            if (snooze.newDueAt != null) '→ ${snooze.newDueAt}',
            if (snooze.note != null) '· ${snooze.note}',
          ].join(' '),
          style: const pw.TextStyle(fontSize: 10, lineSpacing: 2),
        ),
      ),
  ];
}

List<pw.Widget> _closureSection(TaskPrintDocument document) {
  return [
    pw.SizedBox(height: 16),
    _sectionTitle('ΠΡΟΗΓΟΥΜΕΝΗ ΟΛΟΚΛΗΡΩΣΗ'),
    pw.SizedBox(height: 5),
    if (document.completionLine != null)
      pw.Text(
        document.completionLine!,
        style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
      ),
    if (document.sinceLastSnoozeLine != null)
      pw.Text(
        document.sinceLastSnoozeLine!,
        style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
      ),
    if (document.previousSolution != null) ...[
      pw.SizedBox(height: 4),
      pw.Text(
        document.previousSolution!,
        style: const pw.TextStyle(fontSize: 11, lineSpacing: 3),
      ),
    ],
  ];
}

/// Οι κενές γραμμές είναι μέρος του εγγράφου, όχι διακόσμηση: εκεί γράφει ο
/// τεχνικός τι βρήκε, πριν γυρίσει στον υπολογιστή.
List<pw.Widget> _notesSection() {
  return [
    pw.SizedBox(height: 18),
    _sectionTitle('ΣΗΜΕΙΩΣΕΙΣ'),
    pw.SizedBox(height: 10),
    for (var i = 0; i < 5; i++)
      pw.Container(
        height: 22,
        decoration: const pw.BoxDecoration(
          border: pw.Border(
            bottom: pw.BorderSide(width: 0.5, color: PdfColors.grey400),
          ),
        ),
      ),
  ];
}

pw.Widget _sectionTitle(String text) => pw.Text(
  text,
  style: pw.TextStyle(
    fontSize: 9,
    fontWeight: pw.FontWeight.bold,
    color: PdfColors.grey700,
    letterSpacing: 0.4,
  ),
);
