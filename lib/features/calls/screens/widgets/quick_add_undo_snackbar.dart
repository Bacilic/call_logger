import 'dart:async';

import 'package:flutter/material.dart';

/// Πόσο ζει η προσφορά αναίρεσης.
///
/// **Μία πηγή για δύο εμφανίσεις:** τη διάρκεια του SnackBar και τον ορατό
/// αριθμό δίπλα στο «Κλείσιμο». Δύο τιμές θα απέκλιναν σιωπηλά, και τότε η
/// μέτρηση θα έδειχνε χρόνο που δεν υπάρχει.
const int kQuickAddUndoSnackBarSeconds = 10;
const Duration kQuickAddUndoSnackBarDuration = Duration(
  seconds: kQuickAddUndoSnackBarSeconds,
);

/// Περιεχόμενο SnackBar γρήγορης καταχώρησης: μήνυμα, «Αναίρεση» και
/// «Κλείσιμο (N)» με ορατή αντίστροφη μέτρηση.
///
/// Δύο ενέργειες δεν χωρούν σε `SnackBarAction` (δέχεται μία), γι' αυτό το
/// περιεχόμενο γράφεται εδώ — ίδιο μοτίβο με τη διαγραφή εξοπλισμού. Και οι
/// δύο κρατούν την **όψη λέξης-ενέργειας** του snackbar, όχι κουμπιού.
///
/// **Γιατί «Κλείσιμο» και όχι «Προσθήκη»:** η προσθήκη έχει ήδη γίνει. Λέξη
/// που τη λέει ξανά θα υπόσχονταν δεύτερη καταχώρηση· η μόνη ενέργεια που
/// απομένει είναι να φύγει το μήνυμα από την οθόνη.
///
/// **Γιατί φαίνεται η μέτρηση:** το μήνυμα ζει [seconds] δευτερόλεπτα και μετά
/// φεύγει μόνο του — δηλαδή η προσφορά αναίρεσης λήγει. Χρόνος που τρέχει
/// χωρίς να φαίνεται είναι κρυφός κανόνας: ο αριθμός δίπλα στο «Κλείσιμο» λέει
/// πόσο μένει, και στο μηδέν συμβαίνει ακριβώς αυτό που γράφει η λέξη.
class QuickAddUndoSnackBarContent extends StatefulWidget {
  const QuickAddUndoSnackBarContent({
    required this.message,
    required this.onUndo,
    required this.onDismiss,
    this.seconds = kQuickAddUndoSnackBarSeconds,
    super.key,
  });

  final String message;
  final VoidCallback onUndo;
  final VoidCallback onDismiss;

  /// Όσο και η διάρκεια του SnackBar — μία πηγή χρόνου, δύο εμφανίσεις.
  final int seconds;

  @override
  State<QuickAddUndoSnackBarContent> createState() =>
      _QuickAddUndoSnackBarContentState();
}

class _QuickAddUndoSnackBarContentState
    extends State<QuickAddUndoSnackBarContent> {
  late int _secondsLeft;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _secondsLeft = widget.seconds;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_secondsLeft <= 1) {
        _timer?.cancel();
        setState(() => _secondsLeft = 0);
        return;
      }
      setState(() => _secondsLeft--);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Η όψη είναι εκείνη του SnackBarAction: το θέμα δίνει το χρώμα, ώστε οι
    // δύο λέξεις να μη μοιάζουν με κουμπιά φόρμας.
    final actionStyle = TextButton.styleFrom(
      foregroundColor:
          theme.snackBarTheme.actionTextColor ??
          theme.colorScheme.inversePrimary,
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          // Το μήνυμα της καταχώρησης είναι συχνά δίγραμμο (νέος χρήστης ΚΑΙ
          // συσχέτιση): κυλάει αντί να κόβεται.
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 120),
            child: SingleChildScrollView(child: Text(widget.message)),
          ),
        ),
        TextButton(
          onPressed: widget.onUndo,
          style: actionStyle,
          child: const Text('Αναίρεση'),
        ),
        TextButton(
          onPressed: widget.onDismiss,
          style: actionStyle,
          child: Text('Κλείσιμο ($_secondsLeft)'),
        ),
      ],
    );
  }
}
