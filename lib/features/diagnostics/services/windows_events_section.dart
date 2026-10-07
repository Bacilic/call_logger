import '../models/windows_events.dart';
import 'report_format.dart';

/// Η ενότητα «Συμβάντα Windows» του αρχείου διαγνωστικών.
///
/// Λέει πάντα **από ποιον υπολογιστή** είναι τα συμβάντα (μόνο αυτόν που
/// έκανε την εξαγωγή) και **πόσο πίσω** έφτασαν τα Windows: κρατούν ανά
/// μέγεθος, όχι ανά ημέρες, οπότε περίοδος 60 ημερών μπορεί να καλυφθεί
/// μόνο εν μέρει.
///
/// Τα [appGaps] είναι τα κενά πριν από κάθε απότομο τέλος της εφαρμογής (από
/// το τελευταίο σημάδι ζωής ως την επόμενη εκκίνηση): ένα κανονικό κλείσιμο
/// του υπολογιστή μέσα σε τέτοιο κενό **εξηγεί** το απότομο τέλος, οπότε
/// γράφεται αναλυτικά — όλα τα υπόλοιπα κανονικά κλεισίματα είναι ρουτίνα.
void writeWindowsEventsSection(
  StringBuffer out,
  WindowsEventsReport report, {
  List<(DateTime, DateTime)> appGaps = const [],
}) {
  final levels = WindowsEventLevel.selectable
      .where(report.levels.contains)
      .map((level) => level.label.toLowerCase())
      .join(', ');
  out
    ..writeln('## Συμβάντα Windows — υπολογιστής ${report.station}')
    ..writeln()
    ..writeln(
      '- **Περίοδος:** ${reportDay(report.from)} – ${reportDay(report.to)}',
    )
    ..writeln(
      '- **Επίπεδα γενικών συμβάντων:** ${levels.isEmpty ? 'κανένα' : levels}',
    );
  for (final entry in report.oldestByLog.entries) {
    final oldest = entry.value;
    final covers = oldest == null
        ? 'δεν διαβάστηκε'
        : oldest.isAfter(report.from)
        ? 'από ${reportMoment(oldest)} — **νωρίτερα δεν υπάρχουν στοιχεία**, '
              'τα Windows τα έχουν ήδη σβήσει'
        : 'από ${reportDay(oldest)}';
    out.writeln('- **Ημερολόγιο ${entry.key}:** $covers');
  }
  final failure = report.failure;
  if (failure != null) {
    out.writeln('- **Δεν διαβάστηκαν όλα:** $failure');
  }
  out.writeln();

  out
    ..writeln('### Συμβάντα της εφαρμογής (σε κάθε επίπεδο)')
    ..writeln();
  if (report.appEvents.isEmpty) {
    out.writeln(
      'Κανένα — τα Windows δεν κατέγραψαν κατάρρευση, πάγωμα ή αναφορά '
      'σφάλματος για την εφαρμογή στην περίοδο.',
    );
  }
  for (final event in report.appEvents) {
    out
      ..writeln(
        '- ${reportMoment(event.time)} · ${event.provider} ${event.eventId} · '
        '${event.level.label}',
      )
      ..writeln()
      ..writeln(fenced(event.message))
      ..writeln();
  }
  out.writeln();

  out
    ..writeln('### Κλεισίματα, εκκινήσεις και διακοπές ρεύματος')
    ..writeln();
  final routine = report.computerLifecycle.where(_isRoutine).toList();
  final starts = routine.where((e) => e.eventId == 12).length;
  final requested = routine.length - starts;
  out.writeln(
    '- **Ρουτίνα της περιόδου:** $starts εκκινήσεις των Windows, '
    '$requested κλεισίματα/επανεκκινήσεις κατόπιν αιτήματος.',
  );
  final notable = [
    for (final event in report.computerLifecycle)
      if (!_isRoutine(event) || _insideAnyGap(event.time, appGaps)) event,
  ];
  if (notable.isEmpty) {
    out.writeln(
      '- Καμία διακοπή ρεύματος ή απρόσμενο κλείσιμο του υπολογιστή, και '
      'κανένα κλείσιμο κοντά σε απότομο τέλος της εφαρμογής.',
    );
  }
  for (final event in notable) {
    final near = _isRoutine(event)
        ? ' (κοντά σε απότομο τέλος της εφαρμογής)'
        : '';
    out.writeln(
      '- ${reportMoment(event.time)} · ${_lifecycleLabel(event)}$near · '
      '${oneLine(event.message)}',
    );
  }
  out.writeln();

  out
    ..writeln('### Υπόλοιπα συμβάντα, ομαδοποιημένα ανά είδος')
    ..writeln();
  if (report.groups.isEmpty) {
    out.writeln('Κανένα.');
  }
  for (final group in report.groups) {
    out.writeln(
      '- ${group.log} · ${group.provider} ${group.eventId} · '
      '${group.level.label} · ${group.count} '
      '${group.count == 1 ? 'φορά' : 'φορές'} · '
      '${reportMoment(group.firstSeen)} → ${reportMoment(group.lastSeen)} — '
      '${oneLine(group.sampleMessage)}',
    );
  }
  out.writeln();
}

