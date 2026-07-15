import '../../../core/models/remote_tool.dart';
import '../../../core/models/remote_tool_role.dart';

/// Κείμενα βοήθειας για το dropdown «Κύριο κουμπί» στην οθόνη απομακρυσμένων.
class PrimaryToolHelpText {
  const PrimaryToolHelpText._();

  static const String _base =
      'Ορίζει ποιο από τα ενεργά εργαλεία θα εμφανίζεται πρώτο, ως κύριο '
      'κουμπί, στην Οθόνη Κλήσεων — παρακάμπτοντας τη σειρά εμφάνισης του '
      'παραπάνω πίνακα. Ισχύει μόνο όταν το εργαλείο είναι διαθέσιμο για τον '
      'συγκεκριμένο εξοπλισμό (π.χ. έχει συμπληρωμένη παράμετρο στην καρτέλα του).';

  /// Επιστρέφει επεξήγηση· προσθέτει παράδειγμα όταν υπάρχουν ≥ 2 ενεργά εργαλεία.
  static String build(List<RemoteTool> activeTools) {
    if (activeTools.length < 2) return _base;

    final toolA = _pickToolA(activeTools);
    final toolB = _pickToolB(activeTools, toolA);
    if (toolA == null || toolB == null) return _base;

    final nameA = toolA.name;
    final nameB = toolB.name;
    final example =
        'Παράδειγμα: αν σε έναν εξοπλισμό είναι διαθέσιμο το «$nameA», αυτό '
        'θα εμφανίζεται πρώτο και το «$nameB» δεύτερο — ή μέσα στο «⋯», αν '
        'ενεργοποιήσετε και τον παρακάτω διακόπτη.';
    return '$_base $example';
  }

  /// Πρώτο ενεργό με role ≠ VNC· αν όλα είναι VNC, το δεύτερο ενεργό.
  static RemoteTool? _pickToolA(List<RemoteTool> active) {
    for (final t in active) {
      if (t.role != ToolRole.vnc) return t;
    }
    if (active.length >= 2) return active[1];
    return active.isEmpty ? null : active.first;
  }

  /// Πρώτο ενεργό VNC· αλλιώς το πρώτο που διαφέρει από το [toolA].
  static RemoteTool? _pickToolB(List<RemoteTool> active, RemoteTool? toolA) {
    for (final t in active) {
      if (t.role == ToolRole.vnc) return t;
    }
    for (final t in active) {
      if (toolA == null || !identical(t, toolA) && t.id != toolA.id) {
        return t;
      }
    }
    return null;
  }
}
