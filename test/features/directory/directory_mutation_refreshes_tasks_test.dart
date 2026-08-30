// Η διαγραφή μιας οντότητας του καταλόγου φτάνει και στις Εκκρεμότητες.
//
// Ο εξοπλισμός 5010 διαγράφηκε ΑΦΟΥ είχε δημιουργηθεί η εκκρεμότητα: όταν
// φορτώθηκε η λίστα, ο εξοπλισμός ζούσε. Χωρίς ενημέρωση, η κάρτα κρατά για
// πάντα τη μπαγιάτικη εικόνα — δείχνει τον εξοπλισμό ζωντανό και προσφέρει
// κουμπί που δεν ανοίγει τίποτα.
//
// Το τεστ χτυπά τον ΚΟΙΝΟ δρόμο κάθε μετάλλαξης καταλόγου, όχι τον βοηθό του:
// αλλιώς θα περνούσε ακόμη κι αν κανείς δεν τον καλούσε ποτέ.
//
//   flutter test test/features/directory/directory_mutation_refreshes_tasks_test.dart

import 'package:call_logger/core/services/lookup_service.dart';
import 'package:call_logger/features/calls/provider/lookup_provider.dart';
import 'package:call_logger/features/directory/providers/directory_cache_refresh.dart';
import 'package:call_logger/features/tasks/models/task.dart';
import 'package:call_logger/features/tasks/providers/tasks_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Μετρά πόσες φορές ξαναδιαβάστηκε η λίστα, χωρίς να αγγίξει βάση.
class _CountingTasksNotifier extends TasksNotifier {
  static int builds = 0;

  @override
  Future<List<Task>> build() async {
    builds++;
    return const <Task>[];
  }
}

/// Δίνει στο τεστ ένα `Ref` του ίδιου container, όπως θα το είχε ένας provider.
final _refProbe = Provider<Ref>((ref) => ref);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => _CountingTasksNotifier.builds = 0);

  ProviderContainer makeContainer() {
    final container = ProviderContainer(
      overrides: [
        tasksProvider.overrideWith(_CountingTasksNotifier.new),
        lookupServiceProvider.overrideWith(
          (ref) async => LookupLoadResult(service: LookupService.instance),
        ),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('η μετάλλαξη καταλόγου ξαναδιαβάζει τις εκκρεμότητες', () async {
    final container = makeContainer();
    container.listen(tasksProvider, (_, _) {}, fireImmediately: true);
    await container.read(tasksProvider.future);
    expect(_CountingTasksNotifier.builds, 1);

    await refreshDirectoryCaches(container.read(_refProbe));
    await container.read(tasksProvider.future);

    expect(
      _CountingTasksNotifier.builds,
      2,
      reason:
          'Η λίστα κρατά σημαίες διαγραφής των συνδεδεμένων οντοτήτων· αν δεν '
          'ξαναδιαβαστεί, η κάρτα δείχνει διαγραμμένο εξοπλισμό ως ζωντανό.',
    );
  });
}
