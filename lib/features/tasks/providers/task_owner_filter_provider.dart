import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database_helper.dart';
import '../../../core/services/current_operator.dart';
import '../../../core/services/owner_filter_preference.dart';
import '../../../core/services/profile_settings.dart';
import '../../../core/models/owner_filter.dart';
import '../../operators/providers/operator_directory_providers.dart';
import '../../operators/utils/owner_filter_options.dart';
import 'tasks_provider.dart';
import 'task_service_provider.dart';

/// Οι διαθέσιμες επιλογές του φίλτρου, με τη σειρά που εμφανίζονται.
///
/// «Όλοι» πάντα πρώτο, μετά τα ονόματα αλφαβητικά, και «Χωρίς χρήστη» τελευταίο
/// — μόνο όταν υπάρχουν όντως τέτοιες εκκρεμότητες. Ο τρέχων χρήστης μπαίνει
/// πάντα, ακόμη κι αν δεν έχει ανοίξει καμία: αλλιώς δεν θα μπορούσε να
/// διαλέξει τον εαυτό του και να δει ότι η λίστα του είναι άδεια.
///
/// **autoDispose, όπως το αδελφό φίλτρο του Ιστορικού.** Τα ονόματα έρχονται
/// πλέον από τον κοινό κατάλογο προφίλ, που είναι κι αυτός autoDispose: ένα
/// φίλτρο που ζούσε όσο η εφαρμογή θα τον κρατούσε ζωντανό για πάντα, και τα
/// ονόματα θα πάγωναν παντού — και στα σήματα των καρτών.
final taskOwnerOptionsProvider =
    FutureProvider.autoDispose<List<OwnerFilterOption>>((ref) async {
      // Η λίστα ξαναχτίζεται όταν αλλάζουν οι εκκρεμότητες: ο πρώτος που
      // ανοίγει εκκρεμότητα πρέπει να εμφανιστεί στο φίλτρο χωρίς επανεκκίνηση.
      ref.watch(tasksProvider);
      final service = ref.read(taskServiceProvider);

      final ownerIds = (await service.getDistinctOwnerIds()).toSet();
      final active = CurrentOperator.active;
      if (active?.id != null) ownerIds.add(active!.id!);

      return buildOwnerFilterOptions(
        ownerIds: ownerIds,
        names: await ref.watch(operatorNamesProvider.future),
        hasUnassigned: await service.hasUnassignedTasks(),
      );
    });

/// Πόσες εκκρεμότητες κρύβει αυτή τη στιγμή **μόνο** το φίλτρο χρήστη.
///
/// Απαντά στο ερώτημα που γεννά μια άδεια οθόνη: «δεν έμεινε δουλειά, ή απλώς
/// δεν τη βλέπω;». Χωρίς αυτό, η λίστα που άδειασε επειδή διάλεξες το όνομά σου
/// μοιάζει ίδια με λίστα που άδειασε επειδή τελείωσαν όλα — και ο μετρητής της
/// πλοήγησης που εξακολουθεί να λέει «1» μοιάζει με σφάλμα.
///
/// Μηδέν όταν το φίλτρο δείχνει ήδη «Όλοι»: τότε δεν κρύβει τίποτα, και η κενή
/// οθόνη λέει την απλή αλήθεια της.
final tasksHiddenByOwnerFilterProvider = FutureProvider<int>((ref) async {
  final filter = ref.watch(effectiveTaskFilterProvider);
  if (filter.owner.isEveryone) return 0;
  // Παρακολουθεί τη λίστα ώστε ο αριθμός να μη μείνει πίσω μετά από αλλαγή.
  ref.watch(tasksProvider);
  return ref
      .read(taskServiceProvider)
      .countFilteredTasks(filter.copyWith(owner: OwnerFilter.everyone));
});

/// Η επιλογή του χρήστη για το φίλτρο, με μνήμη που τον ακολουθεί.
///
/// Ξεκινά από τον ίδιο («οι δικές μου»), αλλά μόλις την αλλάξει, η νέα τιμή
/// αποθηκεύεται στις **προσωπικές** του ρυθμίσεις: την ξαναβρίσκει και σε άλλον
/// υπολογιστή, και δεν πειράζει την επιλογή κανενός συναδέλφου.
///
/// Χωρίς αναγνωρισμένο χρήστη το φίλτρο δείχνει «Όλοι» — δεν υπάρχει «εγώ» για
/// να προεπιλεγεί, και μια άδεια λίστα χωρίς εξήγηση θα έμοιαζε με σφάλμα.
class TaskOwnerFilterNotifier extends AsyncNotifier<OwnerFilter> {
  @override
  Future<OwnerFilter> build() async {
    final active = CurrentOperator.active;
    if (active?.id == null) return OwnerFilter.everyone;

    final db = await DatabaseHelper.instance.database;
    final stored = await OwnerFilterPreference.read(
      db,
      ProfileSettingKeys.tasksOwnerFilter,
    );
    return stored ?? OwnerFilter.byOperator(active!.id!);
  }

  /// Αλλάζει την επιλογή και τη θυμάται.
  ///
  /// Η οθόνη ενημερώνεται πρώτη και η εγγραφή ακολουθεί: η αποθήκευση αφορά την
  /// **επόμενη** φορά, και δεν υπάρχει λόγος να περιμένει ο χρήστης τη βάση για
  /// να δει τη λίστα του.
  Future<void> select(OwnerFilter owner) async {
    state = AsyncValue.data(owner);
    final db = await DatabaseHelper.instance.database;
    await OwnerFilterPreference.write(
      db,
      ProfileSettingKeys.tasksOwnerFilter,
      owner,
    );
  }
}

final taskOwnerFilterProvider =
    AsyncNotifierProvider<TaskOwnerFilterNotifier, OwnerFilter>(
      TaskOwnerFilterNotifier.new,
    );
