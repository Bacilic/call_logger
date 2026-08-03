import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Αρχεία εκτός `lib/core/database/` που δικαιολογημένα αγγίζουν sqflite
/// (π.χ. desktop FFI bootstrap). Κάθε καταχώρηση απαιτεί σχόλιο αιτιολόγησης.
const _allowlistedRelativePaths = <String>{
  // sqflite FFI αρχικοποίηση (`sqfliteFfiInit`, `databaseFactory`) στην εκκίνηση desktop.
  'lib/main.dart',
};

/// ΧΡΕΟΣ ΠΡΟΣ ΜΕΤΑΚΟΜΙΣΗ — allowlist ΜΟΝΟ για το δομημένο API, που αδειάζει.
///
/// Κάθε αρχείο εδώ έχει σκέτες κλήσεις `db.query`/`db.update` κ.λπ. που πρέπει
/// να μετακομίσουν σε repository. ΔΕΝ προστίθενται νέα αρχεία: αν το τεστ σε
/// έφερε εδώ, μετακόμισε το ερώτημα αντί να μακρύνεις τη λίστα. Κάθε
/// μετακόμιση αφαιρεί τη γραμμή της — όταν αδειάσει, σβήνεται και ο μηχανισμός.
const _structuredApiDebtPaths = <String>{
  // 7 αναγνώσεις προεπισκόπησης οντοτήτων audit — υποψήφιο για μετακόμιση
  // ολόκληρο ως repository (κάνει ΜΟΝΟ queries).
  'lib/features/audit/services/audit_entity_preview_resolver.dart',
  // Ανάγνωση μεταδεδομένων επαναφοράς από app_settings.
  'lib/core/services/backup_reset_metadata.dart',
  // Ανάγνωση/ενημέρωση διαδρομών εικόνων χάρτη (building_map_floors).
  'lib/core/services/building_map_storage.dart',
  // Αναγνώσεις λεξικών + batch εισαγωγές συσσωρευτή.
  'lib/core/services/master_dictionary_service.dart',
  // Ανάγνωση ορισμάτων εργαλείων απομακρυσμένης.
  'lib/core/services/remote_args_service.dart',
};

final _sqfliteImportPattern = RegExp(
  r'''import\s+['"]package:(sqflite|sqflite_common_ffi)/''',
);

final _rawSqlPatterns = <RegExp>[
  RegExp(r'\brawQuery\s*\('),
  RegExp(r'\brawInsert\s*\('),
  RegExp(r'\brawUpdate\s*\('),
  RegExp(r'\brawDelete\s*\('),
  RegExp(r'\.execute\s*\('),
];

/// Δομημένο API πάνω σε handle βάσης: `db.query(...)`, `_db.update(...)`,
/// `dbEx.delete(...)` κ.ο.κ. Ο δείκτης πρέπει να «μυρίζει» βάση (περιέχει
/// db/database) — έτσι δεν πιάνονται άσχετα `.query()` άλλων αντικειμένων.
/// Το lookahead εξαιρεί ονόματα αρχείων (`outDbFile.delete()` είναι File I/O).
///
/// ΣΚΟΠΙΜΑ εκτός: `db.transaction(...)` και οι κλήσεις σε `txn` — το μοτίβο
/// των ατομικών συναλλαγών (ενορχήστρωση transaction σε service με executor)
/// είναι καταγεγραμμένη σχεδίαση και κρίνεται χωριστά, όχι από αυτόν τον φρουρό.
final _structuredApiPatterns = <RegExp>[
  RegExp(
    r'\b(?!\w*[Ff]ile\b)\w*([Dd]b|[Dd]atabase)\w*\.(query|insert|update|delete)\s*\(',
  ),
];

List<File> _dartFilesOutsideDatabaseCore(Directory libRoot) {
  if (!libRoot.existsSync()) return const [];
  return libRoot
      .listSync(recursive: true, followLinks: false)
      .whereType<File>()
      .where((file) => file.path.endsWith('.dart'))
      .where((file) {
        final relative = p.relative(file.path, from: libRoot.parent.path);
        final normalized = relative.replaceAll(r'\', '/');
        return !normalized.startsWith('lib/core/database/');
      })
      .toList();
}

void main() {
  test('SQL isolation — sqflite μόνο μέσα σε core/database repositories', () {
    final projectRoot = Directory.current;
    final libRoot = Directory(p.join(projectRoot.path, 'lib'));
    expect(
      libRoot.existsSync(),
      isTrue,
      reason: 'Αναμένεται φάκελος lib/ στο root του project.',
    );

    final violations = <String>[];

    for (final file in _dartFilesOutsideDatabaseCore(libRoot)) {
      final relative = p
          .relative(file.path, from: projectRoot.path)
          .replaceAll(r'\', '/');
      if (_allowlistedRelativePaths.contains(relative)) continue;

      final structuredDebt = _structuredApiDebtPaths.contains(relative);
      final content = file.readAsStringSync();
      final lines = content.split('\n');

      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        final lineNo = i + 1;
        final trimmed = line.trimLeft();
        if (trimmed.startsWith('//')) continue;

        if (_sqfliteImportPattern.hasMatch(line)) {
          violations.add('$relative:$lineNo — απαγορευμένο import sqflite API');
        }

        for (final pattern in _rawSqlPatterns) {
          if (pattern.hasMatch(line)) {
            violations.add(
              '$relative:$lineNo — απαγορευμένη κλήση ${pattern.pattern}',
            );
          }
        }

        if (structuredDebt) continue;
        for (final pattern in _structuredApiPatterns) {
          if (pattern.hasMatch(line)) {
            violations.add(
              '$relative:$lineNo — δομημένο sqflite API εκτός repository '
              '(db.query/insert/update/delete)',
            );
          }
        }
      }
    }

    if (violations.isNotEmpty) {
      fail(
        'Βρέθηκαν ${violations.length} παραβιάσεις του κανόνα '
        '«SQL μόνο στα Repositories του core/database/»:\n'
        '${violations.join('\n')}',
      );
    }
  });
}
