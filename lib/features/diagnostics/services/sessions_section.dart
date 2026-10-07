import '../../../core/services/log_record.dart';
import '../../../core/services/session_liveness_mark.dart';
import '../../../core/services/shutdown_trace_incident.dart';
import 'report_format.dart';

/// Ένα άνοιγμα της εφαρμογής σε έναν υπολογιστή: από την εκκίνηση ως το
/// τέλος του — όπως κι αν ήρθε το τέλος.
///
/// Ενώνει σε μία γραμμή όσα ήταν σκόρπια: την εκκίνηση με τα βήματά της, το
/// προβληματικό κλείσιμο, και το απότομο τέλος — που το γράφει η **επόμενη**
/// εκκίνηση, γιατί η εκτέλεση που χάθηκε δεν πρόλαβε να το πει.
class AppSession {
  AppSession(this.begin);

  final LogRecord begin;
  final List<LogRecord> steps = [];
  LogRecord? ready;
  int retries = 0;

  /// Η αναφορά της επόμενης εκκίνησης ότι αυτή η εκτέλεση χάθηκε.
  LogRecord? lost;

  /// Το αργό ή αποτυχημένο κλείσιμο αυτής της εκτέλεσης.
  LogRecord? troubledClose;

  /// Ξεκίνησε άλλη συνεδρία μετά — άρα αυτή τελείωσε κάπως.
  bool hasSuccessor = false;

  /// Οι αλλαγές βάσης μέσα στη συνεδρία, ενώ η εφαρμογή ήταν ήδη έτοιμη.
  final List<DatabaseChange> databaseChanges = [];

  /// Η συνεδρία μετακόμισε σε φάκελο άλλης βάσης — δεν έκλεισε εδώ.
  LogRecord? movedAway;

  /// Η αρχή της γράφτηκε σε άλλον φάκελο· εδώ ήρθε με αλλαγή βάσης.
  bool get continued => begin.data['continued'] == true;

  /// Το τελευταίο «έτοιμη», είτε της εκκίνησης είτε της τελευταίας αλλαγής.
  LogRecord? get latestReady =>
      databaseChanges.isEmpty ? ready : databaseChanges.last.ready;

  String get station => begin.station;

  DateTime? get lastSeen =>
      DateTime.tryParse(lost?.data['last_seen']?.toString() ?? '');
}

/// Νέα αρχικοποίηση ενώ η εφαρμογή ήταν ήδη έτοιμη: άλλαξε η βάση (αλλαγή
/// βάσης, επαναφορά αντιγράφου, «ξεκίνα από την αρχή»). Δεν είναι προσπάθεια.
class DatabaseChange {
  DatabaseChange(this.time);

  final DateTime time;
  LogRecord? ready;
}

/// Οι συνεδρίες μιας περιόδου, και τα απότομα τέλη εκτελέσεων **χωρίς
/// καταγεγραμμένη εκκίνηση** — άρχισαν πριν από την περίοδο, ή η εκκίνησή
/// τους γράφτηκε από παλιά έκδοση, πριν από τη μορφή μίας εγγραφής ανά γραμμή.
class AppSessions {
  const AppSessions(this.sessions, this.orphanEnds);

  final List<AppSession> sessions;
  final List<LogRecord> orphanEnds;
}

/// Χτίζει τις συνεδρίες από τις εγγραφές, σε χρονολογική σειρά.
///
/// Το απότομο τέλος γράφεται στην αρχή της επόμενης εκκίνησης, **πριν** από
/// τη δική της εγγραφή αρχής — οπότε ανήκει στη συνεδρία που τρέχει ακόμη
/// τη στιγμή που το συναντάμε.
AppSessions buildAppSessions(Iterable<LogRecord> records) {
  final sessions = <AppSession>[];
  final orphans = <LogRecord>[];
  final current = <String, AppSession>{};
  for (final record in records) {
    final open = current[record.station];
    switch (record.kind) {
      case LogKind.abnormalEnd:
        if (open != null && open.lost == null) {
          open.lost = record;
        } else {
          orphans.add(record);
        }
      case LogKind.startup:
        switch (record.data['phase']) {
          case 'begin':
            open?.hasSuccessor = true;
            final session = AppSession(record);
            sessions.add(session);
            current[record.station] = session;
          case 'step':
            open?.steps.add(record);
          case 'end':
            if (open == null) break;
            if (open.databaseChanges.isEmpty) {
              open.ready = record;
            } else {
              open.databaseChanges.last.ready = record;
            }
          case 'retry':
          case 'reinit':
            if (open != null) _newInitialization(open, record);
          case 'moved':
            open?.movedAway = record;
        }
      case LogKind.shutdown:
        if (open != null) open.troubledClose ??= record;
      case LogKind.error:
      case LogKind.repeat:
        break;
    }
  }
  return AppSessions(sessions, orphans);
}

