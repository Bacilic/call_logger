// Απογραφή και ζώνες μαζικής διαγραφής υπαλλήλων — καθαρή λογική, χωρίς UI.
//
// Ίδια δομή με τη διαγραφή τμημάτων: ο χρήστης βλέπει πρώτα όσους θα του
// ζητήσουν αποφάσεις, και μετά συμπτυγμένα όσους διαγράφονται σιωπηλά.

import 'bulk_deletion_summary.dart';

/// Ένας υπάλληλος προς διαγραφή, με ό,τι θα ζητήσει απόφαση.
class UserDeletionInventory {
  const UserDeletionInventory({
    required this.userId,
    required this.displayLabel,
    required this.exclusivePhoneCount,
    required this.exclusiveEquipmentCount,
  });

  final int userId;

  /// Ήδη μορφής «Όνομα» ή «Όνομα (Τμήμα)».
  final String displayLabel;

  /// Τηλέφωνα που ανήκουν **μόνο** σε αυτόν — θα ρωτηθεί τι γίνεται με αυτά.
  final int exclusivePhoneCount;

  /// Εξοπλισμός που ανήκει **μόνο** σε αυτόν.
  final int exclusiveEquipmentCount;

  int get assetCount => exclusivePhoneCount + exclusiveEquipmentCount;

  bool get hasAssets => assetCount > 0;

  /// Γραμμές περίληψης· παραλείπει τα μηδενικά.
  List<String> buildSummaryLines() {
    return [
      if (exclusivePhoneCount > 0)
        SummaryCount(
          exclusivePhoneCount,
          'προσωπικό τηλέφωνο',
          'προσωπικά τηλέφωνα',
        ).label,
      if (exclusiveEquipmentCount > 0)
        SummaryCount(
          exclusiveEquipmentCount,
          'προσωπικός εξοπλισμός',
          'προσωπικοί εξοπλισμοί',
        ).label,
    ];
  }
}

/// Οι υπάλληλοι χωρισμένοι κατά **το τι θα ζητηθεί από τον χρήστη**.
class UserDeletionZones {
  const UserDeletionZones({required this.withAssets, required this.empty});

  factory UserDeletionZones.from(List<UserDeletionInventory> inventories) {
    final withAssets = <UserDeletionInventory>[];
    final empty = <UserDeletionInventory>[];
    for (final inv in inventories) {
      if (inv.hasAssets) {
        withAssets.add(inv);
      } else {
        empty.add(inv);
      }
    }
    return UserDeletionZones(withAssets: withAssets, empty: empty);
  }

  /// Θα ζητηθεί απόφαση για τα προσωπικά τους στοιχεία.
  final List<UserDeletionInventory> withAssets;

  /// Δεν ζητούν τίποτα — διαγράφονται κατευθείαν.
  final List<UserDeletionInventory> empty;

  /// Συνολικά στοιχεία που θα ρωτηθούν — δηλαδή πόσοι διάλογοι ακολουθούν.
  int get totalAssetCount {
    var total = 0;
    for (final inv in withAssets) {
      total += inv.assetCount;
    }
    return total;
  }

  /// Οι επικεφαλίδες έχουν νόημα μόνο όταν υπάρχει κάτι να ξεχωρίσουν.
  bool get showsZoneHeaders => withAssets.isNotEmpty && empty.isNotEmpty;

  String get withAssetsHeader => 'Με προσωπικά στοιχεία (${withAssets.length})';

  /// Γραμμή για όσους δεν ζητούν τίποτα — `null` όταν δεν υπάρχουν.
  String? get emptyHeader {
    final count = empty.length;
    if (count <= 0) return null;
    if (count == 1) {
      return '1 υπάλληλος χωρίς προσωπικά στοιχεία — διαγράφεται χωρίς ερώτηση';
    }
    return '$count υπάλληλοι χωρίς προσωπικά στοιχεία — διαγράφονται χωρίς '
        'ερώτηση';
  }
}
