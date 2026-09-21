import 'package:sqflite_common/sqflite.dart';

import 'database_integrity_probe.dart';
import 'settings_repository.dart';

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

/// Μια μέτρηση του προφίλ που μπορεί να μην έγινε.
///
/// Υπάρχει επειδή το `null` δεν αρκεί: σε φθαρμένη βάση το πλήθος κλήσεων
/// βγαίνει `null` επειδή **δεν διαβάστηκε**, ενώ σε υγιή άδεια βάση η
/// τελευταία κλήση βγαίνει `null` επειδή **δεν υπάρχει καμία**. Μετρημένο
/// 14/09/2026: στην ίδια φθαρμένη βάση οι κλήσεις και οι υπάλληλοι γύρισαν
/// `null`, ενώ ο εξοπλισμός γύρισε 400 και τα τηλέφωνα 0.
enum DatabaseProfileMetric {
  calls,
  users,
  phones,
  equipment,
  departments,
  latestCall,
}

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
    this.latestAuditAt,
    this.failureReason,
    this.hasDebugScenarioSignature = false,
    this.contentIntegrity = DatabaseIntegrityStatus.inconclusive,
    this.integrityDetail,
    this.unreadableMetrics = const <DatabaseProfileMetric>{},
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

  /// Πότε γράφτηκε τελευταία φορά **οτιδήποτε** σε αυτή τη βάση, κατά το
  /// Ιστορικό της εφαρμογής.
  ///
  /// Συμπληρώνει το [latestCallDate], δεν το αντικαθιστά: καθένα από τα δύο
  /// είναι τυφλό σε ένα σενάριο. Μια βάση όπου δουλεύεται μόνο ο Κατάλογος δεν
  /// αποκτά ποτέ νεότερη κλήση, ενώ το Ιστορικό καθαρίζεται περιοδικά και
  /// μπορεί να μείνει άδειο. «Πότε δούλεψε κάποιος εδώ» το απαντά **η πιο
  /// πρόσφατη από τις δύο**.
  final DateTime? latestAuditAt;

  final String? failureReason;

  /// True όταν το περιεχόμενο φέρει την υπογραφή του σπορέα «Σενάρια
  /// σφαλμάτων» — τα δεδομένα είναι τεχνητά, όποιο όνομα κι αν έχει το αρχείο.
  final bool hasDebugScenarioSignature;

  /// Τι απάντησε το ίδιο το SQLite για το **περιεχόμενο** του αρχείου.
  ///
  /// Ξεχωριστό ερώτημα από το [kind], και δεν το επηρεάζει: οι πίνακες μπορεί
  /// να είναι όλοι στη θέση τους ενώ οι σελίδες από κάτω έχουν αλλοιωθεί. Η
  /// προεπιλογή είναι [DatabaseIntegrityStatus.inconclusive] — «δεν ρωτήθηκε»
  /// και «δεν απαντήθηκε» αξίζουν την ίδια επιφύλαξη, και καμία από τις δύο
  /// δεν είναι απόδειξη ζημιάς.
  final DatabaseIntegrityStatus contentIntegrity;

  /// Το **ωμό** κείμενο του SQLite όταν βρέθηκε φθορά. Δεν μεταφράζεται και
  /// δεν συνοψίζεται: είναι η μόνη πρόταση που λέει τι ακριβώς χάλασε.
  final String? integrityDetail;

  /// Ποιες μετρήσεις δεν απαντήθηκαν επειδή το αρχείο αντιστάθηκε.
  ///
  /// Χωριστό από την τιμή τους: η οθόνη πρέπει να ξεχωρίσει το «κενό» από το
  /// «δεν διαβάζεται», γιατί πάνω σε αυτή τη διαφορά κρίνεται η επαναφορά.
  final Set<DatabaseProfileMetric> unreadableMetrics;

  /// `true` όταν αυτή η μέτρηση απέτυχε — όχι όταν απλώς βγήκε άδεια.
  bool isUnreadable(DatabaseProfileMetric metric) =>
      unreadableMetrics.contains(metric);

  /// `true` μόνο όταν υπάρχει **απόδειξη** φθοράς — ποτέ από σιωπή.
  bool get contentIsCorrupt =>
      contentIntegrity == DatabaseIntegrityStatus.corrupt;
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

    // Το σχήμα στέκει. Απομένει το ερώτημα που κανένας έλεγχος πινάκων δεν
    // απαντά: στέκει και το ΠΕΡΙΕΧΟΜΕΝΟ; Ρωτιέται εδώ, στην ήδη ανοιχτή
    // σύνδεση, γιατί κάθε ροή που κρίνει βάση περνά από αυτό το σημείο — η
    // επαναφορά, η απογραφή αντιγράφου, η αλλαγή αρχείου, η εκκίνηση. Ένας
    // έλεγχος παραπάνω εδώ σημαίνει ότι καμία από αυτές δεν μπορεί να τον
    // ξεχάσει.
    final integrity = await _readIntegrityQuietly(db);

    // Πλήρες βασικό σχήμα: συμπληρώνουμε τα πλήθη που τροφοδοτούν τις
    // προειδοποιήσεις κατάστασης βάσης και τη σύγκριση αντιγράφων.
    //
    // Κάθε μέτρηση που αποτυγχάνει καταγράφεται ονομαστικά: η οθόνη δεν
    // μπορεί να ξεχωρίσει το «κενό» από το «δεν διαβάζεται» αν φτάσει εκεί
    // μόνο ένα `null`.
    final unreadable = <DatabaseProfileMetric>{};
    final calls = await _tryCount(
      db,
      'calls',
      DatabaseProfileMetric.calls,
      unreadable,
    );
    final users = await _tryCount(
      db,
      'users',
      DatabaseProfileMetric.users,
      unreadable,
    );
    final phones = await _tryCount(
      db,
      'phones',
      DatabaseProfileMetric.phones,
      unreadable,
    );
    final equipment = await _tryCount(
      db,
      'equipment',
      DatabaseProfileMetric.equipment,
      unreadable,
    );
    final departments = await _tryCount(
      db,
      'departments',
      DatabaseProfileMetric.departments,
      unreadable,
    );
    final latest = await _tryLatestCallDate(db, unreadable);
    final latestAudit = await _tryLatestAuditAt(db);

    return DatabaseFileProfile(
      kind: DatabaseFileKind.callLogger,
      userVersion: userVersion,
      contentIntegrity: integrity.status,
      integrityDetail: integrity.rawMessage,
      unreadableMetrics: Set.unmodifiable(unreadable),
      callCount: calls,
      userCount: users,
      phoneCount: phones,
      equipmentCount: equipment,
      departmentCount: departments,
      latestCallDate: latest,
      latestAuditAt: latestAudit,
      hasDebugScenarioSignature: tables.contains('app_settings')
          ? await _tryHasDebugScenarioSignature(db)
          : false,
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

/// Ο έλεγχος ακεραιότητας δεν επιτρέπεται να ρίξει την ταξινόμηση ούτε να την
/// κρεμάσει.
///
/// Δύο ξεχωριστοί κίνδυνοι, μία απάντηση: σε κοινόχρηστη βάση δικτύου το
/// ερώτημα μπορεί να αργήσει πολύ, και σε κλειδωμένη ή χωρίς δικαιώματα
/// μπορεί να πετάξει. Καμία από τις δύο περιπτώσεις **δεν** είναι απόδειξη
/// ζημιάς — γι' αυτό και οι δύο καταλήγουν σε `inconclusive` και ο χρήστης
/// δεν βλέπει τίποτα. Μόνο ρητό «malformed» από το SQLite μετρά.
Future<DatabaseIntegrityOutcome> _readIntegrityQuietly(Database db) async {
  try {
    return await readIntegrityFromOpenDatabase(
      db,
    ).timeout(const Duration(seconds: 5));
  } catch (_) {
    return const DatabaseIntegrityOutcome(
      status: DatabaseIntegrityStatus.inconclusive,
    );
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

/// Μετρά, και **καταγράφει** την αποτυχία αντί να τη σβήνει σε `null`.
Future<int?> _tryCount(
  Database db,
  String table,
  DatabaseProfileMetric metric,
  Set<DatabaseProfileMetric> unreadable,
) async {
  try {
    final rows = await db.rawQuery('SELECT COUNT(*) AS c FROM $table');
    if (rows.isEmpty) {
      unreadable.add(metric);
      return null;
    }
    final value = rows.first['c'];
    if (value is int) return value;
    final parsed = int.tryParse('$value');
    if (parsed == null) unreadable.add(metric);
    return parsed;
  } catch (_) {
    unreadable.add(metric);
    return null;
  }
}

Future<bool> _tryHasDebugScenarioSignature(Database db) async {
  try {
    final rows = await db.rawQuery(
      'SELECT value FROM app_settings WHERE key = ? LIMIT 1',
      [kDebugScenarioSignatureSettingKey],
    );
    if (rows.isEmpty) return false;
    final value = (rows.first['value'] as String?)?.trim() ?? '';
    return value.isNotEmpty;
  } catch (_) {
    return false;
  }
}

/// Η πιο πρόσφατη κλήση — ή `null`, που εδώ έχει **δύο** πιθανές σημασίες.
///
/// Κενό αποτέλεσμα σημαίνει «καμία κλήση» και είναι έγκυρη απάντηση· μόνο η
/// εξαίρεση σημαίνει «δεν διαβάστηκε».
/// Πότε γράφτηκε τελευταία φορά κάτι στο Ιστορικό αυτής της βάσης.
///
/// Δεν σημειώνει «μη αναγνώσιμο» σε αποτυχία: το Ιστορικό είναι συμπληρωματικό
/// στοιχείο ηλικίας, όχι μετρικό που δείχνεται σε πίνακα — μια βάση παλαιού
/// σχήματος χωρίς `audit_log` δεν είναι ελλιπής, απλώς δεν έχει να πει κάτι.
Future<DateTime?> _tryLatestAuditAt(Database db) async {
  try {
    final rows = await db.rawQuery('SELECT MAX(timestamp) AS v FROM audit_log');
    if (rows.isEmpty) return null;
    return DateTime.tryParse('${rows.first['v'] ?? ''}');
  } catch (_) {
    return null;
  }
}

Future<String?> _tryLatestCallDate(
  Database db,
  Set<DatabaseProfileMetric> unreadable,
) async {
  try {
    final rows = await db.rawQuery('SELECT MAX(date) AS d FROM calls');
    if (rows.isEmpty) return null;
    final value = (rows.first['d'] as String?)?.trim() ?? '';
    return value.isEmpty ? null : value;
  } catch (_) {
    unreadable.add(DatabaseProfileMetric.latestCall);
    return null;
  }
}
