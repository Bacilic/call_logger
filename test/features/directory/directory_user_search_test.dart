// Widget test: αναζήτηση χρήστη στην καρτέλα Υπάλληλοι του Καταλόγου (μετά από seed).
//
// Ολόκληρο αρχείο:
//   flutter test test/features/directory/directory_user_search_test.dart

import 'package:call_logger/features/directory/screens/widgets/users_data_table.dart';
import 'package:call_logger/main.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_reporter.dart';
import '../../test_setup.dart';

Finder _catalogUserSearchField() {
  return find.byWidgetPredicate(
    (w) =>
        w is TextField &&
        (w.decoration?.hintText?.contains('Όνομα') ?? false),
  );
}

Future<void> _openDirectoryUsersTab(WidgetTester tester) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: callLoggerTestProviderOverrides(),
      child: const MyApp(),
    ),
  );
  await tester.pump();
  await pumpUntilSettledLong(tester);
  await tester.tap(find.byKey(const ValueKey('nav_rail_directory')));
  await pumpUntilSettled(tester);
}

void main() {
  registerCallLoggerIsolatedDatabaseHooks();

  group('Αναζήτηση Καταλόγου — Υπάλληλοι (widget)', () {
    setUpAll(() async {
      await seedTestCallRowForHistorySearch();
    });

    // Καρτέλα Κατάλογος → Υπάλληλοι, αναζήτηση με kTestUserFirstName, εμφάνιση στον πίνακα.
    //   flutter test test/features/directory/directory_user_search_test.dart --plain-name "Κατάλογος: αναζήτηση χρήστη με το όνομα του seed"
    testWidgets(
      'Κατάλογος: αναζήτηση χρήστη με το όνομα του seed',
      (tester) async {
        tester.view.physicalSize = const Size(1600, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final reporter = GreekTestReportCollector();
        reporter.logStep('Φόρτωση εφαρμογής για αναζήτηση στον Κατάλογο');

        await _openDirectoryUsersTab(tester);

        reporter.logStep('Μετάβαση στον Κατάλογο (Υπάλληλοι)');
        final userSearch = _catalogUserSearchField();
        expect(
          userSearch,
          findsOneWidget,
          reason: greekExpectMsg('Πεδίο αναζήτησης καρτέλας Υπάλληλοι'),
        );
        reporter.logStep('Αναζήτηση με το όνομα χρήστη του seed');
        await tester.tap(userSearch);
        await pumpUntilSettled(tester);
        await tester.enterText(userSearch, kTestUserFirstName);
        await pumpUntilSettled(tester);

        expect(
          find.textContaining(kTestUserFirstName),
          findsWidgets,
          reason: greekExpectMsg('Ο πίνακας πρέπει να εμφανίζει το όνομα χρήστη από το seed'),
        );
        reporter.recordPass('Αναζήτηση στον Κατάλογο (Υπάλληλοι)');
        await tester.pump(const Duration(seconds: 11));
      },
      semanticsEnabled: false,
    );

    //   flutter test test/features/directory/directory_user_search_test.dart --plain-name "hover πίνακα"
    testWidgets(
      'Κατάλογος: hover πίνακα δεν κλέβει εστίαση/κείμενο αναζήτησης',
      (tester) async {
        tester.view.physicalSize = const Size(1600, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await _openDirectoryUsersTab(tester);

        final userSearch = _catalogUserSearchField();
        expect(userSearch, findsOneWidget);

        await tester.tap(userSearch);
        await tester.pump();
        tester.testTextInput.register();

        const partialQuery = 'Παπαδ';
        await tester.enterText(userSearch, partialQuery);
        await tester.pump();
        await pumpUntilSettled(tester);

        final editableFinder = find.descendant(
          of: userSearch,
          matching: find.byType(EditableText),
        );
        expect(editableFinder, findsOneWidget);

        final tableFinder = find.byType(UsersDataTable);
        expect(tableFinder, findsOneWidget);

        final tableCenter = tester.getCenter(tableFinder);
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: tableCenter);
        await mouse.moveTo(tableCenter);
        await tester.pump();

        final editableOnHover = tester.widget<EditableText>(editableFinder);
        expect(
          editableOnHover.focusNode.hasFocus,
          isTrue,
          reason: greekExpectMsg(
            'Η εστίαση πρέπει να παραμένει στο πεδίο αναζήτησης όταν ο κέρσορας μπαίνει στον πίνακα',
          ),
        );
        expect(
          editableOnHover.controller.text,
          partialQuery,
          reason: greekExpectMsg(
            'Το κείμενο αναζήτησης δεν πρέπει να κόβεται μετά από hover στον πίνακα',
          ),
        );

        const fullQuery = 'Παπαδ μαρι';
        tester.testTextInput.updateEditingValue(
          TextEditingValue(
            text: fullQuery,
            selection: TextSelection.collapsed(offset: fullQuery.length),
          ),
        );
        await tester.pump();
        await pumpUntilSettled(tester);

        final editableAfterTyping = tester.widget<EditableText>(editableFinder);
        expect(
          editableAfterTyping.controller.text,
          fullQuery,
          reason: greekExpectMsg(
            'Συνέχεια πληκτρολόγησης με hover στον πίνακα πρέπει να διατηρεί το πλήρες κείμενο',
          ),
        );

        await tester.pump(const Duration(seconds: 11));
      },
      semanticsEnabled: false,
    );
  });
}
