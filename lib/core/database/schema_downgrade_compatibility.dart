import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'database_file_classifier.dart';
import 'database_v1_schema.dart';

/// Ετυμηγορία για την υποβάθμιση μιας ΝΕΟΤΕΡΗΣ βάσης στην έκδοση της εφαρμογής.
///
/// Η απόφαση δεν βασίζεται σε δηλώσεις ανά μετάπτωση — η εφαρμογή δεν μπορεί να
/// γνωρίζει τι έκαναν μεταπτώσεις που γράφτηκαν ΜΕΤΑ από αυτήν. Βασίζεται σε
/// **γεγονότα**: το πραγματικό σχήμα του αρχείου συγκρίνεται με το σχήμα που
/// περιμένει η εφαρμογή. Αν το αρχείο είναι υπερσύνολο (όλα τα αναμενόμενα
/// υπάρχουν αυτούσια, τα επιπλέον είναι ακίνδυνα), η υποβάθμιση είναι μία μόνο
/// εγγραφή: ο αριθμός έκδοσης γυρίζει πίσω και τίποτα άλλο δεν αγγίζεται.
class SchemaDowngradeAssessment {
  const SchemaDowngradeAssessment({
    required this.fileVersion,
    required this.appVersion,
    required this.blockers,
  });

  /// Η έκδοση σχήματος του αρχείου (η νεότερη).
  final int fileVersion;

  /// Η έκδοση σχήματος της εφαρμογής (ο στόχος της υποβάθμισης).
  final int appVersion;

  /// Τι ακριβώς εμποδίζει την υποβάθμιση — κενή λίστα σημαίνει «εφικτή».
  ///
  /// Κάθε στοιχείο είναι ολοκληρωμένη ελληνική φράση, έτοιμη να διαβαστεί από
  /// τον χρήστη ως ο λόγος που το κουμπί είναι ανενεργό.
  final List<String> blockers;

  bool get isBridgeable => blockers.isEmpty;

  /// Ενιαίο κείμενο αιτιολόγησης για ανενεργά κουμπιά (κενό όταν εφικτή).
  String get blockersSummary => blockers.join(' · ');
}

/// Στήλη όπως τη βλέπει το `PRAGMA table_info`.
class _ColumnShape {
  const _ColumnShape({
    required this.name,
    required this.affinity,
    required this.notNull,
    required this.hasDefault,
    required this.primaryKeyOrdinal,
  });

  final String name;
  final String affinity;
  final bool notNull;
  final bool hasDefault;
  final int primaryKeyOrdinal;
}

class _TableShape {
  const _TableShape({required this.name, required this.columns});

  final String name;
  final Map<String, _ColumnShape> columns;
}

/// Αξιολογεί αν το [dbPath] (έκδοση [fileVersion], νεότερη της εφαρμογής)
/// μπορεί να υποβαθμιστεί ακίνδυνα στην [databaseSchemaVersionV1].
///
/// Διαβάζει το αρχείο ΜΟΝΟ για ανάγνωση και χτίζει το αναμενόμενο σχήμα σε
/// βάση μνήμης — το αρχείο δεν αγγίζεται σε καμία περίπτωση.
Future<SchemaDowngradeAssessment> assessSchemaDowngrade(
  String dbPath, {
  required int fileVersion,
}) async {
  final expected = await _readExpectedAppSchema();
  final blockers = <String>[];

  Database? db;
  try {
    db = await openDatabase(dbPath, readOnly: true, singleInstance: false);
    final actual = await _readSchemaShapes(db);

    for (final table in expected.values) {
      final actualTable = actual[table.name];
      if (actualTable == null) {
        blockers.add(
          'λείπει ο πίνακας «${table.name}» που χρειάζεται αυτή η έκδοση',
        );
        continue;
      }
      blockers.addAll(_compareTable(expected: table, actual: actualTable));
    }

    for (final actualTable in actual.values) {
      if (expected.containsKey(actualTable.name)) continue;
      blockers.addAll(
        await _extraTableBlockers(db, actualTable.name, expected),
      );
    }
  } finally {
    if (db != null && db.isOpen) {
      try {
        await db.close();
      } catch (_) {}
    }
  }

  return SchemaDowngradeAssessment(
    fileVersion: fileVersion,
    appVersion: databaseSchemaVersionV1,
    blockers: List.unmodifiable(blockers),
  );
}

