/// Σύνδεση βάσης που **δεν περιμένει για πάντα**.
///
/// Όταν η βάση ζει σε δικτυακό φάκελο και η πρόσβαση χαθεί εν ώρα λειτουργίας,
/// τα ερωτήματα που έτρεχαν δεν τελειώνουν ποτέ: ούτε με απάντηση, ούτε με
/// σφάλμα. Οι οθόνες που τα περιμένουν γυρίζουν τον κύκλο φόρτωσης μέχρι να
/// κλείσει η εφαρμογή, και ο χειριστής δεν μαθαίνει ποτέ τι έγινε.
///
/// **Ένα σημείο, όχι 549.** Η εφαρμογή μοιράζει τη σύνδεση από ένα και μόνο
/// σημείο (`DatabaseHelper.database`), και τα repositories την κρατούν ως
/// `final Database db`. Τυλίγοντας εκεί, το όριο το κληρονομούν όλα τα
/// ερωτήματα χωρίς να αγγιχτεί ούτε ένα repository.
///
/// **Τι ΔΕΝ κάνει.** Το όριο τερματίζει την **αναμονή**, δεν ακυρώνει την πράξη
/// που κόλλησε στο λειτουργικό — η SQLite δεν προσφέρει ακύρωση. Ο καλών
/// ελευθερώνεται και η οθόνη λέει τι έγινε· η πράξη από κάτω μπορεί να μένει
/// κολλημένη μέχρι να απαντήσει το δίκτυο. Γι' αυτό η αυτόματη επανασύνδεση
/// είναι **επόμενο** βήμα και θέλει δική της δοκιμή με πραγματική διακοπή.
library;

import 'dart:async';

import 'package:sqflite_common/sqlite_api.dart';

import '../config/app_config.dart';

/// Πόσο περιμένει ένα ερώτημα πριν τα παρατήσει.
///
/// Μεγαλύτερο από το άνοιγμα της βάσης (8 δευτ.) δεν έχει νόημα να είναι· πολύ
/// μικρότερο θα έκοβε αργά αλλά υγιή ερωτήματα σε φορτωμένο διακομιστή.
const Duration kDatabaseQueryTimeout = Duration(seconds: 10);

/// Το σφάλμα που βλέπει ο καλών όταν η βάση δεν απάντησε εγκαίρως.
///
/// Ξεχωριστός τύπος και όχι σκέτο [TimeoutException]: η οθόνη σφάλματος και ο
/// φύλακας προσβασιμότητας χρειάζονται να ξεχωρίσουν το «η βάση δεν απαντά»
/// από κάθε άλλο timeout της εφαρμογής.
class DatabaseUnresponsiveException implements Exception {
  const DatabaseUnresponsiveException(this.timeout, this.operation);

  final Duration timeout;

  /// Ποια πράξη κόλλησε — μπαίνει στο μήνυμα ώστε το ημερολόγιο να λέει κάτι.
  final String operation;

  @override
  String toString() =>
      'Η βάση δεδομένων δεν απάντησε μέσα σε ${timeout.inSeconds} '
      'δευτερόλεπτα ($operation). Πιθανή αιτία: χάθηκε η πρόσβαση στον φάκελο '
      'της βάσης.';
}

/// Χρειάζεται φύλακα η βάση σε αυτή τη διαδρομή;
///
/// **Μόνο οι δικτυακές διαδρομές.** Ένα τοπικό αρχείο δεν σταματά να απαντά:
/// μπορεί να είναι αργό, δεν γίνεται όμως άφταστο ενώ η εφαρμογή τρέχει. Ο
/// φύλακας υπάρχει για τον κοινόχρηστο φάκελο που χάνεται στη μέση της βάρδιας.
///
/// Ίδια οριοθέτηση με την αναμονή κλειδώματος (`database_busy_timeout.dart`):
/// η διαδρομή αποφασίζει, όχι μια καθολική ρύθμιση.
///
/// **Γνωστό όριο:** αναγνωρίζεται η μορφή `\\διακομιστής\φάκελος`. Ένας
/// δικτυακός δίσκος περασμένος ως γράμμα (π.χ. `Z:`) δεν ξεχωρίζει από τοπικό
/// και μένει αφύλαχτος.
bool databaseNeedsTimeoutGuard(String dbPath) =>
    AppConfig.isUncDatabasePath(dbPath);

/// Δίνει στη σύνδεση [raw] τον φύλακα που της αναλογεί.
///
/// Επιστρέφει την ίδια τη σύνδεση όταν δεν χρειάζεται φύλακας — ένα περίβλημα
/// που δεν προστατεύει από τίποτα είναι μόνο ένα χρονόμετρο ανά ερώτημα.
Database guardDatabaseWithTimeout(
  Database raw, {
  Duration timeout = kDatabaseQueryTimeout,
}) => databaseNeedsTimeoutGuard(raw.path)
    ? TimeoutDatabase(raw, timeout: timeout)
    : raw;

