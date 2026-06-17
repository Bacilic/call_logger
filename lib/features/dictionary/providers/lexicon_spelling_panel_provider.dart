import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/spelling_lookup_gemini_service.dart';

/// Στόχος εφαρμογής πρότασης ορθογραφίας (γραμμή πίνακα λεξικού).
class LexiconSpellingTarget {
  const LexiconSpellingTarget({
    required this.normKey,
    required this.displayWord,
    this.entryId,
  });

  final int? entryId;
  final String normKey;
  final String displayWord;
}

/// Κατάσταση πάνελ βοήθειας ορθογραφίας στη Διαχείριση λεξικού.
class LexiconSpellingPanelState {
  const LexiconSpellingPanelState({
    this.visible = false,
    this.queryWord = '',
    this.target,
    this.geminiLoading = false,
    this.geminiError,
    this.geminiResult,
  });

  final bool visible;
  final String queryWord;
  final LexiconSpellingTarget? target;
  final bool geminiLoading;
  final String? geminiError;
  final SpellingLookupGeminiResult? geminiResult;

  LexiconSpellingPanelState copyWith({
    bool? visible,
    String? queryWord,
    LexiconSpellingTarget? target,
    bool clearTarget = false,
    bool? geminiLoading,
    String? geminiError,
    bool clearGeminiError = false,
    SpellingLookupGeminiResult? geminiResult,
    bool clearGeminiResult = false,
  }) {
    return LexiconSpellingPanelState(
      visible: visible ?? this.visible,
      queryWord: queryWord ?? this.queryWord,
      target: clearTarget ? null : (target ?? this.target),
      geminiLoading: geminiLoading ?? this.geminiLoading,
      geminiError: clearGeminiError ? null : (geminiError ?? this.geminiError),
      geminiResult:
          clearGeminiResult ? null : (geminiResult ?? this.geminiResult),
    );
  }
}

class LexiconSpellingPanelNotifier extends Notifier<LexiconSpellingPanelState> {
  @override
  LexiconSpellingPanelState build() => const LexiconSpellingPanelState();

  void toggleVisible() {
    state = state.copyWith(visible: !state.visible);
  }

  void setVisible(bool value) {
    if (state.visible == value) return;
    state = state.copyWith(visible: value);
  }

  void updateFromRow({
    required String word,
    required String normKey,
    int? entryId,
  }) {
    final trimmed = word.trim();
    final target = LexiconSpellingTarget(
      entryId: entryId,
      normKey: normKey,
      displayWord: trimmed,
    );
    final wordChanged = trimmed != state.queryWord;
    state = state.copyWith(
      queryWord: trimmed,
      target: target,
      clearGeminiError: wordChanged,
      clearGeminiResult: wordChanged,
      geminiLoading: wordChanged ? false : state.geminiLoading,
    );
  }

  void setGeminiLoading() {
    state = state.copyWith(
      geminiLoading: true,
      clearGeminiError: true,
    );
  }

  void setGeminiSuccess(SpellingLookupGeminiResult result) {
    state = state.copyWith(
      geminiLoading: false,
      geminiResult: result,
      clearGeminiError: true,
    );
  }

  void setGeminiError(String message) {
    state = state.copyWith(
      geminiLoading: false,
      geminiError: message,
    );
  }
}

final lexiconSpellingPanelProvider =
    NotifierProvider<LexiconSpellingPanelNotifier, LexiconSpellingPanelState>(
  LexiconSpellingPanelNotifier.new,
);
