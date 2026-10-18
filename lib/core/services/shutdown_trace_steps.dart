import 'shutdown_trace_incident.dart';

/// Πώς τελείωσε ένα βήμα του κλεισίματος.
enum ShutdownTraceStepOutcome {
  completed,
  failed,

  /// Το έκοψε το όριο ασφαλείας — κολλημένο βήμα.
  interrupted,

  /// Ξεκίνησε και δεν έγραψε ποτέ τέλος: η εφαρμογή πέθανε εκεί.
  unfinished,
}

/// Ένα βήμα του κλεισίματος, όπως το διαβάζει ο άνθρωπος.
class ShutdownTraceStep {
  const ShutdownTraceStep({
    required this.label,
    required this.outcome,
    this.durationMs,
    this.error,
  });

  final String label;
  final ShutdownTraceStepOutcome outcome;
  final int? durationMs;
  final String? error;

  /// Η έκβαση σε λίγες λέξεις: «18,0 δευτ.», «διακόπηκε», «απέτυχε (2 ms)».
  String get resultText {
    final duration = durationMs == null
        ? null
        : ShutdownTraceIncident.formatDuration(durationMs!);
    return switch (outcome) {
      ShutdownTraceStepOutcome.completed => duration ?? 'ολοκληρώθηκε',
      ShutdownTraceStepOutcome.failed =>
        duration == null ? 'απέτυχε' : 'απέτυχε ($duration)',
      ShutdownTraceStepOutcome.interrupted => 'διακόπηκε',
      ShutdownTraceStepOutcome.unfinished => 'δεν ολοκληρώθηκε',
    };
  }
}

/// Το περιστατικό ως απλό κείμενο, για αντιγραφή: η σύνοψη και ένα βήμα ανά
/// γραμμή — αυτό που βλέπει ο χρήστης στο παράθυρο, όχι το ωμό ίχνος.
String shutdownIncidentPlainText(ShutdownTraceIncident incident) {
  final lines = <String>[incident.describeEvent()];
  for (final step in parseShutdownTraceSteps(incident.trace)) {
    lines.add('• ${step.label} — ${step.resultText}');
    final error = step.error?.trim() ?? '';
    if (error.isNotEmpty) lines.add('  $error');
  }
  return lines.join('\n');
}

final _stepLine = RegExp(
  r'step=(\d+) "([^"]*)" (START|OK|FAIL|INTERRUPTED)'
  r'(?: durationMs=(\d+))?(?: error=(.*))?$',
);

/// Τα βήματα ενός ίχνους κλεισίματος, με τη σειρά που ξεκίνησαν — ένα ανά
/// βήμα, με την τελική του έκβαση.
///
/// Το ίχνος γράφεται γραμμή-γραμμή την ώρα του κλεισίματος (ένα «START» και
/// ένα τέλος ανά βήμα). Γραμμές που δεν είναι βήματα — η αρχή, η σύνοψη που
/// περιμένει το ημερολόγιο — αγνοούνται.
List<ShutdownTraceStep> parseShutdownTraceSteps(String trace) {
  final order = <int>[];
  final steps = <int, ShutdownTraceStep>{};
  for (final line in trace.split('\n')) {
    final match = _stepLine.firstMatch(line.trimRight());
    if (match == null) continue;
    final index = int.parse(match.group(1)!);
    final label = match.group(2)!;
    final outcome = switch (match.group(3)) {
      'OK' => ShutdownTraceStepOutcome.completed,
      'FAIL' => ShutdownTraceStepOutcome.failed,
      'INTERRUPTED' => ShutdownTraceStepOutcome.interrupted,
      _ => ShutdownTraceStepOutcome.unfinished,
    };
    if (!steps.containsKey(index)) order.add(index);
    steps[index] = ShutdownTraceStep(
      label: label,
      outcome: outcome,
      durationMs: int.tryParse(match.group(4) ?? ''),
      error: match.group(5),
    );
  }
  return [for (final index in order) steps[index]!];
}
