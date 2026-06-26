import 'package:flutter/material.dart';

import '../../../../core/services/gemini_prompt_template_syntax.dart';

/// Πεδίο προτροπής Gemini με χρωματισμό placeholders/blocks και έλεγχο συντακτικού.
class GeminiPromptTemplateField extends StatefulWidget {
  const GeminiPromptTemplateField({
    required this.controller,
    this.onChanged,
    this.minLines = 5,
    this.maxLines = 10,
    super.key,
  });

  final TextEditingController controller;
  final ValueChanged<String>? onChanged;
  final int minLines;
  final int maxLines;

  @override
  State<GeminiPromptTemplateField> createState() =>
      _GeminiPromptTemplateFieldState();
}

class _GeminiPromptTemplateFieldState extends State<GeminiPromptTemplateField> {
  final ScrollController _scrollController = ScrollController();
  GeminiPromptTemplateValidation _validation =
      GeminiPromptTemplateValidation.valid;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTextChanged);
    _validation = GeminiPromptTemplateSyntax.validate(widget.controller.text);
    _scrollController.addListener(_onScrollChanged);
  }

  @override
  void didUpdateWidget(covariant GeminiPromptTemplateField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onTextChanged);
      widget.controller.addListener(_onTextChanged);
      _validation = GeminiPromptTemplateSyntax.validate(widget.controller.text);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    _scrollController.removeListener(_onScrollChanged);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScrollChanged() {
    if (mounted) setState(() {});
  }

  void _onTextChanged() {
    final next = GeminiPromptTemplateSyntax.validate(widget.controller.text);
    if (next.isValid != _validation.isValid ||
        next.errors.join() != _validation.errors.join()) {
      setState(() => _validation = next);
    } else {
      setState(() {});
    }
    widget.onChanged?.call(widget.controller.text);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final baseStyle = theme.textTheme.bodyMedium?.copyWith(height: 1.45) ??
        const TextStyle(fontSize: 14, height: 1.45);
    final validation = _validation;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Πράσινο: placeholders · Μπλε: blocks `{@…}` / `{@/…}`',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 6),
        InputDecorator(
          decoration: InputDecoration(
            labelText: 'Προτροπή Gemini',
            border: const OutlineInputBorder(),
            alignLabelWithHint: true,
            errorText: validation.isValid ? null : validation.errors.first,
            errorMaxLines: 4,
          ),
          isFocused: false,
          child: Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              Transform.translate(
                offset: Offset(
                  0,
                  -(_scrollController.hasClients
                      ? _scrollController.offset
                      : 0.0),
                ),
                child: IgnorePointer(
                  child: Text.rich(
                    GeminiPromptTemplateSyntax.buildHighlightedTextSpan(
                      template: widget.controller.text,
                      baseStyle: baseStyle,
                    ),
                  ),
                ),
              ),
              TextField(
                controller: widget.controller,
                scrollController: _scrollController,
                onChanged: widget.onChanged,
                minLines: widget.minLines,
                maxLines: widget.maxLines,
                style: baseStyle.copyWith(color: Colors.transparent),
                cursorColor: theme.colorScheme.primary,
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ),
        if (!validation.isValid && validation.errors.length > 1) ...[
          const SizedBox(height: 4),
          ...validation.errors.skip(1).map(
                (error) => Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(
                    error,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ),
              ),
        ],
      ],
    );
  }
}
