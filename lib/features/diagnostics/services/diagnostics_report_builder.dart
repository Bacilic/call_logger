import '../../../core/services/log_record.dart';
import '../../../core/services/crash_log_service.dart';
import '../models/diagnostics_export_options.dart';
import '../models/windows_events.dart';
import 'log_archive_reader.dart';
import 'report_format.dart';
import 'sessions_section.dart';
import 'windows_events_section.dart';

/// Τα στοιχεία του υπολογιστή που κάνει την εξαγωγή — η κεφαλίδα του αρχείου.
class DiagnosticsContext {
  const DiagnosticsContext({
    required this.exportedAt,
    required this.station,
    required this.appVersion,
    required this.windowsVersion,
    required this.databasePath,
  });

  final DateTime exportedAt;
  final String station;
  final String appVersion;
  final String windowsVersion;
  final String databasePath;
}

/// Συνθέτει το αρχείο διαγνωστικών σε markdown.
///
/// **Ο αναγνώστης είναι ο βοηθός ΤΝ, όχι άνθρωπος.** Γι' αυτό:
/// 1. η κεφαλίδα λέει ρητά τι **δεν** καλύπτει το αρχείο (από πότε υπάρχουν
///    στοιχεία, πόσες γραμμές χάθηκαν), ώστε «κανένα συμβάν» να μη διαβαστεί
///    ψευδώς ως «δεν έγινε τίποτα»·
/// 2. κάθε διαφορετικό σφάλμα γράφεται μία φορά, με πλήθος και διάστημα — το
///    ίδιο σφάλμα σαράντα φορές δεν προσθέτει πληροφορία, μόνο όγκο·
/// 3. το χρονολόγιο έχει μία γραμμή ανά συμβάν, ώστε να φαίνεται τι έγινε
///    λίγο πριν από τι — μαζί με ό,τι κατέγραψαν τα Windows ([windows]).
String buildDiagnosticsReport({
  required LogArchive archive,
  required DiagnosticsExportOptions options,
  required DiagnosticsContext context,
  WindowsEventsReport? windows,
}) {
  final selected = archive.records.where(options.includes).toList();
  final errorGroups = _groupErrors(selected);
  final legacyErrorFiles = _legacyErrorFiles(archive, options);
  // Οι συνεδρίες χτίζονται από **όλες** τις εγγραφές της περιόδου: ένα
  // απότομο τέλος χρειάζεται την εκκίνηση στην οποία ανήκει, ακόμη κι αν οι
  // εκκινήσεις δεν ζητήθηκαν ως περιεχόμενο.
  final sessions =
      options.contents.contains(DiagnosticsContent.startups) ||
          options.contents.contains(DiagnosticsContent.criticalErrors)
      ? buildAppSessions(
          archive.records.where(
            (r) =>
                options.stations.contains(r.station) &&
                options.coversDay(r.time),
          ),
        )
      : null;
  final out = StringBuffer();

  _writeHeader(out, archive, options, context);
  _writeSummary(out, selected, options, legacyErrorFiles.length);
  if (options.contents.contains(DiagnosticsContent.criticalErrors) ||
      options.contents.contains(DiagnosticsContent.nonCriticalErrors)) {
    _writeErrors(out, errorGroups, legacyErrorFiles.length);
  }
  if (sessions != null) writeSessionsSection(out, sessions);
  if (options.contents.contains(DiagnosticsContent.shutdowns)) {
    _writeShutdowns(out, selected);
  }
  final gaps = windows == null
      ? const <(DateTime, DateTime)>[]
      : abnormalEndGaps(
          archive.records.where((r) => r.station == windows.station),
        );
  if (windows != null) {
    writeWindowsEventsSection(out, windows, appGaps: gaps);
  }
  _writeTimeline(out, selected, errorGroups, [
    if (sessions != null) ...sessionTimelineEntries(sessions),
    if (windows != null)
      ...windowsTimelineEntries(
        windows,
        include: options.coversDay,
        appGaps: gaps,
      ),
  ]);
  _writeLegacyAppendix(out, legacyErrorFiles);
  return out.toString();
}

