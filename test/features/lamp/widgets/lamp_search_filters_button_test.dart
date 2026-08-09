// Κουμπί «Φίλτρα» της αναζήτησης Λάμπας — δύο ενότητες.
//
//   flutter test test/features/lamp/widgets/lamp_search_filters_button_test.dart

import 'package:call_logger/core/database/old_database/lamp_search_filter_selection.dart';
import 'package:call_logger/core/database/old_database/lamp_unlinked_entities.dart';
import 'package:call_logger/features/lamp/widgets/lamp_search_filters_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../test_reporter.dart';

void main() {
  const richCounts = LampFilterMenuCounts(
    byKind: <LampUnlinkedEntityKind, int>{
      LampUnlinkedEntityKind.owner: 202,
      LampUnlinkedEntityKind.office: 78,
    },
    emptyRecords: 123,
    equipmentGaps: <LampEquipmentGapKind, int>{
      LampEquipmentGapKind.withoutOffice: 104,
      LampEquipmentGapKind.withoutOwner: 67,
    },
  );

  Future<LampSearchFilterSelection?> pumpAndTap(
    WidgetTester tester, {
    required LampSearchFilterSelection selection,
    LampFilterMenuCounts counts = richCounts,
    String? tapKey,
  }) async {
    LampSearchFilterSelection? changed;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: LampSearchFiltersButton(
              selection: selection,
              loadCounts: () async => counts,
              onChanged: (value) => changed = value,
            ),
          ),
        ),
      ),
    );
    if (tapKey == null) return null;
    await tester.tap(find.byKey(const Key('lamp_filters_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key(tapKey)).first);
    await tester.pump();
    return changed;
  }

  testWidgets('η ένδειξη μετρά ΕΝΟΤΗΤΕΣ, όχι επιλογές', (tester) async {
    await pumpAndTap(
      tester,
      selection: LampSearchFilterSelection.none,
    );
    expect(find.text('Φίλτρα'), findsOneWidget);

    await pumpAndTap(
      tester,
      selection: const LampSearchFilterSelection(
        unlinkedKinds: <LampUnlinkedEntityKind>{
          LampUnlinkedEntityKind.owner,
          LampUnlinkedEntityKind.office,
        },
      ),
    );
    expect(
      find.text('Φίλτρα · 1'),
      findsOneWidget,
      reason: greekExpectMsg(
        'Δύο είδη της ίδιας ενότητας είναι ένα φίλτρο, όχι δύο',
      ),
    );

    await pumpAndTap(
      tester,
      selection: const LampSearchFilterSelection(
        unlinkedKinds: <LampUnlinkedEntityKind>{LampUnlinkedEntityKind.owner},
        equipmentGaps: <LampEquipmentGapKind>{
          LampEquipmentGapKind.withoutOffice,
        },
      ),
    );
    expect(find.text('Φίλτρα · 2'), findsOneWidget);
  });

  testWidgets('το μενού δείχνει και τις δύο ενότητες με τα πλήθη τους', (
    tester,
  ) async {
    await pumpAndTap(tester, selection: LampSearchFilterSelection.none);
    await tester.tap(find.byKey(const Key('lamp_filters_button')));
    await tester.pumpAndSettle();

    expect(find.text('Χωρίς συνδεδεμένο εξοπλισμό'), findsOneWidget);
    expect(find.text('Εξοπλισμός με κενά'), findsOneWidget);
    expect(find.text('202'), findsOneWidget);
    expect(find.text('123'), findsOneWidget);
    expect(find.text('104'), findsOneWidget);
    expect(find.text('67'), findsOneWidget);
  });

  testWidgets('επιλογή είδους ασύνδετων', (tester) async {
    final changed = await pumpAndTap(
      tester,
      selection: LampSearchFilterSelection.none,
      tapKey: 'lamp_filter_owner',
    );

    expect(changed!.unlinkedKinds, <LampUnlinkedEntityKind>{
      LampUnlinkedEntityKind.owner,
    });
  });

  testWidgets('επιλογή κενού εξοπλισμού', (tester) async {
    final changed = await pumpAndTap(
      tester,
      selection: LampSearchFilterSelection.none,
      tapKey: 'lamp_filter_gap_withoutOffice',
    );

    expect(changed!.equipmentGaps, <LampEquipmentGapKind>{
      LampEquipmentGapKind.withoutOffice,
    });
    expect(changed.unlinkedKinds, isEmpty);
  });

  testWidgets('«Όλες» επιλέγει και τα τέσσερα είδη', (tester) async {
    final changed = await pumpAndTap(
      tester,
      selection: LampSearchFilterSelection.none,
      tapKey: 'lamp_filter_all',
    );

    expect(changed!.unlinkedKinds, LampUnlinkedEntityKind.values.toSet());
  });

  testWidgets('«Όλες» με όλα επιλεγμένα καθαρίζει την ενότητα', (tester) async {
    final changed = await pumpAndTap(
      tester,
      selection: LampSearchFilterSelection(
        unlinkedKinds: LampUnlinkedEntityKind.values.toSet(),
        onlyEmptyUnlinked: true,
      ),
      tapKey: 'lamp_filter_all',
    );

    expect(changed!.unlinkedKinds, isEmpty);
    expect(
      changed.onlyEmptyUnlinked,
      isFalse,
      reason: greekExpectMsg(
        'Χωρίς είδη, το «μόνο οι κενές» δεν έχει σε τι να ισχύσει — αν έμενε '
        'αναμμένο, θα ξαναχτυπούσε σιωπηλά στην επόμενη επιλογή',
      ),
    );
  });

  testWidgets('το «μόνο οι κενές» είναι ανενεργό χωρίς επιλεγμένο είδος', (
    tester,
  ) async {
    await pumpAndTap(tester, selection: LampSearchFilterSelection.none);
    await tester.tap(find.byKey(const Key('lamp_filters_button')));
    await tester.pumpAndSettle();

    CheckboxMenuButton buttonFor(String keyName) =>
        tester.widget<CheckboxMenuButton>(
          find.byWidgetPredicate(
            (w) => w is CheckboxMenuButton && w.key == Key(keyName),
          ),
        );

    expect(
      buttonFor('lamp_filter_only_empty').onChanged,
      isNull,
      reason: greekExpectMsg('Υπο-επιλογή χωρίς επιλογή δεν έχει νόημα'),
    );
  });

  testWidgets('είδος με μηδέν ταιριάσματα είναι ανενεργό', (tester) async {
    await pumpAndTap(
      tester,
      selection: LampSearchFilterSelection.none,
      counts: const LampFilterMenuCounts(
        byKind: <LampUnlinkedEntityKind, int>{LampUnlinkedEntityKind.owner: 5},
      ),
    );
    await tester.tap(find.byKey(const Key('lamp_filters_button')));
    await tester.pumpAndSettle();

    CheckboxMenuButton buttonFor(String keyName) =>
        tester.widget<CheckboxMenuButton>(
          find.byWidgetPredicate(
            (w) => w is CheckboxMenuButton && w.key == Key(keyName),
          ),
        );

    expect(
      buttonFor('lamp_filter_contract').onChanged,
      isNull,
      reason: greekExpectMsg(
        'Είδος χωρίς ταιριάσματα θα οδηγούσε σε βέβαιο κενό αποτέλεσμα',
      ),
    );
    expect(buttonFor('lamp_filter_owner').onChanged, isNotNull);
  });
}
