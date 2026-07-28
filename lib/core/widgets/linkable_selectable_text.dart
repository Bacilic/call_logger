import 'package:flutter/material.dart';

import 'linkable_span_engine.dart';
import 'linkable_target_opener.dart';

/// Επιλέξιμο κείμενο με αυτόματη αναγνώριση URL, UNC και τοπικών διαδρομών Windows.
class LinkableSelectableText extends StatefulWidget {
  const LinkableSelectableText({
    super.key,
    required this.text,
    this.style,
    this.linkStyle,
    this.targetOpener,
  });

  final String text;
  final TextStyle? style;
  final TextStyle? linkStyle;
  final LinkableTargetOpener? targetOpener;

  @override
  State<LinkableSelectableText> createState() => LinkableSelectableTextState();
}

class LinkableSelectableTextState extends State<LinkableSelectableText> {
  late final LinkableSpanEngine _engine = LinkableSpanEngine(
    targetOpener: widget.targetOpener,
  );

  @override
  void dispose() {
    _engine.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final baseStyle = widget.style ?? theme.textTheme.bodyMedium;
    final children = _engine.buildSpans(
      context: context,
      text: widget.text,
      baseStyle: baseStyle,
      linkStyle: LinkableSpanEngine.resolveLinkStyle(
        theme,
        baseStyle,
        widget.linkStyle,
      ),
    );

    if (children.isEmpty) {
      return SelectableText('', style: baseStyle);
    }

    return SelectableText.rich(TextSpan(style: baseStyle, children: children));
  }

  /// Ενεργοποιεί το ίδιο onTap που θα έτρεχε από κλικ στον αναγνωρισμένο σύνδεσμο.
  @visibleForTesting
  Future<void> triggerLinkTap(String target) =>
      _engine.triggerLinkTap(context, widget.text, target);
}
