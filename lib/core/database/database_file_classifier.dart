import 'package:sqflite_common/sqflite.dart';

/// Κατηγορία αρχείου SQLite ως προς την εφαρμογή Καταγραφή Κλήσεων / Λάμπα.
enum DatabaseFileKind {
  /// Βάση της Καταγραφής Κλήσεων (πλήρες βασικό σχήμα).
  callLogger,

  /// Βάση της Λάμπας (παλιά βάση εξοπλισμού).
  lamp,

  /// Υβρίδιο: πίνακες Καταγραφής και Λάμπας στο ίδιο αρχείο.
  hybrid,

  /// Υπάρχει `calls` αλλά λείπουν βασικοί πίνακες Καταγραφής.
  incompleteCallLogger,

  /// Έγκυρο SQLite χωρίς πίνακες χρήστη (νόμιμη δημιουργία σχήματος).
  empty,

  /// Άγνωστο / άσχετο σχήμα.
  unknown,

  /// Το αρχείο δεν μπόρεσε να ανοίξει για ανάγνωση, άρα δεν ταξινομείται.
  undetermined,
}

/// Βασικοί πίνακες σχήματος Καταγραφής Κλήσεων.
const List<String> kCallLoggerCoreTables = <String>[
  'calls',
  'users',
  'phones',
  'equipment',
  'departments',
  'categories',
  'tasks',
];

/// Πίνακες που υπάρχουν μόνο στη βάση Λάμπας (όχι στην Καταγραφή Κλήσεων).
const List<String> kLampSignatureTables = <String>[
  'owners',
  'offices',
  'data_issues',
];

/// Προφίλ αρχείου βάσης από ένα πέρασμα μόνο-ανάγνωσης.
class DatabaseFileProfile {
  const DatabaseFileProfile({
    required this.kind,
    this.missingCoreTables = const <String>[],
    this.hasLampSignature = false,
    this.userVersion,
    this.callCount,
    this.userCount,
    this.phoneCount,
    this.equipmentCount,
    this.departmentCount,
    this.latestCallDate,
    this.failureReason,
  });

  final DatabaseFileKind kind;
  final List<String> missingCoreTables;
  final bool hasLampSignature;
  final int? userVersion;
  final int? callCount;
  final int? userCount;
  final int? phoneCount;
  final int? equipmentCount;
  final int? departmentCount;
  final String? latestCallDate;
  final String? failureReason;
}

/// Ταξινομεί αρχείο `.db` με άνοιγμα **μόνο για ανάγνωση** (χωρίς version /
/// onCreate / onUpgrade / onDowngrade / onOpen) — καμία εγγραφή στο αρχείο.
///
/// Σε αποτυχία ανοίγματος/ανάγνωσης επιστρέφει [DatabaseFileKind.undetermined]
/// αντί να πετάει ωμό σφάλμα SQLite.
Future<DatabaseFileKind> classifyDatabaseFile(String dbPath) async {
  final result = await classifyDatabaseFileWithReason(dbPath);
  return result.kind;
}

/// Όπως [classifyDatabaseFile], με προαιρετικό λόγο αποτυχίας όταν η
/// ταξινόμηση δεν ολοκληρώθηκε.
Future<({DatabaseFileKind kind, String? failureReason})>
classifyDatabaseFileWithReason(String dbPath) async {
  final profile = await profileDatabaseFile(dbPath);
  return (kind: profile.kind, failureReason: profile.failureReason);
}

