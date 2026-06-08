import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../features/database/services/database_maintenance_service.dart';
import '../utils/linkable_text_parser.dart';

/// Επιλέξιμο κείμενο με αυτόματη αναγνώριση URL, UNC και τοπικών διαδρομών Windows.
class LinkableSelectableText extends StatefulWidget {
  const LinkableSelectableText({
    super.key,
    required this.text,
    this.style,
    this.linkStyle,
  });

  final String text;
  final TextStyle? style;
  final TextStyle? linkStyle;

  @override
  State<LinkableSelectableText> createState() => _LinkableSelectableTextState();
}

class _LinkableSelectableTextState extends State<LinkableSelectableText> {
  final List<TapGestureRecognizer> _recognizers = [];

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

    if (children.isEmpty) {
      return SelectableText('', style: baseStyle);
    }

    return SelectableText.rich(
      TextSpan(style: baseStyle, children: children),
    );
  }

  Future<void> _openLink(
    BuildContext context,
    String target,
    LinkableTextKind kind,
  ) async {
    try {
      switch (kind) {
        case LinkableTextKind.url:
          final uri = Uri.tryParse(target);
          if (uri == null || !uri.hasScheme) {
            _showSnackBar(context, 'Μη έγκυρο URL: $target');
            return;
          }
          final opened = await launchUrl(
            uri,
            mode: LaunchMode.externalApplication,
          );
          if (!opened && context.mounted) {
            _showSnackBar(context, 'Αποτυχία ανοίγματος URL.');
          }
        case LinkableTextKind.uncPath:
        case LinkableTextKind.localPath:
          await _openFilesystemPath(target);
      }
    } catch (_) {
      if (!context.mounted) return;
      _showSnackBar(context, 'Αποτυχία ανοίγματος: $target');
    }
  }

  Future<void> _openFilesystemPath(String path) async {
    final normalized = path.replaceAll('/', r'\');
    final file = File(normalized);
    if (file.existsSync()) {
      await DatabaseMaintenanceService.revealFileInExplorer(normalized);
      return;
    }
    await DatabaseMaintenanceService.openFolderInExplorer(normalized);
  }

  void _showSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}