/// Σύγκριση πίνακα: ό,τι περιμένει η εφαρμογή πρέπει να υπάρχει αυτούσιο,
/// και ό,τι περισσεύει να μην εμποδίζει τις δικές της εγγραφές.
List<String> _compareTable({
  required _TableShape expected,
  required _TableShape actual,
}) {
  final blockers = <String>[];

  for (final column in expected.columns.values) {
    final actualColumn = actual.columns[column.name];
    if (actualColumn == null) {
      blockers.add(
        'λείπει η στήλη «${column.name}» του πίνακα «${expected.name}» '
        'που χρειάζεται αυτή η έκδοση',
      );
      continue;
    }
    if (actualColumn.affinity != column.affinity) {
      blockers.add(
        'η στήλη «${column.name}» του πίνακα «${expected.name}» άλλαξε τύπο '
        '(${column.affinity} → ${actualColumn.affinity})',
      );
    }
    if (actualColumn.notNull && !column.notNull) {
      blockers.add(
        'η στήλη «${column.name}» του πίνακα «${expected.name}» έγινε '
        'υποχρεωτική στη νεότερη έκδοση',
      );
    }
    if (actualColumn.primaryKeyOrdinal != column.primaryKeyOrdinal) {
      blockers.add(
        'άλλαξε το πρωτεύον κλειδί του πίνακα «${expected.name}» '
        '(στήλη «${column.name}»)',
      );
    }
  }

  for (final actualColumn in actual.columns.values) {
    if (expected.columns.containsKey(actualColumn.name)) continue;
    // Επιπλέον στήλη: ακίνδυνη ΜΟΝΟ αν οι εγγραφές της εφαρμογής μπορούν να
    // την αγνοήσουν — δηλαδή δέχεται NULL ή έχει προεπιλεγμένη τιμή.
    if (actualColumn.notNull && !actualColumn.hasDefault) {
      blockers.add(
        'η νέα στήλη «${actualColumn.name}» του πίνακα «${expected.name}» '
        'απαιτεί υποχρεωτικά τιμή που αυτή η έκδοση δεν γνωρίζει',
      );
    }
  }

  return blockers;
}

/// Άγνωστος (νεότερος) πίνακας: ακίνδυνος, εκτός αν «δένει» εγγραφές πινάκων
/// της εφαρμογής με κανόνα διαγραφής που θα μπλόκαρε τις δικές της διαγραφές.
Future<List<String>> _extraTableBlockers(
  Database db,
  String extraTable,
  Map<String, _TableShape> expected,
) async {
  final blockers = <String>[];
  try {
    final fks = await db.rawQuery('PRAGMA foreign_key_list($extraTable)');
    for (final fk in fks) {
      final referenced =
          (fk['table'] as String?)?.trim().toLowerCase() ?? '';
      if (!expected.containsKey(referenced)) continue;
      final onDelete =
          (fk['on_delete'] as String?)?.trim().toUpperCase() ?? '';
      const harmless = <String>{'CASCADE', 'SET NULL', 'SET DEFAULT'};
      if (!harmless.contains(onDelete)) {
        blockers.add(
          'ο νέος πίνακας «$extraTable» δεσμεύει εγγραφές του πίνακα '
          '«$referenced» και θα εμπόδιζε διαγραφές',
        );
      }
    }
  } catch (_) {
    // Αν το PRAGMA αποτύχει, δεν μπορούμε να αποδείξουμε ότι είναι ακίνδυνος.
    blockers.add(
      'ο νέος πίνακας «$extraTable» δεν μπόρεσε να ελεγχθεί για ασφάλεια',
    );
  }
  return blockers;
}

/// Το σχήμα που περιμένει η εφαρμογή, χτισμένο σε βάση μνήμης από τον ίδιο
/// κώδικα που δημιουργεί νέες βάσεις — καμία λίστα προς χειροκίνητη συντήρηση.
Future<Map<String, _TableShape>> _readExpectedAppSchema() async {
  final db = await openDatabase(inMemoryDatabasePath);
  try {
    await applyDatabaseV1Schema(db);
    return await _readSchemaShapes(db);
  } finally {
    try {
      await db.close();
    } catch (_) {}
  }
}

Future<Map<String, _TableShape>> _readSchemaShapes(Database db) async {
  final tableRows = await db.rawQuery(
    "SELECT name FROM sqlite_master "
    "WHERE type = 'table' AND name NOT LIKE 'sqlite_%'",
  );
  final shapes = <String, _TableShape>{};
  for (final row in tableRows) {
    final name = (row['name'] as String?)?.trim().toLowerCase() ?? '';
    if (name.isEmpty) continue;
    final columnRows = await db.rawQuery('PRAGMA table_info($name)');
    final columns = <String, _ColumnShape>{};
    for (final columnRow in columnRows) {
      final columnName =
          (columnRow['name'] as String?)?.trim().toLowerCase() ?? '';
      if (columnName.isEmpty) continue;
      columns[columnName] = _ColumnShape(
        name: columnName,
        affinity: _typeAffinity((columnRow['type'] as String?) ?? ''),
        notNull: ((columnRow['notnull'] as num?)?.toInt() ?? 0) != 0,
        hasDefault: columnRow['dflt_value'] != null,
        primaryKeyOrdinal: (columnRow['pk'] as num?)?.toInt() ?? 0,
      );
    }
    shapes[name] = _TableShape(name: name, columns: columns);
  }
  return shapes;
}

