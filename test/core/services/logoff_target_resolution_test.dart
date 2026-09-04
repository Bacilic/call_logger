// Ποιον διακομιστή ρωτάμε και ποια συνεδρία προτείνουμε όταν ο χειριστής
// ζητά «Αποσύνδεση χρήστη» από την κάρτα εξοπλισμού.
//
// Οι κανόνες εδώ κρίνουν ποια συνεδρία θα κλείσει — δηλαδή ποιανού η δουλειά
// θα διακοπεί. Γι' αυτό ελέγχονται όλοι, και ιδίως οι περιπτώσεις όπου η
// σωστή απάντηση είναι «μην προτείνεις τίποτα».
//
//   flutter test test/core/services/logoff_target_resolution_test.dart

import 'package:call_logger/core/models/managed_server.dart';
import 'package:call_logger/core/services/server_sessions/logoff_target_resolution.dart';
import 'package:call_logger/core/services/server_sessions/server_session_messages.dart';
import 'package:call_logger/core/services/server_sessions/server_session_models.dart';
import 'package:flutter_test/flutter_test.dart';

ManagedServer _server({
  required int id,
  required String host,
  String name = 'Διακομιστής',
  bool isDefault = false,
}) {
  return ManagedServer(
    id: id,
    name: name,
    host: host,
    adminUser: 'Administrator',
    adminPassword: 'κωδικός',
    isDefault: isDefault,
    sortOrder: id,
  );
}

ServerSession _session({
  required int id,
  required String username,
  String station = '',
  ServerSessionState state = ServerSessionState.active,
}) {
  return ServerSession(
    sessionId: id,
    username: username,
    state: state,
    stationName: station,
  );
}