/// Νέα αρχικοποίηση μέσα σε συνεδρία: προσπάθεια ή αλλαγή βάσης;
///
/// Κρίνεται από την προηγούμενη έκβαση, όχι από τη φάση που γράφτηκε: τα
/// αρχεία πριν από τη φάση `reinit` έγραφαν «νέα προσπάθεια» και για την
/// αλλαγή βάσης, και διαβάζονται κι αυτά σωστά.
void _newInitialization(AppSession session, LogRecord record) {
  final latest = session.latestReady;
  if (latest == null) {
    // Συνέχεια που μόλις ήρθε από άλλη βάση: η αλλαγή είναι ήδη γνωστή.
    if (record.data['phase'] == 'retry') session.retries++;
    return;
  }
  if (latest.data['success'] == true) {
    session.databaseChanges.add(DatabaseChange(record.time));
  } else {
    session.retries++;
  }
}

/// Τα κενά πριν από κάθε απότομο τέλος: από το τελευταίο σημάδι ζωής ως την
/// εκκίνηση που το ανέφερε. Εκεί ψάχνει κανείς στα Windows γιατί χάθηκε.
List<(DateTime, DateTime)> abnormalEndGaps(Iterable<LogRecord> records) => [
  for (final record in records)
    if (record.kind == LogKind.abnormalEnd)
      if (DateTime.tryParse(record.data['last_seen']?.toString() ?? '')
          case final lastSeen?)
        (lastSeen, record.time),
];

void writeSessionsSection(StringBuffer out, AppSessions all) {
  out
    ..writeln('## Συνεδρίες της εφαρμογής')
    ..writeln()
    ..writeln(
      'Κάθε άνοιγμα της εφαρμογής μία φορά: πόσο άργησε να είναι έτοιμη, τα '
      'τρία πιο αργά βήματα, όσα βήματα δεν πήγαν καλά, και πώς τελείωσε.',
    )
    ..writeln();
  if (all.sessions.isEmpty && all.orphanEnds.isEmpty) {
    out
      ..writeln('Καμία συνεδρία στην περίοδο.')
      ..writeln();
    return;
  }
  for (final record in all.orphanEnds) {
    out.writeln(
      '- ${reportMoment(record.time)} · ${record.station} · ΑΠΟΤΟΜΟ ΤΕΛΟΣ '
      'εκτέλεσης χωρίς καταγεγραμμένη εκκίνηση: ${record.message}',
    );
  }
  for (final session in all.sessions) {
    out.writeln(
      '- ${reportMoment(session.begin.time)} · ${session.station} · '
      'v${session.begin.version} · '
      '${session.continued ? 'συνέχεια από άλλη βάση · ' : ''}'
      '${_readiness(session)} · ${_ending(session)}',
    );
    final slowest = [...session.steps.where((s) => s.data['ms'] is int)]
      ..sort((a, b) => _msOf(b).compareTo(_msOf(a)));
    if (slowest.isNotEmpty) {
      final top = slowest
          .take(3)
          .map(
            (s) =>
                '${s.message} '
                '(${ShutdownTraceIncident.formatDuration(_msOf(s))})',
          )
          .join(', ');
      out.writeln('  - πιο αργά: $top');
    }
    for (final step in session.steps) {
      final status = step.data['status'];
      if (status == 'ok' || status == 'skipped') continue;
      final detail = step.details == null ? '' : ' — ${step.details}';
      out.writeln('  - $status: ${step.message}$detail');
    }
    final lastSeen = session.lastSeen;
    final lost = session.lost;
    if (lastSeen != null && lost != null) {
      out.writeln(
        '  - κενό που αξίζει έλεγχο στα Windows: ${reportMoment(lastSeen)} – '
        '${reportMoment(lost.time)}',
      );
    }
  }
  out.writeln();
}

