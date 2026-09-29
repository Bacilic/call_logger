import 'package:call_logger/core/services/station_shutdown_request.dart';
import 'package:call_logger/core/widgets/shutdown_request_notice.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Η ειδοποίηση που βλέπει ο συνάδελφος — και ο **κλειδωμένος** σταθμός που δεν
/// τη βλέπει κανείς.
void main() {
  StationShutdownRequest request({bool immediate = false}) =>
      StationShutdownRequest(
        fromStation: 'PC901',
        requestedAt: DateTime(2026, 9, 28, 10),
        immediate: immediate,
      );

  Future<void> pump(
    WidgetTester tester, {
    required StationShutdownRequest req,
    required VoidCallback onAccepted,
    required VoidCallback onDenied,
    Duration countdown = const Duration(seconds: 3),
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ShutdownRequestNotice(
            request: req,
            countdown: countdown,
            onAccepted: onAccepted,
            onDenied: onDenied,
          ),
        ),
      ),
    );
  }

  testWidgets(
    'σε άδεια θέση η μέτρηση τελειώνει μόνη της και η εφαρμογή κλείνει',
    (tester) async {
      var closed = false;
      await pump(
        tester,
        req: request(),
        onAccepted: () => closed = true,
        onDenied: () {},
      );

      // Κανείς δεν πατά τίποτα — ακριβώς ο κλειδωμένος σταθμός.
      await tester.pump(const Duration(seconds: 1));
      expect(closed, isFalse);
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));

      expect(closed, isTrue);
    },
  );

  testWidgets('το «Όχι τώρα» δεν κλείνει την εφαρμογή', (tester) async {
    var closed = false;
    var denied = false;
    await pump(
      tester,
      req: request(),
      onAccepted: () => closed = true,
      onDenied: () => denied = true,
    );

    await tester.tap(find.text('Όχι τώρα'));
    await tester.pump();

    expect(denied, isTrue);
    expect(closed, isFalse);

    // Και η μέτρηση που έτρεχε δεν κλείνει την εφαρμογή από πίσω.
    await tester.pump(const Duration(seconds: 5));
    expect(closed, isFalse);
  });

  testWidgets('το «Κλείσιμο τώρα» δεν περιμένει τη μέτρηση', (tester) async {
    var closed = false;
    await pump(
      tester,
      req: request(),
      countdown: const Duration(seconds: 60),
      onAccepted: () => closed = true,
      onDenied: () {},
    );

    await tester.tap(find.text('Κλείσιμο τώρα'));
    await tester.pump();

    expect(closed, isTrue);
  });

  testWidgets('το άμεσο αίτημα δεν προσφέρει άρνηση', (tester) async {
    await pump(
      tester,
      req: request(immediate: true),
      onAccepted: () {},
      onDenied: () {},
    );

    expect(find.text('Όχι τώρα'), findsNothing);
    expect(find.text('Κλείσιμο τώρα'), findsOneWidget);
  });

  testWidgets('το άμεσο αίτημα κλείνει χωρίς αναμονή λεπτού', (tester) async {
    var closed = false;
    await pump(
      tester,
      req: request(immediate: true),
      countdown: const Duration(seconds: 60),
      onAccepted: () => closed = true,
      onDenied: () {},
    );

    await tester.pump(const Duration(seconds: 1));

    expect(closed, isTrue);
  });

  testWidgets('η ειδοποίηση λέει ποιος ζητά το κλείσιμο', (tester) async {
    await pump(tester, req: request(), onAccepted: () {}, onDenied: () {});

    expect(find.textContaining('PC901'), findsOneWidget);
  });

  testWidgets('η απόφαση παίρνεται μία φορά, όχι δύο', (tester) async {
    var acceptedTimes = 0;
    await pump(
      tester,
      req: request(),
      countdown: const Duration(seconds: 60),
      onAccepted: () => acceptedTimes += 1,
      onDenied: () {},
    );

    await tester.tap(find.text('Κλείσιμο τώρα'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 120));

    expect(acceptedTimes, 1);
  });
}
