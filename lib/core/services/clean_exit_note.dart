import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'session_liveness_mark.dart';

/// Το σημείωμα «έκλεισα κανονικά», σε φάκελο **αυτού** του υπολογιστή.
///
/// Στο ομαλό κλείσιμο το ίχνος «τρέχω τώρα» σβήνεται από τον κοινό φάκελο.
/// Όταν εκείνος σιωπά (σβηστός διακομιστής), το ίχνος μένει — και η επόμενη
/// εκκίνηση θα το διάβαζε ως κατάρρευση. Το σημείωμα λέει στην επόμενη
/// εκκίνηση ότι **εκείνη ακριβώς** η εκτέλεση έκλεισε κανονικά.
///
/// Η ταύτιση γίνεται με τη στιγμή που ξεκίνησε η εκτέλεση: ένα σημείωμα από
/// παλιότερο κλείσιμο δεν μπορεί να σκεπάσει κατάρρευση μιας νεότερης.
class CleanExitNote {
  CleanExitNote(this.directory);

  final String directory;

  /// `%AppData%\…\session`.
  static Future<String> defaultDirectory() async {
    final support = await getApplicationSupportDirectory();
    return p.join(support.path, 'session');
  }

  File _file(String runSlug) =>
      File(p.join(directory, 'clean_exit_$runSlug.json'));

  /// Κρατά ότι η εκτέλεση του [mark] έκλεισε κανονικά.
  Future<void> write(String runSlug, SessionLivenessMark mark) async {
    try {
      await Directory(directory).create(recursive: true);
      await _file(runSlug).writeAsString(
        jsonEncode({'startedAt': mark.startedAt.toIso8601String()}),
        flush: true,
      );
    } catch (_) {
      // Χωρίς σημείωμα η επόμενη εκκίνηση αναφέρει κατάρρευση, όπως πριν —
      // λάθος συναγερμός, όχι χαμένη πληροφορία.
    }
  }

  /// Έκλεισε κανονικά η εκτέλεση του [previous];
  ///
  /// Το σημείωμα διαβάζεται **μία φορά** και σβήνεται, όποια κι αν είναι η
  /// απάντηση: ανήκει στο προηγούμενο κλείσιμο και μόνο.
  Future<bool> consumeMatches(
    String runSlug,
    SessionLivenessMark? previous,
  ) async {
    final file = _file(runSlug);
    try {
      if (!await file.exists()) return false;
      final raw = await file.readAsString();
      try {
        await file.delete();
      } catch (_) {}
      if (previous == null) return false;
      final data = jsonDecode(raw);
      if (data is! Map<String, Object?>) return false;
      final startedAt = DateTime.tryParse(data['startedAt']?.toString() ?? '');
      return startedAt != null &&
          startedAt.isAtSameMomentAs(previous.startedAt);
    } catch (_) {
      return false;
    }
  }
}
