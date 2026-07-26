import 'package:call_logger/core/providers/active_critical_operations_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late ProviderContainer container;
  late ActiveCriticalOperationsNotifier ops;

  setUp(() {
    container = ProviderContainer();
    ops = container.read(activeCriticalOperationsProvider.notifier);
  });

  tearDown(() => container.dispose());

  test(
    'δύο begin και μία end: η ενέργεια παραμένει ενεργή (αναπαραγωγή σφάλματος)',
    () {
      ops.begin(CriticalOperation.databaseSwitch);
      ops.begin(CriticalOperation.databaseSwitch);
      ops.end(CriticalOperation.databaseSwitch);

      expect(
        container.read(activeCriticalOperationsProvider),
        contains(CriticalOperation.databaseSwitch),
      );
    },
  );

  test('δύο begin και δύο end: φεύγει μόνο μετά τη δεύτερη end', () {
    ops.begin(CriticalOperation.databaseSwitch);
    ops.begin(CriticalOperation.databaseSwitch);
    ops.end(CriticalOperation.databaseSwitch);
    expect(
      container.read(activeCriticalOperationsProvider),
      contains(CriticalOperation.databaseSwitch),
    );

    ops.end(CriticalOperation.databaseSwitch);
    expect(
      container.read(activeCriticalOperationsProvider),
      isNot(contains(CriticalOperation.databaseSwitch)),
    );
  });

  test('μία begin και μία end: δηλώνεται και καθαρίζεται', () {
    ops.begin(CriticalOperation.databaseSwitch);
    expect(
      container.read(activeCriticalOperationsProvider),
      contains(CriticalOperation.databaseSwitch),
    );

    ops.end(CriticalOperation.databaseSwitch);
    expect(container.read(activeCriticalOperationsProvider), isEmpty);
  });

  test('διαφορετικές ενέργειες μετρώνται ανεξάρτητα', () {
    ops.begin(CriticalOperation.databaseSwitch);
    ops.begin(CriticalOperation.lansweeperTicketSubmit);

    ops.end(CriticalOperation.databaseSwitch);

    final active = container.read(activeCriticalOperationsProvider);
    expect(active, isNot(contains(CriticalOperation.databaseSwitch)));
    expect(active, contains(CriticalOperation.lansweeperTicketSubmit));
  });

  test('μετά από πλήρη εκκαθάριση, νέα begin δηλώνει ξανά κανονικά', () {
    ops.begin(CriticalOperation.databaseSwitch);
    ops.begin(CriticalOperation.databaseSwitch);
    ops.end(CriticalOperation.databaseSwitch);
    ops.end(CriticalOperation.databaseSwitch);
    expect(container.read(activeCriticalOperationsProvider), isEmpty);

    ops.begin(CriticalOperation.databaseSwitch);
    expect(
      container.read(activeCriticalOperationsProvider),
      contains(CriticalOperation.databaseSwitch),
    );
  });

  test('end χωρίς begin αφήνει κενή κατάσταση και δεν πετάει εξαίρεση', () {
    try {
      ops.end(CriticalOperation.databaseSwitch);
    } on AssertionError {
      // Σε debug το assert εμφανίζει την ανισορροπία· στην απελευθέρωση αφαιρείται.
    }
    expect(container.read(activeCriticalOperationsProvider), isEmpty);
  });
}