/// Τυλίγει μια [Database] ώστε κάθε ασύγχρονη πράξη της να έχει όριο χρόνου.
class TimeoutDatabase implements Database {
  TimeoutDatabase(this._inner, {this.timeout = kDatabaseQueryTimeout});

  final Database _inner;
  final Duration timeout;

  /// Η γυμνή σύνδεση από κάτω.
  ///
  /// Την χρειάζεται μόνο ο ιδιοκτήτης της σύνδεσης, για το κλείσιμο και τους
  /// ελέγχους κατάστασης. Τα repositories δεν έχουν λόγο να τη ζητήσουν.
  Database get inner => _inner;

  Future<T> _bounded<T>(String operation, Future<T> Function() action) {
    return action().timeout(
      timeout,
      onTimeout: () =>
          throw DatabaseUnresponsiveException(timeout, operation),
    );
  }

  // --- Ιδιότητες: σύγχρονες, περνούν αυτούσιες ---

  @override
  String get path => _inner.path;

  @override
  bool get isOpen => _inner.isOpen;

  /// Επιστρέφει **τον εαυτό του**: όποιος ζητήσει τη βάση μέσα από έναν
  /// executor πρέπει να πάρει επίσης φυλαγμένη σύνδεση, όχι τη γυμνή.
  @override
  Database get database => this;

  /// **Χωρίς όριο, επίτηδες.** Ένα κλείσιμο που «πέτυχε» ενώ η σύνδεση ζει
  /// ακόμη είναι χειρότερο από ένα κλείσιμο που αργεί: ο επόμενος που θα
  /// ανοίξει θα νόμιζε ότι ο δρόμος είναι ελεύθερος. Το κλείσιμο ανήκει στον
  /// ιδιοκτήτη της σύνδεσης, που ξέρει τι κάνει με την αναμονή.
  @override
  Future<void> close() => _inner.close();

  // --- Ερωτήματα ---

  @override
  Future<void> execute(String sql, [List<Object?>? arguments]) =>
      _bounded('execute', () => _inner.execute(sql, arguments));

  @override
  Future<int> rawInsert(String sql, [List<Object?>? arguments]) =>
      _bounded('rawInsert', () => _inner.rawInsert(sql, arguments));

  @override
  Future<int> insert(
    String table,
    Map<String, Object?> values, {
    String? nullColumnHack,
    ConflictAlgorithm? conflictAlgorithm,
  }) => _bounded(
    'insert $table',
    () => _inner.insert(
      table,
      values,
      nullColumnHack: nullColumnHack,
      conflictAlgorithm: conflictAlgorithm,
    ),
  );

  @override
  Future<List<Map<String, Object?>>> query(
    String table, {
    bool? distinct,
    List<String>? columns,
    String? where,
    List<Object?>? whereArgs,
    String? groupBy,
    String? having,
    String? orderBy,
    int? limit,
    int? offset,
  }) => _bounded(
    'query $table',
    () => _inner.query(
      table,
      distinct: distinct,
      columns: columns,
      where: where,
      whereArgs: whereArgs,
      groupBy: groupBy,
      having: having,
      orderBy: orderBy,
      limit: limit,
      offset: offset,
    ),
  );

  @override
  Future<List<Map<String, Object?>>> rawQuery(
    String sql, [
    List<Object?>? arguments,
  ]) => _bounded('rawQuery', () => _inner.rawQuery(sql, arguments));

  @override
  Future<QueryCursor> rawQueryCursor(
    String sql,
    List<Object?>? arguments, {
    int? bufferSize,
  }) => _bounded(
    'rawQueryCursor',
    () => _inner.rawQueryCursor(sql, arguments, bufferSize: bufferSize),
  );

  @override
  Future<QueryCursor> queryCursor(
    String table, {
    bool? distinct,
    List<String>? columns,
    String? where,
    List<Object?>? whereArgs,
    String? groupBy,
    String? having,
    String? orderBy,
    int? limit,
    int? offset,
    int? bufferSize,
  }) => _bounded(
    'queryCursor $table',
    () => _inner.queryCursor(
      table,
      distinct: distinct,
      columns: columns,
      where: where,
      whereArgs: whereArgs,
      groupBy: groupBy,
      having: having,
      orderBy: orderBy,
      limit: limit,
      offset: offset,
      bufferSize: bufferSize,
    ),
  );

  @override
  Future<int> rawUpdate(String sql, [List<Object?>? arguments]) =>
      _bounded('rawUpdate', () => _inner.rawUpdate(sql, arguments));

  @override
  Future<int> update(
    String table,
    Map<String, Object?> values, {
    String? where,
    List<Object?>? whereArgs,
    ConflictAlgorithm? conflictAlgorithm,
  }) => _bounded(
    'update $table',
    () => _inner.update(
      table,
      values,
      where: where,
      whereArgs: whereArgs,
      conflictAlgorithm: conflictAlgorithm,
    ),
  );

