import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/utils/run_after_next_frame.dart';
import '../models/task.dart';
import '../models/task_filter.dart';
import '../../../core/models/owner_filter.dart';
import 'task_owner_filter_provider.dart';
import '../services/task_service.dart';
import 'task_analytics_date_provider.dart';
import 'task_analytics_provider.dart';
import 'task_service_provider.dart';

class TaskFilterNotifier extends Notifier<TaskFilter> {
  @override
  TaskFilter build() => TaskFilter.initial();

  void update(TaskFilter Function(TaskFilter) fn) {
    state = fn(state);
  }
}

final taskFilterProvider = NotifierProvider<TaskFilterNotifier, TaskFilter>(
  TaskFilterNotifier.new,
);

/// Το φίλτρο όπως ισχύει **πραγματικά**: τα chips μαζί με την επιλογή χρήστη.
///
/// Οι δύο επιλογές ζουν χωριστά γιατί έχουν διαφορετική διάρκεια — τα chips
/// ξεκινούν από την αρχή σε κάθε άνοιγμα, ο χρήστης θυμάται. **Το ερώτημα όμως
/// είναι ένα**, και ενώνεται εδώ: όποιος ρωτήσει τη βάση με σκέτο το
/// [taskFilterProvider] θα μετρούσε με τα μισά κριτήρια, και η διαφορά θα
/// φαινόταν μόνο ως αριθμός που δεν βγαίνει.
final effectiveTaskFilterProvider = Provider<TaskFilter>((ref) {
  final base = ref.watch(taskFilterProvider);
  final owner =
      ref.watch(taskOwnerFilterProvider).value ?? OwnerFilter.everyone;
  return base.copyWith(owner: owner);
});

/// Μετρητές ανά κατάσταση (ίδια φίλτρα αναζήτησης/ημερομηνίας, χωρίς status chips).
/// Παρακολουθεί [tasksProvider] ώστε να ενημερώνεται μετά από αλλαγές λίστας.
final taskStatusCountsProvider = FutureProvider<Map<TaskStatus, int>>((
  ref,
) async {
  final filter = ref.watch(effectiveTaskFilterProvider);
  ref.watch(tasksProvider);
  final service = ref.read(taskServiceProvider);
  return service.getTaskCounts(filter);
});

final tasksProvider = AsyncNotifierProvider<TasksNotifier, List<Task>>(
  TasksNotifier.new,
);

/// Πότε διαβάστηκαν τελευταία φορά οι εκκρεμότητες από τη βάση.
///
/// Τροφοδοτεί την ένδειξη «στοιχεία της 18:04». Σε κοινόχρηστη βάση η οθόνη δεν
/// μπορεί να υποσχεθεί ότι είναι πάντα φρέσκια — μπορεί όμως να πει πόσο παλιά
/// είναι, και αυτό είναι η τίμια εκδοχή της ίδιας πληροφορίας.
class TasksFreshnessNotifier extends Notifier<DateTime?> {
  @override
  DateTime? build() => null;

  void stamp([DateTime? at]) => state = at ?? DateTime.now();
}

final tasksFreshnessProvider =
    NotifierProvider<TasksFreshnessNotifier, DateTime?>(
      TasksFreshnessNotifier.new,
    );

/// Αναβολή [invalidate] του [tasksProvider] στο επόμενο frame — αποφυγή
/// `FlutterError` (locked widget tree) μετά το κλείσιμο διαλόγου επεξεργασίας.
Future<void> deferTasksProviderInvalidate(WidgetRef ref) async {
  if (!ref.context.mounted) return;
  return runAfterNextFrame(() {
    if (ref.context.mounted) {
      ref.invalidate(tasksProvider);
    }
  });
}

/// Πλήθος open+snoozed για badge στο κύριο μενού. Ανανεώνεται όταν αλλάζει η λίστα tasks.
final globalPendingTasksCountProvider = FutureProvider<int>((ref) async {
  ref.watch(tasksProvider);
  return ref.read(taskServiceProvider).getGlobalPendingTasksCount();
});

