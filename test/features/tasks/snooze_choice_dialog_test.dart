import 'package:call_logger/core/providers/settings_provider.dart';
import 'package:call_logger/core/providers/spell_check_provider.dart';
import 'package:call_logger/core/services/spell_check_service.dart';
import 'package:call_logger/features/tasks/models/task_settings_config.dart';
import 'package:call_logger/features/tasks/widgets/snooze_choice_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// Και οι δύο άκρες του χρόνου ορίζονται εδώ — καμία δεν έρχεται από το ρολόι
// του μηχανήματος. Αλλιώς η μορφοποίηση του chip αλλάζει ανάλογα με τη μέρα
// που τυχαίνει να τρέξει η σουίτα: η προεπισκόπηση δείχνει σκέτη ώρα όταν η
// λήξη είναι σήμερα και «τρίγραμμο + ώρα» για τις επόμενες έξι ημέρες.

/// Στιγμή αναφοράς του διαλόγου — Παρασκευή απόγευμα.
final _now = DateTime(2026, 7, 31, 18, 0);

/// Στιγμή λήξης που «θα υπολογίσει» η εφαρμογή για την επόμενη εργάσιμη:
/// επόμενη μέρα, δηλαδή μέσα στο παράθυρο «τρίγραμμο ημέρας».
final _nextBusinessDue = DateTime(2026, 8, 1, 8);

/// Λήξη «μέσα στο ωράριο» — ίδια μέρα, ώστε να ελέγχεται και η άλλη διαδρομή
/// της μορφοποίησης (σκέτη ώρα χωρίς τρίγραμμο).
final _dayEndDue = DateTime(2026, 7, 31, 20, 0);

/// Οι τρεις γρήγορες επιλογές δίνουν τρεις **διακριτές** ώρες, ώστε κάθε chip
/// να αναγνωρίζεται μονοσήμαντα από το κείμενό του.
DateTime _fakeCalculateDue(String option, DateTime from) {
  if (option == TaskSettingsConfig.kNextBusiness) return _nextBusinessDue;
  if (option == TaskSettingsConfig.kDayEnd) return _dayEndDue;
  return from.add(const Duration(hours: 1));
}

void main() {
  SnoozeChoiceResult? captured;
  var closed = false;

  Future<void> openDialog(WidgetTester tester) async {
    captured = null;
    closed = false;
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          enableSpellCheckProvider.overrideWith((ref) async => false),
          spellCheckServiceProvider.overrideWith((ref) async {
            final svc = LexiconSpellCheckService();
            await svc.init(lexiconVariants: {});
            return svc;
          }),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => TextButton(
                onPressed: () {
                  showDialog<SnoozeChoiceResult>(
                    context: ctx,
                    builder: (_) => SnoozeChoiceDialog(
                      config: TaskSettingsConfig.defaultConfig(),
                      maxRangeText: 'έως 365 ημέρες',
                      taskTitle: 'Δοκιμαστική εκκρεμότητα',
                      initialNow: _now,
                      calculateDue: _fakeCalculateDue,
                    ),
                  ).then((r) {
                    captured = r;
                    closed = true;
                  });
                },
                child: const Text('άνοιγμα'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('άνοιγμα'));
    await tester.pumpAndSettle();
  }

  testWidgets('το chip δείχνει τη στιγμή λήξης που θα εφαρμοστεί', (
    tester,
  ) async {
    await openDialog(tester);

    expect(find.text('Επόμενη εργάσιμη'), findsOneWidget);
    // Παρασκευή 18:00 → Σάββατο 08:00: αύριο, άρα «τρίγραμμο + ώρα».
    expect(find.text('ΣΑΒ 08:00'), findsOneWidget);
    // Οι δύο επιλογές που πέφτουν την ίδια μέρα: σκέτη ώρα χωρίς τρίγραμμο.
    expect(find.text('19:00'), findsOneWidget);
    expect(find.text('20:00'), findsOneWidget);

    await tester.tap(find.text('Ακύρωση'));
    await tester.pumpAndSettle();
  });

  testWidgets('η επιλογή chip επιστρέφει ακριβώς τη στιγμή που εμφανίστηκε', (
    tester,
  ) async {
    await openDialog(tester);

    await tester.tap(find.text('Επόμενη εργάσιμη'));
    await tester.pumpAndSettle();

    expect(closed, isTrue);
    expect(captured?.choice, TaskSettingsConfig.kNextBusiness);
    expect(captured?.due, _nextBusinessDue);
  });

  testWidgets('ο λόγος γράφεται πριν από την επιλογή και επιστρέφεται μαζί', (
    tester,
  ) async {
    await openDialog(tester);

    await tester.enterText(
      find.byType(TextField),
      'Περιμένω απάντηση από τον προμηθευτή',
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Επόμενη εργάσιμη'));
    await tester.pumpAndSettle();

    expect(captured?.note, 'Περιμένω απάντηση από τον προμηθευτή');
    expect(captured?.due, _nextBusinessDue);
  });

  testWidgets('«Άλλη ημερομηνία…» δεν προαποφασίζει στιγμή λήξης', (
    tester,
  ) async {
    await openDialog(tester);

    await tester.tap(find.text('Άλλη ημερομηνία…'));
    await tester.pumpAndSettle();

    expect(captured?.choice, SnoozeChoiceDialog.customChoice);
    expect(captured?.due, isNull);
  });

  testWidgets('η ακύρωση δεν επιστρέφει επιλογή', (tester) async {
    await openDialog(tester);

    await tester.tap(find.text('Ακύρωση'));
    await tester.pumpAndSettle();

    expect(closed, isTrue);
    expect(captured, isNull);
  });
}