/// Διαβάζει το αρχείο μία φορά (read-only) και επιστρέφει πλήρες προφίλ.
Future<DatabaseFileProfile> profileDatabaseFile(String dbPath) async {
  Database? db;
  try {
    db = await openDatabase(dbPath, readOnly: true, singleInstance: false);

    final tableRows = await db.rawQuery(
      "SELECT name FROM sqlite_master "
      "WHERE type IN ('table', 'view') AND name NOT LIKE 'sqlite_%'",
    );
    final tables = <String>{
      for (final row in tableRows)
        ((row['name'] as String?)?.trim().toLowerCase() ?? ''),
    }..removeWhere((name) => name.isEmpty);

    // Διαβάζουμε το user_version ως μέρος της ταξινόμησης (χωρίς εγγραφή).
    final versionRows = await db.rawQuery('PRAGMA user_version');
    final userVersion = versionRows.isEmpty
        ? null
        : versionRows.first['user_version'] as int?;

    final hasCalls = tables.contains('calls');
    final lampTableHits = kLampSignatureTables
        .where((name) => tables.contains(name))
        .length;
    // Η Λάμπα μπορεί να αναγνωριστεί ΚΑΙ από μόνο τον `equipment`: το δικό της
    // έχει κλειδί `code`, ενώ ο ομώνυμος πίνακας της Καταγραφής έχει πάντα
    // `code_equipment`. Χωρίς αυτόν τον έλεγχο ένα απόσπασμα της Λάμπας με
    // μόνο τον εξοπλισμό θα περνούσε ως «άγνωστο σχήμα».
    final hasLampShapedEquipment = tables.contains('equipment')
        ? await _hasLampShapedEquipment(db)
        : false;
    final hasLampSignature = lampTableHits >= 2 || hasLampShapedEquipment;

    if (hasCalls && hasLampSignature) {
      return DatabaseFileProfile(
        kind: DatabaseFileKind.hybrid,
        hasLampSignature: true,
        userVersion: userVersion,
      );
    }

    if (hasLampSignature) {
      return DatabaseFileProfile(
        kind: DatabaseFileKind.lamp,
        hasLampSignature: true,
        userVersion: userVersion,
      );
    }

    if (hasCalls) {
      final missing = kCallLoggerCoreTables
          .where((name) => !tables.contains(name))
          .toList(growable: false);
      if (missing.isNotEmpty) {
        return DatabaseFileProfile(
          kind: DatabaseFileKind.incompleteCallLogger,
          missingCoreTables: missing,
          userVersion: userVersion,
        );
      }
    } else {
      if (tables.isNotEmpty) {
        return DatabaseFileProfile(
          kind: DatabaseFileKind.unknown,
          userVersion: userVersion,
        );
      }
      return DatabaseFileProfile(
        kind: DatabaseFileKind.empty,
        userVersion: userVersion,
      );
    }

    // Πλήρες βασικό σχήμα: συμπληρώνουμε τα πλήθη που τροφοδοτούν τις
    // προειδοποιήσεις κατάστασης βάσης και τη σύγκριση αντιγράφων.
    return DatabaseFileProfile(
      kind: DatabaseFileKind.callLogger,
      userVersion: userVersion,
      callCount: await _tryCount(db, 'calls'),
      userCount: await _tryCount(db, 'users'),
      phoneCount: await _tryCount(db, 'phones'),
      equipmentCount: await _tryCount(db, 'equipment'),
      departmentCount: await _tryCount(db, 'departments'),
      latestCallDate: await _tryLatestCallDate(db),
    );
  } catch (e) {
    return DatabaseFileProfile(
      kind: DatabaseFileKind.undetermined,
      failureReason: e.toString(),
    );
  } finally {
    if (db != null && db.isOpen) {
      try {
        await db.close();
      } catch (_) {}
    }
  }
}

/// `true` όταν ο πίνακας `equipment` έχει τη μορφή της Λάμπας.
Future<bool> _hasLampShapedEquipment(Database db) async {
  try {
    final columns = await db.rawQuery('PRAGMA table_info(equipment)');
    final names = <String>{
      for (final row in columns)
        ((row['name'] as String?)?.trim().toLowerCase() ?? ''),
    }..removeWhere((name) => name.isEmpty);
    if (names.contains('code_equipment')) return false;
    return names.contains('code');
  } catch (_) {
    return false;
  }
}

Future<int?> _tryCount(Database db, String table) async {
  try {
    final rows = await db.rawQuery('SELECT COUNT(*) AS c FROM $table');
    if (rows.isEmpty) return null;
    final value = rows.first['c'];
    if (value is int) return value;
    return int.tryParse('$value');
  } catch (_) {
    return null;
  }
}

Future<String?> _tryLatestCallDate(Database db) async {
  try {
    final rows = await db.rawQuery('SELECT MAX(date) AS d FROM calls');
    if (rows.isEmpty) return null;
    final value = (rows.first['d'] as String?)?.trim() ?? '';
    return value.isEmpty ? null : value;
  } catch (_) {
    return null;
  }
}
