// Μετρητής βημάτων και καθολικές αποφάσεις της ροής αποδέσμευσης.
//
//   flutter test test/features/directory/services/asset_disconnect_session_test.dart

import 'package:call_logger/features/directory/services/asset_disconnect_models.dart';
import 'package:call_logger/features/directory/services/asset_disconnect_session.dart';
import 'package:flutter_test/flutter_test.dart';

AssetDisconnectSession _sessionWith({
  int phones = 0,
  int equipment = 0,
  String? cancelScope,
}) {
  return AssetDisconnectSession(
    items: <AssetDisconnectItem>[
      for (var i = 0; i < phones; i++) AssetDisconnectItem.phone('25${10 + i}'),
      for (var i = 0; i < equipment; i++)
        AssetDisconnectItem.equipment('EQ${100 + i}'),
    ],
    cancelScopeDescription: cancelScope,
  );
}

void main() {
  group('μετρητής βημάτων', () {
    test(
      'δέκα υπάλληλοι με 12 τηλέφωνα και 6 εξοπλισμούς δίνουν 18 βήματα',
      () {
        final session = _sessionWith(phones: 12, equipment: 6);

        expect(session.totalSteps, 18);
        expect(session.currentStep, 1);
        expect(session.remainingSteps, 18);
        expect(session.showsStepCounter, isTrue);
      },
    );

    test('προχωρά ένα βήμα τη φορά και μετρά σωστά στη μέση', () {
      final session = _sessionWith(phones: 3, equipment: 1);

      session.markResolved(const AssetDisconnectItem.phone('2510'));
      session.markResolved(const AssetDisconnectItem.phone('2511'));

      expect(session.resolvedSteps, 2);
      expect(session.currentStep, 3);
      expect(session.remainingSteps, 2);
      expect(
        assetDisconnectStepLabel(
          currentStep: session.currentStep,
          totalSteps: session.totalSteps,
        ),
        'Βήμα 3 από 4',
      );
    });

    test('ένα μοναδικό στοιχείο δεν δείχνει μετρητή («1 από 1» = θόρυβος)', () {
      final session = _sessionWith(phones: 1);
      expect(session.showsStepCounter, isFalse);
    });

    test('η ετικέτα πλαισίου εξηγεί γιατί ο μετρητής ξαναρχίζει', () {
      expect(
        assetDisconnectStepLabel(
          currentStep: 3,
          totalSteps: 8,
          contextLabel: 'Τμήμα 2 από 3',
        ),
        'Τμήμα 2 από 3 · Βήμα 3 από 8',
      );
      expect(
        assetDisconnectStepLabel(currentStep: 3, totalSteps: 8),
        'Βήμα 3 από 8',
      );
      expect(
        assetDisconnectStepLabel(
          currentStep: 3,
          totalSteps: 8,
          contextLabel: '   ',
        ),
        'Βήμα 3 από 8',
      );
    });

    test('αδήλωτο στοιχείο μεγαλώνει και το σύνολο — ποτέ «Βήμα 3 από 2»', () {
      final session = _sessionWith(phones: 2);

      session.markResolved(const AssetDisconnectItem.phone('2510'));
      session.markResolved(const AssetDisconnectItem.phone('2511'));
      session.markResolved(const AssetDisconnectItem.phone('9999'));

      expect(session.totalSteps, 3);
      expect(session.resolvedSteps, 3);
      expect(session.currentStep, lessThanOrEqualTo(session.totalSteps + 1));
    });

    test('κενές τιμές δεν μετρούν ως βήματα', () {
      final session = AssetDisconnectSession(
        items: const [
          AssetDisconnectItem.phone('2510'),
          AssetDisconnectItem.phone('   '),
          AssetDisconnectItem.equipment(''),
        ],
      );
      expect(session.totalSteps, 1);
    });
  });

  group('καθολικές αποφάσεις', () {
    test('«διαγραφή όλων» πιάνει και τηλέφωνα και εξοπλισμό', () {
      final session = _sessionWith(phones: 2, equipment: 2);
      session.applyStandingDecision(
        const AssetDisconnectStandingDecision.deleteEverything(),
      );

      expect(
        session.standingDecisionFor(AssetDisconnectItemKind.phone),
        isNotNull,
      );
      expect(
        session.standingDecisionFor(AssetDisconnectItemKind.equipment),
        isNotNull,
      );
    });

    test('«διαγραφή όλων των τηλεφώνων» αφήνει τον εξοπλισμό να ρωτηθεί', () {
      final session = _sessionWith(phones: 2, equipment: 2);
      session.applyStandingDecision(
        const AssetDisconnectStandingDecision.deletePhones(),
      );

      expect(
        session.standingDecisionFor(AssetDisconnectItemKind.phone),
        isNotNull,
      );
      expect(
        session.standingDecisionFor(AssetDisconnectItemKind.equipment),
        isNull,
      );
    });

    test('«διαγραφή όλου του εξοπλισμού» αφήνει τα τηλέφωνα να ρωτηθούν', () {
      final session = _sessionWith(phones: 2, equipment: 2);
      session.applyStandingDecision(
        const AssetDisconnectStandingDecision.deleteEquipment(),
      );

      expect(
        session.standingDecisionFor(AssetDisconnectItemKind.phone),
        isNull,
      );
      expect(
        session.standingDecisionFor(AssetDisconnectItemKind.equipment),
        isNotNull,
      );
    });

    test('η απόφαση μεταφράζεται στο σωστό αποτέλεσμα ανά στοιχείο', () {
      expect(
        const AssetDisconnectStandingDecision.deleteEverything()
            .toItemResult()
            .choice,
        SharedAssetDisconnectChoice.delete,
      );
      expect(
        const AssetDisconnectStandingDecision.keepEverything()
            .toItemResult()
            .choice,
        SharedAssetDisconnectChoice.keepInDepartment,
      );

      const target = SharedAssetTransferTarget.existing(7);
      final transfer = const AssetDisconnectStandingDecision.transferEverything(
        target,
      ).toItemResult();
      expect(transfer.choice, SharedAssetDisconnectChoice.transfer);
      expect(transfer.transferTarget?.departmentId, 7);
    });
  });

  group('γραμμές στοιχείων — ποτέ ξεροί αριθμοί', () {
    test('κάθε στοιχείο λέει ποιανού είναι και από πού', () {
      const item = AssetDisconnectItem.phone(
        '2216',
        ownerName: 'Καλλιρρόη Βλαχάκη',
        departmentId: 4,
        departmentName: 'Γραφείο ιατρών Ψυχιατρικής #4',
      );

      expect(
        assetDisconnectItemLine(item),
        '2216 · Καλλιρρόη Βλαχάκη (Γραφείο ιατρών Ψυχιατρικής #4)',
      );
    });

    test('χωρίς κάτοχο γράφεται «κοινόχρηστο»', () {
      const item = AssetDisconnectItem.equipment(
        '526',
        departmentId: 9,
        departmentName: 'Άδειες',
      );

      expect(assetDisconnectItemLine(item), '526 · κοινόχρηστο (Άδειες)');
    });

    test('το ιστορικό μπαίνει στο τέλος της γραμμής', () {
      const item = AssetDisconnectItem.equipment(
        '2101',
        ownerName: 'Βασιλική Οικονόμου',
        departmentId: 2,
        departmentName: 'Ακτινολογικό',
      );

      expect(
        assetDisconnectItemLine(
          item,
          history: const AssetHistoryLinks(calls: 3, tasks: 1),
        ),
        '2101 · Βασιλική Οικονόμου (Ακτινολογικό) · 3 κλήσεις · 1 εκκρεμότητα',
      );
    });

    test(
      'χωρίς ιστορικό δεν γράφεται τίποτα — ο κάτοχος δεν είναι «σύνδεση»',
      () {
        expect(assetDisconnectHistoryLabel(const AssetHistoryLinks()), '');
        expect(assetDisconnectHistoryLabel(null), '');
      },
    );
  });

  group('παραμονή ή μεταφορά — ανάλογα με τα τμήματα', () {
    test('όλα στο ίδιο τμήμα: η παραμονή έχει νόημα', () {
      final session = AssetDisconnectSession(
        items: const [
          AssetDisconnectItem.phone(
            '2510',
            departmentId: 7,
            departmentName: 'Άδειες',
          ),
          AssetDisconnectItem.equipment(
            'EQ1',
            departmentId: 7,
            departmentName: 'Άδειες',
          ),
        ],
      );

      expect(session.commonRemainingDepartmentId, 7);
      expect(session.commonRemainingDepartmentName, 'Άδειες');
      expect(session.remainingDepartmentCount, 1);
    });

    test('διαφορετικά τμήματα: καμία κοινή «παραμονή»', () {
      final session = AssetDisconnectSession(
        items: const [
          AssetDisconnectItem.phone(
            '2510',
            departmentId: 7,
            departmentName: 'Άδειες',
          ),
          AssetDisconnectItem.equipment(
            'EQ1',
            departmentId: 4,
            departmentName: 'Ψυχιατρική',
          ),
        ],
      );

      expect(session.commonRemainingDepartmentId, isNull);
      expect(session.commonRemainingDepartmentName, isNull);
      expect(session.remainingDepartmentCount, 2);
    });

    test('μόλις λυθεί το ξένο στοιχείο, το τμήμα ξαναγίνεται κοινό', () {
      final session = AssetDisconnectSession(
        items: const [
          AssetDisconnectItem.phone(
            '2510',
            departmentId: 4,
            departmentName: 'Ψυχιατρική',
          ),
          AssetDisconnectItem.equipment(
            'EQ1',
            departmentId: 7,
            departmentName: 'Άδειες',
          ),
          AssetDisconnectItem.equipment(
            'EQ2',
            departmentId: 7,
            departmentName: 'Άδειες',
          ),
        ],
      );

      expect(session.commonRemainingDepartmentName, isNull);
      session.markResolved(const AssetDisconnectItem.phone('2510'));
      expect(session.commonRemainingDepartmentName, 'Άδειες');
    });
  });

  group('μηνύματα «τι πρόκειται να συμβεί»', () {
    test('μικτό πλήθος γράφεται «12 τηλέφωνα και 6 εξοπλισμοί»', () {
      expect(
        assetDisconnectCountPhrase(phoneCount: 12, equipmentCount: 6),
        '12 τηλέφωνα και 6 εξοπλισμοί',
      );
      expect(
        assetDisconnectCountPhrase(phoneCount: 1, equipmentCount: 0),
        '1 τηλέφωνο',
      );
      expect(
        assetDisconnectCountPhrase(phoneCount: 0, equipmentCount: 1),
        '1 εξοπλισμός',
      );
    });

    test(
      'η επικεφαλίδα δεν απαριθμεί — τα στοιχεία έχουν δικές τους γραμμές',
      () {
        final items = <AssetDisconnectItem>[
          for (var i = 0; i < 8; i++) AssetDisconnectItem.phone('25${10 + i}'),
        ];

        final headline = assetDisconnectBulkPreviewHeadline(
          choice: SharedAssetDisconnectChoice.delete,
          items: items,
        );

        expect(headline, 'Θα διαγραφούν 8 τηλέφωνα:');
        expect(headline, isNot(contains('•')));
        expect(headline, isNot(contains('ακόμα')));
      },
    );

    test('η διαγραφή δηλώνει ότι αναιρείται — ποτέ «οριστική»', () {
      expect(assetDisconnectUndoReminder, contains('Αναίρεση'));
      expect(
        assetDisconnectUndoReminder.toLowerCase(),
        isNot(contains('οριστικ')),
      );
    });

    test('η παραμονή ΔΕΝ ονομάζει τμήμα στην επικεφαλίδα', () {
      final headline = assetDisconnectBulkPreviewHeadline(
        choice: SharedAssetDisconnectChoice.keepInDepartment,
        items: const [
          AssetDisconnectItem.phone('2510'),
          AssetDisconnectItem.phone('2511'),
        ],
      );

      expect(headline, 'Θα παραμείνουν στο τμήμα τους 2 τηλέφωνα:');
    });

    test('η μεταφορά ονομάζει το τμήμα προορισμού', () {
      final headline = assetDisconnectBulkPreviewHeadline(
        choice: SharedAssetDisconnectChoice.transfer,
        items: const [
          AssetDisconnectItem.phone('2510'),
          AssetDisconnectItem.equipment('EQ100'),
        ],
        transferDepartmentName: 'Αποθήκη Πληροφορικής',
      );

      expect(
        headline,
        'Θα μεταφερθούν στο «Αποθήκη Πληροφορικής» 1 τηλέφωνο και 1 εξοπλισμός:',
      );
    });

    test('ο τίτλος δηλώνει πλήθος και ότι δεν θα ξαναρωτηθεί', () {
      expect(
        assetDisconnectBulkTitle(
          choice: SharedAssetDisconnectChoice.delete,
          itemCount: 18,
        ),
        'Διαγραφή 18 στοιχείων χωρίς άλλη ερώτηση',
      );
    });

    test('στο πρώτο βήμα λέει «όλα», μετά «υπόλοιπα»', () {
      expect(
        assetDisconnectQuickActionsHeader(
          remainingSteps: 7,
          isAtFirstStep: true,
        ),
        '…ή μία απάντηση για όλα τα 7 στοιχεία',
      );
      expect(
        assetDisconnectQuickActionsHeader(
          remainingSteps: 4,
          isAtFirstStep: false,
        ),
        '…ή μία απάντηση για τα υπόλοιπα 4 στοιχεία',
      );
    });

    test('η επικεφαλίδα ατομικών ενεργειών ονομάζει το είδος', () {
      expect(
        assetDisconnectSingleActionsHeader(isPhone: true),
        'Επιλέξτε ενέργεια για αυτό το τηλέφωνο',
      );
      expect(
        assetDisconnectSingleActionsHeader(isPhone: false),
        'Επιλέξτε ενέργεια για αυτόν τον εξοπλισμό',
      );
    });
  });

  group('ακύρωση', () {
    test('δηλώνει τι ακυρώνεται και πόσες απαντήσεις χάνονται', () {
      final message = assetDisconnectCancelMessage(
        resolvedSteps: 6,
        cancelScopeDescription: 'η διαγραφή 10 υπαλλήλων',
      );

      expect(message, contains('Θα ακυρωθεί η διαγραφή 10 υπαλλήλων.'));
      expect(message, contains('Οι 6 απαντήσεις που δώσατε θα χαθούν.'));
      expect(message, contains('Τίποτα δεν έχει γραφτεί ακόμα στη βάση.'));
    });

    test('χωρίς δοσμένες απαντήσεις δεν μιλά για χαμένες απαντήσεις', () {
      final message = assetDisconnectCancelMessage(
        resolvedSteps: 0,
        cancelScopeDescription: 'η διαγραφή 3 υπαλλήλων',
      );

      expect(message, isNot(contains('θα χαθ')));
    });

    test('ένα μοναδικό στοιχείο χωρίς πλαίσιο δεν ζητά επιβεβαίωση', () {
      final session = _sessionWith(phones: 1);
      expect(session.needsCancelConfirmation, isFalse);
    });

    test('με ευρύτερο πλαίσιο ζητά επιβεβαίωση ακόμη και στο πρώτο βήμα', () {
      final session = _sessionWith(
        phones: 1,
        cancelScope: 'η διαγραφή 10 υπαλλήλων',
      );
      expect(session.needsCancelConfirmation, isTrue);
    });

    test('μετά από έστω μία απάντηση ζητά πάντα επιβεβαίωση', () {
      final session = _sessionWith(phones: 2);
      session.markResolved(const AssetDisconnectItem.phone('2510'));
      expect(session.needsCancelConfirmation, isTrue);
    });
  });
}
