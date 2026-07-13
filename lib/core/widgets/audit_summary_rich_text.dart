import 'package:flutter/material.dart';

import '../../features/directory/screens/widgets/department_color_palette.dart';
import '../services/save_confirmation_summary.dart';

enum AuditSummarySegmentKind { text, color }

class AuditSummarySegment {
  const AuditSummarySegment._(this.kind, this.value);

  const AuditSummarySegment.text(String value)
      : this._(AuditSummarySegmentKind.text, value);

  const AuditSummarySegment.color(String value)
      : this._(AuditSummarySegmentKind.color, value);

  final AuditSummarySegmentKind kind;
  final String value;
}

final _auditSummaryHexTokenPattern = RegExp(r'#[0-9A-Fa-f]{6}');

/// Σπάει τη γραμμή σύνοψης audit σε τμήματα απλού κειμένου ή hex χρώματος.
List<AuditSummarySegment> parseAuditSummarySegments(String input) {
  if (input.isEmpty) return const [];

  final segments = <AuditSummarySegment>[];
  var cursor = 0;

  for (final match in _auditSummaryHexTokenPattern.allMatches(input)) {
    if (match.start > cursor) {
      segments.add(AuditSummarySegment.text(input.substring(cursor, match.start)));
    }
    segments.add(AuditSummarySegment.color(match.group(0)!));
    cursor = match.end;
  }

  if (cursor < input.length) {
    segments.add(AuditSummarySegment.text(input.substring(cursor)));
  }

  return segments;
}

/// Τίτλος γραμμής audit με έγχρωμα δείγματα για tokens `#RRGGBB`.
class AuditSummaryRichText extends StatelessWidget {
  const AuditSummaryRichText({
    super.key,
    required this.text,
    this.style,
    this.maxLines,
    this.overflow,
  });

  final String text;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final effectiveStyle = style ?? theme.textTheme.titleMedium;
    final outline = theme.colorScheme.outlineVariant;
    final segments = parseAuditSummarySegments(text);

    if (segments.isEmpty) {
      return Text('', style: effectiveStyle, maxLines: maxLines, overflow: overflow);
    }

    return Text.rich(
      TextSpan(
        style: effectiveStyle,
        children: [
          for (final segment in segments) ..._spanForSegment(segment, outline),
        ],
      ),
      maxLines: maxLines,
      overflow: overflow ?? TextOverflow.clip,
    );
  }

  List<InlineSpan> _spanForSegment(AuditSummarySegment segment, Color outline) {
    if (segment.kind == AuditSummarySegmentKind.text) {
      return [TextSpan(text: segment.value)];
    }

    final parsed = tryParseDepartmentHex(segment.value);
    if (parsed == null) {
      return [TextSpan(text: segment.value)];
    }

    final hexLabel = segment.value.toUpperCase();
    return [
      WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: Container(
          width: 12,
          height: 12,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            color: parsed,
            borderRadius: BorderRadius.circular(2),
            border: Border.all(color: outline, width: 1),
          ),
        ),
      ),
      TextSpan(text: ' ($hexLabel)'),
    ];
  }
}

/// SnackBar επιβεβαίωσης αποθήκευσης με έγχρωμα δείγματα χρωμάτων.
void showSaveConfirmationSnackBar(
  BuildContext context,
  String message, {
  ScaffoldMessengerState? messenger,
}) {
  final theme = Theme.of(context);
  final snackBarTheme = theme.snackBarTheme;
  final textStyle = (snackBarTheme.contentTextStyle ?? theme.textTheme.bodyMedium)
      ?.copyWith(
        color: snackBarTheme.contentTextStyle?.color ??
            theme.colorScheme.onInverseSurface,
      );

  final target = messenger ?? ScaffoldMessenger.maybeOf(context);
  target?.showSnackBar(
    SnackBar(
      content: AuditSummaryRichText(
        text: message,
        style: textStyle,
      ),
      duration: saveConfirmationSnackBarDuration(message),
    ),
  );
}
