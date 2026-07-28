import 'package:flutter/material.dart';

import 'linkable_span_engine.dart';
import 'linkable_target_opener.dart';

/// Μόνο-κλικ κείμενο με αυτόματη αναγνώριση URL, UNC και τοπικών διαδρομών Windows.
class LinkableText extends StatefulWidget {
  const LinkableText({
    super.key,
    required this.text,
    this.style,
    this.linkStyle,
    this.maxLines,
    this.overflow,
    this.targetOpener,
  });

  final String text;
  final TextStyle? style;
  final TextStyle? linkStyle;
  final int? maxLines;
  final TextOverflow? overflow;
  final LinkableTargetOpener? targetOpener;

  @override
  State<LinkableText> createState() => LinkableTextState();
}

class LinkableTextState extends State<LinkableText> {
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

    return Text.rich(
      TextSpan(style: baseStyle, children: children),
      maxLines: widget.maxLines,
      overflow: widget.overflow ?? TextOverflow.clip,
    );
  }

  /// Ενεργοποιεί το ίδιο onTap που θα έτρεχε από κλικ στον αναγνωρισμένο σύνδεσμο.
  @visibleForTesting
  Future<void> triggerLinkTap(String target) =>
      _engine.triggerLinkTap(context, widget.text, target);
}
