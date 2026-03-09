// Εφάπαξ script: αντιγράφει το τμήμα "γράμμα+αριθμός" από το department στο location.
// Π.χ. "Ψυκτικοί Β0" → department: "Ψυκτικοί", location: "Β0"
//      "Γραφείο Λοιμώξεων ΙΙΙ1" → department: "Γραφείο Λοιμώξεων", location: "ΙΙΙ1"
// Όπου δεν υπάρχει τέτοιο τμήμα, το location μένει κενό.
//
// Κλείστε την εφαρμογή πριν τρέξετε το script (η βάση δεν πρέπει να είναι ανοιχτή).
//
// Χρήση (από ρίζα project):
//   dart run tool/split_department_to_location_once.dart
//   dart run tool/split_department_to_location_once.dart "C:\path\to\call_logger.db"
// ignore_for_file: avoid_print

import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Τελευταίο «token» που ταιριάζει: γράμματα (ελληνικά/λατινικά/ρωμαϊκά) + προαιρετικά ψηφία.
/// Π.χ. Β0, Β4, ΙΙΙ1, ΒΟο.
final RegExp _trailingLocationRegex = RegExp(
  r'\s+([\p{L}]+\d*)\s*$',
  unicode: true,
);

void main(List<String> args) async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  final dbPath = args.isNotEmpty
      ? args.first.trim()
      : path.join(Directory.current.path, 'Data Base', 'call_logger.db');

  final file = File(dbPath);
  if (!await file.exists()) {
    print('ΣΦΑΛΜΑ: Δεν βρέθηκε αρχείο βάσης: $dbPath');
    exit(1);
  }

  final db = await openDatabase(dbPath);

  try {
    final rows = await db.rawQuery('SELECT id, department FROM users');
    if (rows.isEmpty) {
      print('Ο πίνακας users είναι κενός. Τίποτα να γίνει.');
      await db.close();
      exit(0);
    }

    int updated = 0;
    for (final row in rows) {
      final id = row['id'] as int?;
      final dept = (row['department'] as String?)?.trim() ?? '';
      if (id == null || dept.isEmpty) continue;

      final match = _trailingLocationRegex.firstMatch(dept);
      if (match == null) {
        await db.rawUpdate(
          'UPDATE users SET department = ?, location = ? WHERE id = ?',
          [dept, '', id],
        );
        continue;
      }

      final location = match.group(1) ?? '';
      final departmentRest = dept.substring(0, match.start).trim();
      await db.rawUpdate(
        'UPDATE users SET department = ?, location = ? WHERE id = ?',
        [departmentRest, location, id],
      );
      updated++;
    }

    print('ΟΚ: Ενημερώθηκαν department/location σε ${rows.length} εγγραφές ($updated με τοποθεσία).');
  } catch (e, st) {
    print('ΣΦΑΛΜΑ: $e');
    print(st);
    exit(1);
  } finally {
    await db.close();
  }
}
