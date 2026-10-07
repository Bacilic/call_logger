import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../core/services/crash_log_service.dart';
import '../../../core/services/log_record.dart';

/// Ένα ημερήσιο αρχείο της παλιάς μορφής κειμένου, όπως βρέθηκε.
class LegacyLogFile {
  const LegacyLogFile({
    required this.name,
    required this.day,
    required this.content,
  });

  final String name;
  final DateTime day;
  final String content;
}

/// Όλα όσα κρατά ο φάκελος των αρχείων καταγραφής, διαβασμένα **μία φορά**.
///
/// Από το ίδιο αρχείο τροφοδοτούνται και ο οδηγός (ποιοι υπολογιστές
/// υπάρχουν, από πότε υπάρχουν στοιχεία) και η εξαγωγή: έτσι ό,τι βλέπει ο
/// χρήστης στον οδηγό είναι ακριβώς ό,τι θα εξαχθεί.
class LogArchive {
  const LogArchive({
    required this.records,
    required this.legacyFiles,
    required this.unreadableLines,
  });

  static const LogArchive empty = LogArchive(
    records: [],
    legacyFiles: [],
    unreadableLines: 0,
  );

  /// Οι εγγραφές της τρέχουσας μορφής, σε χρονολογική σειρά.
  final List<LogRecord> records;

  /// Τα αρχεία της παλιάς μορφής, κατά ημέρα.
  final List<LegacyLogFile> legacyFiles;

  /// Γραμμές που δεν ήταν έγκυρες εγγραφές — μισογραμμένες από κατάρρευση
  /// ή χαμένο δίκτυο τη στιγμή της εγγραφής.
  final int unreadableLines;

  /// Οι υπολογιστές που έγραψαν, αλφαβητικά.
  List<String> get stations {
    final names = {
      for (final record in records)
        if (record.station.isNotEmpty) record.station,
    }.toList()..sort();
    return names;
  }

  /// Η παλαιότερη ημέρα για την οποία υπάρχει οποιοδήποτε αρχείο.
  DateTime? get oldestDay {
    final days = [
      for (final record in records)
        DateTime(record.time.year, record.time.month, record.time.day),
      for (final file in legacyFiles) file.day,
    ];
    if (days.isEmpty) return null;
    return days.reduce((a, b) => a.isBefore(b) ? a : b);
  }
}

/// Διαβάζει τα ημερήσια αρχεία του φακέλου — και των δύο μορφών.
///
/// Ο φάκελος είναι συχνά στο δίκτυο: κάθε ανάγνωση έχει όριο χρόνου, ώστε
/// ένας διακομιστής που δεν απαντά να γίνει μήνυμα και όχι παγωμένος οδηγός.
/// Ανύπαρκτος φάκελος σημαίνει απλώς «καμία καταγραφή ακόμη».
Future<LogArchive> readLogArchive(
  String logsDirectory, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  final dir = Directory(logsDirectory);
  if (!await dir.exists().timeout(timeout)) return LogArchive.empty;

  final files = await dir
      .list()
      .where((entity) => entity is File)
      .cast<File>()
      .toList()
      .timeout(timeout);
  files.sort((a, b) => p.basename(a.path).compareTo(p.basename(b.path)));

  final records = <LogRecord>[];
  final legacy = <LegacyLogFile>[];
  var unreadable = 0;
  for (final file in files) {
    final name = p.basename(file.path);
    final day = CrashLogService.dayOfLogFile(name);
    if (day == null) continue;
    final content = await file
        .readAsString(encoding: const Utf8Codec(allowMalformed: true))
        .timeout(timeout);
    if (CrashLogService.isDailyLogFileName(name)) {
      for (final line in const LineSplitter().convert(content)) {
        if (line.trim().isEmpty) continue;
        final record = LogRecord.tryParse(line);
        if (record == null) {
          unreadable++;
        } else {
          records.add(record);
        }
      }
    } else if (CrashLogService.isLegacyDailyLogFileName(name)) {
      legacy.add(LegacyLogFile(name: name, day: day, content: content));
    }
  }
  // Σταθερή ταξινόμηση: εγγραφές της ίδιας στιγμής κρατούν τη σειρά του
  // αρχείου, που είναι η σειρά που γράφτηκαν.
  final ordered =
      [for (var i = 0; i < records.length; i++) (index: i, record: records[i])]
        ..sort((a, b) {
          final byTime = a.record.time.compareTo(b.record.time);
          return byTime != 0 ? byTime : a.index.compareTo(b.index);
        });
  return LogArchive(
    records: [for (final entry in ordered) entry.record],
    legacyFiles: legacy,
    unreadableLines: unreadable,
  );
}