  @override
  Future<int> rawDelete(String sql, [List<Object?>? arguments]) =>
      _bounded('rawDelete', () => _inner.rawDelete(sql, arguments));

  @override
  Future<int> delete(
    String table, {
    String? where,
    List<Object?>? whereArgs,
  }) => _bounded(
    'delete $table',
    () => _inner.delete(table, where: where, whereArgs: whereArgs),
  );

  // --- Συναλλαγές ---

  /// Το όριο μπαίνει **γύρω από ολόκληρη** τη συναλλαγή, όχι στα ερωτήματά της.
  ///
  /// Μία μέτρηση για μία δουλειά: μια συναλλαγή είναι ένα αδιαίρετο βήμα, και
  /// το ζητούμενο είναι να μη μείνει ο καλών να περιμένει. Όριο ανά εσωτερικό
  /// ερώτημα θα έκοβε τη συναλλαγή στη μέση, αφήνοντας μισοτελειωμένη δουλειά
  /// σε κοινόχρηστη βάση.
  @override
  Future<T> transaction<T>(
    Future<T> Function(Transaction txn) action, {
    bool? exclusive,
  }) => _bounded(
    'transaction',
    () => _inner.transaction(action, exclusive: exclusive),
  );

  @override
  Future<T> readTransaction<T>(Future<T> Function(Transaction txn) action) =>
      _bounded('readTransaction', () => _inner.readTransaction(action));

  @override
  Batch batch() => _TimeoutBatch(_inner.batch(), this);

  // --- Εργαλεία ανάπτυξης: περνούν αυτούσια ---

  @Deprecated('Dev only')
  @override
  Future<T> devInvokeMethod<T>(String method, [Object? arguments]) =>
      // ignore: deprecated_member_use
      _inner.devInvokeMethod<T>(method, arguments);

  @Deprecated('Dev only')
  @override
  Future<T> devInvokeSqlMethod<T>(
    String method,
    String sql, [
    List<Object?>? arguments,
  ]) =>
      // ignore: deprecated_member_use
      _inner.devInvokeSqlMethod<T>(method, sql, arguments);
}

/// Οι δέσμες εντολών περιμένουν στο [commit]/[apply] — εκεί μπαίνει το όριο.
class _TimeoutBatch implements Batch {
  _TimeoutBatch(this._inner, this._owner);

  final Batch _inner;
  final TimeoutDatabase _owner;

  @override
  Future<List<Object?>> commit({
    bool? exclusive,
    bool? noResult,
    bool? continueOnError,
  }) => _owner._bounded(
    'batch commit',
    () => _inner.commit(
      exclusive: exclusive,
      noResult: noResult,
      continueOnError: continueOnError,
    ),
  );

  @override
  Future<List<Object?>> apply({bool? noResult, bool? continueOnError}) =>
      _owner._bounded(
        'batch apply',
        () => _inner.apply(noResult: noResult, continueOnError: continueOnError),
      );

  @override
  int get length => _inner.length;

  @override
  void execute(String sql, [List<Object?>? arguments]) =>
      _inner.execute(sql, arguments);

  @override
  void rawInsert(String sql, [List<Object?>? arguments]) =>
      _inner.rawInsert(sql, arguments);

  @override
  void insert(
    String table,
    Map<String, Object?> values, {
    String? nullColumnHack,
    ConflictAlgorithm? conflictAlgorithm,
  }) => _inner.insert(
    table,
    values,
    nullColumnHack: nullColumnHack,
    conflictAlgorithm: conflictAlgorithm,
  );

  @override
  void rawUpdate(String sql, [List<Object?>? arguments]) =>
      _inner.rawUpdate(sql, arguments);

  @override
  void update(
    String table,
    Map<String, Object?> values, {
    String? where,
    List<Object?>? whereArgs,
    ConflictAlgorithm? conflictAlgorithm,
  }) => _inner.update(
    table,
    values,
    where: where,
    whereArgs: whereArgs,
    conflictAlgorithm: conflictAlgorithm,
  );

  @override
  void rawDelete(String sql, [List<Object?>? arguments]) =>
      _inner.rawDelete(sql, arguments);

  @override
  void delete(String table, {String? where, List<Object?>? whereArgs}) =>
      _inner.delete(table, where: where, whereArgs: whereArgs);

  @override
  void query(
    String table, {
    bool? distinct,
    List<String>? columns,
    String? where,
    List<Object?>? whereArgs,
    String? groupBy,
    String? having,
    String? orderBy,
    int? limit,
    int? offset,
  }) => _inner.query(
    table,
    distinct: distinct,
    columns: columns,
    where: where,
    whereArgs: whereArgs,
    groupBy: groupBy,
    having: having,
    orderBy: orderBy,
    limit: limit,
    offset: offset,
  );

  @override
  void rawQuery(String sql, [List<Object?>? arguments]) =>
      _inner.rawQuery(sql, arguments);
}
