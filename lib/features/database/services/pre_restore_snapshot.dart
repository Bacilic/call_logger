// Η βάση που φυλάχτηκε πριν από μια επαναφορά — και πώς τη βρίσκει ξανά ο
// χειριστής.
//
// Η επαναφορά δεν διαγράφει ποτέ την τρέχουσα βάση: τη μετονομάζει σε αρχείο
// «_pre_restore_» δίπλα της. Η θέση του ειπώθηκε όμως μόνο στον διάλογο
// αναφοράς, που κλείνει. Όταν η επαναφορά αποδειχθεί κακή —φθαρμένο αντίγραφο,
// λάθος ημερομηνία— ο χειριστής ξέρει ότι «κάπου υπάρχει η παλιά» και ψάχνει
// σε φάκελο με δεκάδες αρχεία.

import 'dart:io';

import 'package:path/path.dart' as p;

import 'database_file_replacement.dart';

/// Ένα αρχείο βάσης που φυλάχτηκε πριν από επαναφορά.
class PreRestoreSnapshot {
  const PreRestoreSnapshot({required this.path, required this.savedAt});

  final String path;
  final DateTime savedAt;

  String get fileName => p.basename(path);
}

/// Υποψήφιο αρχείο προς κρίση — χωρίς εξάρτηση από τον δίσκο, ώστε η επιλογή
/// να ελέγχεται με ημερομηνίες που ορίζει το τεστ.
typedef DatabaseFileEntry = ({String path, DateTime modified});

/// Το **πιο πρόσφατο** αρχείο που φυλάχτηκε πριν από επαναφορά της
/// [currentDatabasePath], ή `null` όταν δεν υπάρχει.
///
/// Κρίνεται η ώρα εγγραφής και όχι η ημερομηνία μέσα στο όνομα: δύο επαναφορές
/// την ίδια μέρα δίνουν ονόματα που διαφέρουν σε λεπτά ή σε μετρητή, και η
/// αλφαβητική σειρά τους δεν είναι η χρονική.
PreRestoreSnapshot? latestPreRestoreSnapshot({
  required String currentDatabasePath,
  required Iterable<DatabaseFileEntry> candidates,
}) {
  final current = currentDatabasePath.trim();
  if (current.isEmpty) return null;

  final prefix =
      '${p.basenameWithoutExtension(current)}'
      '${DatabaseFileReplacement.preRestoreSuffix}';

  PreRestoreSnapshot? best;
  for (final entry in candidates) {
    final name = p.basename(entry.path);
    if (!name.startsWith(prefix)) continue;
    if (!name.toLowerCase().endsWith('.db')) continue;
    if (best == null || entry.modified.isAfter(best.savedAt)) {
      best = PreRestoreSnapshot(path: entry.path, savedAt: entry.modified);
    }
  }
  return best;
}

/// Διαβάζει τον φάκελο της τρέχουσας βάσης και εφαρμόζει την παραπάνω κρίση.
///
/// Ποτέ δεν πετάει: ένας φάκελος που δεν διαβάζεται σημαίνει «δεν έχω κάτι να
/// δείξω», όχι σφάλμα προς τον χειριστή.
Future<PreRestoreSnapshot?> findLatestPreRestoreSnapshot(
  String currentDatabasePath,
) async {
  final current = currentDatabasePath.trim();
  if (current.isEmpty) return null;
  try {
    final dir = Directory(p.dirname(p.absolute(current)));
    if (!await dir.exists()) return null;

    final entries = <DatabaseFileEntry>[];
    await for (final entity in dir.list(followLinks: false)) {
      if (entity is! File) continue;
      try {
        entries.add((path: entity.path, modified: await entity.lastModified()));
      } catch (_) {
        // Αρχείο που εξαφανίστηκε ή δεν απαντά: απλώς δεν είναι υποψήφιο.
      }
    }
    return latestPreRestoreSnapshot(
      currentDatabasePath: current,
      candidates: entries,
    );
  } catch (_) {
    return null;
  }
}
