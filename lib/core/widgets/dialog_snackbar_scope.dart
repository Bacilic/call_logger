import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Τοπικό [ScaffoldMessenger] μέσα σε διάλογο — τα snackbar εμφανίζονται πάνω από το overlay.
class DialogSnackbarScope extends StatelessWidget {
  const DialogSnackbarScope({
    required this.messengerKey,
    required this.child,
    super.key,
  });

  final GlobalKey<ScaffoldMessengerState> messengerKey;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ScaffoldMessenger(
      key: messengerKey,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: child,
      ),
    );
  }
}

/// Mixin για State διαλόγου με τοπικό messenger και προαιρετική αντιγραφή κειμένου.
mixin DialogSnackbarHost<T extends StatefulWidget> on State<T> {
  final GlobalKey<ScaffoldMessengerState> dialogMessengerKey =
      GlobalKey<ScaffoldMessengerState>();

  void showDialogSnackBar(SnackBar snackBar, {String? copyText}) {
    if (!mounted) return;
    final messenger = dialogMessengerKey.currentState;
    if (messenger == null) return;

    final textToCopy = (copyText ?? '').trim();
    if (textToCopy.isEmpty) {
      messenger.showSnackBar(snackBar);
      return;
    }

    messenger.showSnackBar(
      SnackBar(
        content: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: snackBar.content),
            IconButton(
              tooltip: 'Αντιγραφή',
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              icon: const Icon(Icons.content_copy_outlined, size: 18),
              color: Theme.of(context).colorScheme.inversePrimary,
              onPressed: () => unawaited(_copyDialogSnackBarText(textToCopy)),
            ),
          ],
        ),
        duration: snackBar.duration,
        behavior: snackBar.behavior,
      ),
    );
  }

  Future<void> _copyDialogSnackBarText(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    dialogMessengerKey.currentState?.hideCurrentSnackBar();
    showDialogSnackBar(
      const SnackBar(
        content: Text('Αντιγραφή στο πρόχειρο.'),
        duration: Duration(seconds: 2),
      ),
    );
  }
}
