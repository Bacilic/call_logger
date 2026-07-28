import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../utils/linkable_text_parser.dart';
import 'linkable_target_opener.dart';

/// Κοινή μηχανή των widgets συνδέσμων (LinkableText, LinkableSelectableText):
/// χτίζει τα spans με τους αναγνωρισμένους συνδέσμους, κρατά τον κύκλο ζωής
/// των recognizers και ανοίγει τον σύνδεσμο δείχνοντας το αποτέλεσμα σε
/// snackbar. Ο κάτοχος (State) οφείλει να καλέσει [dispose].
class LinkableSpanEngine {
  LinkableSpanEngine({LinkableTargetOpener? targetOpener})
    : _targetOpener = targetOpener ?? LinkableTargetOpener();

  final LinkableTargetOpener _targetOpener;
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

  void _disposeRecognizers() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }
}