void _writeHeader(
  StringBuffer out,
  LogArchive archive,
  DiagnosticsExportOptions options,
  DiagnosticsContext context,
) {
  final stations = options.stations.toList()..sort();
  final contents = DiagnosticsContent.values
      .where(options.contents.contains)
      .map((content) => content.label.toLowerCase())
      .join(', ');
  out
    ..writeln('# Διαγνωστικά — Καταγραφή Κλήσεων')
    ..writeln()
    ..writeln('## Πλαίσιο')
    ..writeln()
    ..writeln(
      '- **Εξαγωγή:** ${reportMoment(context.exportedAt)} από τον υπολογιστή '
      '${context.station}',
    )
    ..writeln('- **Έκδοση εφαρμογής:** ${context.appVersion}')
    ..writeln(
      '- **Windows:** ${describeWindowsVersion(context.windowsVersion)}',
    )
    ..writeln(
      '- **Βάση δεδομένων:** '
      '${context.databasePath.trim().isEmpty ? 'άγνωστη' : context.databasePath}',
    )
    ..writeln(
      '- **Περίοδος:** ${reportDay(options.from)} – ${reportDay(options.to)}',
    )
    ..writeln('- **Υπολογιστές:** ${stations.join(', ')}')
    ..writeln('- **Περιεχόμενο:** $contents');

  final oldest = archive.oldestDay;
  if (oldest == null) {
    out.writeln(
      '- **Διαθέσιμα αρχεία εφαρμογής:** κανένα — ο φάκελος δεν έχει ακόμη '
      'καταγραφές.',
    );
  } else if (oldest.isAfter(options.from)) {
    out.writeln(
      '- **Διαθέσιμα αρχεία εφαρμογής:** από ${reportDay(oldest)}. Πριν από αυτή '
      'την ημέρα **δεν υπάρχουν στοιχεία** (έχουν σβηστεί από τη ρύθμιση '
      'διατήρησης) — η απουσία συμβάντων εκεί δεν σημαίνει ότι δεν έγινε '
      'τίποτα.',
    );
  } else {
    out.writeln('- **Διαθέσιμα αρχεία εφαρμογής:** από ${reportDay(oldest)}');
  }
  if (archive.unreadableLines > 0) {
    out.writeln(
      '- **Γραμμές που δεν διαβάστηκαν:** ${archive.unreadableLines} '
      '(μισογραμμένες — συνήθως από κατάρρευση ή χαμένο δίκτυο τη στιγμή '
      'της εγγραφής)',
    );
  }
  out.writeln();
}

void _writeSummary(
  StringBuffer out,
  List<LogRecord> selected,
  DiagnosticsExportOptions options,
  int legacyErrorFileCount,
) {
  final columns = <(String, int Function(Iterable<LogRecord>))>[
    if (options.contents.contains(DiagnosticsContent.startups))
      ('Εκκινήσεις', (records) => records.where(_isStartupBegin).length),
    if (options.contents.contains(DiagnosticsContent.criticalErrors)) ...[
      (
        'Απότομα τέλη',
        (records) => records.where((r) => r.kind == LogKind.abnormalEnd).length,
      ),
      (
        'Κρίσιμα σφάλματα',
        (records) => records
            .where(
              (r) =>
                  r.kind == LogKind.error && r.severity == LogSeverity.critical,
            )
            .length,
      ),
    ],
    if (options.contents.contains(DiagnosticsContent.nonCriticalErrors))
      ('Μη κρίσιμα σφάλματα', _nonCriticalOccurrences),
    if (options.contents.contains(DiagnosticsContent.shutdowns))
      (
        'Προβληματικά κλεισίματα',
        (records) => records.where((r) => r.kind == LogKind.shutdown).length,
      ),
  ];
  out
    ..writeln('## Σύνοψη')
    ..writeln()
    ..writeln('| Υπολογιστής | ${columns.map((c) => c.$1).join(' | ')} |')
    ..writeln('|---|${columns.map((_) => '---:').join('|')}|');
  final stations = options.stations.toList()..sort();
  for (final station in stations) {
    final ofStation = selected.where((r) => r.station == station);
    out.writeln(
      '| $station | ${columns.map((c) => c.$2(ofStation)).join(' | ')} |',
    );
  }
  if (legacyErrorFileCount > 0) {
    out
      ..writeln()
      ..writeln(
        'Η σύνοψη μετρά **μόνο τη νέα μορφή** καταγραφής. Για την ίδια περίοδο '
        'υπάρχουν και $legacyErrorFileCount αρχεία σφαλμάτων παλιάς μορφής, '
        'ωμά στο παράρτημα — δεν μετρώνται εδώ.',
      );
  }
  out.writeln();
}

