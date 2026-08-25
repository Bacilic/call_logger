// Οι ρυθμίσεις της φόρμας Lansweeper ζουν σε ΕΝΑ κλειδί. Δύο διαχειριστές με
// την οθόνη ανοιχτή άλλαζαν διαφορετικά πράγματα — και ο δεύτερος έγραφε
// ολόκληρο το JSON από την εικόνα που είχε φορτώσει, σβήνοντας την αλλαγή του
// πρώτου χωρίς να το μάθει κανείς.
//
// Δύο διαφορετικοί κανόνες, γιατί το κλειδί κρατά δύο είδη περιεχομένου:
//   * απλές επιλογές (προεπιλογές, διακόπτες) → σιωπηλή στοχευμένη εγγραφή
//   * λίστες που πληκτρολογεί ο χρήστης       → ρωτιέται ο άνθρωπος
//
//   flutter test test/features/history/lansweeper_ticket_submit_config_concurrent_write_test.dart

import 'dart:io';

import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/database/settings_repository.dart';
import 'package:call_logger/core/services/lansweeper_ticket_submit_config.dart';
import 'package:call_logger/core/services/settings_list_conflict.dart';
import 'package:call_logger/features/history/providers/lansweeper_ticket_submit_config_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test_setup.dart';

void main() {
  group('Ρυθμίσεις Lansweeper — δύο διαχειριστές στο ίδιο κλειδί', () {
    late Database db;

    setUpAll(() async {
      initSqfliteFfiForTests();
      final dir = await Directory.systemTemp.createTemp('lansweeper_config_');
      await DatabaseHelper.bindTestDatabaseFile('${dir.path}/config.db');
      db = await DatabaseHelper.instance.database;
    });

    setUp(() async {
      await seedIsolatedTestDatabase();
      await db.delete('app_settings');
    });

    tearDownAll(() async {
      await releaseCallLoggerTestDatabase();
    });

    Future<LansweeperTicketSubmitConfig> stored() async {
      final raw = await SettingsRepository(
        db,
      ).getSetting(kLansweeperTicketSubmitConfigSettingKey);
      return raw == null
          ? LansweeperTicketSubmitConfig.defaults()
          : LansweeperTicketSubmitConfig.decodeFromStorage(raw);
    }

    /// Μία οθόνη ρυθμίσεων, με τη δική της εικόνα των δεδομένων.
    Future<
      ({
        ProviderContainer container,
        LansweeperTicketSubmitConfigNotifier notifier,
      })
    >
    openScreen() async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      // Το provider ειναι autoDispose: χωρις ζωντανο ακροατη σβηνει στο πρωτο
      // await, οπως ακριβως θα εσβηνε αν εκλεινε η οθονη ρυθμισεων.
      final subscription = container.listen(
        lansweeperTicketSubmitConfigProvider,
        (_, _) {},
      );
      addTearDown(subscription.close);
      final notifier = container.read(
        lansweeperTicketSubmitConfigProvider.notifier,
      );
      await notifier.hydrationFuture;
      return (container: container, notifier: notifier);
    }

    test('δύο απλές επιλογές επιβιώνουν και οι δύο', () async {
      final first = await openScreen();
      final second = await openScreen();

      // Ο πρώτος αλλάζει την προεπιλεγμένη κατάσταση αιτήματος.
      await first.notifier.setDefaultTicketState('Pending');

      // Ο δεύτερος, με την οθόνη ανοιχτή από πριν, σβήνει τον χρόνο από τη
      // σημείωση. Η εικόνα του ΔΕΝ έχει την αλλαγή του πρώτου.
      await second.notifier.setIncludeNoteTime(false);

      final result = await stored();
      expect(result.includeNoteTime, isFalse, reason: 'η δική μου αλλαγή');
      expect(
        result.defaultTicketState,
        'Pending',
        reason: 'η επιλογή του συναδέλφου δεν επιτρέπεται να επανέλθει',
      );
    });

    test('πέντε διαδοχικές αλλαγές συσσωρεύονται, δεν αλληλοσβήνονται', () async {
      final screen = await openScreen();

      await screen.notifier.setNoteType('Public');
      await screen.notifier.setEnableAddNoteStep(false);
      await screen.notifier.setEnableStateUpdateStep(false);
      await screen.notifier.setRememberFormSelections(false);
      await screen.notifier.setDefaultTicketState('Closed');

      final result = await stored();
      expect(result.noteType, 'Public');
      expect(result.enableAddNoteStep, isFalse);
      expect(result.enableStateUpdateStep, isFalse);
      expect(result.rememberFormSelections, isFalse);
      expect(result.defaultTicketState, 'Closed');
    });

    test('η οθόνη μου δείχνει ό,τι όντως αποθηκεύτηκε, όχι τη δική μου εικόνα', () async {
      final first = await openScreen();
      final second = await openScreen();

      // Τιμή διαφορετική από την προεπιλογή, αλλιώς το τεστ θα περνούσε
      // ακόμη κι αν η οθόνη έδειχνε τη δική της αρχική εικόνα.
      await first.notifier.setNoteType('Public');
      await second.notifier.setIncludeNoteTime(false);

      expect(
        second.container.read(lansweeperTicketSubmitConfigProvider).noteType,
        'Public',
        reason: 'η αλλαγή του συναδέλφου φαίνεται στη δική μου οθόνη',
      );
    });

    test('λίστα που άλλαξε ο άλλος: η αποθήκευση σταματά και ρωτάει', () async {
      final first = await openScreen();
      final second = await openScreen();
      final baseline = second.container
          .read(lansweeperTicketSubmitConfigProvider)
          .ticketStates;

      // Ο πρώτος προσθέτει κατάσταση.
      await first.notifier.setTicketStates(<String>[
        ...baseline,
        'Awaiting Order',
      ], expected: baseline);

      // Ο δεύτερος σώζει τη δική του λίστα, χωρίς να ξέρει.
      await expectLater(
        () => second.notifier.setTicketStates(<String>[
          ...baseline,
          'Escalated',
        ], expected: baseline),
        throwsA(isA<SettingsListStaleException>()),
      );

      expect(
        (await stored()).ticketStates,
        contains('Awaiting Order'),
        reason: 'η προσθήκη του συναδέλφου μένει ώσπου να αποφασίσει ο άνθρωπος',
      );
    });

    test('η διένεξη λέει τι πρόσθεσε ο άλλος και τι θα χαθεί', () async {
      final first = await openScreen();
      final second = await openScreen();
      final baseline = second.container
          .read(lansweeperTicketSubmitConfigProvider)
          .ticketStates;

      await first.notifier.setTicketStates(<String>[
        ...baseline,
        'Awaiting Order',
      ], expected: baseline);

      try {
        await second.notifier.setTicketStates(
          baseline,
          expected: baseline,
        );
        fail('περιμέναμε διένεξη');
      } on SettingsListStaleException catch (stale) {
        expect(stale.conflict.addedByOther, contains('Awaiting Order'));
        expect(stale.conflict.lostIfIOverwrite, contains('Awaiting Order'));
      }
    });

    test('με force γράφεται η δική μου λίστα', () async {
      final first = await openScreen();
      final second = await openScreen();
      final baseline = second.container
          .read(lansweeperTicketSubmitConfigProvider)
          .ticketStates;

      await first.notifier.setTicketStates(<String>[
        ...baseline,
        'Awaiting Order',
      ], expected: baseline);

      await second.notifier.setTicketStates(
        baseline,
        expected: baseline,
        force: true,
      );

      expect((await stored()).ticketStates, isNot(contains('Awaiting Order')));
    });

    test('χωρίς ξένη αλλαγή η λίστα σώζεται κανονικά', () async {
      final screen = await openScreen();
      final baseline = screen.container
          .read(lansweeperTicketSubmitConfigProvider)
          .ticketStates;

      await screen.notifier.setTicketStates(<String>[
        ...baseline,
        'Escalated',
      ], expected: baseline);

      expect((await stored()).ticketStates, contains('Escalated'));
    });

    test('τα προσαρμοσμένα πεδία του άλλου δεν σβήνονται αμίλητα', () async {
      final first = await openScreen();
      final second = await openScreen();
      final baseline = second.container
          .read(lansweeperTicketSubmitConfigProvider)
          .customFields;

      await first.notifier.replaceCustomFields(<LansweeperCustomFieldDef>[
        ...baseline,
        const LansweeperCustomFieldDef(
          id: 'severity',
          apiName: 'severity',
          formLabel: 'Σοβαρότητα',
          widgetType: LansweeperFieldWidgetType.text,
        ),
      ], expected: baseline);

      await expectLater(
        () => second.notifier.replaceCustomFields(
          baseline,
          expected: baseline,
        ),
        throwsA(isA<SettingsListStaleException>()),
      );
    });
  });
}
