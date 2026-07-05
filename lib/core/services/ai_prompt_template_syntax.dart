import 'package:flutter/material.dart';

/// Placeholder προτροπής ΤΝ (token → ετικέτα UI).
typedef AiPromptPlaceholder = ({String token, String label});

const List<AiPromptPlaceholder> kAiPromptPlaceholders = [
  (token: '{Υπάλληλος}', label: 'Υπάλληλος'),
  (token: '{Εξοπλισμός}', label: 'Εξοπλισμός'),
  (token: '{Τμήμα}', label: 'Τμήμα'),
  (token: '{Κατηγορία}', label: 'Κατηγορία'),
  (token: '{Τίτλος}', label: 'Τίτλος'),
  (token: '{Σημειώσεις}', label: 'Σημειώσεις'),
  (token: '{Πρόβλημα}', label: 'Πρόβλημα'),
  (token: '{Λύση}', label: 'Λύση'),
];

/// Blueprint οδηγίας μορφής JSON απάντησης ΤΝ (εισαγωγή στο πρότυπο).
const String kAiJsonResponseBlueprint =
    '{"title":"...","description":"...","solution":"..."}';

const String kDefaultAiPromptTemplate = '''Δημιούργησε τίτλο και πλήρη περιγραφή για ticket helpdesk στο Lansweeper.

Υπάλληλος: {Υπάλληλος}. Τμήμα: {Τμήμα}.
{@Εξοπλισμός}Εξοπλισμός: {Εξοπλισμός}. {@/Εξοπλισμός}
{@Κατηγορία}Κατηγορία: {Κατηγορία}. {@/Κατηγορία}

Πρόβλημα: {Πρόβλημα}
{@Λύση}Λύση (προσχέδιο): {Λύση}. {@/Λύση}

Τρέχον προσχέδιο τίτλου: {Τίτλος}
Τρέχουσα περιγραφή: {Σημειώσεις}

Βελτίωσε το προσχέδιο με βάση τα στοιχεία κλήσης.
Η περιγραφή (description) να περιέχει ΜΟΝΟ το πρόβλημα/αιτιολόγηση.
Η λύση/αντιμετώπιση να μπει στο πεδίο solution, όχι στην description.
Απάντησε ΜΟΝΟ σε JSON χωρίς markdown: {"title":"...","description":"...","solution":"..."}''';

/// Είδος token προτροπής για χρωματισμό / έλεγχο.
enum AiPromptTokenKind {
  plain,
  knownPlaceholder,
  unknownPlaceholder,
  blockOpen,
  blockClose,
  unknownBlock,
  jsonResponseInstruction,
}

/// Ένα τμήμα κειμένου προτροπής μετά την tokenization.
class AiPromptTokenSpan {
  const AiPromptTokenSpan({
    required this.text,
    required this.kind,
    this.placeholderName,
  });

  final String text;
  final AiPromptTokenKind kind;
  final String? placeholderName;
}

/// Αποτέλεσμα ελέγχου συντακτικού προτροπής.
class AiPromptTemplateValidation {
  const AiPromptTemplateValidation({
    required this.isValid,
    this.errors = const [],
    this.warnings = const [],
  });

  final bool isValid;
  final List<String> errors;

  /// Προειδοποιήσεις που δεν επηρεάζουν την εγκυρότητα (`isValid`).
  final List<String> warnings;

  static const valid = AiPromptTemplateValidation(
    isValid: true,
    errors: <String>[],
    warnings: <String>[],
  );
}

/// Σύνταξη προαιρετικών blocks `{@Όνομα}…{@/Όνομα}` και placeholders `{Όνομα}`.
abstract final class AiPromptTemplateSyntax {
  static final RegExp _braceTokenPattern = RegExp(r'\{[^}]+\}');

  static const List<String> _jsonResponseKeys = [
    'title',
    'description',
    'solution',
  ];

  static Set<String> get knownPlaceholderTokens => {
        for (final p in kAiPromptPlaceholders) p.token,
      };

