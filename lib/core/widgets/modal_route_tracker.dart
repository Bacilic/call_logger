import 'package:flutter/material.dart';

/// Μετρά πόσοι διάλογοι είναι ανοιχτοί αυτή τη στιγμή.
///
/// Υπάρχει για μία ερώτηση: «δουλεύει τώρα ο χρήστης πάνω σε κάτι;». Την κάνει
/// η αυτόματη ανανέωση της κοινόχρηστης βάσης, ώστε να μην τραβήξει το χαλί
/// κάτω από τα πόδια κάποιου που γράφει λύση σε διάλογο.
///
/// **Ένα σημείο για όλους τους διαλόγους:** μπαίνει στα `navigatorObservers`
/// της εφαρμογής, οπότε πιάνει κάθε `showDialog` — και τα 295 σημεία της
/// εφαρμογής — χωρίς κανένα από αυτά να χρειάζεται να το ξέρει.
///
/// Μετρά μόνο [PopupRoute] (διάλογοι, μενού, φύλλα): η κανονική πλοήγηση
/// ανάμεσα σε οθόνες δεν είναι «απασχόληση».
class ModalRouteTracker extends NavigatorObserver {
  int _openCount = 0;

  /// Καλείται όταν κλείσει ο **τελευταίος** ανοιχτός διάλογος.
  ///
  /// Έτσι μια κρατημένη ανανέωση εκτελείται με το που ελευθερώνεται ο χρήστης,
  /// αντί να περιμένει τον επόμενο κύκλο του φρουρού.
  VoidCallback? onAllClosed;

  /// Ο ανοιχτός διάλογος αντέχει ανανέωση **όσο** αυτή η συνθήκη είναι αληθής.
  ///
  /// Υπάρχει για μία οθόνη με ξεχωριστή ανάγκη: η Αναφορά Lansweeper είναι
  /// διάλογος, και είναι ακριβώς εκείνη που χρειάζεται περισσότερο τη φρεσκάδα
  /// — δύο άνθρωποι δουλεύουν την ίδια ουρά κάθε μεσημέρι. Όσο ο χρήστης δεν
  /// έχει τσεκάρει καμία κλήση, η λίστα μπορεί να ανανεωθεί χωρίς να του
  /// χαλάσει τίποτα· μόλις επιλέξει, παγώνει.
  ///
  /// **Συνθήκη και όχι σημαία:** η επιλογή αλλάζει σε επτά σημεία μέσα στον
  /// διάλογο. Μια σημαία θα ήθελε ενημέρωση σε καθένα, και το πρώτο που θα την
  /// ξεχνούσε θα άφηνε την ουρά παγωμένη για πάντα.
  bool Function()? refreshTolerantWhile;

  /// Δουλεύει τώρα ο χρήστης πάνω σε κάτι που δεν πρέπει να διακοπεί;
  bool get isUserBusy {
    if (_openCount == 0) return false;
    final tolerant = refreshTolerantWhile;
    // Μόνο όταν ο ανεκτικός διάλογος είναι ο ΜΟΝΟΣ ανοιχτός: ένας δεύτερος από
    // πάνω του (επιβεβαίωση, φόρμα, επιλογέας) σημαίνει ότι ο χρήστης όντως
    // δουλεύει, ό,τι κι αν λέει ο από κάτω.
    if (tolerant != null && _openCount == 1 && tolerant()) return false;
    return true;
  }

  bool _counts(Route<dynamic>? route) => route is PopupRoute;

  void _release() {
    if (_openCount == 0) return;
    _openCount--;
    if (_openCount == 0) onAllClosed?.call();
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (_counts(route)) _openCount++;
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (_counts(route)) _release();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (_counts(route)) _release();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final was = _counts(oldRoute);
    final now = _counts(newRoute);
    if (was && !now) {
      _release();
    } else if (!was && now) {
      _openCount++;
    }
  }
}

/// Ο παρατηρητής της τρέχουσας συνεδρίας.
///
/// Καθολικός επίτηδες: ο `NavigatorObserver` δηλώνεται στο `MaterialApp`, πολύ
/// πάνω από όποιον ρωτά. Ένα δεύτερο αντίγραφο θα μετρούσε τους μισούς
/// διαλόγους και θα απαντούσε «ελεύθερος» ενώ κάποιος γράφει.
final ModalRouteTracker appModalRouteTracker = ModalRouteTracker();
