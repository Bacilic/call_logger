/// Η επιλογή του μενού «Φίλτρα» στην αναζήτηση της Λάμπας.
///
/// **Δεν κόβει αποτελέσματα — ορίζει τι ψάχνουμε.** Γι' αυτό λειτουργεί ακόμη
/// και με εντελώς κενή αναζήτηση: «δείξε μου όλα τα γραφεία χωρίς εξοπλισμό»
/// είναι πλήρες ερώτημα από μόνο του.
///
/// Δύο ανεξάρτητες ενότητες, που συνδυάζονται:
/// - **Οντότητες χωρίς εξοπλισμό** ([unlinkedKinds]) — ιδιοκτήτες, γραφεία,
///   μοντέλα, συμβάσεις που δεν τις χρησιμοποιεί κανένας εξοπλισμός.
/// - **Εξοπλισμός με κενά** ([equipmentGaps]) — εξοπλισμός που υπάρχει, αλλά
///   του λείπει γραφείο ή ιδιοκτήτης.
library;

import 'lamp_unlinked_entities.dart';

/// Τα πλήθη που δείχνει το μενού φίλτρων δίπλα σε κάθε επιλογή.
///
/// Με ενεργή αναζήτηση είναι τα ταιριάσματά της· αλλιώς τα συνολικά της βάσης.
class LampFilterMenuCounts {
  const LampFilterMenuCounts({
    this.byKind = const <LampUnlinkedEntityKind, int>{},
    this.emptyRecords = 0,
    this.equipmentGaps = const <LampEquipmentGapKind, int>{},
  });

  final Map<LampUnlinkedEntityKind, int> byKind;
  final int emptyRecords;
  final Map<LampEquipmentGapKind, int> equipmentGaps;
}

class LampSearchFilterSelection {
  const LampSearchFilterSelection({
    this.unlinkedKinds = const <LampUnlinkedEntityKind>{},
    this.onlyEmptyUnlinked = false,
    this.equipmentGaps = const <LampEquipmentGapKind>{},
  });

  static const none = LampSearchFilterSelection();

  /// Είδη ασύνδετων οντοτήτων προς εμφάνιση· κενό = καμία επιλογή.
  final Set<LampUnlinkedEntityKind> unlinkedKinds;

  /// Περιορισμός στις «κενές» εγγραφές — αυτές χωρίς κανένα στοιχείο ζωής.
  /// Αγνοείται όταν δεν έχει επιλεγεί κανένα είδος.
  final bool onlyEmptyUnlinked;

  /// Ποια κενά εξοπλισμού ζητούνται· κενό = κανένα.
  final Set<LampEquipmentGapKind> equipmentGaps;

  bool get hasUnlinked => unlinkedKinds.isNotEmpty;
  bool get hasEquipmentGaps => equipmentGaps.isNotEmpty;
  bool get isActive => hasUnlinked || hasEquipmentGaps;

  /// Πόσες ενότητες φίλτρου είναι ενεργές — για την ένδειξη στο κουμπί.
  int get activeSectionCount =>
      (hasUnlinked ? 1 : 0) + (hasEquipmentGaps ? 1 : 0);

  /// Κρύβεται εντελώς ο εξοπλισμός;
  ///
  /// Μόνο όταν ζητούνται ασύνδετες **και δεν** ζητείται εξοπλισμός με κενά:
  /// αν ζητηθούν και τα δύο, ο χρήστης θέλει να δει και τα δύο.
  bool get hidesEquipment => hasUnlinked && !hasEquipmentGaps;

  LampSearchFilterSelection copyWith({
    Set<LampUnlinkedEntityKind>? unlinkedKinds,
    bool? onlyEmptyUnlinked,
    Set<LampEquipmentGapKind>? equipmentGaps,
  }) {
    return LampSearchFilterSelection(
      unlinkedKinds: unlinkedKinds ?? this.unlinkedKinds,
      onlyEmptyUnlinked: onlyEmptyUnlinked ?? this.onlyEmptyUnlinked,
      equipmentGaps: equipmentGaps ?? this.equipmentGaps,
    );
  }

  /// Ταιριάζει η ασύνδετη οντότητα με την επιλογή ειδών;
  bool acceptsUnlinked(LampUnlinkedEntity entity) {
    if (!unlinkedKinds.contains(entity.kind)) return false;
    if (onlyEmptyUnlinked && !entity.isEmptyRecord) return false;
    return true;
  }
}
