import '../../../../core/models/remote_tool.dart';
import '../../../../core/models/remote_tool_role.dart';

/// Κείμενα βοήθειας για το πεδίο παραμέτρου απομακρυσμένης σύνδεσης εξοπλισμού.
///
/// Ακολουθεί την ίδια διάκριση ρόλων με το `_buildRemoteParamField`
/// (AnyDesk / VNC / RDP διεύθυνση / RDP αρχείο / γενικό).
class RemoteParamHelpText {
  const RemoteParamHelpText._();

  /// Επιστρέφει επεξηγηματικό κείμενο για το εργαλείο και τον τύπο παραμέτρου.
  static String forTool({
    required RemoteTool? tool,
    required bool acceptsFileParam,
  }) {
    final toolPhrase = _toolConnectPhrase(tool);

    return switch (tool?.role) {
      ToolRole.anydesk =>
        'Ο κωδικός AnyDesk στον οποίο θα συνδεθεί το AnyDesk για αυτόν τον '
            'εξοπλισμό. Συνήθως χρησιμοποιείται για εξοπλισμούς εκτός οργανισμού. '
            'Μορφή: 9-10 ψηφία.',
      ToolRole.vnc =>
        'Η διεύθυνση IP ή το όνομα υπολογιστή στον οποίο θα συνδεθεί'
            '$toolPhrase. Αφήστε το κενό για να χρησιμοποιηθεί ο προεπιλεγμένος '
            'στόχος (PC + κωδικός εξοπλισμού).',
      ToolRole.rdp when acceptsFileParam =>
        'Η διαδρομή ενός αρχείου σύνδεσης .rdp που θα ανοίξει'
            '$toolPhrase για αυτόν τον εξοπλισμό. Αφήστε κενό για απενεργοποίηση.',
      ToolRole.rdp =>
        'Η διεύθυνση IP ή το όνομα υπολογιστή στον οποίο θα συνδεθεί'
            '$toolPhrase. Αφήστε κενό για απενεργοποίηση αυτού του εργαλείου '
            'για τον εξοπλισμό.',
      _ =>
        'Ο στόχος σύνδεσης (π.χ. διεύθυνση ή αναγνωριστικό) που θα χρησιμοποιήσει'
            '$toolPhrase για αυτόν τον εξοπλισμό. Αφήστε κενό για απενεργοποίηση.',
    };
  }

  /// « το «Όνομα»» ή κενό όταν λείπει όνομα — ώστε η πρόταση να μένει ομαλή.
  static String _toolConnectPhrase(RemoteTool? tool) {
    final name = tool?.name.trim() ?? '';
    if (name.isEmpty) return '';
    return ' το «$name»';
  }
}
