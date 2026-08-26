import 'dart:async';

import 'package:flutter/material.dart';

const int _kCategoryUndoSnackSeconds = 5;

/// Περιεχόμενο SnackBar διαγραφής κατηγορίας με ορατή αντίστροφη μέτρηση.
class CategoryUndoSnackBarContent extends StatefulWidget {
  const CategoryUndoSnackBarContent({
    super.key,
    required this.message,
    this.tooltipMessage,
  });

  final String message;
  final String? tooltipMessage;

  @override
  State<CategoryUndoSnackBarContent> createState() =>
      _CategoryUndoSnackBarContentState();
}

class _CategoryUndoSnackBarContentState
    extends State<CategoryUndoSnackBarContent> {
  late int _secondsLeft;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _secondsLeft = _kCategoryUndoSnackSeconds;
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
    final subtle = theme.colorScheme.onInverseSurface.withValues(alpha: 0.88);

    final textWidget = Text(
      widget.message,
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Το κουμπί κλεισίματος είναι του ίδιου του SnackBar — δεν χτίζεται
        // εδώ μέσα, ώστε να δείχνει παντού ίδιο.
        if (widget.tooltipMessage != null)
          Tooltip(message: widget.tooltipMessage!, child: textWidget)
        else
          textWidget,
        const SizedBox(height: 6),
        Text(
          'Αυτόματο κλείσιμο σε $_secondsLeft δευτ.',
          style: theme.textTheme.bodySmall?.copyWith(color: subtle),
        ),
      ],
    );
  }
}

/// Εμφανίζει SnackBar διαγραφής κατηγορίας (5 δευτ., αντίστροφη μέτρηση, Αναίρεση).
class CategoryUndoSnackBar {
  CategoryUndoSnackBar._();

  static void show(
    ScaffoldMessengerState messenger, {
    required String message,
    String? tooltipMessage,
    required VoidCallback onUndo,
  }) {
    messenger.showSnackBar(
      SnackBar(
        duration: const Duration(seconds: _kCategoryUndoSnackSeconds),
        // Ρητή διάρκεια ζωής: από το Flutter 3.47 κάθε μήνυμα με κουμπί
        // ενέργειας βαφτίζεται μόνο του «μόνιμο» και δεν φεύγει ποτέ,
        // μπλοκάροντας και την ουρά των επόμενων μηνυμάτων.
        // Εδώ η ρητή δήλωση κρατά και μια υπόσχεση της οθόνης: το ίδιο το
        // μήνυμα γράφει «Αυτόματο κλείσιμο σε X δευτ.».
        persist: false,
        showCloseIcon: true,
        content: CategoryUndoSnackBarContent(
          message: message,
          tooltipMessage: tooltipMessage,
        ),
        action: SnackBarAction(label: 'Αναίρεση', onPressed: onUndo),
      ),
    );
  }
}
