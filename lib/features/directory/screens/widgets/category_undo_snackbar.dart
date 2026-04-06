import 'dart:async';

import 'package:flutter/material.dart';

const int _kCategoryUndoSnackSeconds = 5;

/// Περιεχόμενο SnackBar διαγραφής κατηγορίας με ορατή αντίστροφη μέτρηση.
class CategoryUndoSnackBarContent extends StatefulWidget {
  const CategoryUndoSnackBarContent({
    super.key,
    required this.message,
    this.tooltipMessage,
    this.showCloseIcon = false,
  });

  final String message;
  final String? tooltipMessage;
  final bool showCloseIcon;

  @override
  State<CategoryUndoSnackBarContent> createState() =>
      _CategoryUndoSnackBarContentState();
}

class _CategoryUndoSnackBarContentState extends State<CategoryUndoSnackBarContent> {
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
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: widget.tooltipMessage != null
                  ? Tooltip(
                      message: widget.tooltipMessage!,
                      child: textWidget,
                    )
                  : textWidget,
            ),
            if (widget.showCloseIcon)
              IconButton(
                icon: const Icon(Icons.close, size: 20),
                onPressed: () =>
                    ScaffoldMessenger.of(context).hideCurrentSnackBar(),
                style: IconButton.styleFrom(
                  foregroundColor: theme.colorScheme.onInverseSurface,
                  padding: const EdgeInsets.all(4),
                  minimumSize: const Size(32, 32),
                ),
              ),
          ],
        ),
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
    bool showCloseIcon = false,
    required VoidCallback onUndo,
  }) {
    messenger.showSnackBar(
      SnackBar(
        duration: const Duration(seconds: _kCategoryUndoSnackSeconds),
        content: CategoryUndoSnackBarContent(
          message: message,
          tooltipMessage: tooltipMessage,
          showCloseIcon: showCloseIcon,
        ),
        action: SnackBarAction(
          label: 'Αναίρεση',
          onPressed: onUndo,
        ),
      ),
    );
  }
}
