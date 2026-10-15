// Πλήκτρα πάνω σε πίνακα γραμμών: ↑↓, Page Up/Down, Home/End, Enter, Space,
// Delete — και ο πίνακας ΠΑΙΡΝΕΙ τα πλήκτρα με ένα κλικ.
//
// Ανεξάρτητο από το τι δείχνει ο πίνακας: ξέρει μόνο πόσες γραμμές έχει, ποια
// έχει εστίαση, και ρωτά τον πίνακα τι σημαίνει «άνοιξε», «βάλε τικ»,
// «διάγραψε». Έτσι ξαναχρησιμοποιείται σε κάθε πίνακα της εφαρμογής.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../utils/run_after_next_frame.dart';
import 'row_navigation_logic.dart';

/// Τυλίγει έναν πίνακα και του δίνει πλήκτρα.
///
/// **Πότε παίρνει ο πίνακας τα πλήκτρα:**
/// - με κλικ οπουδήποτε πάνω του (και από την Αναζήτηση), και
/// - όταν το ποντίκι μπαίνει πάνω του, εκτός αν ο χρήστης πληκτρολογεί
///   εκείνη τη στιγμή σε πεδίο κειμένου.
///
/// Το δεξί και το αριστερό βέλος **δεν κάνουν τίποτα** όσο ο πίνακας έχει τα
/// πλήκτρα — αλλιώς το Flutter τα χρησιμοποιεί για να περπατά η εστίαση στα
/// γειτονικά κουμπιά και στην πλευρική στήλη.
class KeyboardRowNavigation extends StatefulWidget {
  const KeyboardRowNavigation({
    super.key,
    required this.rowCount,
    required this.focusedRowIndex,
    required this.onFocusRow,
    required this.child,
    this.pageStep = kDefaultRowPageStep,
    this.onRevealRow,
    this.onOpen,
    this.onToggleRow,
    this.onDelete,
  });

  final int rowCount;

  /// Η γραμμή με εστίαση — την κρατά ο καλών (π.χ. provider), όχι ο μηχανισμός.
  final int? focusedRowIndex;

  /// Ζητά εστίαση σε γραμμή.
  final void Function(int index) onFocusRow;

  /// Γραμμές ανά Page Up/Down. Σε πίνακα με σελίδες είναι το μέγεθος σελίδας.
  final int pageStep;

  /// Καλείται **μετά το επόμενο frame** όταν η εστίαση άλλαξε, ώστε ο πίνακας
  /// να φέρει τη γραμμή στην οθόνη (κύλιση). Η αλλαγή σελίδας δεν γίνεται εδώ:
  /// πρέπει να έχει ήδη γίνει μέχρι να χτιστεί ο πίνακας.
  final void Function(int index, {required bool movingDown})? onRevealRow;

  /// Enter. Το όρισμα είναι `null` όταν καμία γραμμή δεν έχει εστίαση.
  final void Function(int? focusedIndex)? onOpen;

  /// Space, μόνο όταν υπάρχει γραμμή με εστίαση.
  final void Function(int index)? onToggleRow;

  /// Delete. Το όρισμα είναι `null` όταν καμία γραμμή δεν έχει εστίαση.
  final void Function(int? focusedIndex)? onDelete;

  final Widget child;

  @override
  State<KeyboardRowNavigation> createState() => _KeyboardRowNavigationState();
}

class _KeyboardRowNavigationState extends State<KeyboardRowNavigation> {
  final FocusNode _focusNode = FocusNode(debugLabel: 'KeyboardRowNavigation');

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(KeyboardRowNavigation oldWidget) {
    super.didUpdateWidget(oldWidget);
    final now = widget.focusedRowIndex;
    final before = oldWidget.focusedRowIndex;
    final reveal = widget.onRevealRow;
    if (now == null || now == before || reveal == null) return;
    runAfterNextFrame(() {
      if (!mounted) return;
      reveal(now, movingDown: before == null || now > before);
    });
  }

  bool get _typingInTextField {
    final context = FocusManager.instance.primaryFocus?.context;
    return context?.findAncestorStateOfType<EditableTextState>() != null;
  }

  void _takeFocus() {
    if (!_focusNode.hasFocus) _focusNode.requestFocus();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isControlPressed ||
        keyboard.isAltPressed ||
        keyboard.isMetaPressed) {
      return KeyEventResult.ignored;
    }
    final count = widget.rowCount;
    if (count == 0) return KeyEventResult.ignored;

    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowRight) {
      return KeyEventResult.handled;
    }

    final target = rowIndexAfterKey(
      key: key,
      current: widget.focusedRowIndex,
      count: count,
      pageStep: widget.pageStep,
    );
    if (target != null) {
      widget.onFocusRow(target);
      return KeyEventResult.handled;
    }

    // Οι ενέργειες δεν επαναλαμβάνονται όσο κρατιέται το πλήκτρο: ένα
    // ξεχασμένο δάχτυλο στο Enter θα άνοιγε φόρμες σε σειρά.
    final isRepeat = event is KeyRepeatEvent;
    final focused = widget.focusedRowIndex;
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      if (!isRepeat) widget.onOpen?.call(focused);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.space) {
      if (!isRepeat && focused != null) widget.onToggleRow?.call(focused);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.delete) {
      if (!isRepeat) widget.onDelete?.call(focused);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focusNode,
      onKeyEvent: _onKey,
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => _takeFocus(),
        child: MouseRegion(
          onEnter: (_) {
            if (!_typingInTextField) _takeFocus();
          },
          child: widget.child,
        ),
      ),
    );
  }
}

/// Κλειδί ανά γραμμή, για να βρίσκει ο πίνακας πού βρίσκεται μια γραμμή στην
/// οθόνη και να την κυλά στο ορατό τμήμα.
///
/// Χρειάζεται επειδή οι γραμμές έχουν διαφορετικά ύψη (κείμενο σε πολλές
/// γραμμές): η θέση δεν υπολογίζεται από το νούμερο της γραμμής.
class RowKeys {
  final Map<int, GlobalKey> _keys = {};

  /// Το κλειδί της γραμμής [index] — μπαίνει στο πρώτο κελί της.
  GlobalKey keyFor(int index) =>
      _keys.putIfAbsent(index, () => GlobalKey(debugLabel: 'row $index'));

  /// Πετά τα κλειδιά γραμμών που δεν υπάρχουν πια.
  void retainFirst(int count) =>
      _keys.removeWhere((index, _) => index >= count);

  /// Κυλά τον πλησιέστερο κύλιστρο (τον κατακόρυφο του πίνακα) το ελάχιστο που
  /// χρειάζεται ώστε η γραμμή [index] να φαίνεται ολόκληρη. Δεν κάνει τίποτα αν
  /// φαίνεται ήδη ή αν η γραμμή δεν είναι χτισμένη.
  void reveal(int index, {required bool movingDown}) {
    final context = _keys[index]?.currentContext;
    if (context == null) return;
    final render = context.findRenderObject();
    final scrollable = Scrollable.maybeOf(context);
    if (render == null || scrollable == null) return;
    scrollable.position.ensureVisible(
      render,
      alignmentPolicy: movingDown
          ? ScrollPositionAlignmentPolicy.keepVisibleAtEnd
          : ScrollPositionAlignmentPolicy.keepVisibleAtStart,
    );
  }
}
