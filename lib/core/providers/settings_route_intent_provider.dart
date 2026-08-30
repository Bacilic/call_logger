import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Ενότητα των Ρυθμίσεων που πρέπει να έχει μπροστά του ο χρήστης όταν
/// ανοίγει η οθόνη από αλλού.
enum SettingsSection {
  /// «Ενημερώσεις» — εκεί ζει ο φάκελος ελέγχου ενημερώσεων.
  updates,
}

/// Αίτημα ανοίγματος της οθόνης Ρυθμίσεων, προαιρετικά σε συγκεκριμένη
/// ενότητα. Καταναλώνεται από το [MainShell].
///
/// Οι Ρυθμίσεις δεν είναι προορισμός της μπάρας — ανοίγουν από πάνω σαν
/// φύλλο. Γι' αυτό έχουν δικό τους δίαυλο αντί να μπουν στο αίτημα
/// πλοήγησης: η οθόνη από κάτω μένει ζωντανή, και όποιος ζήτησε το άνοιγμα
/// τη βρίσκει όπως την άφησε όταν κλείσουν.
class SettingsRouteIntentNotifier extends Notifier<SettingsSection?> {
  @override
  SettingsSection? build() => null;

  void openSection(SettingsSection section) {
    state = section;
  }

  void clear() {
    state = null;
  }
}

final settingsRouteIntentProvider =
    NotifierProvider<SettingsRouteIntentNotifier, SettingsSection?>(
      SettingsRouteIntentNotifier.new,
    );
