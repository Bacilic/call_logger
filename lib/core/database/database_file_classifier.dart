import 'package:sqflite_common/sqflite.dart';

/// Κατηγορία αρχείου SQLite ως προς την εφαρμογή Καταγραφή Κλήσεων / Λάμπα.
enum DatabaseFileKind {
  /// Βάση της Καταγραφής Κλήσεων (υπάρχει πίνακας `calls`).
  callLogger,

  /// Βάση της Λάμπας (παλιά βάση εξοπλισμού).
  lamp,

  /// Έγκυρο SQLite χωρίς πίνακες χρήστη (νόμιμη δημιουργία σχήματος).
  empty,

  /// Άγνωστο / άσχετο σχήμα.
  unknown,
}

/// Πίνακες που υπάρχουν μόνο στη βάση Λάμπας (όχι στην Καταγραφή Κλήσεων).
const List<String> kLampSignatureTables = <String>[
  'owners',
  'offices',
  'data_issues',
];

/// Ταξινομεί αρχείο `.db` με άνοιγμα **μόνο για ανάγνωση** (χωρίς version /
/// onCreate / onUpgrade / onDowngrade / onOpen) — καμία εγγραφή στο αρχείο.
Future<DatabaseFileKind> classifyDatabaseFile(String dbPath) async {
  Database? db;
  try {
    db = await openDatabase(
      dbPath,
      readOnly: true,
      singleInstance: false,
    );

    final tableRows = await db.rawQuery(
      "SELECT name FROM sqlite_master "
      "WHERE type = 'table' AND name NOT LIKE 'sqlite_%'",
    );
    final tables = <String>{
      for (final row in tableRows)
        ((row['name'] as String?)?.trim().toLowerCase() ?? ''),
    }..removeWhere((name) => name.isEmpty);

    // Διαβάζουμε το user_version ως μέρος της ταξινόμησης (χωρίς εγγραφή).
    await db.rawQuery('PRAGMA user_version');

    if (tables.contains('calls')) {
      return DatabaseFileKind.callLogger;
    }

    final lampHits = kLampSignatureTables
        .where((name) => tables.contains(name))
        .length;
    if (lampHits >= 2) {
      return DatabaseFileKind.lamp;
    }

    if (tables.isEmpty) {
      return DatabaseFileKind.empty;
    }

    return DatabaseFileKind.unknown;
  } finally {
    if (db != null && db.isOpen) {
      await db.close();
    }
  }
}
