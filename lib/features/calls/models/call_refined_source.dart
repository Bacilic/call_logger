import 'package:intl/intl.dart';

/// Πώς προέκυψε η Περιγραφή μιας κλήσης όταν πέρασε από εξευγενισμό
/// (`calls.refined_source`).
///
/// Η διάκριση δεν είναι διακοσμητική: «το έγραψε η ΤΝ και το άφησα ως έχει»
/// και «το έγραψε η ΤΝ και το διόρθωσα» λένε διαφορετικά πράγματα για το πόσο
/// εμπιστεύεσαι το κείμενο όταν το ξαναδιαβάζεις μήνες μετά.
abstract final class CallRefinedSource {
  CallRefinedSource._();

  /// Πρόταση ΤΝ που στάλθηκε χωρίς καμία αλλαγή.
  static const String ai = 'ai';

  /// Πρόταση ΤΝ που ο χρήστης διόρθωσε πριν την αποστολή.
  static const String aiEdited = 'ai_edited';

  /// Γραμμένο εξ ολοκλήρου με το χέρι, χωρίς ΤΝ.
  static const String manual = 'manual';

  static const Set<String> all = <String>{ai, aiEdited, manual};

  /// Ετικέτα προέλευσης για το UI· κενή όταν η τιμή είναι άγνωστη.
  static String label(String? source) => switch ((source ?? '').trim()) {
    ai => 'από ΤΝ',
    aiEdited => 'από ΤΝ · επεξεργασμένο',
    manual => 'χειρόγραφο',
    _ => '',
  };

  /// «από ΤΝ · επεξεργασμένο · 10/08 09:38» — κενή όταν λείπουν και τα δύο.
  ///
  /// Το κοινό ίχνος της Περιγραφής: το δείχνουν η καρτέλα επεξεργασίας δίπλα
  /// στον τίτλο του πεδίου και η στήλη του Ιστορικού Κλήσεων στο tooltip.
  static String provenanceLabel({String? source, String? refinedAt}) {
    final parts = <String>[];
    final sourceLabel = label(source);
    if (sourceLabel.isNotEmpty) parts.add(sourceLabel);
    final stamp = DateTime.tryParse((refinedAt ?? '').trim());
    if (stamp != null) parts.add(DateFormat('dd/MM HH:mm').format(stamp));
    return parts.join(' · ');
  }
}
