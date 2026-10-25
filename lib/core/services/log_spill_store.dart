import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'log_file_names.dart';

/// Η τοπική αναμονή του ημερολογίου: ό,τι δεν έφτασε στον κοινό φάκελο.
///
/// Ο φάκελος `logs` ζει δίπλα στη βάση — στο δίκτυο, όταν η βάση είναι κοινή.
/// Όσο εκείνος σιωπά, οι εγγραφές έρχονται εδώ, σε φάκελο **αυτού** του
/// υπολογιστή, και περιμένουν. Χωρίς αυτό χάνονταν ακριβώς τα σφάλματα της
/// ώρας που το δίκτυο είχε πρόβλημα.
///
/// Κάθε εγγραφή θυμάται **για ποιον φάκελο γράφτηκε** και σε ποιο ημερήσιο
/// αρχείο ανήκει: φτάνει μόνο εκεί, ακόμη κι αν η επόμενη εκκίνηση γίνει πάνω
/// σε άλλη βάση. Η γραμμή μένει όπως σφραγίστηκε τη στιγμή του γεγονότος —
/// με τον σταθμό, την έκδοση και την αρχική της ώρα.
///
/// Δεν κρίνει πότε ο κοινός φάκελος απαντά· αυτό το κρίνει ο κάτοχός του
/// (`CrashLogService`), που καλεί το [drainTo].
class LogSpillStore {
  LogSpillStore(this.directory);

  final String directory;

  static const String fileName = 'pending.jsonl';

  /// `%AppData%\…\logs-pending` — δίπλα στον τοπικό φάκελο του ίχνους
  /// κλεισίματος.
  static Future<String> defaultDirectory() async {
    final support = await getApplicationSupportDirectory();
    return p.join(support.path, 'logs-pending');
  }

  String get _path => p.join(directory, fileName);

  /// Προσθήκη και μεταφορά δεν τρέχουν ποτέ ταυτόχρονα: μια εγγραφή που
  /// έρχεται στη μέση της μεταφοράς δεν σβήνεται από το ξαναγράψιμο.
  Future<void> _chain = Future<void>.value();

  Future<T> _serial<T>(Future<T> Function() operation) {
    final next = _chain.then((_) => operation());
    _chain = next.then((_) {}, onError: (Object _) {});
    return next;
  }

  /// Κρατά μία γραμμή του ημερολογίου. Επιστρέφει αν κρατήθηκε.
  Future<bool> add({
    required String logsDirectory,
    required String dailyFileName,
    required String content,
  }) {
    return _serial(() async {
      try {
        await Directory(directory).create(recursive: true);
        await File(_path).writeAsString(
          '${jsonEncode({'dir': logsDirectory, 'file': dailyFileName, 'content': content})}\n',
          mode: FileMode.append,
          flush: true,
        );
        return true;
      } catch (_) {
        return false;
      }
    });
  }

  /// Στέλνει στον [logsDirectory] όσα γράφτηκαν γι' αυτόν, ένα ημερήσιο αρχείο
  /// τη φορά. Ό,τι γράφτηκε φεύγει· ό,τι απέτυχε ή ανήκει σε άλλον φάκελο
  /// μένει για την επόμενη ευκαιρία.
  ///
  /// Εγγραφές ημέρας παλαιότερης από το [oldestKept] σβήνονται χωρίς να
  /// σταλούν: το ημερολόγιο δεν τις κρατά πια, οπότε θα είχαν σβηστεί έτσι κι
  /// αλλιώς — και για φάκελο που δεν ξαναγύρισε ποτέ, δεν περιμένουν για
  /// πάντα.
  ///
  /// Επιστρέφει πόσες γραμμές έφτασαν.
  Future<int> drainTo({
    required String logsDirectory,
    required DateTime oldestKept,
    required Future<bool> Function(String path, String content) write,
  }) {
    return _serial(() async {
      final file = File(_path);
      List<String> lines;
      try {
        if (!await file.exists()) return 0;
        lines = await file.readAsLines();
      } catch (_) {
        return 0;
      }

      final kept = <String>[];
      final mine = <String, List<String>>{};
      for (final line in lines) {
        final entry = _SpilledLine.tryParse(line);
        if (entry == null) continue;
        final day = LogFileNames.dayOfLogFile(entry.dailyFileName);
        if (day != null && day.isBefore(oldestKept)) continue;
        if (p.equals(entry.logsDirectory, logsDirectory)) {
          mine.putIfAbsent(entry.dailyFileName, () => []).add(line);
        } else {
          kept.add(line);
        }
      }

      var moved = 0;
      for (final MapEntry(key: dailyFileName, value: group) in mine.entries) {
        final content = [
          for (final line in group) _SpilledLine.tryParse(line)!.content,
        ].join();
        if (await write(p.join(logsDirectory, dailyFileName), content)) {
          moved += group.length;
        } else {
          kept.addAll(group);
        }
      }

      try {
        if (kept.isEmpty) {
          await file.delete();
        } else if (kept.length != lines.length) {
          await file.writeAsString(
            '${kept.join('\n')}\n',
            mode: FileMode.write,
            flush: true,
          );
        }
      } catch (_) {
        // Αν το ξαναγράψιμο αποτύχει, όσα στάλθηκαν θα ξανασταλούν: διπλή
        // γραμμή στο ημερολόγιο είναι μικρότερο κακό από χαμένη.
      }
      return moved;
    });
  }
}

class _SpilledLine {
  const _SpilledLine(this.logsDirectory, this.dailyFileName, this.content);

  final String logsDirectory;
  final String dailyFileName;
  final String content;

  static _SpilledLine? tryParse(String line) {
    if (line.trim().isEmpty) return null;
    try {
      final data = jsonDecode(line);
      if (data is! Map<String, Object?>) return null;
      final dir = data['dir'];
      final file = data['file'];
      final content = data['content'];
      if (dir is! String || file is! String || content is! String) {
        return null;
      }
      return _SpilledLine(dir, file, content);
    } catch (_) {
      return null;
    }
  }
}