/// Αποτέλεσμα υποβάθμισης βάσης στην έκδοση σχήματος της εφαρμογής.
class DowngradeOutcome {
  const DowngradeOutcome.success(this.dbPath) : errorMessage = null;

  const DowngradeOutcome.failure(this.errorMessage) : dbPath = null;

  /// Η διαδρομή του υποβαθμισμένου αρχείου (πρωτότυπο ή αντίγραφο).
  final String? dbPath;

  final String? errorMessage;

  bool get isSuccess => dbPath != null && dbPath!.trim().isNotEmpty;
}

/// Υποβαθμίζει το [dbPath] στην [databaseSchemaVersionV1] — ΠΑΝΩ στο αρχείο.
///
/// Η υποβάθμιση δεν μετατρέπει τίποτα: όταν η σύγκριση σχήματος αποδείξει ότι
/// το αρχείο είναι υπερσύνολο του αναμενόμενου, η μόνη εγγραφή είναι ο
/// αριθμός έκδοσης που γυρίζει πίσω. Οι νεότερες στήλες μένουν στη θέση τους,
/// αγνοημένες. Η αξιολόγηση επαναλαμβάνεται εδώ — ποτέ δεν εμπιστευόμαστε
/// απόφαση που πάρθηκε πάνω σε προηγούμενη μορφή του αρχείου.
///
/// Ζει στο core/database (και όχι στην υπηρεσία του feature) επειδή γράφει
/// στη βάση — «SQL μόνο στα Repositories», ο αρχιτεκτονικός κανόνας.
Future<DowngradeOutcome> downgradeDatabaseFileToAppVersion(
  String dbPath,
) async {
  if (!await File(dbPath).exists()) {
    return DowngradeOutcome.failure(
      'Το αρχείο «${p.basename(dbPath)}» δεν βρέθηκε.',
    );
  }

  final profile = await profileDatabaseFile(dbPath);
  final fileVersion = profile.userVersion ?? 0;
  if (fileVersion <= databaseSchemaVersionV1) {
    // Ήδη στην έκδοση της εφαρμογής (ή παλαιότερη) — καμία εγγραφή.
    return DowngradeOutcome.success(dbPath);
  }

  final SchemaDowngradeAssessment assessment;
  try {
    assessment = await assessSchemaDowngrade(dbPath, fileVersion: fileVersion);
  } catch (e) {
    return DowngradeOutcome.failure(
      'Ο έλεγχος συμβατότητας δεν ολοκληρώθηκε: $e',
    );
  }
  if (!assessment.isBridgeable) {
    return DowngradeOutcome.failure(
      'Δεν είναι δυνατή η υποβάθμιση: ${assessment.blockersSummary}.',
    );
  }

  Database? db;
  try {
    db = await openDatabase(dbPath, singleInstance: false);
    await db.rawQuery('PRAGMA user_version = $databaseSchemaVersionV1');
  } catch (e) {
    return DowngradeOutcome.failure('Η υποβάθμιση απέτυχε: $e');
  } finally {
    if (db != null && db.isOpen) {
      try {
        await db.close();
      } catch (_) {}
    }
  }
  return DowngradeOutcome.success(dbPath);
}

/// Κανόνες συγγένειας τύπων του SQLite (documentation §3.1): συγκρίνουμε
/// συγγένεια, όχι το κείμενο της δήλωσης, ώστε το `VARCHAR(50)` να ισούται
/// με το `TEXT` όπως ισούται και για την ίδια τη μηχανή.
String _typeAffinity(String declaredType) {
  final upper = declaredType.trim().toUpperCase();
  if (upper.contains('INT')) return 'INTEGER';
  if (upper.contains('CHAR') || upper.contains('CLOB') || upper.contains('TEXT')) {
    return 'TEXT';
  }
  if (upper.isEmpty || upper.contains('BLOB')) return 'BLOB';
  if (upper.contains('REAL') || upper.contains('FLOA') || upper.contains('DOUB')) {
    return 'REAL';
  }
  return 'NUMERIC';
}
