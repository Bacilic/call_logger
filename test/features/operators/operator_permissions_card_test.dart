import 'package:call_logger/core/models/app_permission.dart';
import 'package:call_logger/features/operators/widgets/operator_permissions_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ό,τι επέστρεψε τελευταία η κάρτα. Η κάρτα δεν κρατά κατάσταση — τη γράφει
/// στον γονέα, οπότε αυτό είναι ο «γονέας» των ελέγχων.
Map<String, bool>? _lastResult;

Future<void> _pumpCard(
  WidgetTester tester, {
  Map<String, bool> overrides = const <String, bool>{},
  bool isAdmin = false,
  bool readOnly = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: OperatorPermissionsCard(
            overrides: overrides,
            isAdmin: isAdmin,
            readOnly: readOnly,
            onChanged: (next) => _lastResult = next,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _tapPermission(WidgetTester tester, AppPermission which) async {
  final target = find.text(which.label);
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => _lastResult = null);

  testWidgets('ξετικάρισμα γράφει παράκαμψη όταν διαφέρει από την προεπιλογή', (
    tester,
  ) async {
    await _pumpCard(tester);

    // Η Περιήγηση Βάσης επιτρέπεται από προεπιλογή· το ξετικάρισμα είναι
    // απόκλιση και πρέπει να αποθηκευτεί ρητά.
    await _tapPermission(tester, AppPermission.browseDatabase);

    expect(_lastResult, {AppPermission.browseDatabase.key: false});
  });

  testWidgets(
    'επαναφορά στην προεπιλογή σβήνει την εγγραφή αντί να τη γράψει',
    (tester) async {
      await _pumpCard(
        tester,
        overrides: {AppPermission.browseDatabase.key: false},
      );

      await _tapPermission(tester, AppPermission.browseDatabase);

      expect(
        _lastResult,
        isEmpty,
        reason:
            'Αποθηκεύονται μόνο οι παρακάμψεις. Αν έμενε εγγραφή ίδια με την '
            'προεπιλογή, μια μελλοντική αλλαγή της προεπιλογής δεν θα έφτανε '
            'ποτέ σε αυτό το προφίλ.',
      );
    },
  );

  testWidgets('παράκαμψη άλλου δικαιώματος επιβιώνει της αλλαγής', (
    tester,
  ) async {
    await _pumpCard(tester, overrides: {AppPermission.fullBackup.key: true});

    await _tapPermission(tester, AppPermission.browseDatabase);

    expect(_lastResult, {
      AppPermission.fullBackup.key: true,
      AppPermission.browseDatabase.key: false,
    });
  });

  testWidgets('με σημασμένο διαχειριστή τα τικ δεν δέχονται αλλαγή', (
    tester,
  ) async {
    await _pumpCard(tester, isAdmin: true);

    final tiles = tester.widgetList<CheckboxListTile>(
      find.byType(CheckboxListTile),
    );
    expect(tiles, hasLength(AppPermission.values.length));
    for (final tile in tiles) {
      expect(
        tile.onChanged,
        isNull,
        reason:
            'Η πύλη αφήνει τον διαχειριστή να περάσει χωρίς να κοιτάξει τη '
            'λίστα — τικ που δεν κάνει τίποτα δεν πρέπει να πατιέται.',
      );
    }
  });

  testWidgets('ο διαχειριστής βλέπει γιατί η λίστα είναι ανενεργή', (
    tester,
  ) async {
    await _pumpCard(tester, isAdmin: true);

    expect(find.textContaining('δεν περνά από αυτή τη λίστα'), findsOneWidget);
  });

  testWidgets('μόνο για ανάγνωση: τα τικ δεν δέχονται αλλαγή', (tester) async {
    await _pumpCard(tester, readOnly: true);

    final tiles = tester.widgetList<CheckboxListTile>(
      find.byType(CheckboxListTile),
    );
    expect(tiles, hasLength(AppPermission.values.length));
    for (final tile in tiles) {
      expect(tile.onChanged, isNull);
    }
  });

  testWidgets('μόνο για ανάγνωση: εξηγείται ΠΟΙΟΣ τα ορίζει', (tester) async {
    // Ο λόγος είναι διαφορετικός από τον διαχειριστή, άρα και το μήνυμα: εδώ
    // ο θεατής ρωτά «γιατί δεν μπορώ εγώ», όχι «γιατί δεν χρειάζεται γι' αυτόν».
    await _pumpCard(tester, readOnly: true);

    expect(find.textContaining('μόνο ο διαχειριστής'), findsOneWidget);
    expect(find.textContaining('αφαιρέστε πρώτα τη σήμανση'), findsNothing);
  });

  testWidgets('μόνο για ανάγνωση: οι τιμές φαίνονται κανονικά', (tester) async {
    // Το νόημα της προβολής είναι ακριβώς αυτό — να δει ο χρήστης τι ισχύει
    // για αυτόν χωρίς να ρωτήσει κανέναν.
    await _pumpCard(
      tester,
      readOnly: true,
      overrides: {AppPermission.browseDatabase.key: false},
    );

    final tile = tester.widget<CheckboxListTile>(
      find.ancestor(
        of: find.text(AppPermission.browseDatabase.label),
        matching: find.byType(CheckboxListTile),
      ),
    );
    expect(tile.value, isFalse);
  });

  testWidgets('σημαίνονται ακριβώς όσα δικαιώματα δεν επιβάλλονται ακόμη', (
    tester,
  ) async {
    await _pumpCard(tester);

    expect(
      find.text('δεν ισχύει ακόμη'),
      findsNWidgets(AppPermission.notYetEnforced.length),
    );
  });
}