/// Οι μη κρίσιμες εμφανίσεις, μαζί με όσες κράτησαν μόνο οι συνόψεις
/// επαναλήψεων.
int _nonCriticalOccurrences(Iterable<LogRecord> records) {
  var count = 0;
  for (final record in records) {
    if (record.kind == LogKind.repeat) {
      count += _intOf(record.data['count']);
    } else if (record.kind == LogKind.error &&
        record.severity != LogSeverity.critical) {
      count++;
    }
  }
  return count;
}

/// Ένα διαφορετικό σφάλμα και όλες οι εμφανίσεις του.
class _ErrorGroup {
  _ErrorGroup(this.code, this.first);

  final String code;
  final LogRecord first;
  final Set<String> stations = {};
  int occurrences = 0;
  late DateTime firstSeen = first.time;
  late DateTime lastSeen = first.time;

  void add(LogRecord record, int count) {
    occurrences += count;
    stations.add(record.station);
    if (record.time.isBefore(firstSeen)) firstSeen = record.time;
    if (record.time.isAfter(lastSeen)) lastSeen = record.time;
  }
}

/// Ομαδοποιεί τα σφάλματα κατά μήνυμα και πρώτη γραμμή στοίβας — το ίδιο
/// κλειδί με το οποίο το ημερολόγιο αραιώνει τις επαναλήψεις.
Map<String, _ErrorGroup> _groupErrors(List<LogRecord> selected) {
  final groups = <String, _ErrorGroup>{};
  final byPreview = <String, _ErrorGroup>{};
  for (final record in selected.where((r) => r.kind == LogKind.error)) {
    final group = groups.putIfAbsent(
      _errorKey(record),
      () => _ErrorGroup('Σ${groups.length + 1}', record),
    );
    group.add(record, 1);
    byPreview.putIfAbsent(firstLineOf(record.message), () => group);
  }
  for (final record in selected.where((r) => r.kind == LogKind.repeat)) {
    final preview = record.data['error']?.toString() ?? record.message;
    final group =
        byPreview[firstLineOf(preview)] ??
        groups.putIfAbsent(
          'repeat\n$preview',
          () => _ErrorGroup('Σ${groups.length + 1}', record),
        );
    group.add(record, _intOf(record.data['count']));
  }
  return groups;
}

void _writeErrors(
  StringBuffer out,
  Map<String, _ErrorGroup> groups,
  int legacyErrorFileCount,
) {
  out
    ..writeln('## Διαφορετικά σφάλματα')
    ..writeln();
  if (groups.isEmpty) {
    out
      ..writeln(
        legacyErrorFileCount > 0
            ? 'Κανένα σφάλμα στη νέα μορφή — δείτε και το παράρτημα παλιάς '
                  'μορφής.'
            : 'Κανένα σφάλμα στην περίοδο.',
      )
      ..writeln();
    return;
  }
  final ordered = groups.values.toList()
    ..sort((a, b) => b.occurrences.compareTo(a.occurrences));
  for (final group in ordered) {
    final severity = group.first.severity == LogSeverity.critical
        ? 'κρίσιμο'
        : 'μη κρίσιμο';
    final stations = group.stations.toList()..sort();
    out
      ..writeln(
        '### ${group.code} — $severity · ${group.occurrences} '
        '${group.occurrences == 1 ? 'φορά' : 'φορές'} · '
        '${stations.join(', ')} · πρώτη ${reportMoment(group.firstSeen)} · '
        'τελευταία ${reportMoment(group.lastSeen)}',
      )
      ..writeln()
      ..writeln(fenced(group.first.message));
    final details = group.first.details;
    if (details != null && details.trim().isNotEmpty) {
      out.writeln(fenced(firstLinesOf(details, 40)));
    }
    out.writeln();
  }
}

void _writeShutdowns(StringBuffer out, List<LogRecord> selected) {
  final shutdowns = selected.where((r) => r.kind == LogKind.shutdown).toList();
  out
    ..writeln('## Προβληματικά κλεισίματα')
    ..writeln();
  if (shutdowns.isEmpty) {
    out
      ..writeln('Κανένα.')
      ..writeln();
    return;
  }
  for (final record in shutdowns) {
    out
      ..writeln(
        '### ${reportMoment(record.time)} · ${record.station} · ${record.message}',
      )
      ..writeln();
    final trace = record.details;
    if (trace != null && trace.trim().isNotEmpty) {
      out.writeln(fenced(trace.trimRight()));
    }
    out.writeln();
  }
}