/// Συνολικό πλήθος εγγραφών στον πίνακα tasks (χωρίς φίλτρα UI).
/// Δεν παρακολουθεί [tasksProvider] — ανανεώνεται ρητά μετά από προσθήκη/διαγραφή.
final totalTasksCountProvider = FutureProvider<int>((ref) async {
  return ref.read(taskServiceProvider).getTotalTaskCount();
});

class TasksNotifier extends AsyncNotifier<List<Task>> {
  Future<void>? _refreshInFlight;

  @override
  Future<List<Task>> build() async {
    final service = ref.read(taskServiceProvider);
    final filter = ref.watch(effectiveTaskFilterProvider);
    return service.getFilteredTasks(filter);
  }

  void _afterTasksMutated({bool refreshAnalytics = false}) {
    ref.invalidate(totalTasksCountProvider);
    ref.invalidate(orphanCallsProvider);
    if (refreshAnalytics) {
      ref.invalidate(taskAnalyticsProvider);
      unawaited(
        ref.read(taskAnalyticsDateProvider.notifier).refreshCreationSpan(),
      );
    }
  }

  Future<void> refresh() async {
    if (_refreshInFlight != null) {
      await _refreshInFlight;
      return;
    }
    final service = ref.read(taskServiceProvider);
    final filter = ref.read(effectiveTaskFilterProvider);
    _refreshInFlight = () async {
      state = await AsyncValue.guard(() => service.getFilteredTasks(filter));
      if (state.hasError) {
        ref.invalidateSelf();
        return;
      }
      // Η σφραγίδα μπαίνει ΕΔΩ, στο ένα σημείο απ' όπου περνούν όλες οι
      // αναγνώσεις: χειροκίνητο κουμπί, αυτόματος φρουρός και κάθε αποθήκευση.
      // Σε δεύτερο σημείο θα ξεχνιόταν, και η ένδειξη θα έλεγε ψέματα.
      ref.read(tasksFreshnessProvider.notifier).stamp();
    }();
    try {
      await _refreshInFlight;
    } finally {
      _refreshInFlight = null;
    }
  }

  Future<void> addTask(Task task) async {
    final service = ref.read(taskServiceProvider);
    await service.createTask(task);
    _afterTasksMutated(refreshAnalytics: true);
    await refresh();
  }

  /// Με [force] `true` η εγγραφή περνά παρά τη διένεξη — ο χρήστης είδε τι
  /// άλλαξε και επέλεξε να κρατήσει τη δική του εικόνα.
  /// Το [expected] είναι η εγγραφή όπως τη διάβασε η οθόνη — χωρίς αυτήν ο
  /// φρουρός δεν ξεχωρίζει τη δική μου αλλαγή από την ξένη.
  Future<void> updateTask(
    Task task, {
    Task? expected,
    bool force = false,
  }) async {
    final service = ref.read(taskServiceProvider);
    await service.updateTask(task, expected: expected, force: force);
    _afterTasksMutated(refreshAnalytics: true);
    await refresh();
  }

  Future<void> deleteTask(int id) async {
    final service = ref.read(taskServiceProvider);
    await service.deleteTask(id);
    _afterTasksMutated(refreshAnalytics: true);
    await refresh();
  }

  /// Κλείσιμο εκκρεμότητας.
  ///
  /// Δέχεται ολόκληρη την [task] και όχι μόνο το αναγνωριστικό, ώστε η σφραγίδα
  /// «όπως τη διάβασε η οθόνη» να φτάνει **πάντα** στον φρουρό: με σκέτο `id` ο
  /// καλών μπορούσε να την ξεχάσει, και η διένεξη θα περνούσε αόρατη.
  Future<void> closeTask(
    Task task,
    String solutionNotes, {
    bool force = false,
  }) async {
    final id = task.id;
    if (id == null) return;
    final service = ref.read(taskServiceProvider);
    await service.closeTask(
      id,
      solutionNotes,
      expectedUpdatedAt: task.updatedAt,
      force: force,
    );
    _afterTasksMutated(refreshAnalytics: true);
    await refresh();
  }
}

/// Κλήσεις pending/open χωρίς αντίστοιχο task. Invalidate μετά δημιουργία tasks.
final orphanCallsProvider = FutureProvider<List<OrphanCall>>((ref) async {
  final service = ref.read(taskServiceProvider);
  return service.getCallsWithoutTask();
});
