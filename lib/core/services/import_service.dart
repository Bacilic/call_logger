import 'dart:io';

import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';

/// Αποτέλεσμα εισαγωγής Excel.
class ImportResult {
  const ImportResult({
    required this.success,
    this.totalCount = 0,
    this.errorMessage,
  });

  final bool success;
  final int totalCount;
  final String? errorMessage;
}

/// Υπηρεσία εισαγωγής δεδομένων από Master Excel (.xlsx) με πολλαπλά φύλλα.
class ImportService {
  /// Επιστρέφει την τιμή κελιού ως String; ασφαλής για Int/Double/Text. Για Double αφαιρεί το .0.
  static String? _getCellValue(Data? cell) {
    final value = cell?.value;
    if (value == null) return null;
    final String result;
    switch (value) {
      case TextCellValue():
        result = value.value.toString();
      case IntCellValue():
        result = value.value.toString();
      case DoubleCellValue():
        final s = value.value.toString();
        result = s.endsWith('.0') ? s.substring(0, s.length - 2) : s;
      default:
        result = value.toString();
    }
    return result;
  }

  /// Επιλογή αρχείου .xlsx και εισαγωγή. Καλεί [onLog] για κάθε γραμμή (ιδιαίτερα owners/equipment).
  Future<ImportResult> importFromExcel({
    required void Function(String) onLog,
  }) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
        allowMultiple: false,
      );
      if (result == null || result.files.isEmpty) {
        return const ImportResult(success: false, errorMessage: 'Δεν επιλέχθηκε αρχείο.');
      }

      final file = result.files.single;
      final bytes = file.bytes ?? (file.path != null ? await File(file.path!).readAsBytes() : null);
      if (bytes == null || bytes.isEmpty) {
        return const ImportResult(success: false, errorMessage: 'Δεν ήταν δυνατή η ανάγνωση του αρχείου.');
      }

      final excel = Excel.decodeBytes(bytes);
      int totalCount = 0;
      const yieldEvery = 15;

      // Φύλλο offices
      final officesTable = excel.tables['offices'];
      if (officesTable != null) {
        onLog('--- Φύλλο: offices ---');
        final rows = officesTable.rows;
        for (var i = 1; i < rows.length; i++) {
          if (i % yieldEvery == 0) await Future.delayed(Duration.zero);
          final row = rows[i];
          if (row.isEmpty) continue;
          final name = _getCellValue(row.isNotEmpty ? row[0] : null) ?? '';
          final dept = _getCellValue(row.length > 1 ? row[1] : null) ?? '';
          final phones = _getCellValue(row.length > 2 ? row[2] : null) ?? '';
          if (name.trim().isEmpty && dept.trim().isEmpty) continue;
          onLog('[$i] $name | $dept | $phones');
          totalCount++;
        }
      }

      // Φύλλο owners – log format: [index] lastName firstName | Κε: code | Τηλ: phone | Γραφείο: officeName
      final ownersTable = excel.tables['owners'];
      if (ownersTable != null) {
        onLog('--- Φύλλο: owners ---');
        final rows = ownersTable.rows;
        for (var i = 1; i < rows.length; i++) {
          if (i % yieldEvery == 0) await Future.delayed(Duration.zero);
          final row = rows[i];
          if (row.isEmpty) continue;
          final lastName = _getCellValue(row.isNotEmpty ? row[0] : null) ?? '';
          final firstName = _getCellValue(row.length > 1 ? row[1] : null) ?? '';
          final officeRef = _getCellValue(row.length > 2 ? row[2] : null) ?? '';
          final phones = _getCellValue(row.length > 3 ? row[3] : null) ?? '';
          final code = _getCellValue(row.length > 4 ? row[4] : null) ?? '';
          final officeName = officeRef;
          if (lastName.trim().isEmpty && firstName.trim().isEmpty) continue;
          onLog('[$i] $lastName $firstName | Κε: $code | Τηλ: $phones | Γραφείο: $officeName');
          totalCount++;
        }
      }

      // Φύλλο equipment – φίλτρο: description περιέχει υπολογιστής / Laptop / Desktop
      final equipmentTable = excel.tables['equipment'];
      if (equipmentTable != null) {
        onLog('--- Φύλλο: equipment ---');
        final rows = equipmentTable.rows;
        var dataRowIndex = 0;
        for (var i = 1; i < rows.length; i++) {
          if (i % yieldEvery == 0) await Future.delayed(Duration.zero);
          final row = rows[i];
          if (row.isEmpty) continue;
          final descriptionRaw = _getCellValue(row.isNotEmpty ? row[0] : null) ?? '';
          final descriptionLower = descriptionRaw.toLowerCase();
          if (!descriptionLower.contains('υπολογιστής') &&
              !descriptionLower.contains('laptop') &&
              !descriptionLower.contains('desktop')) {
            continue;
          }
          dataRowIndex++;
          final code = _getCellValue(row.length > 1 ? row[1] : null) ?? '';
          final ownerRef = _getCellValue(row.length > 2 ? row[2] : null) ?? '';
          onLog('[$dataRowIndex] $descriptionRaw | Κε: $code | Τηλ: - | Γραφείο: $ownerRef');
          totalCount++;
        }
      }

      onLog('ΕΠΙΤΥΧΙΑ: Εισήχθησαν συνολικά $totalCount εγγραφές.');
      return ImportResult(success: true, totalCount: totalCount);
    } catch (e) {
      onLog('ΣΦΑΛΜΑ: $e');
      return ImportResult(success: false, errorMessage: e.toString());
    }
  }
}
