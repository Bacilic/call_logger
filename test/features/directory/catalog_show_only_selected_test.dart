// Ο διακόπτης «Δείξε μόνο τα επιλεγμένα» του Καταλόγου: τι δείχνει η λίστα, τι
// γίνεται με την αναζήτηση, και πώς σβήνει μόνος του.
//
//   flutter test test/features/directory/catalog_show_only_selected_test.dart

import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/features/calls/provider/lookup_provider.dart';
import 'package:call_logger/features/directory/providers/directory_provider.dart';
import 'package:call_logger/features/directory/screens/widgets/catalog_selection_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_reporter.dart';
import '../../test_setup.dart';

const String _kAlfa = 'Αλφαμιχαηλίδης';
const String _kBita = 'Βητακωνσταντίνου';

/// Δύο υπάλληλοι με επώνυμα που δεν μοιράζονται γράμματα, ώστε μια αναζήτηση να
/// κρύβει σίγουρα τον έναν.
Future<void> _seedTwoDistinctUsers() async {
  final db = await DatabaseHelper.instance.database;
  for (final last in [_kAlfa, _kBita]) {
    await db.delete('users', where: 'last_name = ?', whereArgs: [last]);
    await db.insert('users', {
      'first_name': 'Δοκιμαστικός',
      'last_name': last,
      'is_deleted': 0,
    });
  }
}

Future<DirectoryNotifier> _loadedDirectory(ProviderContainer container) async {
  await _seedTwoDistinctUsers();
  await container.read(lookupServiceProvider.future);
  final notifier = container.read(directoryProvider.notifier);
  await notifier.loadUsers();
  return notifier;
}

List<String> _shownLastNames(ProviderContainer container) => container
    .read(directoryProvider)
    .filteredUsers
    .map((u) => u.lastName ?? '')
    .toList();

int _idOf(ProviderContainer container, String lastName) => container
    .read(directoryProvider)
    .allUsers
    .firstWhere((u) => u.lastName == lastName)
    .id!;

