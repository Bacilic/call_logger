import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/calls/provider/quick_call_session_provider.dart';
import '../../features/calls/screens/widgets/quick_call_dialog.dart';
import 'draggable_dialog_shell.dart';
import 'modal_route_tracker.dart';

/// Ρωτά πριν κλείσει η εφαρμογή, όταν ο χρήστης έχει ανοιχτό διάλογο.
///
/// Επιστρέφει `true` όταν το κλείσιμο προχωρά: όταν δεν υπάρχει διάλογος ή
/// όταν ο χρήστης διάλεξε «Κλείσιμο». Το «Επιστροφή» — και η προεπιλογή του
/// Enter — αφήνει τη δουλειά του ανέγγιχτη.
///
/// **Γιατί ερώτηση:** μέχρι 14/10/2026 το «Χ» έκλεινε την εφαρμογή με ανοιχτή
/// «Επεξεργασία Υπαλλήλου» και ό,τι αποθηκευόταν στο μεταξύ γραφόταν κανονικά
/// — μέσα στο κλείσιμο, χωρίς ο χρήστης να ξέρει τι θα μείνει.
///
/// Η ελαχιστοποιημένη γρήγορη καταγραφή μετρά όπως ο ανοιχτός διάλογος: είναι
/// κλήση σε εξέλιξη. Με «Επιστροφή» ξανανοίγει, για να τη διευθετήσει ο χρήστης.
Future<bool> confirmCloseWithOpenDialog(ModalRouteTracker tracker) async {
  final top = tracker.topDialog;
  final navigator = tracker.navigator;
  if (navigator == null || !navigator.mounted) return true;
  final minimizedCall =
      top == null &&
      ProviderScope.containerOf(
            navigator.context,
            listen: false,
          ).read(quickCallSessionProvider) ==
          QuickCallPhase.minimized;
  if (top == null && !minimizedCall) return true;

  final title = top == null ? kQuickCallDialogTitle : openDialogTitle(top);
  final answer = await showDialog<bool>(
    context: navigator.context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      title: const Text('Κλείσιμο εφαρμογής'),
      content: Text(closeWithOpenDialogMessage(title)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Κλείσιμο'),
        ),
        FilledButton(
          autofocus: true,
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Επιστροφή'),
        ),
      ],
    ),
  );
  final proceed = answer ?? false;
  if (!proceed && minimizedCall && navigator.mounted) {
    unawaited(showQuickCallDialog(navigator.context));
  }
  return proceed;
}

/// Το κείμενο της ερώτησης — με το όνομα του διαλόγου, όταν έχει.
String closeWithOpenDialogMessage(String? dialogTitle) {
  final name = dialogTitle?.trim() ?? '';
  return name.isEmpty
      ? 'Υπάρχει ανοιχτό ζήτημα, θέλετε να το διευθετήσετε;'
      : 'Υπάρχει ανοιχτό ζήτημα «$name», θέλετε να το διευθετήσετε;';
}

/// Ο τίτλος του διαλόγου, όπως τον βλέπει ο χρήστης.
///
/// Διαβάζεται από τον ίδιο τον διάλογο — το πλαίσιο (`DraggableDialogShell`)
/// ή το `AlertDialog`/`SimpleDialog` μέσα του — ώστε κανένα από τα εκατοντάδες
/// σημεία που ανοίγουν διάλογο να μη χρειάζεται να δηλώσει όνομα. `null` όταν
/// ο διάλογος δεν έχει τίτλο (μενού, ειδικοί διάλογοι): τότε η ερώτηση
/// βγαίνει χωρίς όνομα.
String? openDialogTitle(Route<dynamic> route) {
  if (route is! ModalRoute) return null;
  final root = route.subtreeContext;
  if (root is! Element) return null;

  String? found;
  void visit(Element element) {
    if (found != null) return;
    final widget = element.widget;
    final title = switch (widget) {
      DraggableDialogShell(:final title) => title,
      AlertDialog(:final title) => title,
      SimpleDialog(:final title) => title,
      _ => null,
    };
    if (title != null) {
      found = _textOf(element, title);
      if (found != null) return;
    }
    element.visitChildren(visit);
  }

  visit(root);
  return found;
}

/// Το κείμενο του πρώτου `Text` κάτω από το στοιχείο του [title].
String? _textOf(Element scope, Widget title) {
  Element? titleElement;
  void findTitle(Element element) {
    if (titleElement != null) return;
    if (identical(element.widget, title)) {
      titleElement = element;
      return;
    }
    element.visitChildren(findTitle);
  }

  findTitle(scope);
  final start = titleElement;
  if (start == null) return null;

  String? text;
  void findText(Element element) {
    if (text != null) return;
    final widget = element.widget;
    // Το εικονίδιο σχεδιάζεται ως γράμμα γραμματοσειράς — δεν είναι τίτλος.
    if (widget is Icon) return;
    final value = switch (widget) {
      Text(:final data, :final textSpan) => data ?? textSpan?.toPlainText(),
      RichText(:final text) => text.toPlainText(),
      _ => null,
    };
    if (value != null && value.trim().isNotEmpty) {
      text = value.trim();
      return;
    }
    element.visitChildren(findText);
  }

  findText(start);
  return text;
}
