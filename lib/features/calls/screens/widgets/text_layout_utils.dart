import 'package:flutter/material.dart';

/// Ελέγχει αν το κείμενο ξεπερνά το διαθέσιμο πλάτος σε μία γραμμή (TextPainter).
bool textOverflowsSingleLine({
  required String text,
  required TextStyle style,
  required double maxWidth,
  required TextDirection textDirection,
}) {
  if (text.trim().isEmpty || maxWidth <= 0) return false;
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    maxLines: 1,
    textDirection: textDirection,
  )..layout(maxWidth: double.infinity);
  return painter.width > maxWidth;
}
