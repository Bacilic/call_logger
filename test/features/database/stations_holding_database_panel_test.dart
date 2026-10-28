import 'package:call_logger/core/services/session_liveness_mark.dart';
import 'package:call_logger/core/services/station_shutdown_request.dart';
import 'package:call_logger/features/database/widgets/stations_holding_database_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Η οθόνη του αιτούντα: ποιον βλέπει, σε ποιον στέλνει, και τι μαθαίνει πίσω.
///
/// Ο «κοινός φάκελος» είναι εδώ ένας χάρτης: ό,τι στέλνει η οθόνη μπαίνει σε
/// αυτόν, και ό,τι μαζεύει ο παραλήπτης βγαίνει — όπως στο δίκτυο.
void main() {
  final now = DateTime(2026, 9, 28, 10, 0, 17);

  SessionLivenessMark holder({
    String station = 'PC922',
    String instance = 'run-a',
    bool listens = true,
    DateTime? startedAt,
    DateTime? lastSeen,
    bool dead = false,
    String? operator,
  }) => SessionLivenessMark(
    station: station,
    version: '0.58.0',
    startedAt: startedAt ?? DateTime(2026, 9, 28, 8),
    lastSeen: lastSeen ?? DateTime(2026, 9, 28, 10),
    instance: instance,
    listensForShutdownRequests: listens,
    databaseConnectionDead: dead,
    operatorName: operator,
  );

  late Map<String, StationShutdownRequest> folder;
  late List<String> sentTo;
  late List<SessionLivenessMark> holders;

  String keyOf(SessionLivenessMark h) => '${h.station}|${h.instance}';

  setUp(() {
    folder = {};
    sentTo = [];
    holders = [holder()];
  });

  Future<void> pump(
    WidgetTester tester, {
    String? Function(SessionLivenessMark, bool)? failSend,
    Future<StationShutdownReply?> Function(SessionLivenessMark)? takeDenial,
    Duration refreshInterval = const Duration(seconds: 5),
    bool lockedDatabase = false,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StationsHoldingDatabasePanel(
            lockedDatabase: lockedDatabase,
            loadHolders: () async => holders,
            sendRequest: (h, immediate) async {
              final failure = failSend?.call(h, immediate);
              if (failure != null) return failure;
              sentTo.add('${h.station}|$immediate');
              folder[keyOf(h)] = StationShutdownRequest(
                fromStation: 'PC901',
                requestedAt: now,
                immediate: immediate,
              );
              return null;
            },
            pendingRequest: (h) async => folder[keyOf(h)],
            takeDenial: takeDenial ?? (_) async => null,
            now: () => now,
            myStation: 'PC901',
            refreshInterval: refreshInterval,
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> nextRefresh(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 5));
    await tester.pump();
  }

  ButtonStyleButton button(WidgetTester tester, String label) =>
      tester.widget<ButtonStyleButton>(
        find.ancestor(
          of: find.text(label),
          matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
        ),
      );

  testWidgets('δείχνει ποιος κρατά τη βάση', (tester) async {
    await pump(tester);

    expect(find.textContaining('PC922'), findsWidgets);
  });

  group('κλειδωμένη βάση', () {
    // Περιστατικό 26–27/10/2026: η εφαρμογή του PC922 με νεκρή σύνδεση κράτησε
    // τη βάση όλη τη νύχτα, και ο συνάδελφος δεν ήξερε ποιον να αναζητήσει.
    testWidgets('ο πιθανός υπαίτιος ξεχωρίζει, με το όνομα του χρήστη', (
      tester,
    ) async {
      holders = [
        holder(station: 'PC3569', instance: 'run-b'),
        holder(dead: true, operator: 'Βλάσης'),
      ];
      await pump(tester, lockedDatabase: true);

      expect(find.textContaining('Πιθανότατα κρατά τη βάση'), findsOneWidget);
      expect(find.textContaining('PC922 (Βλάσης)'), findsOneWidget);
    });

    testWidgets('το αίτημα κλεισίματος πηγαίνει μόνο στον ύποπτο', (
      tester,
    ) async {
      holders = [
        holder(station: 'PC3569', instance: 'run-b'),
        holder(dead: true),
      ];
      await pump(tester, lockedDatabase: true);

      await tester.tap(find.text('Αίτημα κλεισίματος'));
      await tester.pump();

      expect(sentTo, [
        'PC922|false',
      ], reason: 'Ο συνάδελφος που απλώς περιμένει δεν φταίει.');
    });

    testWidgets('χωρίς ύποπτο, το λέει αντί να δείξει λάθος υπολογιστή', (
      tester,
    ) async {
      await pump(tester, lockedDatabase: true);

      expect(find.textContaining('Πιθανότατα'), findsNothing);
      expect(
        find.textContaining('Καμία από αυτές δεν δηλώνει κολλημένη σύνδεση'),
        findsOneWidget,
      );
    });
  });

  testWidgets('το αίτημα φτάνει στον σταθμό που ακούει', (tester) async {
    await pump(tester);

    await tester.tap(find.text('Αίτημα κλεισίματος'));
    await tester.pump();

    expect(sentTo, ['PC922|false']);
  });

  testWidgets('το άμεσο κλείσιμο στέλνει άλλο είδος αιτήματος', (tester) async {
    await pump(tester);

    await tester.tap(find.text('Άμεσο κλείσιμο'));
    await tester.pump();

    expect(sentTo, ['PC922|true']);
  });

  testWidgets('μετά την αποστολή λέει πότε θα δει ο συνάδελφος το αίτημα', (
    tester,
  ) async {
    await pump(tester);

    await tester.tap(find.text('Αίτημα κλεισίματος'));
    await tester.pump();

    expect(find.textContaining('PC922 θα το δει σε 0:43'), findsOneWidget);
  });

  testWidgets('στο άμεσο κλείσιμο λέει πότε θα ΚΛΕΙΣΕΙ η εφαρμογή — ο '
      'συνάδελφος δεν βλέπει αίτημα να απαντήσει', (tester) async {
    await pump(tester);

    await tester.tap(find.text('Άμεσο κλείσιμο'));
    await tester.pump();

    expect(
      find.textContaining('η εφαρμογή του PC922 θα κλείσει σε 0:43'),
      findsOneWidget,
    );
    expect(find.textContaining('θα το δει'), findsNothing);
  });

  testWidgets('μετά το αίτημα το κουμπί του μένει γκρίζο, το άμεσο κλείσιμο '
      'μένει διαθέσιμο για κλιμάκωση', (tester) async {
    await pump(tester);

    await tester.tap(find.text('Αίτημα κλεισίματος'));
    await tester.pump();
    await nextRefresh(tester);

    expect(button(tester, 'Αίτημα κλεισίματος').onPressed, isNull);
    expect(button(tester, 'Άμεσο κλείσιμο').onPressed, isNotNull);

    await tester.tap(find.text('Άμεσο κλείσιμο'));
    await tester.pump();

    expect(sentTo, ['PC922|false', 'PC922|true']);
    expect(button(tester, 'Άμεσο κλείσιμο').onPressed, isNull);
  });

  testWidgets('δεύτερο πάτημα δεν ξαναστέλνει', (tester) async {
    await pump(tester);

    await tester.tap(find.text('Άμεσο κλείσιμο'));
    await tester.pump();
    await tester.tap(find.text('Άμεσο κλείσιμο'));
    await tester.pump();

    expect(sentTo, ['PC922|true']);
  });

  testWidgets('όταν ο συνάδελφος μαζέψει το αίτημα, η οθόνη λέει ότι το είδε', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.text('Αίτημα κλεισίματος'));
    await tester.pump();

    folder.clear();
    await nextRefresh(tester);

    expect(find.textContaining('PC922 είδε το αίτημα'), findsOneWidget);
  });

  testWidgets('ξανάνοιγμα της οθόνης: το αίτημα που περιμένει στον φάκελο '
      'φαίνεται, και δεν προσφέρεται να ξανασταλεί', (tester) async {
    folder[keyOf(holders.single)] = StationShutdownRequest(
      fromStation: 'PC901',
      requestedAt: now,
      immediate: false,
    );

    await pump(tester);

    expect(find.textContaining('PC922 θα το δει σε 0:43'), findsOneWidget);
    expect(button(tester, 'Αίτημα κλεισίματος').onPressed, isNull);
  });

  testWidgets('ο συνάδελφος ξανάνοιξε την εφαρμογή του: κανένα «Στάλθηκε» '
      'για αίτημα που δεν του στάλθηκε ποτέ', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Άμεσο κλείσιμο'));
    await tester.pump();

    // Το PC922 μάζεψε το αίτημα, έκλεισε, και ξανάνοιξε — ίδια ταυτότητα
    // εφαρμογής, νέα εκκίνηση.
    folder.clear();
    holders = [holder(startedAt: DateTime(2026, 9, 28, 10, 0, 5))];
    await nextRefresh(tester);

    expect(find.textContaining('Στάλθηκε'), findsNothing);
    expect(find.textContaining('θα κλείσει'), findsNothing);
    expect(find.text('Μπορεί να λάβει αίτημα κλεισίματος.'), findsOneWidget);
    expect(button(tester, 'Άμεσο κλείσιμο').onPressed, isNotNull);
  });

  testWidgets('πέρασε η ώρα και ο συνάδελφος δεν το είδε: το λέει', (
    tester,
  ) async {
    holders = [holder(lastSeen: DateTime(2026, 9, 28, 9, 58))];
    folder[keyOf(holders.single)] = StationShutdownRequest(
      fromStation: 'PC901',
      requestedAt: now,
      immediate: false,
    );

    await pump(tester);

    expect(find.textContaining('δεν το έχει δει ακόμη'), findsOneWidget);
  });

  testWidgets('σταθμός με παλιά έκδοση δεν παίρνει αίτημα', (tester) async {
    holders = [holder(listens: false)];
    await pump(tester);

    expect(find.textContaining('παλιά έκδοση'), findsWidgets);
    // Χωρίς κανέναν που να ακούει, δεν προσφέρεται καν κουμπί.
    expect(find.text('Αίτημα κλεισίματος'), findsNothing);
    expect(sentTo, isEmpty);
  });

  testWidgets('εφαρμογή που μόλις ξεκίνησε δεν βαφτίζεται «παλιά έκδοση»', (
    tester,
  ) async {
    holders = [
      holder(listens: false, startedAt: DateTime(2026, 9, 28, 10, 0, 10)),
    ];
    await pump(tester);

    expect(find.textContaining('ξεκινά ακόμη'), findsOneWidget);
    expect(find.textContaining('παλιά έκδοση'), findsNothing);
  });

  testWidgets(
    'όταν κάποιος ακούει και κάποιος όχι, το αίτημα πάει μόνο στον πρώτο',
    (tester) async {
      holders = [
        holder(station: 'PC922', instance: 'a'),
        holder(station: 'PC777', instance: 'b', listens: false),
      ];
      await pump(tester);

      await tester.tap(find.text('Αίτημα κλεισίματος'));
      await tester.pump();

      expect(sentTo, ['PC922|false']);
    },
  );

  testWidgets('η άρνηση του συναδέλφου φτάνει στην οθόνη και ξαναζωντανεύει '
      'το κουμπί', (tester) async {
    StationShutdownReply? denial;
    await pump(tester, takeDenial: (h) async => denial);

    await tester.tap(find.text('Αίτημα κλεισίματος'));
    await tester.pump();
    // Ο συνάδελφος μάζεψε το αίτημα και είπε «όχι τώρα».
    folder.clear();
    denial = StationShutdownReply(
      fromStation: 'PC922',
      repliedAt: DateTime(2026, 9, 28, 10, 0, 10),
    );
    await nextRefresh(tester);

    expect(find.textContaining('αρνήθηκε'), findsOneWidget);
    expect(button(tester, 'Αίτημα κλεισίματος').onPressed, isNotNull);
  });

  testWidgets('φάκελος που δεν δέχτηκε το αίτημα λέει γιατί', (tester) async {
    await pump(
      tester,
      failSend: (_, _) => 'ο κοινός φάκελος δεν απάντησε εγκαίρως',
    );

    await tester.tap(find.text('Αίτημα κλεισίματος'));
    await tester.pump();

    expect(
      find.textContaining(
        'δεν στάλθηκε: ο κοινός φάκελος δεν απάντησε εγκαίρως',
      ),
      findsOneWidget,
    );
    expect(button(tester, 'Αίτημα κλεισίματος').onPressed, isNotNull);
  });

  testWidgets('όταν αδειάσει το πεδίο, το λέει καθαρά', (tester) async {
    holders = const [];
    await pump(tester);

    expect(find.textContaining('Κανείς άλλος δεν κρατά'), findsOneWidget);
    expect(find.text('Αίτημα κλεισίματος'), findsNothing);
  });

  testWidgets('η λίστα ανανεώνεται μόνη της χωρίς Επαναδοκιμή', (tester) async {
    await pump(tester, refreshInterval: const Duration(seconds: 2));
    expect(find.textContaining('PC922'), findsWidgets);

    // Ο συνάδελφος έκλεισε την εφαρμογή του.
    holders = const [];
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();

    expect(find.textContaining('Κανείς άλλος δεν κρατά'), findsOneWidget);
  });
}
