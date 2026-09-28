// Στήσιμο πραγματικού σεναρίου: «η κοινή βάση θέλει αναβάθμιση ενώ δουλεύουν
// ακόμη συνάδελφοι».
//
//   dart run tool/stage_schema_upgrade_scenario.dart <διαδρομή.db>          (κατάσταση)
//   dart run tool/stage_schema_upgrade_scenario.dart <διαδρομή.db> --set 65 (στήσιμο)
//
// Ρίχνει ΜΟΝΟ τον αριθμό έκδοσης σχήματος (`PRAGMA user_version`), χωρίς να
// αγγίξει δεδομένα ή πίνακες. Η εφαρμογή θα δει τη βάση ως παλιότερη και θα
// ζητήσει αναβάθμιση — που είναι ακριβώς το σημείο που ελέγχουμε.
//
// Ασφαλές για αυτή τη συγκεκριμένη πτώση: οι μεταπτώσεις v59→v66 είναι
// idempotent (κάθε στήλη μπαίνει μόνο αν λείπει), οπότε όταν τελικά τρέξει η
// αναβάθμιση δεν θα βρει τίποτα να χαλάσει. ΜΗΝ το χρησιμοποιήσεις για πτώση
// κάτω από το v44: εκεί υπάρχουν μεταπτώσεις που σβήνουν πίνακα και στήλη.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const int _lowestSafeVersion = 44;

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln(
      'Χρήση: dart run tool/stage_schema_upgrade_scenario.dart '
      '<διαδρομή.db> [--set <έκδοση>]',
    );
    exit(2);
  }

  final dbPath = args.first;
  if (!File(dbPath).existsSync()) {
    stderr.writeln('Δεν βρέθηκε το αρχείο: $dbPath');
    exit(2);
  }

  int? target;
  final setIndex = args.indexOf('--set');
  if (setIndex != -1) {
    if (setIndex + 1 >= args.length) {
      stderr.writeln('Το --set θέλει αριθμό έκδοσης.');
      exit(2);
    }
    target = int.tryParse(args[setIndex + 1]);
    if (target == null || target < _lowestSafeVersion) {
      stderr.writeln(
        'Η έκδοση πρέπει να είναι αριθμός >= $_lowestSafeVersion '
        '(πιο κάτω υπάρχουν μεταπτώσεις που σβήνουν δεδομένα).',
      );
      exit(2);
    }
  }

  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  final db = await databaseFactory.openDatabase(
    dbPath,
    options: OpenDatabaseOptions(singleInstance: false),
  );
  try {
    final before = _versionOf(await db.rawQuery('PRAGMA user_version'));
    stdout.writeln('Αρχείο:          $dbPath');
    stdout.writeln('Έκδοση σχήματος: $before');

    final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' "
      "AND name NOT LIKE 'sqlite_%' ORDER BY name",
    );
    final names = [for (final r in tables) r['name'] as String];
    stdout.writeln('Πίνακες:         ${names.length}');
    if (names.isNotEmpty) {
      stdout.writeln(
        '                 ${names.take(12).join(', ')}'
        '${names.length > 12 ? ', …' : ''}',
      );
    }
    final hasTitle = await db
        .rawQuery('PRAGMA table_info(calls)')
        .then((rows) => rows.any((r) => r['name'] == 'title'));
    stdout.writeln(
      'Στήλη calls.title (v66): ${hasTitle ? 'υπάρχει' : 'λείπει'}',
    );

    if (target != null) {
      await db.execute('PRAGMA user_version = $target');
      final after = _versionOf(await db.rawQuery('PRAGMA user_version'));
      stdout.writeln('Νέα έκδοση:      $after');
    }
  } finally {
    await db.close();
  }

  _reportLivenessMarks(dbPath);
}

int? _versionOf(List<Map<String, Object?>> rows) =>
    rows.isEmpty ? null : rows.first['user_version'] as int?;

/// Ποιος κρατά τη βάση αυτή τη στιγμή, όπως το βλέπει ο φρουρός: τα ίχνη
/// «τρέχω τώρα» στον φάκελο logs δίπλα στη βάση.
void _reportLivenessMarks(String dbPath) {
  final logsDir = Directory(p.join(p.dirname(dbPath), 'logs'));
  stdout.writeln('');
  stdout.writeln('Ίχνη «τρέχω τώρα» στο ${logsDir.path}:');
  if (!logsDir.existsSync()) {
    stdout.writeln('  (ο φάκελος δεν υπάρχει)');
    return;
  }
  final now = DateTime.now();
  var found = 0;
  for (final entry in logsDir.listSync()) {
    final name = p.basename(entry.path).toLowerCase();
    if (entry is! File ||
        !name.startsWith('session_') ||
        !name.endsWith('.lock')) {
      continue;
    }
    found++;
    final raw = entry.readAsStringSync().trim();
    final seen = RegExp(r'"lastSeen"\s*:\s*"([^"]+)"').firstMatch(raw);
    final station = RegExp(r'"station"\s*:\s*"([^"]+)"').firstMatch(raw);
    final lastSeen = seen == null ? null : DateTime.tryParse(seen.group(1)!);
    final age = lastSeen == null ? null : now.difference(lastSeen);
    final fresh = age != null && age < const Duration(minutes: 3);
    stdout.writeln(
      '  ${station?.group(1) ?? p.basename(entry.path)} · '
      '${age == null ? 'άγνωστη ηλικία' : 'πριν από ${age.inSeconds}″'} · '
      '${fresh ? 'ΜΕΤΡΑΕΙ ως ανοιχτό' : 'μπαγιάτικο, δεν μετράει'}',
    );
  }
  if (found == 0) stdout.writeln('  (κανένα ίχνος)');
}
