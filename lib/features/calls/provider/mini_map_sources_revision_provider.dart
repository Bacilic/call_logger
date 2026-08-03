import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../directory/building_map/providers/building_map_providers.dart';
import '../../directory/models/department_model.dart';
import '../../directory/providers/department_directory_provider.dart';
import 'lookup_provider.dart';

/// Αύξων αριθμός που ανεβαίνει όποτε αλλάζει **οποιαδήποτε** πηγή του μικρού
/// χάρτη της κλήσης. Ο χάρτης ακούει μόνο αυτόν αντί για τρεις χωριστούς
/// providers: η γνώση «τι επηρεάζει τον χάρτη» ζει σε ένα σημείο, και μια
/// μελλοντική πηγή προστίθεται εδώ — όχι μέσα στο widget.
///
/// Οι πηγές:
/// 1. **Χαρτογράφηση τμημάτων** — θέση/γεωμετρία τμήματος στον χάρτη κτιρίου.
/// 2. **Φύλλα κατόψης** — προσθήκη, αντικατάσταση εικόνας ή περιστροφή.
/// 3. **Συσχετίσεις καταλόγου** — ποιος εξοπλισμός/τηλέφωνο/υπάλληλος ανήκει
///    σε ποιο τμήμα (το τμήμα-στόχος προκύπτει από αυτές).
final miniMapSourcesRevisionProvider =
    NotifierProvider<MiniMapSourcesRevisionNotifier, int>(
      MiniMapSourcesRevisionNotifier.new,
    );

class MiniMapSourcesRevisionNotifier extends Notifier<int> {
  @override
  int build() {
    ref.listen<List<DepartmentModel>>(
      departmentDirectoryProvider.select((s) => s.allDepartments),
      _bumpOnChange,
    );
    ref.listen<int>(buildingMapFloorReloadSeqProvider, _bumpOnChange);
    // Μόνο ολοκληρωμένες φορτώσεις: η ενδιάμεση «φορτώνει ακόμη» δεν είναι
    // αλλαγή δεδομένων και θα προκαλούσε διπλή ανανέωση σε κάθε mutation.
    ref.listen<LookupLoadResult?>(
      lookupServiceProvider.select((async) => async.value),
      (previous, next) {
        if (next == null) return;
        _bumpOnChange(previous, next);
      },
    );
    return 0;
  }

  void _bumpOnChange(Object? previous, Object? next) {
    // Η πρώτη τιμή δεν είναι αλλαγή — ο χάρτης μόλις φόρτωσε με αυτήν.
    if (previous == null || identical(previous, next)) return;
    if (previous == next) return;
    state = state + 1;
  }
}
