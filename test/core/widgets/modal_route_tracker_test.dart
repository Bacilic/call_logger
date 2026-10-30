// «Δουλεύει τώρα ο χρήστης;» — η ερώτηση που κρατά την αυτόματη ανανέωση από
// το να τραβήξει το χαλί. Ελέγχεται χωρίς οθόνη: του δίνουμε διαδρομές και
// μετράμε την απάντηση.
//
//   flutter test test/core/widgets/modal_route_tracker_test.dart

import 'package:call_logger/core/widgets/modal_route_tracker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Διάλογος — μετράει ως απασχόληση.
///
/// Ελάχιστη [PopupRoute] και όχι `DialogRoute`: εκείνη απαιτεί ζωντανό context
/// με MaterialLocalizations, ενώ ο παρατηρητής κοιτά μόνο τον τύπο διαδρομής.
Route<void> _modal() => _TestPopupRoute();

/// Διάλογος που μόνο δείχνει στοιχεία — στατιστικά, προεπισκοπήσεις.
Route<void> _readOnly() => _TestPopupRoute(settings: readOnlyRouteSettings);

/// Κανονική οθόνη — η πλοήγηση ανάμεσα σε οθόνες δεν είναι απασχόληση.
Route<void> _page() =>
    MaterialPageRoute<void>(builder: (_) => const SizedBox.shrink());

class _TestPopupRoute extends PopupRoute<void> {
  _TestPopupRoute({super.settings});

  @override
  Color? get barrierColor => null;

  @override
  bool get barrierDismissible => false;

  @override
  String? get barrierLabel => null;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) => const SizedBox.shrink();

  @override
  Duration get transitionDuration => Duration.zero;
}

void main() {
  group('ModalRouteTracker', () {
    late ModalRouteTracker tracker;

    setUp(() => tracker = ModalRouteTracker());

    test('χωρίς διαλόγους ο χρήστης είναι ελεύθερος', () {
      expect(tracker.isUserBusy, isFalse);
    });

    test('ανοιχτός διάλογος σημαίνει απασχολημένος', () {
      tracker.didPush(_modal(), null);
      expect(tracker.isUserBusy, isTrue);
    });

    test('η πλοήγηση σε οθόνη ΔΕΝ είναι απασχόληση', () {
      tracker.didPush(_page(), null);
      expect(
        tracker.isUserBusy,
        isFalse,
        reason: 'αλλιώς καμία οθόνη δεν θα ανανεωνόταν ποτέ',
      );
    });

    test('το κλείσιμο του τελευταίου διαλόγου ειδοποιεί', () {
      var released = 0;
      tracker.onAllClosed = () => released++;

      final first = _modal();
      final second = _modal();
      tracker.didPush(first, null);
      tracker.didPush(second, null);
      tracker.didPop(second, first);
      expect(released, 0, reason: 'μένει ακόμη ένας ανοιχτός');

      tracker.didPop(first, null);
      expect(released, 1);
    });

    group('ανοχή ανανέωσης', () {
      test('ανεκτικός διάλογος με αληθή συνθήκη: ελεύθερος', () {
        tracker.refreshTolerantWhile = () => true;
        tracker.didPush(_modal(), null);
        expect(tracker.isUserBusy, isFalse);
      });

      test('ανεκτικός διάλογος με ψευδή συνθήκη: απασχολημένος', () {
        // Η ουρά με τσεκαρισμένες κλήσεις — η λίστα δεν κουνιέται.
        tracker.refreshTolerantWhile = () => false;
        tracker.didPush(_modal(), null);
        expect(tracker.isUserBusy, isTrue);
      });

      test('η συνθήκη ρωτιέται κάθε φορά, δεν φωτογραφίζεται', () {
        var hasSelection = false;
        tracker.refreshTolerantWhile = () => !hasSelection;
        tracker.didPush(_modal(), null);
        expect(tracker.isUserBusy, isFalse);

        hasSelection = true;
        expect(
          tracker.isUserBusy,
          isTrue,
          reason: 'η επιλογή αλλάζει σε επτά σημεία — σημαία θα ξεχνιόταν',
        );

        hasSelection = false;
        expect(tracker.isUserBusy, isFalse);
      });

      test('δεύτερος διάλογος από πάνω ακυρώνει την ανοχή', () {
        tracker.refreshTolerantWhile = () => true;
        final queue = _modal();
        tracker.didPush(queue, null);
        expect(tracker.isUserBusy, isFalse);

        final confirm = _modal();
        tracker.didPush(confirm, queue);
        expect(
          tracker.isUserBusy,
          isTrue,
          reason: 'επιβεβαίωση ή φόρμα από πάνω σημαίνει ότι όντως δουλεύει',
        );

        tracker.didPop(confirm, queue);
        expect(tracker.isUserBusy, isFalse);
      });
    });

    group('οθόνες μόνο-ανάγνωσης στο κλείσιμο', () {
      // Απόφαση Διευθυντή 24/10/2026: ανοιχτές «Αναφορές Εκκρεμοτήτων» και
      // «Χ» → η εφαρμογή ρωτούσε για «ανοιχτό ζήτημα», ενώ δεν υπήρχε τίποτα
      // να χαθεί.
      test('μόνη της, δεν ζητά ερώτηση', () {
        tracker.didPush(_readOnly(), null);
        expect(tracker.topDialogNeedingAttention, isNull);
      });

      test('πάνω από φόρμα, η φόρμα εξακολουθεί να ρωτά', () {
        final form = _modal();
        tracker.didPush(form, null);
        tracker.didPush(_readOnly(), form);
        expect(tracker.topDialogNeedingAttention, same(form));
      });

      test('φόρμα πάνω της ρωτά κανονικά', () {
        final report = _readOnly();
        final form = _modal();
        tracker.didPush(report, null);
        tracker.didPush(form, report);
        expect(tracker.topDialogNeedingAttention, same(form));
      });

      // Ο χάρτης κτιρίου είναι ένα παράθυρο με δύο καταστάσεις: στην
      // «Προβολή» μόνο δείχνει, στην «Επεξεργασία» δουλεύει ο χρήστης.
      test('παράθυρο που μόνο δείχνει υπό συνθήκη: η συνθήκη ρωτιέται τη '
          'στιγμή του κλεισίματος', () {
        var editing = false;
        final map = _TestPopupRoute(
          settings: readOnlyRouteSettingsWhile(() => !editing),
        );
        tracker.didPush(map, null);
        expect(tracker.topDialogNeedingAttention, isNull);

        editing = true;
        expect(tracker.topDialogNeedingAttention, same(map));
      });
    });
  });
}