void main() {
  registerCallLoggerIsolatedDatabaseHooks();

  group('Κατάλογος → «Δείξε μόνο τα επιλεγμένα»', () {
    test('φέρνει πίσω επιλογή που είχε κρύψει η αναζήτηση', () async {
      final container = ProviderContainer(
        overrides: callLoggerTestProviderOverrides(),
      );
      addTearDown(container.dispose);
      final notifier = await _loadedDirectory(container);

      // Το σενάριο της καταχώρησης: επιλέγω έναν, ψάχνω κάτι άλλο που τον
      // κρύβει, επιλέγω και τον δεύτερο.
      notifier.toggleSelection(_idOf(container, _kAlfa));
      notifier.setSearchQuery('Βητακωνστ');
      expect(
        _shownLastNames(container),
        isNot(contains(_kAlfa)),
        reason: greekExpectMsg('Η αναζήτηση κρύβει τον πρώτο επιλεγμένο'),
      );
      notifier.toggleSelection(_idOf(container, _kBita));

      notifier.toggleShowOnlySelected();

      expect(
        _shownLastNames(container),
        containsAll(<String>[_kAlfa, _kBita]),
        reason: greekExpectMsg(
          'Το φίλτρο δείχνει ΟΛΟΥΣ τους επιλεγμένους, ακόμη κι όσους είχε '
          'κρύψει η αναζήτηση',
        ),
      );
      expect(
        container.read(directoryProvider).searchQuery,
        '',
        reason: greekExpectMsg('Ανάβοντας το φίλτρο, η αναζήτηση καθαρίζει'),
      );
    });

    test('κρύβει ό,τι δεν είναι επιλεγμένο', () async {
      final container = ProviderContainer(
        overrides: callLoggerTestProviderOverrides(),
      );
      addTearDown(container.dispose);
      final notifier = await _loadedDirectory(container);

      notifier.toggleSelection(_idOf(container, _kAlfa));
      notifier.toggleShowOnlySelected();

      expect(_shownLastNames(container), [_kAlfa]);
    });

    test('ξε-επιλογή μέσα στο φίλτρο βγάζει τη γραμμή από την οθόνη', () async {
      final container = ProviderContainer(
        overrides: callLoggerTestProviderOverrides(),
      );
      addTearDown(container.dispose);
      final notifier = await _loadedDirectory(container);

      final bitaId = _idOf(container, _kBita);
      notifier.toggleSelection(_idOf(container, _kAlfa));
      notifier.toggleSelection(bitaId);
      notifier.toggleShowOnlySelected();
      expect(_shownLastNames(container).length, 2);

      notifier.toggleSelection(bitaId);

      expect(
        _shownLastNames(container),
        [_kAlfa],
        reason: greekExpectMsg(
          'Με ενεργό φίλτρο η λίστα ΕΙΝΑΙ η επιλογή — ό,τι ξε-επιλέγεται φεύγει',
        ),
      );
    });

    test(
      'ο καθαρισμός επιλογής σβήνει το φίλτρο και επιστρέφει όλους',
      () async {
        final container = ProviderContainer(
          overrides: callLoggerTestProviderOverrides(),
        );
        addTearDown(container.dispose);
        final notifier = await _loadedDirectory(container);

        notifier.toggleSelection(_idOf(container, _kAlfa));
        notifier.toggleShowOnlySelected();
        expect(container.read(directoryProvider).showOnlySelected, isTrue);

        notifier.clearSelection();

        expect(
          container.read(directoryProvider).showOnlySelected,
          isFalse,
          reason: greekExpectMsg(
            'Χωρίς επιλογή το φίλτρο σβήνει μόνο του — αλλιώς ο κατάλογος θα '
            'έμοιαζε άδειος',
          ),
        );
        expect(_shownLastNames(container), containsAll([_kAlfa, _kBita]));
      },
    );

    test('«Δείξε όλα» επιστρέφει ολόκληρη τη λίστα', () async {
      final container = ProviderContainer(
        overrides: callLoggerTestProviderOverrides(),
      );
      addTearDown(container.dispose);
      final notifier = await _loadedDirectory(container);

      notifier.toggleSelection(_idOf(container, _kAlfa));
      notifier.toggleShowOnlySelected();
      notifier.toggleShowOnlySelected();

      expect(container.read(directoryProvider).showOnlySelected, isFalse);
      expect(_shownLastNames(container), containsAll([_kAlfa, _kBita]));
    });
  });

  group('CatalogSelectionBar (widget)', () {
    Widget bar({
      required bool showOnlySelected,
      required TextEditingController controller,
      VoidCallback? onToggle,
    }) {
      return MaterialApp(
        home: Scaffold(
          body: CatalogSelectionBar(
            selectedCount: 5,
            countLabel: 'επιλεγμένοι',
            showOnlySelected: showOnlySelected,
            searchController: controller,
            onToggleShowOnlySelected: onToggle ?? () {},
            onClearSelection: () {},
            actions: const [],
          ),
        ),
      );
    }

    testWidgets('το κουμπί καθαρίζει το πεδίο αναζήτησης όταν ανάβει', (
      tester,
    ) async {
      final controller = TextEditingController(text: 'ζη');
      addTearDown(controller.dispose);
      var toggled = 0;

      await tester.pumpWidget(
        bar(
          showOnlySelected: false,
          controller: controller,
          onToggle: () => toggled++,
        ),
      );
      await tester.tap(
        find.byKey(const Key('catalog_selection_filter_toggle')),
      );
      await tester.pump();

      expect(controller.text, '');
      expect(toggled, 1);
    });

    testWidgets('πατώντας «Δείξε όλα» δεν πειράζει την αναζήτηση', (
      tester,
    ) async {
      final controller = TextEditingController(text: 'ζη');
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        bar(showOnlySelected: true, controller: controller),
      );
      await tester.tap(
        find.byKey(const Key('catalog_selection_filter_toggle')),
      );
      await tester.pump();

      expect(controller.text, 'ζη');
    });
  });
}
