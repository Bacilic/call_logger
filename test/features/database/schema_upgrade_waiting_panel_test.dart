import 'package:call_logger/core/services/session_liveness_mark.dart';
import 'package:call_logger/core/services/station_shutdown_request.dart';
import 'package:call_logger/features/database/widgets/schema_upgrade_waiting_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Η οθόνη του αιτούντα: ποιον βλέπει, σε ποιον στέλνει, και τι μαθαίνει πίσω.
void main() {
  SessionLivenessMark holder({
    String station = 'PC922',
    String instance = 'run-a',
    bool listens = true,
    DateTime? lastSeen,
  }) => SessionLivenessMark(
    station: station,
    version: '0.58.0',
    startedAt: DateTime(2026, 9, 28, 8),
    lastSeen: lastSeen ?? DateTime(2026, 9, 28, 10),
    instance: instance,
    listensForShutdownRequests: listens,
  );

  Future<void> pump(
    WidgetTester tester, {
    required List<SessionLivenessMark> holders,
    Future<bool> Function(SessionLivenessMark, bool)? sendRequest,
    Future<StationShutdownReply?> Function(SessionLivenessMark)? takeDenial,
    DateTime? now,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SchemaUpgradeWaitingPanel(
            loadHolders: () async => holders,
            sendRequest: sendRequest ?? (_, _) async => true,
            takeDenial: takeDenial ?? (_) async => null,
            now: () => now ?? DateTime(2026, 9, 28, 10, 0, 17),
            myStation: 'PC901',
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('δείχνει ποιος κρατά τη βάση', (tester) async {
    await pump(tester, holders: [holder()]);

    expect(find.textContaining('PC922'), findsWidgets);
  });

  testWidgets('το αίτημα φτάνει στον σταθμό που ακούει', (tester) async {
    final sentTo = <String>[];
    await pump(
      tester,
      holders: [holder()],
      sendRequest: (h, immediate) async {
        sentTo.add('${h.station}|$immediate');
        return true;
      },
    );

    await tester.tap(find.text('Αίτημα κλεισίματος'));
    await tester.pump();

    expect(sentTo, ['PC922|false']);
  });

  testWidgets('το άμεσο κλείσιμο στέλνει άλλο είδος αιτήματος', (tester) async {
    final sentTo = <String>[];
    await pump(
      tester,
      holders: [holder()],
      sendRequest: (h, immediate) async {
        sentTo.add('${h.station}|$immediate');
        return true;
      },
    );

    await tester.tap(find.text('Άμεσο κλείσιμο'));
    await tester.pump();

    expect(sentTo, ['PC922|true']);
  });

  testWidgets('μετά την αποστολή λέει πότε θα δει ο συνάδελφος το αίτημα', (
    tester,
  ) async {
    await pump(tester, holders: [holder()]);

    await tester.tap(find.text('Αίτημα κλεισίματος'));
    await tester.pump();

    expect(find.textContaining('θα δει το αίτημα σε 0:43'), findsOneWidget);
  });

  testWidgets('σταθμός με παλιά έκδοση δεν παίρνει αίτημα', (tester) async {
    final sentTo = <String>[];
    await pump(
      tester,
      holders: [holder(listens: false)],
      sendRequest: (h, _) async {
        sentTo.add(h.station);
        return true;
      },
    );

    expect(find.textContaining('Παλιά έκδοση'), findsOneWidget);
    // Χωρίς κανέναν που να ακούει, δεν προσφέρεται καν κουμπί.
    expect(find.text('Αίτημα κλεισίματος'), findsNothing);
    expect(sentTo, isEmpty);
  });

  testWidgets(
    'όταν κάποιος ακούει και κάποιος όχι, το αίτημα πάει μόνο στον πρώτο',
    (tester) async {
      final sentTo = <String>[];
      await pump(
        tester,
        holders: [
          holder(station: 'PC922', instance: 'a'),
          holder(station: 'PC777', instance: 'b', listens: false),
        ],
        sendRequest: (h, _) async {
          sentTo.add(h.station);
          return true;
        },
      );

      await tester.tap(find.text('Αίτημα κλεισίματος'));
      await tester.pump();

      expect(sentTo, ['PC922']);
    },
  );

  testWidgets('η άρνηση του συναδέλφου φτάνει στην οθόνη', (tester) async {
    await pump(
      tester,
      holders: [holder()],
      takeDenial: (h) async => StationShutdownReply(
        fromStation: h.station,
        repliedAt: DateTime(2026, 9, 28, 10, 0, 10),
      ),
    );

    await tester.tap(find.text('Αίτημα κλεισίματος'));
    await tester.pump();
    // Ο επόμενος γύρος ανανέωσης μαζεύει την απάντηση.
    await tester.pump(const Duration(seconds: 5));
    await tester.pump();

    expect(find.textContaining('αρνήθηκε'), findsOneWidget);
  });

  testWidgets('φάκελος που δεν δέχτηκε το αίτημα το λέει', (tester) async {
    await pump(tester, holders: [holder()], sendRequest: (_, _) async => false);

    await tester.tap(find.text('Αίτημα κλεισίματος'));
    await tester.pump();

    expect(find.textContaining('δεν στάλθηκε'), findsOneWidget);
  });

  testWidgets('όταν αδειάσει το πεδίο, το λέει καθαρά', (tester) async {
    await pump(tester, holders: const []);

    expect(find.textContaining('Κανείς άλλος δεν κρατά'), findsOneWidget);
    expect(find.text('Αίτημα κλεισίματος'), findsNothing);
  });

  testWidgets('η λίστα ανανεώνεται μόνη της χωρίς Επαναδοκιμή', (tester) async {
    var holders = [holder()];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SchemaUpgradeWaitingPanel(
            loadHolders: () async => holders,
            sendRequest: (_, _) async => true,
            takeDenial: (_) async => null,
            now: () => DateTime(2026, 9, 28, 10, 0, 17),
            myStation: 'PC901',
            refreshInterval: const Duration(seconds: 2),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.textContaining('PC922'), findsWidgets);

    // Ο συνάδελφος έκλεισε την εφαρμογή του.
    holders = const [];
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();

    expect(find.textContaining('Κανείς άλλος δεν κρατά'), findsOneWidget);
  });
}