  static Set<String> get knownPlaceholderNames => {
        for (final p in kAiPromptPlaceholders)
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

  /// Αν το token είναι το block οδηγίας JSON απάντησης (όχι placeholder).
  static bool isJsonResponseInstructionToken(String token) {
    if (!token.startsWith('{') || !token.endsWith('}')) return false;
    final inner = token.substring(1, token.length - 1);
    for (final key in _jsonResponseKeys) {
      if (inner.contains('"$key"')) return true;
    }
    return false;
  }

  static bool templateContainsJsonResponseKey(String template, String key) {
    return template.contains('"$key"');
  }

  static List<String> missingJsonResponseKeys(String template) {
    return <String>[
      for (final key in _jsonResponseKeys)
        if (!templateContainsJsonResponseKey(template, key)) key,
    ];
  }

  static List<String> validateJsonResponseKeys(String template) {
    final missing = missingJsonResponseKeys(template);
    if (missing.length == _jsonResponseKeys.length) {
      return <String>[
        'Η προτροπή δεν περιλαμβάνει οδηγίες μορφής JSON απάντησης '
        '($kAiJsonResponseBlueprint) — η ΤΝ δεν θα γνωρίζει σε ποια μορφή να απαντήσει.',
      ];
    }
    if (missing.isEmpty) return const <String>[];
    return <String>[
      for (final key in missing)
        'Λείπει το πεδίο `$key` από το αναμενόμενο JSON αποτέλεσμα — '
        'η απάντηση της ΤΝ δεν θα περιέχει ${_jsonKeyLabel(key)}.',
    ];
  }

  /// Μετρά `{…}` tokens που περιέχουν και τα τρία κλειδιά JSON απάντησης.
  static int countJsonResponseInstructionBlocks(String template) {
    var count = 0;
    for (final match in _braceTokenPattern.allMatches(template)) {
      if (isJsonResponseInstructionToken(match.group(0)!)) {
        count++;
      }
    }
    return count;
  }

  static List<String> validateDuplicateJsonResponseBlocks(String template) {
    if (countJsonResponseInstructionBlocks(template) <= 1) {
      return const <String>[];
    }
    return <String>[
      'Η προτροπή περιλαμβάνει περισσότερες από μία οδηγίες μορφής JSON '
      '($kAiJsonResponseBlueprint) — η ΤΝ μπορεί να μπερδευτεί. '
      'Κρατήστε μόνο μία υπόδειξη απάντησης σε JSON.',
    ];
  }

  static String _jsonKeyLabel(String key) => switch (key) {
        'title' => 'τίτλο',
        'description' => 'περιγραφή/πρόβλημα',
        'solution' => 'λύση',
        _ => key,
      };

  static AiPromptTemplateValidation validate(String template) {
    final errors = <String>[];
    final warnings = <String>[];
    final stack = <String>[];

    errors.addAll(validateJsonResponseKeys(template));
    errors.addAll(validateDuplicateJsonResponseBlocks(template));

    for (final match in _braceTokenPattern.allMatches(template)) {
      final token = match.group(0)!;
      if (isJsonResponseInstructionToken(token)) {
        continue;
      }
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
        // Εμφωλιασμένα blocks διαφορετικού ονόματος ({@A}…{@B}…{@/B}…{@/A})
        // είναι έγκυρα συντακτικά — η στοίβα τα χειρίζεται κανονικά.
        if (stack.contains(name)) {
          errors.add(
            'Το block `{@$name}` ανοίγει ξανά ενώ είναι ήδη ανοιχτό — '
            'πιθανό λάθος αντιγραφής.',
          );
        }
        stack.add(name);
        continue;
      }

      if (knownPlaceholderTokens.contains(token)) {
        if (stack.isNotEmpty) {
          final blockName = stack.last;
          final placeholderName = placeholderNameFromToken(token);
          if (placeholderName != blockName) {
            warnings.add(
              'Το `$token` βρίσκεται μέσα στο block `{@$blockName}` — '
              'αν το `{$blockName}` είναι κενό, θα αφαιρεθεί ολόκληρη η '
              'περιοχή μαζί με αυτό το placeholder, ακόμη κι αν το `$token` '
              'έχει τιμή.',
            );
          }
        }
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

    if (errors.isEmpty && warnings.isEmpty) {
      return AiPromptTemplateValidation.valid;
    }
    return AiPromptTemplateValidation(
      isValid: errors.isEmpty,
      errors: errors,
      warnings: warnings,
    );
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

  static List<AiPromptTokenSpan> tokenize(String template) {
    final spans = <AiPromptTokenSpan>[];
    var index = 0;
    for (final match in _braceTokenPattern.allMatches(template)) {
      if (match.start > index) {
        spans.add(
          AiPromptTokenSpan(
            text: template.substring(index, match.start),
            kind: AiPromptTokenKind.plain,
          ),
        );
      }
      final token = match.group(0)!;
      spans.add(_classifyToken(token));
      index = match.end;
    }
    if (index < template.length) {
      spans.add(
        AiPromptTokenSpan(
          text: template.substring(index),
          kind: AiPromptTokenKind.plain,
        ),
      );
    }
    return spans;
  }

  static AiPromptTokenSpan _classifyToken(String token) {
    if (token.startsWith('{@/')) {
      final name = token.substring(3, token.length - 1);
      return AiPromptTokenSpan(
        text: token,
        kind: knownPlaceholderNames.contains(name)
            ? AiPromptTokenKind.blockClose
            : AiPromptTokenKind.unknownBlock,
        placeholderName: name,
      );
    }
    if (token.startsWith('{@')) {
      final name = token.substring(2, token.length - 1);
      return AiPromptTokenSpan(
        text: token,
        kind: knownPlaceholderNames.contains(name)
            ? AiPromptTokenKind.blockOpen
            : AiPromptTokenKind.unknownBlock,
        placeholderName: name,
      );
    }
    if (knownPlaceholderTokens.contains(token)) {
      return AiPromptTokenSpan(
        text: token,
        kind: AiPromptTokenKind.knownPlaceholder,
        placeholderName: placeholderNameFromToken(token),
      );
    }
    if (isJsonResponseInstructionToken(token)) {
      return AiPromptTokenSpan(
        text: token,
        kind: AiPromptTokenKind.jsonResponseInstruction,
      );
    }
    return AiPromptTokenSpan(
      text: token,
      kind: AiPromptTokenKind.unknownPlaceholder,
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
        AiPromptTokenKind.plain => baseStyle,
        AiPromptTokenKind.knownPlaceholder =>
          baseStyle.copyWith(color: placeholder, fontWeight: FontWeight.w600),
        AiPromptTokenKind.blockOpen ||
        AiPromptTokenKind.blockClose =>
          baseStyle.copyWith(color: block, fontWeight: FontWeight.w600),
        AiPromptTokenKind.jsonResponseInstruction =>
          baseStyle.copyWith(
            color: const Color(0xFF7C3AED),
            fontWeight: FontWeight.w500,
          ),
        AiPromptTokenKind.unknownPlaceholder ||
        AiPromptTokenKind.unknownBlock =>
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