/// Οι γραμμές των Windows που μπαίνουν στο κοινό χρονολόγιο: όσα αφορούν την
/// εφαρμογή και ό,τι έκλεισε ή ξεκίνησε τον υπολογιστή. Τα ομαδοποιημένα
/// μένουν έξω — θα έπνιγαν τη σειρά των γεγονότων.
///
/// Μόνο ό,τι περνά το [include] — η περίοδος **της εφαρμογής**. Το χρονολόγιο
/// δείχνει τι έγινε λίγο πριν από τι· πενήντα ημέρες κλεισιμάτων χωρίς καμία
/// εγγραφή της εφαρμογής δεν απαντούν σε αυτό.
///
/// Τα κανονικά ανοίγματα και κλεισίματα του υπολογιστή είναι ρουτίνα· στο
/// χρονολόγιο μπαίνουν μόνο όταν πέφτουν μέσα σε κάποιο από τα [appGaps]
/// — τότε εξηγούν ένα απότομο τέλος της εφαρμογής.
List<(DateTime, String)> windowsTimelineEntries(
  WindowsEventsReport report, {
  required bool Function(DateTime moment) include,
  List<(DateTime, DateTime)> appGaps = const [],
}) => [
  for (final event in report.appEvents)
    if (include(event.time))
      (
        event.time,
        'WINDOWS · ${event.provider} ${event.eventId}: '
            '${oneLine(event.message, max: 160)}',
      ),
  for (final event in report.computerLifecycle)
    if (include(event.time) &&
        (!_isRoutine(event) || _insideAnyGap(event.time, appGaps)))
      (event.time, 'WINDOWS · ${_lifecycleLabel(event)}'),
];

/// Κανονικό άνοιγμα ή κλείσιμο του υπολογιστή — συμβαίνει καθημερινά.
bool _isRoutine(WindowsEventEntry event) =>
    (event.provider == 'User32' && event.eventId == 1074) ||
    (event.provider == 'Microsoft-Windows-Kernel-General' &&
        event.eventId == 12);

/// Περιθώριο γύρω από κάθε κενό: το σημάδι ζωής γράφεται ανά λεπτό, και το
/// κλείσιμο των Windows καταγράφεται λίγο πριν σβήσει η εφαρμογή.
const Duration _gapMargin = Duration(minutes: 5);

bool _insideAnyGap(DateTime moment, List<(DateTime, DateTime)> gaps) =>
    gaps.any(
      (gap) =>
          !moment.isBefore(gap.$1.subtract(_gapMargin)) &&
          !moment.isAfter(gap.$2.add(_gapMargin)),
    );

String _lifecycleLabel(WindowsEventEntry event) =>
    switch ((event.provider, event.eventId)) {
      ('Microsoft-Windows-Kernel-Power', 41) =>
        'ΔΙΑΚΟΠΗ ΡΕΥΜΑΤΟΣ ή κλείσιμο χωρίς τερματισμό',
      ('EventLog', 6008) => 'ΑΠΡΟΣΜΕΝΟ ΚΛΕΙΣΙΜΟ του υπολογιστή',
      ('User32', 1074) => 'κλείσιμο/επανεκκίνηση κατόπιν αιτήματος',
      ('Microsoft-Windows-Kernel-General', 12) => 'εκκίνηση των Windows',
      _ => '${event.provider} ${event.eventId}',
    };
