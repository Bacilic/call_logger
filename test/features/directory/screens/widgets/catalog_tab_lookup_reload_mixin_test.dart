// Αναπαραγωγή: setState/markNeedsBuild κατά το build όταν προσάρτηση listener
// lookup γίνεται με βρόμικο lookupServiceProvider (ζωντανή αλλαγή βάσης).
//
//   flutter test test/features/directory/screens/widgets/catalog_tab_lookup_reload_mixin_test.dart

import 'package:call_logger/core/services/lookup_service.dart';
import 'package:call_logger/features/calls/layout/calls_field_groups_provider.dart';
import 'package:call_logger/features/calls/provider/lookup_provider.dart';
import 'package:call_logger/features/directory/screens/widgets/catalog_tab_lookup_reload_mixin.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _MinimalCatalogTab extends ConsumerStatefulWidget {
  const _MinimalCatalogTab();

  @override
  ConsumerState<_MinimalCatalogTab> createState() => _MinimalCatalogTabState();
}

class _MinimalCatalogTabState extends ConsumerState<_MinimalCatalogTab>
    with CatalogTabLookupReloadMixin {
  @override
  void initState() {
    super.initState();
    attachCatalogLookupReloadListener();
  }

  @override
  void dispose() {
    detachCatalogLookupReloadListener();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const Text('catalog-tab');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'attachCatalogLookupReloadListener δεν προκαλεί setState during build '
    'όταν το lookup είναι βρόμικο και υπάρχει ζωντανός listener στο '
    'callsFieldGroupsProvider',
    (tester) async {
      final container = ProviderContainer(
        overrides: [
          lookupServiceProvider.overrideWith((ref) async {
            return LookupLoadResult(service: LookupService.instance);
          }),
        ],
      );
      addTearDown(container.dispose);

      // Κρατά ζωντανό τον callsFieldGroupsProvider → παρακολουθεί lookup.
      final groupsSub = container.listen(callsFieldGroupsProvider, (_, _) {});
      addTearDown(groupsSub.close);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(body: SizedBox.shrink()),
          ),
        ),
      );

      await container.read(lookupServiceProvider.future);
      // Αφήνει το lookup «βρόμικο» όπως μετά από ζωντανή αλλαγή βάσης.
      container.invalidate(lookupServiceProvider);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: Consumer(
                builder: (context, ref, _) {
                  ref.watch(callsFieldGroupsProvider);
                  return const _MinimalCatalogTab();
                },
              ),
            ),
          ),
        ),
      );

      // Flush Riverpod scheduler + post-frame προσάρτησης listener.
      await tester.pump();
      await tester.pump(Duration.zero);

      expect(
        tester.takeException(),
        isNull,
        reason:
            'Δεν πρέπει να εμφανίζεται setState()/markNeedsBuild() during build '
            'όταν ανοίγει καρτέλα καταλόγου με βρόμικο lookup',
      );
      expect(find.text('catalog-tab'), findsOneWidget);

      // Καθαρισμός δέντρου πριν το tearDown (χωρίς pending timers).
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(Duration.zero);
    },
  );
}
