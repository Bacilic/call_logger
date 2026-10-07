// Εξαγωγή διαγνωστικών: τι μπαίνει στο αρχείο, τι μένει έξω, και η ροή από
// το κουμπί ως το αρχείο στον δίσκο.
//
//   flutter test test/features/diagnostics/diagnostics_export_test.dart

import 'dart:io';

import 'package:call_logger/core/services/log_record.dart';
import 'package:call_logger/core/services/station_name.dart';
import 'package:call_logger/features/diagnostics/diagnostics_export_flow.dart';
import 'package:call_logger/features/diagnostics/models/diagnostics_export_options.dart';
import 'package:call_logger/features/diagnostics/models/windows_events.dart';
import 'package:call_logger/features/diagnostics/services/diagnostics_report_builder.dart';
import 'package:call_logger/features/diagnostics/services/log_archive_reader.dart';
import 'package:call_logger/features/diagnostics/services/report_format.dart';
import 'package:call_logger/features/diagnostics/services/windows_event_collector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../test_reporter.dart';

LogRecord _record(
  DateTime time,
  String station,
  LogKind kind, {
  LogSeverity severity = LogSeverity.nonCritical,
  String message = 'μήνυμα',
  String? details,
  Map<String, Object?> data = const {},
}) => LogRecord(
  time: time,
  kind: kind,
  severity: severity,
  message: message,
  details: details,
  data: data,
  station: station,
  version: '0.61.0',
);

final _context = DiagnosticsContext(
  exportedAt: DateTime(2026, 10, 5, 18, 40),
  station: 'PICINIO',
  appVersion: '0.61.0',
  windowsVersion: 'Windows 11',
  databasePath: r'\\POPINIO\CallLogger\Data Base\hospital.db',
);

DiagnosticsExportOptions _options({
  DateTime? from,
  DateTime? to,
  Set<String> stations = const {'PICINIO', 'POPINIO'},
  Set<DiagnosticsContent>? contents,
}) => DiagnosticsExportOptions(
  from: from ?? DateTime(2026, 10, 1),
  to: to ?? DateTime(2026, 10, 5),
  stations: stations,
  contents: contents ?? {...DiagnosticsContent.values},
);

String _build(List<LogRecord> records, DiagnosticsExportOptions options) =>
    buildDiagnosticsReport(
      archive: LogArchive(
        records: records,
        legacyFiles: const [],
        unreadableLines: 0,
      ),
      options: options,
      context: _context,
    );

