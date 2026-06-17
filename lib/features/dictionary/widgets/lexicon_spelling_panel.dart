import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/spell_check_provider.dart';
import '../../../core/services/gemini_runtime_settings.dart';
import '../../../core/services/gemini_ticket_service.dart';
import '../../../core/services/spelling_lookup_gemini_service.dart';
import '../../../core/widgets/lexicon_spell_menu_helper.dart';
import '../providers/lexicon_spelling_panel_provider.dart';

const double kLexiconSpellingPanelWidth = 300;

/// Πλευρικό πάνελ βοήθειας ορθογραφίας (τοπικό λεξικό· ΤΝ/διαδίκτυο κατόπιν αιτήματος).
class LexiconSpellingPanel extends ConsumerWidget {
  const LexiconSpellingPanel({
    super.key,
    required this.onApplySuggestion,
  });

  final Future<void> Function(String suggestion) onApplySuggestion;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final panel = ref.watch(lexiconSpellingPanelProvider);
    final theme = Theme.of(context);
    final spell = switch (ref.watch(spellCheckServiceProvider)) {
      AsyncData(:final value) => value,
      _ => null,
    };

    final query = panel.queryWord.trim();
    final localSuggestions = query.length >= 2 && spell != null
        ? spell.getSuggestions(query)
        : const <String>[];

    return Material(
      elevation: 1,
      color: theme.colorScheme.surfaceContainerLow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 4, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Ορθογραφία',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  tooltip: 'Απόκρυψη πάνελ',
                  icon: const Icon(Icons.close, size: 20),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => ref
                      .read(lexiconSpellingPanelProvider.notifier)
                      .setVisible(false),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              query.isEmpty
                  ? 'Εστιάστε σε πεδίο «Λέξη» για αναζήτηση.'
                  : '«$query»',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              children: [
                _sectionTitle(context, 'Τοπικό λεξικό'),
                if (query.length < 2)
                  _hintText(
                    context,
                    'Πληκτρολογήστε τουλάχιστον 2 χαρακτήρες.',
                  )
                else if (spell == null)
                  _hintText(context, 'Φόρτωση λεξικού ορθογραφίας…')
                else if (localSuggestions.isEmpty)
                  _hintText(context, 'Δεν βρέθηκαν κοντινές λέξεις.')
                else
                  ...localSuggestions.map(
                    (s) => _SuggestionTile(
                      label: s,
                      onApply: () => onApplySuggestion(s),
                    ),
                  ),
                const SizedBox(height: 16),
                _sectionTitle(context, 'Εξωτερική βοήθεια'),
                const SizedBox(height: 6),
                FilledButton.tonalIcon(
                  onPressed: query.isEmpty || panel.geminiLoading
                      ? null
                      : () => _askGemini(ref, query),
                  icon: panel.geminiLoading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.auto_awesome_outlined, size: 18),
                  label: const Text('Ερώτηση ΤΝ'),
                ),
                if (panel.geminiError != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    panel.geminiError!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ],
                if (panel.geminiResult != null) ...[
                  const SizedBox(height: 8),
                  if (panel.geminiResult!.note != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(
                        panel.geminiResult!.note!,
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ...panel.geminiResult!.suggestions.map(
                    (s) => _SuggestionTile(
                      label: s,
                      subtitle: 'ΤΝ',
                      onApply: () => onApplySuggestion(s),
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: query.isEmpty
                      ? null
                      : () => unawaited(
                            LexiconSpellMenuHelper.openGoogleSpellSearch(query),
                          ),
                  icon: const Icon(Icons.language_outlined, size: 18),
                  label: const Text('Αναζήτηση στο διαδίκτυο'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static Widget _sectionTitle(BuildContext context, String title) {
    return Text(
      title,
      style: Theme.of(context).textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
    );
  }

  static Widget _hintText(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 4),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
      ),
    );
  }

  Future<void> _askGemini(WidgetRef ref, String query) async {
    final notifier = ref.read(lexiconSpellingPanelProvider.notifier);
    notifier.setGeminiLoading();

    final settings = await GeminiRuntimeSettings.loadFromDatabase();
    final apiKey = settings.apiKey.trim();
    if (apiKey.isEmpty) {
      notifier.setGeminiError(
        'Δεν έχει οριστεί Gemini API key (Ιστορικό → Lansweeper).',
      );
      return;
    }

    try {
      final result = await SpellingLookupGeminiService.suggest(
        word: query,
        apiKey: apiKey,
        endpoint: settings.endpoint,
        primaryModel: settings.primaryModel,
      );
      notifier.setGeminiSuccess(result);
    } on GeminiException catch (e) {
      notifier.setGeminiError(e.message);
    } catch (e) {
      notifier.setGeminiError('$e');
    }
  }
}

class _SuggestionTile extends StatelessWidget {
  const _SuggestionTile({
    required this.label,
    required this.onApply,
    this.subtitle,
  });

  final String label;
  final String? subtitle;
  final VoidCallback onApply;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(label, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle!,
              style: theme.textTheme.labelSmall,
            ),
      trailing: IconButton(
        tooltip: 'Εφαρμογή στο πεδίο',
        icon: const Icon(Icons.check_circle_outline, size: 20),
        visualDensity: VisualDensity.compact,
        onPressed: onApply,
      ),
      onTap: onApply,
    );
  }
}
