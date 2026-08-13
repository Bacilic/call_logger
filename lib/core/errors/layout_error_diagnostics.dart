import 'package:flutter/foundation.dart';

/// True αν το μήνυμα περιγράφει σφάλμα διάταξης (overflow / RenderBox).
bool isLayoutErrorMessage(String message) {
  final lower = message.toLowerCase();
  return lower.contains('overflowed') ||
      lower.contains('renderflex') ||
      lower.contains('renderbox');
}

/// Οι γραμμές που κρατάμε από τα συνοδευτικά ενός σφάλματος διάταξης.
///
/// Ένα σφάλμα διάταξης **δεν φέρνει ποτέ στοίβα κλήσεων** — το `stack` του
/// είναι κενό. Ό,τι ξέρει το Flutter για την προέλευσή του ζει στον
/// `informationCollector`, και κυρίως στη γραμμή `debugCreator`: την αλυσίδα
/// των widget που γέννησαν το στοιχείο που ξεχείλισε. Χωρίς αυτήν, η εγγραφή
/// στο ημερολόγιο λέει «κάτι ξεχείλισε κατά 25 pixel» και δεν οδηγεί πουθενά.
///
/// Κρατάμε μόνο όσα δείχνουν **πού**. Οι γενικές συμβουλές του framework
/// («σκεφτείτε ένα Expanded…») είναι ίδιες σε κάθε overflow και δεν προσθέτουν
/// τίποτα στη διάγνωση.
String? layoutErrorDiagnostics(FlutterErrorDetails details) {
  final lines = <String>[];

  final context = details.context?.toString().trim();
  if (context != null && context.isNotEmpty) {
    lines.add('Φάση: $context');
  }

  final information =
      details.informationCollector?.call() ?? const <DiagnosticsNode>[];
  for (final node in information) {
    final text = node.toStringDeep().trim();
    if (text.isEmpty) continue;
    if (text.startsWith('debugCreator:')) {
      lines.add(text);
      continue;
    }
    if (text.startsWith('The specific RenderFlex in question is:') ||
        text.startsWith('The specific RenderBox in question is:')) {
      // Μόνο η πρώτη γραμμή: ακολουθεί η διακοσμητική σήμανση της άκρης που
      // ξεχείλισε, δεκάδες γραμμές γεωμετρικά σύμβολα χωρίς καμία πληροφορία.
      lines.add(text.split('\n').first.trim());
    }
  }

  if (lines.isEmpty) return null;
  return lines.join('\n');
}
