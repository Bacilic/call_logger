import 'dart:async';

import 'package:flutter/foundation.dart';

/// «Τρέχει αντίγραφο;». Ζει όσο η εφαρμογή και δεν αποδεσμεύεται ποτέ. Έχει
/// δικό της τύπο ώστε ο έλεγχος διαρροών των τεστ να την εξαιρεί ονομαστικά,
/// χωρίς να τυφλωθεί για τα υπόλοιπα `ValueNotifier<bool>`.
class BackupRunningNotifier extends ValueNotifier<bool> {
  BackupRunningNotifier() : super(false);
}

/// Η μία πύλη από την οποία περνά **κάθε** αντίγραφο ασφαλείας της εφαρμογής.
///
/// Δύο αντίγραφα που γράφουν ταυτόχρονα σβήνουν το ένα το αρχείο του άλλου, και
/// η εφαρμογή μπορεί να δηλώσει επιτυχία χωρίς να υπάρχει αρχείο. Ο κανόνας
/// ζει εδώ, κι όχι σε κάθε καλούντα, ώστε μια νέα ροή να μην μπορεί να τον
/// ξεχάσει. Καλύπτει μόνο αυτή την εκτέλεση της εφαρμογής· δύο υπολογιστές στον
/// ίδιο φάκελο τους χωρίζει η εγγραφή σε προσωρινό φάκελο, [BackupWorkFolder].
abstract final class BackupRunGate {
  static final BackupRunningNotifier _running = BackupRunningNotifier();
  static Completer<void>? _finished;

  /// Για οθόνες που πρέπει να αλλάζουν όσο τρέχει αντίγραφο.
  static ValueListenable<bool> get running => _running;

  static bool get isRunning => _running.value;

  /// Τρέχει το [job] μόνο αν δεν τρέχει άλλο αντίγραφο· αλλιώς επιστρέφει
  /// `null` χωρίς να το ξεκινήσει.
  ///
  /// Ο έλεγχος και η δέσμευση γίνονται χωρίς `await` ανάμεσά τους, οπότε δύο
  /// πατήματα δεν μπορούν να περάσουν μαζί.
  static Future<T?> tryRun<T extends Object>(Future<T> Function() job) async {
    if (_finished != null) return null;
    final finished = Completer<void>();
    _finished = finished;
    _running.value = true;
    try {
      return await job();
    } finally {
      _finished = null;
      _running.value = false;
      finished.complete();
    }
  }

  /// Περιμένει όποιο αντίγραφο τρέχει τώρα· τελειώνει αμέσως αν δεν τρέχει κανένα.
  static Future<void> whenIdle() async {
    while (_finished != null) {
      await _finished!.future;
    }
  }
}
