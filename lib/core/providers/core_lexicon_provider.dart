import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/core_lexicon_service.dart';
import 'settings_provider.dart';

/// Διαχείριση κατάστασης λεξικού-πυρήνα (συγχρονισμένη με [CoreLexiconService]).
class CoreLexiconNotifier extends Notifier<CoreLexiconState> {
  CoreLexiconService get _svc => CoreLexiconService.instance;

  @override
  CoreLexiconState build() => _svc.state;

  void _sync() => state = _svc.state;

  Future<bool> bootstrapFromSavedPath() async {
    final ok = await _svc.bootstrapFromSavedPath();
    _sync();
    return ok;
  }

  Future<bool> loadFromDiskPath(String path, {bool persistPath = true}) async {
    final ok = await _svc.loadFromDiskPath(path, persistPath: persistPath);
    _sync();
    return ok;
  }

  Future<bool> installFromBundledAsset(String assetPath) async {
    final ok = await _svc.installFromBundledAsset(assetPath);
    _sync();
    return ok;
  }

  Future<bool> installFromExternalFile(String sourcePath) async {
    final ok = await _svc.installFromExternalFile(sourcePath);
    _sync();
    return ok;
  }

  void unload() {
    _svc.unload();
    _sync();
  }
}

final coreLexiconProvider =
    NotifierProvider<CoreLexiconNotifier, CoreLexiconState>(
      CoreLexiconNotifier.new,
    );

final coreLexiconLoadedProvider = Provider<bool>(
  (ref) => ref.watch(coreLexiconProvider).loaded,
);

/// Ορατότητα στοιχείου πλοήγησης «Λεξικό».
///
/// Δύο συνθήκες, με αυτή τη σειρά, και **καμία εξαίρεση**:
///
/// 1. Χωρίς ορθογραφικό έλεγχο το Λεξικό δεν έχει νόημα.
/// 2. Αλλιώς αποφασίζει ο χρήστης.
///
/// Ο κανόνας είχε τρίτη γραμμή: όταν δεν είχε φορτωθεί λεξικό-πυρήνας κρατούσε
/// το εικονίδιο ορατό «για να μη χαθεί η προειδοποίηση». Η πρόθεση ήταν καλή
/// αλλά η κατάσταση όπου η ρύθμιση αγνοούνταν ήταν **ακριβώς** η κατάσταση
/// όπου το εικονίδιο φορούσε το θαυμαστικό: ο χρήστης το έκρυβε και του
/// επέστρεφε με προειδοποίηση. Η προειδοποίηση ζει στις Ρυθμίσεις, κάτω από
/// τον διακόπτη «Ορθογραφικός έλεγχος» — εκεί όπου ο χρήστης κοιτάζει όταν
/// αποφασίζει, και όχι σε μια μπάρα από την οποία ζήτησε να φύγει.
bool isDictionaryNavVisible({
  required bool enableSpellCheck,
  required bool showDictionaryNav,
}) {
  if (!enableSpellCheck) return false;
  return showDictionaryNav;
}

/// Φαίνεται τελικά το Λεξικό στην πλευρική μπάρα;
///
/// Μοναδικό σημείο για κάθε πύλη που οδηγεί εκεί — η μπάρα και όποιο κουμπί
/// υπόσχεται μετάβαση στο Λεξικό. Χωρίς αυτό, ένα κουμπί «πήγαινε στις
/// διαδρομές λεξικού» θα ζητούσε οθόνη που ο χρήστης έχει κρύψει, και δεν θα
/// άνοιγε τίποτα — σιωπηλά.
///
/// Όσο οι προτιμήσεις φορτώνουν, ο προορισμός θεωρείται ορατός — ίδια
/// συμπεριφορά με την μπάρα.
final dictionaryNavVisibleProvider = Provider<bool>((ref) {
  return isDictionaryNavVisible(
    enableSpellCheck: ref
        .watch(enableSpellCheckProvider)
        .maybeWhen(data: (value) => value, orElse: () => true),
    showDictionaryNav: ref
        .watch(showDictionaryNavProvider)
        .maybeWhen(data: (value) => value, orElse: () => true),
  );
});
