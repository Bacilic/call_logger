import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../layout/call_form_content.dart';
import '../layout/calls_field_groups_provider.dart';
import 'call_entry_provider.dart';
import 'smart_entity_selector_provider.dart';

/// Πού βρίσκεται η γρήγορη καταγραφή.
enum QuickCallPhase {
  /// Δεν υπάρχει γρήγορη καταγραφή.
  closed,

  /// Ο διάλογος είναι ανοιχτός μπροστά στην οθόνη.
  open,

  /// Ελαχιστοποιημένη: η κλήση συνεχίζει (πεδία, χρονόμετρο) και φαίνεται ως
  /// τηλέφωνο που χτυπά.
  minimized,
}

/// Η ΜΙΑ γρήγορη καταγραφή της εφαρμογής.
///
/// Η κατάσταση της φόρμας (πεδία, σημειώσεις, κατηγορία, χρονόμετρο) ζει σε
/// δικά της providers, παιδιά του κεντρικού container — όχι μέσα στον
/// διάλογο. Έτσι η ελαχιστοποίηση κλείνει τον διάλογο χωρίς να χάνεται τίποτα,
/// και η επαναφορά τον ξαναχτίζει πάνω στα ίδια providers.
///
/// Η καταγραφή τελειώνει ΜΟΝΟ με [end]: καταχώρηση, ρητό κλείσιμο ή
/// «Διακοπή κλήσης» του φρουρού αλλαγής βάσης.
class QuickCallSessionNotifier extends Notifier<QuickCallPhase> {
  ProviderContainer? _container;

  /// Καταγραφή που τελείωσε ενώ ο διάλογός της ήταν ακόμη στην οθόνη (π.χ. στο
  /// σβήσιμο του κλεισίματος): τα providers της πεθαίνουν μόλις φύγει κι αυτός,
  /// ποτέ κάτω από widgets που τα διαβάζουν ακόμη.
  ProviderContainer? _retiring;

  /// Πόσοι διάλογοι γρήγορης καταγραφής βρίσκονται στο δέντρο — μαζί με όσους
  /// σβήνουν. Μια επαναφορά αμέσως μετά την ελαχιστοποίηση τους κάνει δύο.
  int _views = 0;

  @override
  QuickCallPhase build() {
    ref.onDispose(() {
      _container?.dispose();
      _container = null;
      _retiring?.dispose();
      _retiring = null;
    });
    return QuickCallPhase.closed;
  }

  /// Ο διάλογος μπήκε στο δέντρο.
  void attachView() => _views++;

  /// Ο διάλογος βγήκε από το δέντρο.
  void detachView() {
    _views--;
    if (_views > 0) return;
    _retiring?.dispose();
    _retiring = null;
  }

  /// Ανοίγει τη γρήγορη καταγραφή — καινούρια, ή την ελαχιστοποιημένη όπως
  /// την άφησε ο χρήστης — και επιστρέφει τα providers της φόρμας της.
  ProviderContainer open() {
    final container = _container ??= ProviderContainer(
      parent: ref.container,
      overrides: [
        callSmartEntityProvider.overrideWith(SmartEntitySelectorNotifier.new),
        callEntryProvider.overrideWith(CallEntryNotifier.new),
        ...isolatedCallsScreenStateOverrides(),
      ],
    );
    state = QuickCallPhase.open;
    return container;
  }

  /// Κατεβάζει την ανοιχτή καταγραφή· χωρίς καταγραφή δεν κάνει τίποτα.
  void minimize() {
    // Οι καλούντες έρχονται και μετά από αναμονή (κλείσιμο διαλόγου): η
    // εφαρμογή μπορεί να έχει κλείσει στο μεταξύ.
    if (!ref.mounted || _container == null) return;
    state = QuickCallPhase.minimized;
  }

  /// Τέλος της καταγραφής: ό,τι είχε γραφτεί σβήνει.
  void end() {
    if (!ref.mounted) return;
    final container = _container;
    _container = null;
    state = QuickCallPhase.closed;
    if (container == null) return;
    if (_views > 0) {
      _retiring?.dispose();
      _retiring = container;
    } else {
      container.dispose();
    }
  }

  /// Έχει γραφτεί κάτι που θα χανόταν με το [end];
  bool get hasContent {
    final container = _container;
    if (container == null) return false;
    return callFormHasContent(
      container.read(callSmartEntityProvider),
      container.read(callEntryProvider),
    );
  }
}

final quickCallSessionProvider =
    NotifierProvider<QuickCallSessionNotifier, QuickCallPhase>(
      QuickCallSessionNotifier.new,
    );
