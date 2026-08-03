import 'package:flutter/material.dart';

/// Πλάτος κειμένου σε μία γραμμή (TextPainter) — για «έξυπνο» πλάτος που
/// καθορίζεται από την πιο επιμήκη εγγραφή αντί για καρφωτή τιμή.
double singleLineTextWidth({
  required String text,
  required TextStyle style,
  TextScaler textScaler = TextScaler.noScaling,
}) {
  if (text.isEmpty) return 0;
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    maxLines: 1,
    textDirection: TextDirection.ltr,
    textScaler: textScaler,
  );
  try {
    painter.layout(maxWidth: double.infinity);
    return painter.size.width;
  } finally {
    painter.dispose();
  }
}

/// Πλάτος της πιο μακριάς εγγραφής από ένα σύνολο κειμένων (0 αν είναι κενό).
///
/// Ό,τι μετριέται εδώ αφορά τη διάταξη: το χρώμα του [style] δεν επηρεάζει.
double widestSingleLineTextWidth({
  required Iterable<String> texts,
  required TextStyle style,
  TextScaler textScaler = TextScaler.noScaling,
}) {
  var widest = 0.0;
  for (final text in texts) {
    final width = singleLineTextWidth(
      text: text,
      style: style,
      textScaler: textScaler,
    );
    if (width > widest) widest = width;
  }
  return widest;
}

/// Ελέγχει αν το κείμενο ξεπερνά το διαθέσιμο πλάτος σε μία γραμμή (TextPainter).
bool textOverflowsSingleLine({
  required String text,
  required TextStyle style,
  required double maxWidth,
  required TextDirection textDirection,
  TextScaler textScaler = TextScaler.noScaling,
}) {
  if (text.trim().isEmpty || maxWidth <= 0) return false;
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    maxLines: 1,
    textDirection: textDirection,
    textScaler: textScaler,
  );
  try {
    painter.layout(maxWidth: double.infinity);
    return painter.width > maxWidth;
  } finally {
    painter.dispose();
  }
}
