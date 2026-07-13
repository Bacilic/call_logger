import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../utils/linkable_text_parser.dart';
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
  final List<TapGestureRecognizer> _recognizers = [];
  late final LinkableTargetOpener _targetOpener =
      widget.targetOpener ?? LinkableTargetOpener();

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  void _disposeRecognizers() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }

  @override
  Widget build(BuildContext context) {
    _disposeRecognizers();

    final theme = Theme.of(context);
    final baseStyle = widget.style ?? theme.textTheme.bodyMedium;
    final resolvedLinkStyle = widget.linkStyle ??
        baseStyle?.copyWith(
          color: theme.colorScheme.primary,
          decoration: TextDecoration.underline,
          decorationColor: theme.colorScheme.primary,
        );

    final segments = LinkableTextParser.parse(widget.text);
    final children = <InlineSpan>[];

    for (final segment in segments) {
      switch (segment) {
        case PlainLinkableTextSegment(:final text):
          if (text.isEmpty) continue;
          children.add(TextSpan(text: text, style: baseStyle));
        case LinkLinkableTextSegment(:final text, :final kind):
          final recognizer = TapGestureRecognizer()
            ..onTap = () => _openLink(context, text, kind);
          _recognizers.add(recognizer);
          children.add(
            TextSpan(
              text: text,
              style: resolvedLinkStyle,
              recognizer: recognizer,
            ),
          );
      }
    }

    return Text.rich(
      TextSpan(style: baseStyle, children: children),
      maxLines: widget.maxLines,
      overflow: widget.overflow ?? TextOverflow.clip,
    );
  }

  Future<void> _openLink(
    BuildContext context,
    String target,
    LinkableTextKind kind,
  ) async {
    final result = await _targetOpener.open(target: target, kind: kind);
    if (!context.mounted) return;

    final message = switch (result) {
      LinkOpenResult.opened => null,
      LinkOpenResult.pathNotFound => 'Η διαδρομή δεν βρέθηκε: $target',
      LinkOpenResult.invalidUrl => 'Μη έγκυρο URL: $target',
      LinkOpenResult.urlOpenFailed => 'Αποτυχία ανοίγματος URL.',
      LinkOpenResult.error => 'Αποτυχία ανοίγματος: $target',
    };
    if (message != null) {
      _showSnackBar(context, message);
    }
  }

  void _showSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  /// Ενεργοποιεί το ίδιο onTap που θα έτρεχε από κλικ στον αναγνωρισμένο σύνδεσμο.
  @visibleForTesting
  Future<void> triggerLinkTap(String target) async {
    for (final segment in LinkableTextParser.parse(widget.text)) {
      if (segment is LinkLinkableTextSegment && segment.text == target) {
        await _openLink(context, target, segment.kind);
        return;
      }
    }
    throw StateError('Δεν βρέθηκε σύνδεσμος: $target');
  }
}
