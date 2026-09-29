import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../services/crash_log_service.dart';
import '../services/settings_service.dart';
import '../utils/linkable_text_parser.dart';
import 'link_open_confirmation_dialog.dart';
import 'linkable_target_opener.dart';

/// Διαβάζει αν ο χρήστης θέλει ερώτηση πριν ανοίξει σύνδεσμος.
typedef AskBeforeOpeningLinksFn = Future<bool> Function();

/// Κοινή μηχανή των widgets συνδέσμων (LinkableText, LinkableSelectableText):
/// χτίζει τα spans με τους αναγνωρισμένους συνδέσμους, κρατά τον κύκλο ζωής
/// των recognizers και ανοίγει τον σύνδεσμο δείχνοντας το αποτέλεσμα σε
/// snackbar. Ο κάτοχος (State) οφείλει να καλέσει [dispose].
///
/// Κάθε σύνδεσμος περνά από εδώ, οπότε εδώ ζει και η ερώτηση πριν από το
/// άνοιγμα: ο προορισμός γράφτηκε από άνθρωπο και μπορεί να δείχνει σε ξένο
/// μηχάνημα.
class LinkableSpanEngine {
  LinkableSpanEngine({
    LinkableTargetOpener? targetOpener,
    AskBeforeOpeningLinksFn? askBeforeOpening,
  }) : _targetOpener = targetOpener ?? LinkableTargetOpener(),
       _askBeforeOpening = askBeforeOpening ?? _readAskBeforeOpening;

  final LinkableTargetOpener _targetOpener;
  final AskBeforeOpeningLinksFn _askBeforeOpening;
  final List<TapGestureRecognizer> _recognizers = [];

  /// Προεπιλεγμένο στυλ συνδέσμου όταν το widget δεν ορίζει δικό του.
  static TextStyle? resolveLinkStyle(
    ThemeData theme,
    TextStyle? baseStyle,
    TextStyle? override,
  ) {
    return override ??
        baseStyle?.copyWith(
          color: theme.colorScheme.primary,
          decoration: TextDecoration.underline,
          decorationColor: theme.colorScheme.primary,
        );
  }

  /// Χτίζει τα spans του [text]. Καλείται μέσα από build· απελευθερώνει τους
  /// recognizers του προηγούμενου build πριν δημιουργήσει νέους.
  List<InlineSpan> buildSpans({
    required BuildContext context,
    required String text,
    required TextStyle? baseStyle,
    required TextStyle? linkStyle,
  }) {
    _disposeRecognizers();

    final children = <InlineSpan>[];
    for (final segment in LinkableTextParser.parse(text)) {
      switch (segment) {
        case PlainLinkableTextSegment(:final text):
          if (text.isEmpty) continue;
          children.add(TextSpan(text: text, style: baseStyle));
        case LinkLinkableTextSegment(:final text, :final kind):
          final recognizer = TapGestureRecognizer()
            ..onTap = () => openLink(context, text, kind);
          _recognizers.add(recognizer);
          children.add(
            TextSpan(text: text, style: linkStyle, recognizer: recognizer),
          );
      }
    }
    return children;
  }

  Future<void> openLink(
    BuildContext context,
    String target,
    LinkableTextKind kind,
  ) async {
    // Η ερώτηση προηγείται και του ελέγχου ύπαρξης: σε διαδρομή δικτύου, ήδη
    // ο έλεγχος συνδέει τον υπολογιστή με το μηχάνημα του προορισμού.
    if (await _askBeforeOpening()) {
      if (!context.mounted) return;
      final confirmed = await showLinkOpenConfirmationDialog(
        context,
        target: target,
        kind: kind,
      );
      if (!confirmed) return;
    }
    if (!context.mounted) return;

    final outcome = await _targetOpener.open(target: target, kind: kind);
    if (!context.mounted) return;

    final message = LinkableTargetOpener.messageFor(outcome, target);
    if (message != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  /// Ενεργοποιεί το ίδιο onTap που θα έτρεχε από κλικ στον αναγνωρισμένο
  /// σύνδεσμο [target] του [text]. Υπάρχει για τα τεστ-άγκιστρα των widgets.
  Future<void> triggerLinkTap(
    BuildContext context,
    String text,
    String target,
  ) async {
    for (final segment in LinkableTextParser.parse(text)) {
      if (segment is LinkLinkableTextSegment && segment.text == target) {
        await openLink(context, target, segment.kind);
        return;
      }
    }
    throw StateError('Δεν βρέθηκε σύνδεσμος: $target');
  }

  void dispose() {
    _disposeRecognizers();
  }

  /// Αν η ρύθμιση δεν διαβάζεται (π.χ. η βάση δεν απαντά), ρωτάμε: η σιωπηλή
  /// παράλειψη της ερώτησης είναι ακριβώς ο κίνδυνος που αποτρέπει.
  static Future<bool> _readAskBeforeOpening() async {
    try {
      return await SettingsService().windowUi.getConfirmLinkOpen();
    } catch (e, st) {
      CrashLogService.instanceOrNull?.logError(e, st, fatal: false);
      return true;
    }
  }

  void _disposeRecognizers() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }
}