void main() {
  group('Επιλογή διακομιστή', () {
    final primary = _server(
      id: 1,
      host: '192.168.13.82',
      name: 'Medico κύριος',
      isDefault: true,
    );
    final secondary = _server(
      id: 2,
      host: '192.168.13.83',
      name: 'Medico δευτερεύων',
    );
    final servers = [primary, secondary];

    test('η διεύθυνση του εξοπλισμού διαλέγει τον αντίστοιχο διακομιστή', () {
      final choice = LogoffTargetResolution.resolveServer(
        equipmentRemoteAddress: '192.168.13.83',
        servers: servers,
      );

      expect(choice.server?.id, secondary.id);
      expect(choice.origin, ServerTargetOrigin.fromEquipment);
    });

    test('χωρίς διεύθυνση πέφτουμε στον προεπιλεγμένο', () {
      final choice = LogoffTargetResolution.resolveServer(
        equipmentRemoteAddress: '   ',
        servers: servers,
      );

      expect(choice.server?.id, primary.id);
      expect(choice.origin, ServerTargetOrigin.fallbackNoAddress);
    });

    test(
      'διεύθυνση που δεν είναι καταχωρημένος διακομιστής ΔΕΝ ακολουθείται',
      () {
        // Το πεδίο «Απομακρυσμένη» είναι ελεύθερο κείμενο: μπορεί κάλλιστα να
        // κρατά όνομα υπολογιστή γραφείου. Ένα τυφλό ταξίδι εκεί θα ζητούσε
        // τερματισμό συνεδρίας σε λάθος μηχάνημα.
        final choice = LogoffTargetResolution.resolveServer(
          equipmentRemoteAddress: 'PC3698',
          servers: servers,
        );

        expect(choice.server?.id, primary.id);
        expect(choice.origin, ServerTargetOrigin.fallbackUnknownAddress);
        expect(choice.explanation, contains('PC3698'));
      },
    );

    test('χωρίς κανέναν διακομιστή δεν επιστρέφεται στόχος', () {
      final choice = LogoffTargetResolution.resolveServer(
        equipmentRemoteAddress: '192.168.13.82',
        servers: const [],
      );

      expect(choice.server, isNull);
      expect(choice.origin, ServerTargetOrigin.none);
    });

    test('χωρίς σημαδεμένη προεπιλογή χρησιμοποιείται ο πρώτος', () {
      final choice = LogoffTargetResolution.resolveServer(
        equipmentRemoteAddress: '',
        servers: [
          _server(id: 7, host: '10.0.0.1'),
          secondary,
        ],
      );

      expect(choice.server?.id, 7);
    });
  });

  group('Αποτέλεσμα ενέργειας', () {
    test('η άρνηση πρόσβασης αναγνωρίζεται από τον κωδικό της', () {
      // Είναι η διαφορά ανάμεσα σε «ξαναδοκίμασε» και «μην το ξαναδοκιμάσεις»:
      // η άρνηση αφορά τα δικαιώματα στον διακομιστή, όχι τη συνεδρία.
      const denied = SessionLogoffResult.failure(
        'άρνηση',
        code: ServerSessionMessages.errorAccessDenied,
      );

      expect(denied.isAccessDenied, isTrue);
    });

    test('άλλη αποτυχία δεν περνά για άρνηση πρόσβασης', () {
      const timeout = SessionLogoffResult.failure('δεν απάντησε');
      const gone = SessionLogoffResult.failure(
        'χάθηκε',
        code: ServerSessionMessages.errorCtxWinstationNotFound,
      );

      expect(timeout.isAccessDenied, isFalse);
      expect(gone.isAccessDenied, isFalse);
    });

    test('η επιτυχία δεν είναι ποτέ άρνηση', () {
      expect(const SessionLogoffResult.success().isAccessDenied, isFalse);
    });
  });

  group('Πρόταση συνεδρίας', () {
    test('μία συνεδρία από τον σταθμό του εξοπλισμού προεπιλέγεται', () {
      final plan = LogoffTargetResolution.buildPlan(
        sessions: [
          _session(id: 10, username: 'nslpathall', station: 'PC3414'),
          _session(id: 11, username: 'tep2', station: 'PC3140'),
        ],
        equipmentStationName: 'PC3414',
        adminUser: 'Administrator',
      );

      expect(plan.preselectedSessionId, 10);
      expect(plan.matchCount, 1);
      expect(plan.needsExplicitChoice, isFalse);
      expect(plan.candidates.first.matchesEquipment, isTrue);
    });

    test('δύο συνεδρίες από τον ΙΔΙΟ σταθμό δεν προεπιλέγουν καμία', () {
      // Επιβεβαιωμένο στον .82: ο λογαριασμός dockardkli2 εμφανίστηκε δύο
      // φορές από το PC3686. Το αυτόματο μάντεμα θα έκλεινε λάθος συνεδρία.
      final plan = LogoffTargetResolution.buildPlan(
        sessions: [
          _session(id: 2, username: 'dockardkli2', station: 'PC3686'),
          _session(id: 9, username: 'dockardkli2', station: 'PC3686'),
        ],
        equipmentStationName: 'PC3686',
        adminUser: 'Administrator',
      );

      expect(plan.preselectedSessionId, isNull);
      expect(plan.matchCount, 2);
      expect(plan.needsExplicitChoice, isTrue);
    });

    test('όταν κανένας σταθμός δεν ταιριάζει δεν προτείνεται τίποτα', () {
      final plan = LogoffTargetResolution.buildPlan(
        sessions: [_session(id: 5, username: 'docgastr', station: 'IUSER182')],
        equipmentStationName: 'PC3414',
        adminUser: 'Administrator',
      );

      expect(plan.preselectedSessionId, isNull);
      expect(plan.matchCount, 0);
      expect(plan.candidates.single.matchesEquipment, isFalse);
    });

    test('άγνωστος σταθμός εξοπλισμού δεν ταιριάζει με κενά ονόματα', () {
      // Και οι δύο πλευρές κενές: χωρίς φρουρό, το «κενό ισούται με κενό» θα
      // πρότεινε την πρώτη τυχούσα συνεδρία.
      final plan = LogoffTargetResolution.buildPlan(
        sessions: [_session(id: 3, username: 'kapoios', station: '')],
        equipmentStationName: '',
        adminUser: 'Administrator',
      );

      expect(plan.preselectedSessionId, isNull);
      expect(plan.matchCount, 0);
    });

    test('η συνεδρία του λογαριασμού διαχειριστή σημαδεύεται', () {
      final plan = LogoffTargetResolution.buildPlan(
        sessions: [
          _session(id: 23, username: 'Administrator', station: 'PC3569'),
        ],
        equipmentStationName: 'PC3414',
        adminUser: 'administrator',
      );

      expect(plan.candidates.single.isAdminAccount, isTrue);
    });

    test('συνεδρίες σε μεταβατική κατάσταση δεν προσφέρονται', () {
      final plan = LogoffTargetResolution.buildPlan(
        sessions: [
          _session(id: 0, username: '', state: ServerSessionState.other),
          _session(
            id: 4,
            username: 'listener',
            state: ServerSessionState.other,
          ),
          _session(id: 8, username: 'pragmatikos', station: 'PC1'),
        ],
        equipmentStationName: 'PC1',
        adminUser: 'Administrator',
      );

      expect(plan.candidates.map((c) => c.session.sessionId), [8]);
    });

    test('ταξινόμηση: πρώτα ο εξοπλισμός, μετά οι ενεργές', () {
      final plan = LogoffTargetResolution.buildPlan(
        sessions: [
          _session(
            id: 1,
            username: 'aaa',
            state: ServerSessionState.disconnected,
          ),
          _session(id: 2, username: 'bbb'),
          _session(
            id: 3,
            username: 'zzz',
            station: 'PC9',
            state: ServerSessionState.disconnected,
          ),
        ],
        equipmentStationName: 'PC9',
        adminUser: 'Administrator',
      );

      expect(plan.candidates.map((c) => c.session.sessionId), [3, 2, 1]);
    });
  });
}
