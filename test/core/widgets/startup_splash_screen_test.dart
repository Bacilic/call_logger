import 'package:call_logger/core/init/startup_journal.dart';
import 'package:call_logger/core/init/startup_splash_artwork.dart';
import 'package:call_logger/core/widgets/startup_splash_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Η οθόνη εκκίνησης έχει μία υπόσχεση: δείχνει ό,τι έγινε και φεύγει όταν
/// πρέπει — ούτε νωρίτερα από την ελάχιστη διάρκεια, ούτε πριν πει τα βήματα.
void main() {
  late StartupJournal journal;

  setUp(() {
    journal = StartupJournal.instance..reset();
  });

  /// Χωρίς εικόνες: η οθόνη πέφτει στη χρωματική εφεδρεία και τα widget tests
  /// δεν χρειάζονται πραγματικό asset bundle.
  Widget host({
    required bool complete,
    required VoidCallback onFinished,
    Duration minimum = const Duration(milliseconds: 300),
  }) {
    return MaterialApp(
      home: StartupSplashScreen(
        appVersion: '0.36.0',
        initializationComplete: complete,
        onFinished: onFinished,
        // Χωρίς άγγιγμα των τοπικών ρυθμίσεων: η οθόνη δεν έχει δουλειά να
        // εξαρτάται από αποθηκευμένη προτίμηση για να ζωγραφίσει.
        artworkPicker: SplashArtworkPicker(
          bundle: _EmptyAssetBundle(),
          readLastAsset: () async => null,
          writeLastAsset: (_) async {},
        ),
        minimumDuration: minimum,
        lineInterval: const Duration(milliseconds: 20),
      ),
    );
  }

  testWidgets('τα βήματα του ημερολογίου φτάνουν στην οθόνη', (tester) async {
    journal.begin('Έλεγχος διαδρομής βάσης').ok();
    journal.begin('Άνοιγμα βάσης δεδομένων').ok();

    await tester.pumpWidget(host(complete: false, onFinished: () {}));
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Έλεγχος διαδρομής βάσης'), findsOneWidget);
    expect(find.text('Άνοιγμα βάσης δεδομένων'), findsOneWidget);
    await tester.pumpAndSettle(const Duration(milliseconds: 400));
  });

  testWidgets('τα βήματα χωρίς δουλειά δεν εμφανίζονται', (tester) async {
    journal.begin('Καθαρισμός υπολειμμάτων ενημέρωσης').skip();
    journal.begin('Έλεγχος υγείας βάσης').ok();

    await tester.pumpWidget(host(complete: false, onFinished: () {}));
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Καθαρισμός υπολειμμάτων ενημέρωσης'), findsNothing);
    expect(find.text('Έλεγχος υγείας βάσης'), findsOneWidget);
    await tester.pumpAndSettle(const Duration(milliseconds: 400));
  });

  testWidgets('δεν φεύγει πριν ολοκληρωθεί η αρχικοποίηση', (tester) async {
    journal.begin('Έλεγχος διαδρομής βάσης').ok();
    var finished = false;

    await tester.pumpWidget(
      host(complete: false, onFinished: () => finished = true),
    );
    await tester.pump(const Duration(seconds: 2));

    expect(finished, isFalse);
    await tester.pumpAndSettle(const Duration(milliseconds: 400));
  });

  testWidgets('δεν φεύγει πριν περάσει η ελάχιστη διάρκεια', (tester) async {
    journal.begin('Έλεγχος διαδρομής βάσης').ok();
    var finished = false;

    await tester.pumpWidget(
      host(
        complete: true,
        onFinished: () => finished = true,
        minimum: const Duration(seconds: 5),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));

    expect(finished, isFalse, reason: 'η ελάχιστη διάρκεια δεν πέρασε');
    await tester.pumpAndSettle(const Duration(milliseconds: 400));
  });

  testWidgets('φεύγει όταν όλα έχουν ειπωθεί και ο χρόνος πέρασε', (
    tester,
  ) async {
    journal.begin('Έλεγχος διαδρομής βάσης').ok();
    journal.begin('Άνοιγμα βάσης δεδομένων').ok();
    var finished = false;

    await tester.pumpWidget(
      host(complete: true, onFinished: () => finished = true),
    );
    await tester.pump(const Duration(milliseconds: 600));

    expect(finished, isTrue);
    await tester.pumpAndSettle(const Duration(milliseconds: 400));
  });

  testWidgets('η προειδοποίηση για εικόνα που λείπει μπαίνει στο ημερολόγιο', (
    tester,
  ) async {
    await tester.pumpWidget(host(complete: false, onFinished: () {}));
    await tester.pump(const Duration(milliseconds: 200));

    final warnings = journal.steps.value
        .where((s) => s.status == StartupStepStatus.warning)
        .toList();
    expect(warnings, hasLength(1));
    expect(warnings.single.label, 'Η εικόνα εκκίνησης δεν φορτώθηκε');
    await tester.pumpAndSettle(const Duration(milliseconds: 400));
  });

  testWidgets('η έκδοση φαίνεται δίπλα στο όνομα', (tester) async {
    await tester.pumpWidget(host(complete: false, onFinished: () {}));
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Καταγραφή Κλήσεων'), findsOneWidget);
    expect(find.text('έκδοση 0.36.0'), findsOneWidget);
    await tester.pumpAndSettle(const Duration(milliseconds: 400));
  });
}

/// Δέσμη assets χωρίς κανένα asset — αναγκάζει τη διαδρομή εφεδρείας.
class _EmptyAssetBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async {
    throw FlutterError('χωρίς assets στο τεστ');
  }
}
