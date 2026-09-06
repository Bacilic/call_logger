/// Γράφει την εξαγωγή των Στατιστικών σε αρχείο Excel.
///
/// Ένα φύλλο ανά πίνακα, και ένα πρώτο φύλλο «Σύνοψη» που κουβαλά και τα φίλτρα
/// της στιγμής: το αρχείο ταξιδεύει μακριά από την οθόνη που το γέννησε, οπότε
/// πρέπει να λέει μόνο του τι δείχνει.
library;

import 'dart:typed_data';

import 'package:justkawal_excel_updated/justkawal_excel_updated.dart';

import 'dashboard_export_document.dart';

/// Το όνομα φύλλου του Excel δεν αντέχει τα πάντα: μέχρι 31 χαρακτήρες, και
/// χωρίς τα σημεία που το ίδιο το Excel κρατά για τις αναφορές του.
String sanitizeExcelSheetName(String title) {
  var name = title;
  for (final forbidden in const [r'\', '/', '*', '?', ':', '[', ']']) {
    name = name.replaceAll(forbidden, ' ');
  }
  name = name.trim();
  if (name.isEmpty) name = 'Φύλλο';
  return name.length <= 31 ? name : name.substring(0, 31);
}

/// Τα bytes ενός `.xlsx` με το περιεχόμενο του [document].
Uint8List buildDashboardExcel(DashboardExportDocument document) {
  final excel = Excel.createExcel();
  final defaultSheetName = excel.getDefaultSheet();

  final headerStyle = CellStyle(bold: true);
  final titleStyle = CellStyle(bold: true, fontSize: 14);

  final usedNames = <String>{};
  for (final table in document.tables) {
    var sheetName = sanitizeExcelSheetName(table.title);
    // Δύο πίνακες με το ίδιο κομμένο όνομα θα έγραφαν ο ένας πάνω στον άλλον.
    var suffix = 2;
    while (!usedNames.add(sheetName)) {
      final tail = ' ($suffix)';
      final head = sanitizeExcelSheetName(table.title);
      sheetName =
          (head.length + tail.length <= 31
              ? head
              : head.substring(0, 31 - tail.length)) +
          tail;
      suffix++;
    }

    final sheet = excel[sheetName];

    if (table == document.tables.first) {
      _writeDocumentHeader(sheet, document, titleStyle, headerStyle);
    }

    sheet.appendRow([
      for (final column in table.columns) TextCellValue(column),
    ]);
    final headerRowIndex = sheet.maxRows - 1;
    for (var column = 0; column < table.columns.length; column++) {
      sheet
          .cell(
            CellIndex.indexByColumnRow(
              columnIndex: column,
              rowIndex: headerRowIndex,
            ),
          )
          .cellStyle = headerStyle;
    }

    if (table.isEmpty) {
      sheet.appendRow([TextCellValue('Δεν υπάρχουν δεδομένα.')]);
      continue;
    }

    for (final row in table.rows) {
      sheet.appendRow([for (final value in row) TextCellValue(value)]);
    }
  }

  // Το κενό φύλλο που δημιουργεί το πακέτο δεν έχει θέση σε παραδοτέο αρχείο.
  if (defaultSheetName != null && !usedNames.contains(defaultSheetName)) {
    excel.delete(defaultSheetName);
  }

  final bytes = excel.encode();
  if (bytes == null) {
    throw StateError('Η δημιουργία του αρχείου Excel δεν επέστρεψε δεδομένα.');
  }
  return Uint8List.fromList(bytes);
}

void _writeDocumentHeader(
  Sheet sheet,
  DashboardExportDocument document,
  CellStyle titleStyle,
  CellStyle headerStyle,
) {
  sheet.appendRow([TextCellValue(document.title)]);
  sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0)).cellStyle =
      titleStyle;

  sheet.appendRow([
    TextCellValue('Διάστημα'),
    TextCellValue(document.rangeLabel),
  ]);
  sheet.appendRow([
    TextCellValue('Δημιουργήθηκε'),
    TextCellValue(document.generatedAtLabel),
  ]);
  sheet.appendRow([
    TextCellValue('Ενεργά φίλτρα'),
    TextCellValue(document.activeFilterLabels.join(' · ')),
  ]);
  sheet.appendRow([]);

  for (var row = 1; row <= 3; row++) {
    sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row))
        .cellStyle = headerStyle;
  }
}