/// Μία σύντομη γραμμή ανά συνεδρία για το χρονολόγιο — οι λεπτομέρειες
/// μένουν στην ενότητα των συνεδριών. Το απότομο τέλος μπαίνει στη στιγμή
/// του τελευταίου σημαδιού ζωής, εκεί όπου συναντά τα συμβάντα των Windows.
List<(DateTime, String)> sessionTimelineEntries(AppSessions all) => [
  for (final record in all.orphanEnds)
    (
      DateTime.tryParse(record.data['last_seen']?.toString() ?? '') ??
          record.time,
      '${record.station} · ΑΠΟΤΟΜΟ ΤΕΛΟΣ εκτέλεσης χωρίς καταγεγραμμένη '
          'εκκίνηση',
    ),
  for (final session in all.sessions) ...[
    (
      session.begin.time,
      '${session.station} · '
          '${session.continued ? 'ΣΥΝΕΔΡΙΑ συνεχίζει από άλλη βάση' : 'ΣΥΝΕΔΡΙΑ ξεκίνησε'}'
          ' · ${_readiness(session)}',
    ),
    for (final change in session.databaseChanges)
      (
        change.time,
        '${session.station} · άλλαξε βάση η συνεδρία της '
            '${_clock(session.begin.time)}',
      ),
    if (session.movedAway case final moved?)
      (
        moved.time,
        '${session.station} · η συνεδρία της ${_clock(session.begin.time)} '
            'συνέχισε σε άλλη βάση',
      ),
    if (session.lastSeen case final lastSeen?)
      (
        lastSeen,
        '${session.station} · ΑΠΟΤΟΜΟ ΤΕΛΟΣ της συνεδρίας της '
            '${_clock(session.begin.time)} (τελευταίο σημάδι ζωής)',
      ),
  ],
];

String _readiness(AppSession session) {
  final ready = session.ready;
  final retried = session.retries > 0
      ? ' (μετά από ${session.retries + 1} προσπάθειες)'
      : '';
  final changes = [
    for (final change in session.databaseChanges)
      ' · άλλαξε βάση ${_clock(change.time)}'
          '${change.ready == null ? '' : ' (${_outcome(change.ready!)})'}',
  ].join();
  if (ready == null) return 'η εκκίνηση δεν ολοκληρώθηκε$changes';
  return '${_outcome(ready)}$retried$changes';
}

String _outcome(LogRecord ready) {
  final total = ShutdownTraceIncident.formatDuration(
    _intOf(ready.data['total_ms']),
  );
  return ready.data['success'] == true
      ? 'έτοιμη σε $total'
      : 'η εκκίνηση ΑΠΕΤΥΧΕ μετά από $total';
}

String _ending(AppSession session) {
  final lastSeen = session.lastSeen;
  if (session.lost != null) {
    if (lastSeen == null) return 'ΤΕΛΕΙΩΣΕ ΑΠΟΤΟΜΑ';
    final lived = SessionLivenessMark.formatLifetime(
      lastSeen.difference(session.begin.time),
    );
    return 'ΤΕΛΕΙΩΣΕ ΑΠΟΤΟΜΑ — τελευταίο σημάδι ζωής ${_clock(lastSeen)}, '
        'έζησε $lived';
  }
  final troubled = session.troubledClose;
  if (troubled != null) {
    return 'έκλεισε με πρόβλημα ${_clock(troubled.time)}: ${troubled.message}';
  }
  if (session.movedAway case final moved?) {
    return 'συνέχισε σε άλλη βάση ${_clock(moved.time)}';
  }
  if (session.hasSuccessor) return 'έκλεισε ομαλά';
  return 'τελευταία συνεδρία — τρέχει ακόμη ή έκλεισε ομαλά';
}

String _clock(DateTime moment) => reportMoment(moment).split(' ').last;

int _msOf(LogRecord step) => _intOf(step.data['ms']);

int _intOf(Object? value) => value is int ? value : 0;
