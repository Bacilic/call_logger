import 'package:flutter/material.dart';

/// Placeholder προτροπής Gemini (token → ετικέτα UI).
typedef GeminiPromptPlaceholder = ({String token, String label});

const List<GeminiPromptPlaceholder> kGeminiPromptPlaceholders = [
  (token: '{Υπάλληλος}', label: 'Υπάλληλος'),
  (token: '{Εξοπλισμός}', label: 'Εξοπλισμός'),
  (token: '{Τμήμα}', label: 'Τμήμα'),
  (token: '{Κατηγορία}', label: 'Κατηγορία'),
  (token: '{Τίτλος}', label: 'Τίτλος'),
  (token: '{Σημειώσεις}', label: 'Σημειώσεις'),
  (token: '{Πρόβλημα}', label: 'Πρόβλημα'),
  (token: '{Λύση}', label: 'Λύση'),
];

/// Είδος token προτροπής για χρωματισμό / έλεγχο.
enum GeminiPromptTokenKind {
  plain,
  knownPlaceholder,
  unknownPlaceholder,
  blockOpen,
  blockClose,
  unknownBlock,
}

/// Ένα τμήμα κειμένου προτροπής μετά την tokenization.
class GeminiPromptTokenSpan {
  const GeminiPromptTokenSpan({
    required this.text,
    required this.kind,
    this.placeholderName,
  });

  final String text;
  final GeminiPromptTokenKind kind;
  final String? placeholderName;
}

/// Αποτέλεσμα ελέγχου συντακτικού προτροπής.
class GeminiPromptTemplateValidation {
  const GeminiPromptTemplateValidation({
    required this.isValid,
    this.errors = const [],
  });

  final bool isValid;
  final List<String> errors;

  static const valid = GeminiPromptTemplateValidation(isValid: true);
}

/// Σύνταξη προαιρετικών blocks `{@Όνομα}…{@/Όνομα}` και placeholders `{Όνομα}`.
abstract final class GeminiPromptTemplateSyntax {
  static final RegExp _braceTokenPattern = RegExp(r'\{[^}]+\}');

  static Set<String> get knownPlaceholderTokens => {
        for (final p in kGeminiPromptPlaceholders) p.token,
      };

  static Set<String> get knownPlaceholderNames => {
        for (final p in kGeminiPromptPlaceholders)
          placeholderNameFromToken(p.token),
      };

  static String placeholderNameFromToken(String token) {
    if (token.length < 3 || !token.startsWith('{') || !token.endsWith('}')) {
      return token;
    }
    return token.substring(1, token.length - 1);
  }

  static String blockOpenTag(String name) => '{@$name}';

  static String blockCloseTag(String name) => '{@/$name}';

  /// Αφαιρεί τα tags `{@Όνομα}` / `{@/Όνομα}`, κρατώντας το εσωτερικό κείμενο.
  static String stripBlockMarkers(String template) {
    var result = template;
    for (final name in knownPlaceholderNames) {
      result = result.replaceAll(blockOpenTag(name), '');
      result = result.replaceAll(blockCloseTag(name), '');
    }
    return result;
  }

  /// Αφαιρεί blocks των οποίων το placeholder είναι κενό.
  static String stripEmptyOptionalBlocks(
    String template,
    Set<String> emptyPlaceholderTokens,
  ) {
    var result = template;
    for (final token in emptyPlaceholderTokens) {
      final name = placeholderNameFromToken(token);
      final open = blockOpenTag(name);
      final close = blockCloseTag(name);
      while (true) {
        final start = result.indexOf(open);
        if (start < 0) break;
        final end = result.indexOf(close, start + open.length);
        if (end < 0) break;
        result = result.replaceRange(start, end + close.length, '');
      }
    }
    return compactWhitespace(result);
  }

  static String compactWhitespace(String text) {
    var result = text;
    result = result.replaceAll(RegExp(r'[ \t]+\n'), '\n');
    result = result.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    result = result.replaceAll(RegExp(r'[ \t]{2,}'), ' ');
    return result.trim();
  }

  static GeminiPromptTemplateValidation validate(String template) {
    final errors = <String>[];
    final stack = <String>[];

    for (final match in _braceTokenPattern.allMatches(template)) {
      final token = match.group(0)!;
      if (token.startsWith('{@/')) {
        final name = token.substring(3, token.length - 1);
        if (!knownPlaceholderNames.contains(name)) {
          errors.add('Άγνωστο κλείσιμο block: `$token`.');
          continue;
        }
        if (stack.isEmpty) {
          errors.add('Το `$token` δεν έχει αντίστοιχο άνοιγμα block.');
          continue;
        }
        final openName = stack.removeLast();
        if (openName != name) {
          errors.add(
            'Αναντιστοιχία block: `{@$openName}` κλείνει με `$token`.',
          );
        }
        continue;
      }
      if (token.startsWith('{@')) {
        final name = token.substring(2, token.length - 1);
        if (!knownPlaceholderNames.contains(name)) {
          errors.add('Άγνωστο άνοιγμα block: `$token`.');
          continue;
        }
        stack.add(name);
        continue;
      }

      if (!knownPlaceholderTokens.contains(token)) {
        final suggestion = _suggestPlaceholder(token);
        if (suggestion != null) {
          errors.add(
            'Άγνωστο placeholder: `$token` — εννοείτε `$suggestion`;',
          );
        } else {
          errors.add('Άγνωστο placeholder: `$token`.');
        }
      }
    }

    for (final openName in stack.reversed) {
      errors.add('Το block `{@$openName}` δεν κλείνει.');
    }

    if (errors.isEmpty) {
      return GeminiPromptTemplateValidation.valid;
    }
    return GeminiPromptTemplateValidation(isValid: false, errors: errors);
  }