void main() {
  group('Σύνθεση αρχείου', () {
    test('μόνο οι υπολογιστές που διαλέχτηκαν μπαίνουν στο αρχείο', () {
      final report = _build([
        _record(
          DateTime(2026, 10, 4, 9),
          'POPINIO',
          LogKind.error,
          message: 'Σφάλμα του POPINIO',
        ),
        _record(
          DateTime(2026, 10, 4, 10),
          'PICINIO',
          LogKind.error,
          message: 'Σφάλμα του PICINIO',
        ),
      ], _options(stations: {'POPINIO'}));

      expect(report, contains('Σφάλμα του POPINIO'));
      expect(
        report,
        isNot(contains('Σφάλμα του PICINIO')),
        reason: greekExpectMsg('Ζητήθηκε μόνο το ιστορικό του POPINIO'),
      );
      expect(report, isNot(contains('| PICINIO |')));
    });

    test('ό,τι είναι έξω από την περίοδο δεν μπαίνει', () {
      final report = _build([
        _record(
          DateTime(2026, 9, 20),
          'PICINIO',
          LogKind.error,
          message: 'Παλιό σφάλμα',
        ),
        _record(
          DateTime(2026, 10, 3),
          'PICINIO',
          LogKind.error,
          message: 'Σφάλμα της περιόδου',
        ),
      ], _options());

      expect(report, contains('Σφάλμα της περιόδου'));
      expect(report, isNot(contains('Παλιό σφάλμα')));
    });

    test('το ίδιο σφάλμα γράφεται μία φορά, με όλες τις επαναλήψεις του', () {
      final records = [
        for (var hour = 9; hour < 12; hour++)
          _record(
            DateTime(2026, 10, 4, hour),
            'PICINIO',
            LogKind.error,
            message: 'Null check operator used on a null value',
            details: '#0 TaskAnalyticsSummary.build (x.dart:10)',
          ),
        _record(
          DateTime(2026, 10, 4, 13),
          'PICINIO',
          LogKind.repeat,
          message: 'επαναλήφθηκε 100 φορές — …',
          data: {
            'count': 100,
            'error': 'Null check operator used on a null value',
          },
        ),
      ];
      final report = _build(records, _options());

      expect(
        'Null check operator used on a null value'.allMatches(report).length,
        // Μία φορά στην ομάδα, τρεις στο χρονολόγιο (μία ανά εμφάνιση).
        4,
      );
      expect(
        report,
        contains('103 φορές'),
        reason: greekExpectMsg(
          'Οι επαναλήψεις που κράτησε μόνο η σύνοψη μετρούν στο ίδιο σφάλμα',
        ),
      );
    });

    test('όταν τα αρχεία ξεκινούν μετά την περίοδο, το αρχείο το λέει', () {
      final report = buildDiagnosticsReport(
        archive: LogArchive(
          records: [_record(DateTime(2026, 10, 3), 'PICINIO', LogKind.error)],
          legacyFiles: const [],
          unreadableLines: 2,
        ),
        options: _options(from: DateTime(2026, 9, 1)),
        context: _context,
      );

      expect(
        report,
        contains('Πριν από αυτή την ημέρα **δεν υπάρχουν στοιχεία**'),
        reason: greekExpectMsg(
          '«Κανένα συμβάν» δεν πρέπει να διαβαστεί ως «δεν έγινε τίποτα»',
        ),
      );
      expect(report, contains('Γραμμές που δεν διαβάστηκαν:** 2'));
    });

    test('περιεχόμενο που δεν διαλέχτηκε λείπει εντελώς', () {
      final report = _build([
        _record(
          DateTime(2026, 10, 4, 8),
          'PICINIO',
          LogKind.startup,
          severity: LogSeverity.info,
          message: 'ΕΚΚΙΝΗΣΗ v0.61.0',
          data: {'phase': 'begin'},
        ),
        _record(
          DateTime(2026, 10, 4, 9),
          'PICINIO',
          LogKind.error,
          message: 'Σφάλμα',
        ),
      ], _options(contents: {DiagnosticsContent.nonCriticalErrors}));

      expect(report, isNot(contains('## Συνεδρίες')));
      expect(report, isNot(contains('ΕΚΚΙΝΗΣΗ v0.61.0')));
      expect(report, contains('Σφάλμα'));
    });

    test('η εκκίνηση συνοψίζεται με έκβαση, χρόνο και πιο αργά βήματα', () {
      final report = _build([
        _record(
          DateTime(2026, 10, 4, 8),
          'PICINIO',
          LogKind.startup,
          severity: LogSeverity.info,
          message: 'ΕΚΚΙΝΗΣΗ v0.61.0',
          data: {'phase': 'begin'},
        ),
        _record(
          DateTime(2026, 10, 4, 8),
          'PICINIO',
          LogKind.startup,
          severity: LogSeverity.warning,
          message: 'Έλεγχος ενημέρωσης',
          details: 'το δίκτυο δεν απάντησε',
          data: {'phase': 'step', 'status': 'warning', 'ms': 3000},
        ),
        _record(
          DateTime(2026, 10, 4, 8),
          'PICINIO',
          LogKind.startup,
          severity: LogSeverity.info,
          message: 'ΕΤΟΙΜΗ',
          data: {'phase': 'end', 'success': true, 'total_ms': 3300},
        ),
      ], _options());

      expect(report, contains('έτοιμη σε 3,3 δευτ.'));
      expect(report, contains('πιο αργά: Έλεγχος ενημέρωσης (3,0 δευτ.)'));
      expect(
        report,
        contains('warning: Έλεγχος ενημέρωσης — το δίκτυο δεν απάντησε'),
      );
    });

    test('στο παράρτημα μπαίνουν μόνο τα παλιά σφάλματα της περιόδου', () {
      final report = buildDiagnosticsReport(
        archive: LogArchive(
          records: const [],
          legacyFiles: [
            LegacyLogFile(
              name: 'errors_2026-10-02.log',
              day: DateTime(2026, 10, 2),
              content: '[2026-10-02 10:00:00] v0.60.0 ΚΡΙΣΙΜΟ\nπαλιό σφάλμα',
            ),
            LegacyLogFile(
              name: 'session_2026-10-02.log',
              day: DateTime(2026, 10, 2),
              content: '[2026-10-02 08:00:00] ΕΝΤΑΞΕΙ  Φόρτωση μηχανής SQLite',
            ),
            LegacyLogFile(
              name: 'errors_2026-09-01.log',
              day: DateTime(2026, 9, 1),
              content: 'εκτός περιόδου',
            ),
          ],
          unreadableLines: 0,
        ),
        options: _options(),
        context: _context,
      );

      expect(report, contains('## Παράρτημα — σφάλματα παλιάς μορφής'));
      expect(report, contains('παλιό σφάλμα'));
      expect(report, isNot(contains('εκτός περιόδου')));
      expect(
        report,
        isNot(contains('Φόρτωση μηχανής SQLite')),
        reason: greekExpectMsg(
          'Τα παλιά αρχεία συνεδριών ήταν το 80% του παραρτήματος· τις '
          'εκκινήσεις τις συνοψίζει ήδη η νέα μορφή',
        ),
      );
    });

    test('χωρίς κανένα συμβάν, το λέει ρητά', () {
      final report = _build(const [], _options());

      expect(report, contains('Κανένα συμβάν στην περίοδο.'));
    });
  });

  group('Ανάγνωση φακέλου', () {
    late Directory root;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('diagnostics_test_');
    });

    tearDown(() async {
      try {
        await root.delete(recursive: true);
      } catch (_) {}
    });

    test(
      'διαβάζει και τις δύο μορφές και προσπερνά τη μισογραμμένη γραμμή',
      () async {
        final good = _record(
          DateTime(2026, 10, 4, 9),
          'POPINIO',
          LogKind.error,
        ).toJsonLine();
        File(p.join(root.path, 'events_2026-10-04.jsonl')).writeAsStringSync(
          '$good\n{"time":"2026-10-04T10:00:00","kind":"err\n',
        );
        File(
          p.join(root.path, 'session_2026-10-03.log'),
        ).writeAsStringSync('παλιά συνεδρία');
        File(
          p.join(root.path, 'session_POPINIO_abcd1234.lock'),
        ).writeAsStringSync('ίχνος — όχι αρχείο ημέρας');

        final archive = await readLogArchive(root.path);

        expect(archive.records, hasLength(1));
        expect(archive.unreadableLines, 1);
        expect(archive.stations, ['POPINIO']);
        expect(archive.legacyFiles.map((f) => f.name), [
          'session_2026-10-03.log',
        ]);
        expect(archive.oldestDay, DateTime(2026, 10, 3));
      },
    );

    test('ανύπαρκτος φάκελος σημαίνει «καμία καταγραφή»', () async {
      final archive = await readLogArchive(p.join(root.path, 'δεν-υπάρχει'));
      expect(archive.records, isEmpty);
      expect(archive.oldestDay, isNull);
    });
  });

  group('Συμβάντα Windows', () {
    RawWindowsEvent raw({
      String log = 'Application',
      String provider = 'Κάποια πηγή',
      int id = 1,
      WindowsEventLevel level = WindowsEventLevel.error,
      DateTime? time,
      String data = '',
    }) => RawWindowsEvent(
      log: log,
      provider: provider,
      eventId: id,
      level: level,
      time: time ?? DateTime(2026, 10, 4, 12),
      dataText: data,
    );

    WindowsEventCollector collector({
      Set<WindowsEventLevel> levels = const {
        WindowsEventLevel.critical,
        WindowsEventLevel.error,
      },
    }) =>
        WindowsEventCollector(appExecutable: 'call_logger.exe', levels: levels);

    test('το συμβάν της εφαρμογής μπαίνει και σε επίπεδο «Πληροφορία»', () {
      final c = collector();
      c.add(
        raw(
          provider: 'Windows Error Reporting',
          id: 1001,
          level: WindowsEventLevel.information,
          data: 'RADAR_PRE_LEAK_64 | call_logger.exe | 0.46.0.66',
        ),
        () => 'Ελαττωματικός κάδος',
      );

      expect(
        c.appEvents.single.message,
        'Ελαττωματικός κάδος',
        reason: greekExpectMsg(
          'Το μόνο συμβάν της εφαρμογής στο σπίτι ήταν «Πληροφορία» — '
          'φίλτρο επιπέδου θα το έχανε',
        ),
      );
      expect(c.groups, isEmpty);
    });

    test('κλείσιμο του υπολογιστή μπαίνει πάντα, άλλη πληροφορία όχι', () {
      final c = collector();
      c.add(
        raw(
          log: 'System',
          provider: 'User32',
          id: 1074,
          level: WindowsEventLevel.information,
        ),
        () => 'Η διεργασία winlogon.exe εκκίνησε το Κλειστό',
      );
      c.add(
        raw(
          log: 'System',
          provider: 'EventLog',
          id: 6005,
          level: WindowsEventLevel.information,
        ),
        () => 'Η υπηρεσία καταγραφής συμβάντων έχει ξεκινήσει.',
      );

      expect(c.computerLifecycle, hasLength(1));
      expect(c.computerLifecycle.single.eventId, 1074);
      expect(c.groups, isEmpty);
    });

    test('το ίδιο είδος γίνεται μία ομάδα, με ένα μόνο μήνυμα-δείγμα', () {
      final c = collector();
      var formatted = 0;
      for (var day = 1; day <= 3; day++) {
        c.add(
          raw(provider: 'nvlddmkm', id: 153, time: DateTime(2026, 10, day)),
          () {
            formatted++;
            return 'Error occurred on GPUID';
          },
        );
      }

      final group = c.groups.single;
      expect(group.count, 3);
      expect(group.firstSeen, DateTime(2026, 10, 1));
      expect(group.lastSeen, DateTime(2026, 10, 3));
      expect(
        formatted,
        1,
        reason: greekExpectMsg(
          'Το μήνυμα ζητείται από τα Windows μία φορά ανά είδος — είναι το '
          'ακριβό κομμάτι της ανάγνωσης',
        ),
      );
    });

    test('επίπεδο που δεν διαλέχτηκε μένει έξω', () {
      final c = collector();
      c.add(raw(level: WindowsEventLevel.warning), () => 'προειδοποίηση');

      expect(c.groups, isEmpty);
    });

    test('τα συμβάντα της εφαρμογής μπαίνουν στο χρονολόγιο με τη σειρά', () {
      final report = buildDiagnosticsReport(
        archive: LogArchive(
          records: [
            _record(
              DateTime(2026, 10, 4, 9),
              'PICINIO',
              LogKind.abnormalEnd,
              severity: LogSeverity.critical,
              message: 'Η προηγούμενη εκτέλεση δεν τερμάτισε ομαλά',
            ),
          ],
          legacyFiles: const [],
          unreadableLines: 0,
        ),
        options: _options(),
        context: _context,
        windows: WindowsEventsReport(
          station: 'PICINIO',
          from: DateTime(2026, 9, 1),
          to: DateTime(2026, 10, 5),
          levels: {WindowsEventLevel.error},
          appEvents: [
            WindowsEventEntry(
              log: 'Application',
              provider: 'Application Hang',
              eventId: 1002,
              level: WindowsEventLevel.error,
              time: DateTime(2026, 10, 4, 8, 55),
              message: 'Το πρόγραμμα call_logger.exe σταμάτησε να αλληλεπιδρά',
            ),
          ],
          computerLifecycle: const [],
          groups: const [],
          oldestByLog: {'Application': DateTime(2026, 9, 20), 'System': null},
        ),
      );

      final timeline = report.substring(report.indexOf('## Χρονολόγιο'));
      final hang = timeline.indexOf('- 04/10/2026 08:55:00 · WINDOWS');
      final end = timeline.indexOf('- 04/10/2026 09:00:00 · PICINIO');
      expect(hang, isNonNegative);
      expect(
        hang,
        lessThan(end),
        reason: greekExpectMsg(
          'Το πάγωμα των Windows φαίνεται ΑΜΕΣΩΣ πριν από το απότομο τέλος',
        ),
      );
      expect(
        report,
        contains('νωρίτερα δεν υπάρχουν στοιχεία'),
        reason: greekExpectMsg(
          'Τα Windows κρατούν ως τις 20/09 — η περίοδος ζητούσε από 01/09',
        ),
      );
    });
  });

  group('Αναγνωσιμότητα αρχείου', () {
    WindowsEventEntry lifecycle(String provider, int id, DateTime time) =>
        WindowsEventEntry(
          log: 'System',
          provider: provider,
          eventId: id,
          level: WindowsEventLevel.information,
          time: time,
          message: '$provider $id',
        );

    String reportWith(List<WindowsEventEntry> events) => buildDiagnosticsReport(
      archive: LogArchive(
        records: [
          _record(
            DateTime(2026, 10, 4, 9),
            'PICINIO',
            LogKind.abnormalEnd,
            severity: LogSeverity.critical,
            message: 'Η προηγούμενη εκτέλεση δεν τερμάτισε ομαλά',
            data: {'last_seen': DateTime(2026, 10, 3, 22).toIso8601String()},
          ),
        ],
        legacyFiles: const [],
        unreadableLines: 0,
      ),
      options: _options(),
      context: _context,
      windows: WindowsEventsReport(
        station: 'PICINIO',
        from: DateTime(2026, 8, 7),
        to: DateTime(2026, 10, 5),
        levels: const {},
        appEvents: const [],
        computerLifecycle: events,
        groups: const [],
        oldestByLog: const {},
      ),
    );

    test('το χρονολόγιο μένει στην περίοδο της εφαρμογής', () {
      final report = reportWith([
        lifecycle('Microsoft-Windows-Kernel-Power', 41, DateTime(2026, 8, 20)),
        lifecycle('Microsoft-Windows-Kernel-Power', 41, DateTime(2026, 10, 2)),
      ]);
      final timeline = report.substring(report.indexOf('## Χρονολόγιο'));

      expect(timeline, contains('02/10/2026'));
      expect(
        timeline,
        isNot(contains('20/08/2026')),
        reason: greekExpectMsg(
          'Η εφαρμογή ζητήθηκε 01/10–05/10· ο Αύγουστος των Windows δεν '
          'λέει τι έγινε λίγο πριν από τι',
        ),
      );
      expect(
        report.substring(0, report.indexOf('## Χρονολόγιο')),
        contains('20/08/2026'),
        reason: greekExpectMsg('Στην ενότητα των Windows μένει κανονικά'),
      );
    });

    test('η ρουτίνα γίνεται πλήθος· αναλυτικά μόνο όσα εξηγούν κάτι', () {
      final report = reportWith([
        for (var day = 10; day < 20; day++) ...[
          lifecycle(
            'Microsoft-Windows-Kernel-General',
            12,
            DateTime(2026, 8, day, 7),
          ),
          lifecycle('User32', 1074, DateTime(2026, 8, day, 22)),
        ],
        lifecycle('User32', 1074, DateTime(2026, 10, 3, 22, 1)),
        lifecycle('EventLog', 6008, DateTime(2026, 9, 1)),
      ]);
      final section = report.substring(
        report.indexOf('### Κλεισίματα, εκκινήσεις'),
        report.indexOf('### Υπόλοιπα συμβάντα'),
      );

      expect(section, contains('10 εκκινήσεις των Windows, 11 κλεισίματα'));
      expect(section, isNot(contains('15/08/2026')));
      expect(section, contains('ΑΠΡΟΣΜΕΝΟ ΚΛΕΙΣΙΜΟ'));
      expect(
        section,
        contains(
          '03/10/2026 22:01:00 · κλείσιμο/επανεκκίνηση κατόπιν '
          'αιτήματος (κοντά σε απότομο τέλος της εφαρμογής)',
        ),
        reason: greekExpectMsg(
          'Ο υπολογιστής έκλεισε ενώ η εφαρμογή ήταν ανοιχτή — αυτό εξηγεί '
          'το απότομο τέλος',
        ),
      );
    });

    LogRecord begin(DateTime t) => _record(
      t,
      'PICINIO',
      LogKind.startup,
      severity: LogSeverity.info,
      message: 'ΕΚΚΙΝΗΣΗ v0.61.0',
      data: {'phase': 'begin'},
    );
    LogRecord ready(DateTime t) => _record(
      t,
      'PICINIO',
      LogKind.startup,
      severity: LogSeverity.info,
      message: 'ΕΤΟΙΜΗ',
      data: {'phase': 'end', 'success': true, 'total_ms': 3300},
    );
    const lostMessage = 'Η προηγούμενη εκτέλεση δεν τερμάτισε ομαλά (μήνυμα)';
    LogRecord lost(DateTime t, DateTime lastSeen) => _record(
      t,
      'PICINIO',
      LogKind.abnormalEnd,
      severity: LogSeverity.critical,
      message: lostMessage,
      data: {'last_seen': lastSeen.toIso8601String()},
    );

    test('κάθε άνοιγμα γράφεται μία φορά, μαζί με το πώς τελείωσε', () {
      final report = _build([
        begin(DateTime(2026, 10, 4, 8)),
        ready(DateTime(2026, 10, 4, 8, 0, 3)),
        begin(DateTime(2026, 10, 4, 10)),
        ready(DateTime(2026, 10, 4, 10, 0, 3)),
        lost(DateTime(2026, 10, 4, 12, 30), DateTime(2026, 10, 4, 12, 5)),
        begin(DateTime(2026, 10, 4, 12, 30)),
        ready(DateTime(2026, 10, 4, 12, 30, 3)),
      ], _options());

      final sessions = report.substring(
        report.indexOf('## Συνεδρίες'),
        report.indexOf('## Χρονολόγιο'),
      );
      expect(
        sessions,
        contains(
          '04/10/2026 08:00:00 · PICINIO · v0.61.0 · '
          'έτοιμη σε 3,3 δευτ. · έκλεισε ομαλά',
        ),
      );
      expect(
        sessions,
        contains(
          '04/10/2026 10:00:00 · PICINIO · v0.61.0 · έτοιμη σε 3,3 '
          'δευτ. · ΤΕΛΕΙΩΣΕ ΑΠΟΤΟΜΑ — τελευταίο σημάδι ζωής 12:05:00, '
          'έζησε 2 ώρες και 5 λεπτά',
        ),
        reason: greekExpectMsg(
          'Το απότομο τέλος το γράφει η ΕΠΟΜΕΝΗ εκκίνηση — ανήκει όμως στη '
          'συνεδρία που χάθηκε',
        ),
      );
      expect(sessions, contains('τελευταία συνεδρία'));
      expect(
        report,
        isNot(contains(lostMessage)),
        reason: greekExpectMsg(
          'Το μακρύ μήνυμα δεν επαναλαμβάνεται — η συνεδρία το λέει μία φορά',
        ),
      );

      final timeline = report.substring(report.indexOf('## Χρονολόγιο'));
      expect('ΣΥΝΕΔΡΙΑ ξεκίνησε'.allMatches(timeline), hasLength(3));
      expect(
        timeline,
        contains(
          '04/10/2026 12:05:00 · PICINIO · ΑΠΟΤΟΜΟ ΤΕΛΟΣ της '
          'συνεδρίας της 10:00:00',
        ),
        reason: greekExpectMsg(
          'Στο χρονολόγιο το απότομο τέλος μπαίνει στη στιγμή του τελευταίου '
          'σημαδιού ζωής, εκεί που συναντά τα Windows',
        ),
      );
    });

    String sessionsOf(String report) => report.substring(
      report.indexOf('## Συνεδρίες'),
      report.indexOf('## Χρονολόγιο'),
    );

    LogRecord startup(DateTime t, Map<String, Object?> data) => _record(
      t,
      'POPINIO',
      LogKind.startup,
      severity: LogSeverity.info,
      data: data,
    );

    test('αλλαγή βάσης μετά από επιτυχημένη εκκίνηση ΔΕΝ μετρά ως '
        'προσπάθεια', () {
      for (final phase in ['reinit', 'retry']) {
        final report = _build([
          startup(DateTime(2026, 10, 5, 19, 41, 47), {'phase': 'begin'}),
          startup(DateTime(2026, 10, 5, 19, 41, 48), {
            'phase': 'end',
            'success': true,
            'total_ms': 210,
          }),
          startup(DateTime(2026, 10, 5, 19, 42, 11), {'phase': phase}),
          startup(DateTime(2026, 10, 5, 19, 42, 14), {
            'phase': 'end',
            'success': true,
            'total_ms': 2500,
          }),
        ], _options());

        final sessions = sessionsOf(report);
        expect(
          sessions,
          isNot(contains('προσπάθειες')),
          reason: greekExpectMsg(
            'Φάση «$phase»: η πρώτη αρχικοποίηση πέτυχε — η δεύτερη ήταν '
            'αλλαγή βάσης, όχι επανάληψη μετά από αποτυχία',
          ),
        );
        expect(
          sessions,
          contains(
            'έτοιμη σε 210 ms · άλλαξε βάση 19:42:11 (έτοιμη σε 2,5 δευτ.)',
          ),
        );
      }
    });

    test('η επανάληψη μετά από ΑΠΟΤΥΧΙΑ μετρά ακόμη ως προσπάθεια', () {
      final report = _build([
        startup(DateTime(2026, 10, 5, 8), {'phase': 'begin'}),
        startup(DateTime(2026, 10, 5, 8, 0, 20), {
          'phase': 'end',
          'success': false,
          'total_ms': 20000,
        }),
        startup(DateTime(2026, 10, 5, 8, 1), {'phase': 'retry'}),
        startup(DateTime(2026, 10, 5, 8, 1, 3), {
          'phase': 'end',
          'success': true,
          'total_ms': 3000,
        }),
      ], _options());

      expect(
        sessionsOf(report),
        contains('έτοιμη σε 3,0 δευτ. (μετά από 2 προσπάθειες)'),
      );
    });

    test('η συνεδρία που ήρθε από άλλη βάση εμφανίζεται ως συνέχεια, και '
        'εκεί που έφυγε δεν «κλείνει ομαλά»', () {
      final arrived = _build([
        startup(DateTime(2026, 10, 5, 19, 42, 28), {
          'phase': 'begin',
          'continued': true,
        }),
        startup(DateTime(2026, 10, 5, 19, 42, 31), {
          'phase': 'end',
          'success': true,
          'total_ms': 2500,
        }),
      ], _options());
      expect(
        sessionsOf(arrived),
        contains(
          '05/10/2026 19:42:28 · POPINIO · v0.61.0 · συνέχεια από άλλη '
          'βάση · έτοιμη σε 2,5 δευτ.',
        ),
      );

      final left = _build([
        startup(DateTime(2026, 10, 5, 19, 40), {'phase': 'begin'}),
        startup(DateTime(2026, 10, 5, 19, 40, 1), {
          'phase': 'end',
          'success': true,
          'total_ms': 900,
        }),
        startup(DateTime(2026, 10, 5, 19, 42, 28), {'phase': 'moved'}),
        startup(DateTime(2026, 10, 5, 20), {'phase': 'begin'}),
      ], _options());
      final movedLine = sessionsOf(
        left,
      ).split('\n').singleWhere((line) => line.contains('19:40:00'));
      expect(movedLine, contains('συνέχισε σε άλλη βάση 19:42:28'));
      expect(
        movedLine,
        isNot(contains('έκλεισε ομαλά')),
        reason: greekExpectMsg(
          'Η συνεδρία δεν έκλεισε — μετακόμισε σε άλλη βάση',
        ),
      );
    });

    test('η ρουτίνα των Windows μένει έξω από το χρονολόγιο — εκτός αν '
        'εξηγεί απότομο τέλος', () {
      final report = buildDiagnosticsReport(
        archive: LogArchive(
          records: [
            begin(DateTime(2026, 10, 4, 10)),
            lost(DateTime(2026, 10, 4, 12, 30), DateTime(2026, 10, 4, 12, 5)),
            begin(DateTime(2026, 10, 4, 12, 30)),
          ],
          legacyFiles: const [],
          unreadableLines: 0,
        ),
        options: _options(),
        context: _context,
        windows: WindowsEventsReport(
          station: 'PICINIO',
          from: DateTime(2026, 10, 1),
          to: DateTime(2026, 10, 5),
          levels: const {},
          appEvents: const [],
          computerLifecycle: [
            WindowsEventEntry(
              log: 'System',
              provider: 'User32',
              eventId: 1074,
              level: WindowsEventLevel.information,
              time: DateTime(2026, 10, 3, 22),
              message: 'κανονικό κλείσιμο το βράδυ',
            ),
            WindowsEventEntry(
              log: 'System',
              provider: 'User32',
              eventId: 1074,
              level: WindowsEventLevel.information,
              time: DateTime(2026, 10, 4, 12, 6),
              message: 'κλείσιμο ενώ έτρεχε η εφαρμογή',
            ),
          ],
          groups: const [],
          oldestByLog: const {},
        ),
      );
      final timeline = report.substring(report.indexOf('## Χρονολόγιο'));

      expect(timeline, isNot(contains('03/10/2026 22:00:00')));
      expect(timeline, contains('04/10/2026 12:06:00 · WINDOWS'));
    });

    test('η σύνοψη λέει ότι τα σφάλματα παλιάς μορφής δεν μετρώνται', () {
      final report = buildDiagnosticsReport(
        archive: LogArchive(
          records: const [],
          legacyFiles: [
            LegacyLogFile(
              name: 'errors_2026-10-04.log',
              day: DateTime(2026, 10, 4),
              content: 'παλιό σφάλμα',
            ),
          ],
          unreadableLines: 0,
        ),
        options: _options(),
        context: _context,
      );

      expect(report, contains('μετρά **μόνο τη νέα μορφή**'));
      expect(report, contains('Κανένα σφάλμα στη νέα μορφή'));
    });

    test('οι στοίβες κόβονται, το υπόλοιπο κείμενο μένει', () {
      final text = [
        '[2026-10-04 12:00:17] v0.60.0 ΜΗ-ΚΡΙΣΙΜΟ',
        'type Null is not a subtype',
        for (var i = 0; i < 100; i++) '#$i      Frame.layout (x.dart:$i)',
        '',
        '[2026-10-04 12:05:00] v0.60.0 ΚΡΙΣΙΜΟ',
      ].join('\n');

      final trimmed = trimStackRuns(text, 40);

      expect(trimmed, contains('#39 '));
      expect(trimmed, isNot(contains('#40 ')));
      expect(trimmed, contains('… (+60 γραμμές στοίβας)'));
      expect(trimmed, contains('[2026-10-04 12:05:00] v0.60.0 ΚΡΙΣΙΜΟ'));
    });

    test('τα Windows 11 λέγονται Windows 11', () {
      expect(
        describeWindowsVersion('"Windows 10 Pro" 10.0 (Build 26300)'),
        'Windows 11 Pro 10.0 (Build 26300)',
      );
      expect(
        describeWindowsVersion('"Windows 10 Pro" 10.0 (Build 19045)'),
        'Windows 10 Pro 10.0 (Build 19045)',
      );
    });
  });

  group('Ροή εξαγωγής', () {
    late Directory root;

    setUp(() async {
      StationName.reader = () => 'PICINIO';
      root = await Directory.systemTemp.createTemp('diagnostics_flow_');
    });

    tearDown(() async {
      StationName.reader = StationName.defaultReader;
      try {
        await root.delete(recursive: true);
      } catch (_) {}
    });

    testWidgets(
      'κουμπί → οδηγός → «Εξαγωγή…» → το αρχείο γράφεται εκεί που διαλέχτηκε',
      (tester) async {
        final logs = Directory(p.join(root.path, 'logs'))..createSync();
        final now = DateTime.now();
        File(
          p.join(logs.path, 'events_${_stamp(now)}.jsonl'),
        ).writeAsStringSync(
          '${_record(now, 'PICINIO', LogKind.error, message: 'Σφάλμα δοκιμής ροής').toJsonLine()}\n',
        );
        final target = p.join(root.path, 'έξοδος.md');
        String? suggested;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () => runDiagnosticsExport(
                    context: context,
                    logsDirectory: logs.path,
                    databasePath: r'C:\Data Base\hospital.db',
                    readWindows: (request) async => WindowsEventsReport(
                      station: request.station,
                      from: request.from,
                      to: request.to,
                      levels: request.levels,
                      appEvents: const [],
                      computerLifecycle: const [],
                      groups: const [],
                      oldestByLog: const {'Application': null},
                    ),
                    pickSavePath: (name, _) async {
                      suggested = name;
                      return target;
                    },
                  ),
                  child: const Text('Εξαγωγή διαγνωστικών…'),
                ),
              ),
            ),
          ),
        );

        await tester.runAsync(() async {
          await tester.tap(find.text('Εξαγωγή διαγνωστικών…'));
          await Future<void>.delayed(const Duration(milliseconds: 300));
        });
        await tester.pumpAndSettle();
        expect(find.text('Εξαγωγή διαγνωστικών'), findsOneWidget);
        expect(find.text('PICINIO (αυτός)'), findsOneWidget);

        await tester.runAsync(() async {
          await tester.tap(find.text('Εξαγωγή…'));
          await tester.pump();
          await Future<void>.delayed(const Duration(milliseconds: 300));
        });
        await tester.pump();

        expect(suggested, 'Διαγνωστικά_PICINIO_${_stamp(now)}.md');
        final written = await tester.runAsync(
          () => File(target).readAsString(),
        );
        expect(written, contains('# Διαγνωστικά — Καταγραφή Κλήσεων'));
        expect(written, contains('Σφάλμα δοκιμής ροής'));
        expect(
          written,
          contains('## Συμβάντα Windows — υπολογιστής PICINIO'),
          reason: greekExpectMsg('Τα Windows είναι επιλεγμένα από προεπιλογή'),
        );
        expect(
          find.textContaining('Τα διαγνωστικά αποθηκεύτηκαν'),
          findsOneWidget,
        );
      },
    );
  });
}

String _stamp(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';
