import 'dart:async';

import 'package:flutter/material.dart';

import '../services/spell_check_service.dart' show LexiconSpellCheckService;

/// [TextEditingController] με κυματοειδή υπογράμμιση άγνωστων λέξεων (debounce 500 ms).
///
/// Η επιλογή/composing (IME) χειρίζεται χωριστά ώστε να μην «σπάει» ο κέρσορας σε Windows.
class SpellCheckController extends TextEditingController {
  SpellCheckController({
    LexiconSpellCheckService? spellService,
    this.spellCheckEnabled = true,
  }) : _spell = spellService {
    addListener(_onTextChanged);
  }

  static final RegExp wordPattern = RegExp(r'[\p{L}\p{M}]+', unicode: true);

  LexiconSpellCheckService? _spell;
  bool spellCheckEnabled;

  Timer? _debounce;
  String _analyzedText = '';
  List<(int start, int end)> _wrongRanges = [];

  void attachSpellService(LexiconSpellCheckService? service) {
    if (_spell == service) return;
    _spell = service;
    _scheduleSpellRecompute();
  }

  void setSpellCheckEnabled(bool value) {
    if (spellCheckEnabled == value) return;
    spellCheckEnabled = value;
    _scheduleSpellRecompute();
  }

  void _onTextChanged() {
    _scheduleSpellRecompute();
  }

  void _scheduleSpellRecompute() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      refreshSpellDecorations();
    });
  }

  /// Άμεση ανανέωση υπογραμμίσεων (π.χ. μετά από «Προσθήκη στο λεξικό»).
  void refreshSpellDecorations() {
    _analyzedText = text;
    _wrongRanges = _computeWrongRanges(text);
    notifyListeners();
  }

  List<(int, int)> _computeWrongRanges(String value) {
    if (!spellCheckEnabled || _spell == null || value.isEmpty) {
      return [];
    }
    final out = <(int, int)>[];
    for (final m in wordPattern.allMatches(value)) {
      final w = m.group(0);
      if (w == null || w.isEmpty) continue;
      if (_spell!.isCorrect(w)) continue;
      out.add((m.start, m.end));
    }
    return out;
  }

  /// Όσο το κείμενο αλλάζει πριν ολοκληρωθεί το debounce, δεν εμφανίζονται υπογραμμίσεις.
  List<(int, int)> get _effectiveWrongRanges {
    if (text != _analyzedText) return [];
    return _wrongRanges;
  }

  bool _isWrongRange(int start, int end) {
    for (final r in _effectiveWrongRanges) {
      if (r.$1 == start && r.$2 == end) return true;
    }
    return false;
  }

  TextStyle? _wrongStyleFor(TextStyle? base) {
    const wavy = TextStyle(
      decoration: TextDecoration.underline,
      decorationColor: Colors.red,
      decorationStyle: TextDecorationStyle.wavy,
      decorationThickness: 2.0,
    );
    return base == null ? wavy : base.merge(wavy);
  }

  List<InlineSpan> _spellChildrenForSegment(
    String segment,
    TextStyle? style,
    int baseOffset,
  ) {
    if (segment.isEmpty) return [];
    final spans = <InlineSpan>[];
    var last = 0;
    for (final m in wordPattern.allMatches(segment)) {
      if (m.start > last) {
        spans.add(
          TextSpan(text: segment.substring(last, m.start), style: style),
        );
      }
      final word = m.group(0)!;
      final gStart = baseOffset + m.start;
      final gEnd = baseOffset + m.end;
      final wrong =
          spellCheckEnabled &&
          _spell != null &&
          !_spell!.isCorrect(word) &&
          _isWrongRange(gStart, gEnd);
      spans.add(
        TextSpan(
          text: word,
          style: wrong ? _wrongStyleFor(style) : style,
        ),
      );
      last = m.end;
    }
    if (last < segment.length) {
      spans.add(TextSpan(text: segment.substring(last), style: style));
    }
    return spans;
  }

  /// Λέξη στο offset του κέρσορα (για context menu).
  String? wordAtCursorOffset(TextEditingValue v, int offset) {
    final t = v.text;
    if (offset < 0 || offset > t.length) return null;
    for (final m in wordPattern.allMatches(t)) {
      if (offset >= m.start && offset <= m.end) {
        return m.group(0);
      }
    }
    return null;
  }

  bool isWordMisspelledAt(TextEditingValue v, int offset) {
    final w = wordAtCursorOffset(v, offset);
    if (w == null || _spell == null || !spellCheckEnabled) return false;
    return !_spell!.isCorrect(w);
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

    if (!spellCheckEnabled || _spell == null) {
      return super.buildTextSpan(
        context: context,
        style: style,
        withComposing: withComposing,
      );
    }

    if (!withComposing) {
      return TextSpan(
        style: style,
        children: _spellChildrenForSegment(val.text, style, 0),
      );
    }

    if (!val.isComposingRangeValid || val.composing.isCollapsed) {
      return TextSpan(
        style: style,
        children: _spellChildrenForSegment(val.text, style, 0),
      );
    }

    final composingStyle =
        style?.merge(
          const TextStyle(decoration: TextDecoration.underline),
        ) ??
        const TextStyle(decoration: TextDecoration.underline);

    final range = val.composing;
    final full = val.text;
    final s0 = range.start.clamp(0, full.length);
    final s1 = range.end.clamp(s0, full.length);
    final before = full.substring(0, s0);
    final inside = full.substring(s0, s1);
    final after = full.substring(s1);

    return TextSpan(
      style: style,
      children: <InlineSpan>[
        ..._spellChildrenForSegment(before, style, 0),
        TextSpan(style: composingStyle, text: inside),
        ..._spellChildrenForSegment(after, style, s1),
      ],
    );
  }

  @override
  void dispose() {
    _debounce?.cancel();
    removeListener(_onTextChanged);
    super.dispose();
  }
}