  static String? _suggestPlaceholder(String token) {
    final inner = placeholderNameFromToken(token);
    String? best;
    var bestDistance = 999;
    for (final known in knownPlaceholderNames) {
      final distance = _levenshtein(inner, known);
      if (distance < bestDistance) {
        bestDistance = distance;
        best = known;
      }
    }
    if (best != null && bestDistance > 0 && bestDistance <= 2) {
      return '{$best}';
    }
    return null;
  }

  static int _levenshtein(String a, String b) {
    if (a == b) return 0;
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;
    final rows = List<int>.generate(b.length + 1, (i) => i);
    for (var i = 0; i < a.length; i++) {
      var prev = rows[0];
      rows[0] = i + 1;
      for (var j = 0; j < b.length; j++) {
        final temp = rows[j + 1];
        final cost = a.codeUnitAt(i) == b.codeUnitAt(j) ? 0 : 1;
        rows[j + 1] = [
          rows[j] + 1,
          rows[j + 1] + 1,
          prev + cost,
        ].reduce((x, y) => x < y ? x : y);
        prev = temp;
      }
    }
    return rows[b.length];
  }

  static List<GeminiPromptTokenSpan> tokenize(String template) {
    final spans = <GeminiPromptTokenSpan>[];
    var index = 0;
    for (final match in _braceTokenPattern.allMatches(template)) {
      if (match.start > index) {
        spans.add(
          GeminiPromptTokenSpan(
            text: template.substring(index, match.start),
            kind: GeminiPromptTokenKind.plain,
          ),
        );
      }
      final token = match.group(0)!;
      spans.add(_classifyToken(token));
      index = match.end;
    }
    if (index < template.length) {
      spans.add(
        GeminiPromptTokenSpan(
          text: template.substring(index),
          kind: GeminiPromptTokenKind.plain,
        ),
      );
    }
    return spans;
  }

  static GeminiPromptTokenSpan _classifyToken(String token) {
    if (token.startsWith('{@/')) {
      final name = token.substring(3, token.length - 1);
      return GeminiPromptTokenSpan(
        text: token,
        kind: knownPlaceholderNames.contains(name)
            ? GeminiPromptTokenKind.blockClose
            : GeminiPromptTokenKind.unknownBlock,
        placeholderName: name,
      );
    }
    if (token.startsWith('{@')) {
      final name = token.substring(2, token.length - 1);
      return GeminiPromptTokenSpan(
        text: token,
        kind: knownPlaceholderNames.contains(name)
            ? GeminiPromptTokenKind.blockOpen
            : GeminiPromptTokenKind.unknownBlock,
        placeholderName: name,
      );
    }
    if (knownPlaceholderTokens.contains(token)) {
      return GeminiPromptTokenSpan(
        text: token,
        kind: GeminiPromptTokenKind.knownPlaceholder,
        placeholderName: placeholderNameFromToken(token),
      );
    }
    return GeminiPromptTokenSpan(
      text: token,
      kind: GeminiPromptTokenKind.unknownPlaceholder,
      placeholderName: placeholderNameFromToken(token),
    );
  }

  static TextSpan buildHighlightedTextSpan({
    required String template,
    required TextStyle baseStyle,
    Color? placeholderColor,
    Color? blockColor,
    Color? errorColor,
  }) {
    final placeholder = placeholderColor ?? const Color(0xFF16A34A);
    final block = blockColor ?? const Color(0xFF2563EB);
    final error = errorColor ?? const Color(0xFFDC2626);

    final children = <InlineSpan>[];
    for (final span in tokenize(template)) {
      final style = switch (span.kind) {
        GeminiPromptTokenKind.plain => baseStyle,
        GeminiPromptTokenKind.knownPlaceholder =>
          baseStyle.copyWith(color: placeholder, fontWeight: FontWeight.w600),
        GeminiPromptTokenKind.blockOpen ||
        GeminiPromptTokenKind.blockClose =>
          baseStyle.copyWith(color: block, fontWeight: FontWeight.w600),
        GeminiPromptTokenKind.unknownPlaceholder ||
        GeminiPromptTokenKind.unknownBlock =>
          baseStyle.copyWith(
            color: error,
            fontWeight: FontWeight.w600,
            decoration: TextDecoration.underline,
            decorationColor: error,
          ),
      };
      children.add(TextSpan(text: span.text, style: style));
    }
    return TextSpan(style: baseStyle, children: children);
  }
}
