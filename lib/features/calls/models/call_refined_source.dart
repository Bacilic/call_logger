/// Πώς προέκυψε το καθαρό κείμενο μιας κλήσης (`calls.refined_source`).
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
}
