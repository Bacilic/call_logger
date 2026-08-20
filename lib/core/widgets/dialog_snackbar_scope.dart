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
      child: Scaffold(backgroundColor: Colors.transparent, body: child),
    );
  }
}

/// Mixin για State διαλόγου με τοπικό messenger και προαιρετική αντιγραφή κειμένου.
mixin DialogSnackbarHost<T extends StatefulWidget> on State<T> {
  final GlobalKey<ScaffoldMessengerState> dialogMessengerKey =
      GlobalKey<ScaffoldMessengerState>();

  /// Εμφανίζει το μήνυμα στον τοπικό messenger του διαλόγου· αν εκείνος δεν
  /// μπορεί να το δείξει, πέφτει στον ριζικό.
  ///
  /// **Γιατί υπάρχει η εφεδρεία:** ένας [ScaffoldMessenger] χωρίς [Scaffold]
  /// από κάτω δεν έχει πού να εμφανίσει τίποτα. Σε debug σκάει με
  /// «no descendant Scaffolds» τη στιγμή που ο κώδικας πάει να μιλήσει στον
  /// χρήστη· σε release δεν σκάει, απλώς **χάνει σιωπηλά** το μήνυμα — που
  /// είναι χειρότερο. Γι' αυτό ο έλεγχος γίνεται στο δέντρο και όχι με
  /// `try/catch`: το `catch` πιάνει μόνο το debug σύμπτωμα.
  ///
  /// Η κατάσταση προκύπτει όταν ένας διάλογος δηλώνει σκέτο
  /// [ScaffoldMessenger] αντί για [DialogSnackbarScope] — αναγκαστική επιλογή
  /// μέσα σε `DraggableDialogShell`, που απαγορεύει τοπικό `Scaffold` επειδή
  /// σκοτώνει το κλείσιμο με κλικ στο φόντο.
  void showDialogSnackBar(SnackBar snackBar, {String? copyText}) {
    if (!mounted) return;
    final toShow = _composeSnackBar(snackBar, copyText);
    final local = dialogMessengerKey.currentState;
    if (local != null && _canPresent(dialogMessengerKey.currentContext)) {
      local.showSnackBar(toShow);
      return;
    }
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(toShow);
  }

  /// True όταν κάτω από τον [ScaffoldMessenger] υπάρχει [Scaffold] να
  /// φιλοξενήσει το snackbar.
  static bool _canPresent(BuildContext? messengerContext) {
    if (messengerContext == null) return false;
    var found = false;
    void visit(Element element) {
      if (found) return;
      if (element.widget is Scaffold) {
        found = true;
        return;
      }
      element.visitChildren(visit);
    }

    messengerContext.visitChildElements(visit);
    return found;
  }

  /// Το snackbar όπως θα εμφανιστεί: με κουμπί αντιγραφής όταν ζητηθεί.
  ///
  /// Το `SnackBar` δεν έχει `copyWith`, οπότε το αντίγραφο χτίζεται στο χέρι.
  /// Αντιγράφονται **όλα** τα πεδία, με πρότυπο το `SnackBar.withAnimation` του
  /// ίδιου του framework — αλλάζει μόνο το `content`.
  ///
  /// Η πληρότητα δεν είναι σχολαστικότητα: όσο μεταφέρονταν μόνο η διάρκεια και
  /// η συμπεριφορά, κάθε άλλη ρύθμιση του καλούντος έσβηνε σιωπηλά μόλις ζητούσε
  /// αντιγραφή — ένα χρώμα φόντου ή ένα πλάτος χάνονταν χωρίς προειδοποίηση από
  /// τον μεταγλωττιστή. Αν κάποτε προστεθεί νέο πεδίο στο `SnackBar`, η λίστα
  /// εδώ ενημερώνεται από εκεί.
  SnackBar _composeSnackBar(SnackBar snackBar, String? copyText) {
    final textToCopy = (copyText ?? '').trim();
    if (textToCopy.isEmpty) return snackBar;
    return SnackBar(
      key: snackBar.key,
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
      backgroundColor: snackBar.backgroundColor,
      elevation: snackBar.elevation,
      margin: snackBar.margin,
      padding: snackBar.padding,
      width: snackBar.width,
      shape: snackBar.shape,
      hitTestBehavior: snackBar.hitTestBehavior,
      behavior: snackBar.behavior,
      action: snackBar.action,
      actionOverflowThreshold: snackBar.actionOverflowThreshold,
      showCloseIcon: snackBar.showCloseIcon,
      closeIconColor: snackBar.closeIconColor,
      duration: snackBar.duration,
      persist: snackBar.persist,
      animation: snackBar.animation,
      onVisible: snackBar.onVisible,
      dismissDirection: snackBar.dismissDirection,
      clipBehavior: snackBar.clipBehavior,
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
