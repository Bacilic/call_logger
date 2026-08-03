// Καθαρή λογική και κείμενα διαχείρισης απομακρυσμένων εργαλείων.
//
// Χωρίς widgets και χωρίς βάση: ό,τι μπορεί να αποδειχθεί με σκέτη κλήση
// συνάρτησης ζει εδώ, ώστε η οθόνη διαχείρισης να μείνει διάταξη και ενέργειες.

import '../../../core/models/remote_tool.dart';
import '../../../core/models/remote_tool_arg.dart';

/// Πόσα ονόματα δείχνουμε πριν πέσουμε σε σκέτο πλήθος.
const int kRemoteToolRemovalMaxVisible = 5;

/// Κατάληξη ονόματος αντιγράφου εργαλείου.
const String kRemoteToolCloneSuffix = ' (αντίγραφο)';

// ---------------------------------------------------------------------------
// Λίστα εργαλείων
// ---------------------------------------------------------------------------

/// Μετατροπή δεικτών `ReorderableListView` σε θέση 1-based για την αναδιάταξη.
int reorderedPositionOneBased(int oldIndex, int newIndex) {
  var adjusted = newIndex;
  if (newIndex > oldIndex) {
    adjusted -= 1;
  }
  return adjusted + 1;
}

/// Σύνοψη ενεργών ορισμάτων για τη λίστα εργαλείων (με απόκρυψη κωδικών).
String remoteToolArgumentsSummary(RemoteTool t) {
  final active = t.arguments.where((a) => a.isActive).toList();
  if (active.isEmpty) return '—';
  final parts = active
      .take(2)
      .map((a) => RemoteToolArg.maskSecretValues(a.value))
      .toList();
  var s = parts.join(', ');
  if (active.length > 2) s = '$s…';
  if (s.length > 80) s = '${s.substring(0, 77)}…';
  return s;
}

/// Υπόδειξη στήλης ονόματος: πόσοι εξοπλισμοί έχουν προεπιλογή αυτό το εργαλείο.
String remoteToolUsageTooltip(int defaultUsageCount) {
  if (defaultUsageCount <= 0) {
    return 'Δεν είναι ορισμένο ως προεπιλογή σε κανέναν εξοπλισμό.';
  }
  if (defaultUsageCount == 1) return 'Ενεργοποιημένο σε 1 εξοπλισμό.';
  return 'Ενεργοποιημένο σε $defaultUsageCount εξοπλισμούς.';
}

// ---------------------------------------------------------------------------
// Αντίγραφο
// ---------------------------------------------------------------------------

/// Μοναδικό όνομα «… (αντίγραφο)» ή «… (αντίγραφο 2)» κ.ο.κ.
///
/// Η σύγκριση αγνοεί πεζά/κεφαλαία και κενά στις άκρες, ώστε το «VNC» και το
/// «vnc » να μη θεωρηθούν διαφορετικά ονόματα.
String uniqueRemoteToolCloneName(
  String baseName,
  List<RemoteTool> existingTools,
) {
  final taken = existingTools.map((e) => e.name.trim().toLowerCase()).toSet();
  final trimmed = baseName.trim();
  var candidate = '$trimmed$kRemoteToolCloneSuffix';
  if (!taken.contains(candidate.toLowerCase())) return candidate;
  var i = 2;
  while (true) {
    candidate = '$trimmed$kRemoteToolCloneSuffix $i';
    if (!taken.contains(candidate.toLowerCase())) return candidate;
    i++;
  }
}

// ---------------------------------------------------------------------------
// Απενεργοποίηση
// ---------------------------------------------------------------------------

/// Ερώτηση απενεργοποίησης — εμφανίζεται μόνο όταν το εργαλείο χρησιμοποιείται.
String remoteToolDeactivationQuestion(int defaultUsageCount) {
  if (defaultUsageCount == 1) {
    return 'Το παραπάνω εργαλείο είναι ενεργοποιημένο σε 1 εξοπλισμό. '
        'Να απενεργοποιηθεί;';
  }
  return 'Το παραπάνω εργαλείο είναι ενεργοποιημένο σε $defaultUsageCount '
      'εξοπλισμούς. Να απενεργοποιηθεί;';
}

/// Καθησυχασμός: η απενεργοποίηση δεν χάνει ρυθμίσεις.
String remoteToolDeactivationReassurance(String toolName) {
  return 'Οι ρυθμίσεις δεν θα χαθούν· θα επανέλθουν με την ενεργοποίηση του '
      'εργαλείου «$toolName».';
}

// ---------------------------------------------------------------------------
// Απομάκρυνση
// ---------------------------------------------------------------------------

/// Εμφάνιση εξοπλισμού με τον χειροκίνητο στόχο του: `1001 (123456789)`.
String equipmentManualTargetLabel(String code, String target) {
  final c = code.trim().isEmpty ? '—' : code.trim();
  final t = target.trim();
  if (t.isEmpty) return c;
  return '$c ($t)';
}

/// Πρώτη γραμμή: τι είναι το εργαλείο και πόσοι το έχουν ως προεπιλογή.
String remoteToolRemovalDefaultUsageLine({
  required String toolName,
  required int defaultUsageCount,
}) {
  if (defaultUsageCount <= 0) {
    return 'Να απομακρυνθεί από τη λίστα το εργαλείο «$toolName»;';
  }
  if (defaultUsageCount == 1) {
    return 'Το εργαλείο «$toolName» είναι ορισμένο ως προεπιλογή σε 1 εξοπλισμό. '
        'Να απομακρυνθεί από τη λίστα;';
  }
  return 'Το εργαλείο «$toolName» είναι ορισμένο ως προεπιλογή σε '
      '$defaultUsageCount εξοπλισμούς. Να απομακρυνθεί από τη λίστα;';
}

/// Δεύτερη γραμμή: οι εξοπλισμοί με **χειροκίνητο στόχο**, ονομαστικά έως
/// [kRemoteToolRemovalMaxVisible] και από εκεί και πάνω ως πλήθος.
///
/// Επιστρέφει `null` όταν δεν υπάρχει κανένας — τότε η γραμμή δεν εμφανίζεται
/// καθόλου, αντί για «0 εξοπλισμοί».
String? remoteToolManualTargetsLine(List<String> labels) {
  final count = labels.length;
  if (count <= 0) return null;
  if (count == 1) {
    return 'Υπάρχει 1 εξοπλισμός με χειροκίνητο στόχο για αυτό το εργαλείο:\n'
        '• ${labels.first}';
  }
  final buf = StringBuffer(
    'Υπάρχουν $count εξοπλισμοί με χειροκίνητο στόχο για αυτό το εργαλείο:',
  );
  for (final label in labels.take(kRemoteToolRemovalMaxVisible)) {
    buf.write('\n• $label');
  }
  if (count > kRemoteToolRemovalMaxVisible) {
    buf.write('\n• +${count - kRemoteToolRemovalMaxVisible} ακόμη');
  }
  return buf.toString();
}
