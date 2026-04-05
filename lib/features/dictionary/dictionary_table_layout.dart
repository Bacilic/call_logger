import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/database/database_helper.dart';
import 'widgets/dictionary_grid_row.dart';

/// Πλάτη στηλών πίνακα λεξικού (τρέχουσα σελίδα + επικεφαλίδες).
class DictionaryTableLayout {
  const DictionaryTableLayout({
    required this.wordWidth,
    required this.sourceWidth,
    required this.categoryWidth,
    this.actionsWidth = kDictionaryGridActionsWidth,
  });

  final double wordWidth;
  final double sourceWidth;
  final double categoryWidth;
  final double actionsWidth;

  double get baseTotal =>
      wordWidth +
      kDictionaryWordColumnResizeHandleWidth +
      sourceWidth +
      categoryWidth +
      actionsWidth;
}

double dictionaryMeasureTextWidth(String text, TextStyle style) {
  final tp = TextPainter(
    text: TextSpan(text: text, style: style),
    maxLines: 1,
    textDirection: TextDirection.ltr,
  )..layout(minWidth: 0, maxWidth: double.infinity);
  return tp.width;
}

/// Υπολογίζει πλάτη από τα δεδομένα της σελίδας· επιπλέον πλάτος viewport
/// δίνεται στη στήλη «Λέξη».
DictionaryTableLayout computeDictionaryTableLayout({
  required BuildContext context,
  required List<Map<String, dynamic>> rows,
  required double viewportWidth,
}) {
  final theme = Theme.of(context);
  final headerStyle = theme.textTheme.labelLarge?.copyWith(
        fontWeight: FontWeight.w600,
      ) ??
      const TextStyle(fontWeight: FontWeight.w600, fontSize: 14);
  final wordFieldStyle =
      theme.textTheme.bodyLarge ?? const TextStyle(fontSize: 16);
  final smallStyle = theme.textTheme.bodySmall ?? const TextStyle(fontSize: 12);
  final catCellStyle = smallStyle;

  /// Οριζόντιο padding πεδίου λέξης (8+8) + μικρό περιθώριο για δρομέα (caret).
  const padWord = 26.0;
  const padSrc = 16.0;
  const padCat = 16.0;

  var wWord = dictionaryMeasureTextWidth('Λέξη', headerStyle) + padWord;
  var wSrc = dictionaryMeasureTextWidth('Πηγή', headerStyle) + padSrc;
  var wCat = dictionaryMeasureTextWidth('Κατηγορία', headerStyle) + padCat;

  for (final r in rows) {
    final dw = r['display_word'] as String? ?? '';
    final src = r['src'] as String? ?? '';
    final cat = r['cat'] as String? ?? '';
    wWord = math.max(
        wWord, dictionaryMeasureTextWidth(dw, wordFieldStyle) + padWord);
    wSrc = math.max(
      wSrc,
      dictionaryMeasureTextWidth(
            DatabaseHelper.lexiconSourceUiLabel(src),
            smallStyle,
          ) +
          padSrc,
    );
    wCat = math.max(wCat, dictionaryMeasureTextWidth(cat, catCellStyle) + padCat);
  }

  wWord = wWord.clamp(88.0, 2000.0);
  wSrc = wSrc.clamp(72.0, 220.0);
  wCat = wCat.clamp(80.0, 280.0);

  return DictionaryTableLayout(
    wordWidth: wWord,
    sourceWidth: wSrc,
    categoryWidth: wCat,
  );
}

/// Πλάτος dropdown ώστε να χωράει το μεγαλύτερο στοιχείο + βέλος.
double computeDropdownMenuWidth(
  BuildContext context,
  List<String> labels, {
  double trailingPadding = 36,
}) {
  final style = Theme.of(context).textTheme.bodyLarge ?? const TextStyle(fontSize: 16);
  var m = 0.0;
  for (final s in labels) {
    m = math.max(m, dictionaryMeasureTextWidth(s, style));
  }
  return (m + trailingPadding).clamp(64.0, 360.0);
}