void _writeTimeline(
  StringBuffer out,
  List<LogRecord> selected,
  Map<String, _ErrorGroup> groups,
  List<(DateTime, String)> otherEntries,
) {
  out
    ..writeln('## Χρονολόγιο')
    ..writeln()
    ..writeln(
      'Μία σύντομη γραμμή ανά συμβάν, με τη σειρά που έγιναν· οι λεπτομέρειες '
      'είναι στις ενότητες παραπάνω. Από τα Windows μπαίνουν μόνο όσα αφορούν '
      'την εφαρμογή, τα σπάνια (διακοπή ρεύματος, απρόσμενο κλείσιμο) και τα '
      'κλεισίματα κοντά σε απότομο τέλος.',
    )
    ..writeln();
  final entries = <(DateTime, String)>[
    for (final record in selected)
      if (_timelineLine(record, groups) case final line?)
        (record.time, '${record.station} · $line'),
    ...otherEntries,
  ];
  // Σταθερή ταξινόμηση: ό,τι συνέβη την ίδια στιγμή κρατά τη σειρά του.
  final ordered =
      [for (var i = 0; i < entries.length; i++) (index: i, entry: entries[i])]
        ..sort((a, b) {
          final byTime = a.entry.$1.compareTo(b.entry.$1);
          return byTime != 0 ? byTime : a.index.compareTo(b.index);
        });
  for (final item in ordered) {
    out.writeln('- ${reportMoment(item.entry.$1)} · ${item.entry.$2}');
  }
  if (ordered.isEmpty) out.writeln('Κανένα συμβάν στην περίοδο.');
  out.writeln();
}

String? _timelineLine(LogRecord record, Map<String, _ErrorGroup> groups) =>
    switch (record.kind) {
      // Εκκινήσεις και απότομα τέλη μπαίνουν ως συνεδρίες, μία φορά.
      LogKind.startup || LogKind.abnormalEnd => null,
      LogKind.error =>
        '${record.severity == LogSeverity.critical ? 'ΚΡΙΣΙΜΟ' : 'σφάλμα'} '
            '${groups[_errorKey(record)]?.code ?? ''}: '
            '${firstLineOf(record.message)}',
      LogKind.repeat => record.message,
      LogKind.shutdown => 'ΚΛΕΙΣΙΜΟ: ${record.message}',
    };

/// Μόνο τα παλιά αρχεία σφαλμάτων της περιόδου: εκεί είναι η ουσία. Τα παλιά
/// αρχεία συνεδριών είναι πίνακες βημάτων εκκίνησης — μετρημένα, το 80% του
/// παραρτήματος — και τις εκκινήσεις τις συνοψίζει ήδη η νέα μορφή.
List<LegacyLogFile> _legacyErrorFiles(
  LogArchive archive,
  DiagnosticsExportOptions options,
) => archive.legacyFiles
    .where(
      (file) =>
          file.name.startsWith(CrashLogService.legacyErrorLogPrefix) &&
          options.coversDay(file.day),
    )
    .toList();

void _writeLegacyAppendix(StringBuffer out, List<LegacyLogFile> files) {
  if (files.isEmpty) return;
  out
    ..writeln('## Παράρτημα — σφάλματα παλιάς μορφής')
    ..writeln()
    ..writeln(
      'Γραμμένα από έκδοση πριν από τη μορφή μίας εγγραφής ανά γραμμή. '
      'Μπαίνουν **ωμά, χωρίς φίλτρο υπολογιστή ή περιεχομένου**: οι παλιές '
      'εγγραφές σφαλμάτων δεν έγραφαν σταθμό. Τα παλιά αρχεία συνεδριών '
      '(βήματα εκκίνησης) μένουν έξω.',
    )
    ..writeln();
  for (final file in files) {
    out
      ..writeln('### ${file.name}')
      ..writeln()
      ..writeln(fenced(trimStackRuns(file.content.trimRight(), 40)))
      ..writeln();
  }
}

String _errorKey(LogRecord record) =>
    '${record.message}\n${firstLineOf(record.details)}';

bool _isStartupBegin(LogRecord record) =>
    record.kind == LogKind.startup && record.data['phase'] == 'begin';

int _intOf(Object? value) => value is int ? value : 0;
