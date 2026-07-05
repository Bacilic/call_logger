import 'package:flutter/material.dart';

import 'ai_prompt_template_syntax.dart';

/// [TextEditingController] με χρωματισμό placeholders/blocks μέσω [buildTextSpan].
///
/// Η επιλογή/composing (IME) χειρίζεται χωριστά ώστε να μην «σπάει» ο κέρσορας σε Windows.
class AiPromptTemplateTextEditingController extends TextEditingController {
  AiPromptTemplateTextEditingController({super.text});

  static List<InlineSpan> highlightedChildren(String text, TextStyle? style) {
    if (text.isEmpty) return const <InlineSpan>[];
    final span = AiPromptTemplateSyntax.buildHighlightedTextSpan(
      template: text,
      baseStyle: style ?? const TextStyle(),
    );
    return span.children ?? <InlineSpan>[TextSpan(text: text, style: style)];
  }

  static TextSpan highlightedTextSpan(String text, TextStyle? style) {
    return TextSpan(
      style: style,
      children: highlightedChildren(text, style),
    );
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final val = value;
    assert(
      !val.composing.isValid || !withComposing || val.isComposingRangeValid,
    );

    if (!withComposing ||
        !val.isComposingRangeValid ||
        val.composing.isCollapsed) {
      return highlightedTextSpan(val.text, style);
    }

    final composingStyle =
        style?.merge(
          const TextStyle(decoration: TextDecoration.underline),
        ) ??
        const TextStyle(decoration: TextDecoration.underline);

    final range = val.composing;
    final full = val.text;
    final start = range.start.clamp(0, full.length);
    final end = range.end.clamp(start, full.length);
    final before = full.substring(0, start);
    final inside = full.substring(start, end);
    final after = full.substring(end);

    return TextSpan(
      style: style,
      children: <InlineSpan>[
        ...highlightedChildren(before, style),
        TextSpan(style: composingStyle, text: inside),
        ...highlightedChildren(after, style),
      ],
    );
  }
}
