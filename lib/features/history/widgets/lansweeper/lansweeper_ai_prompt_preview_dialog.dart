import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Διάλογος προεπισκόπησης της τελικής προτροπής Gemini (μετά αντικατάσταση placeholders).
Future<void> showLansweeperGeminiPromptPreviewDialog(
  BuildContext context, {
  required String promptText,
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) {
      final theme = Theme.of(dialogContext);
      final maxHeight = MediaQuery.sizeOf(dialogContext).height * 0.62;
      return AlertDialog(
        title: const Text('Προεπισκόπηση προτροπής'),
        content: SizedBox(
          width: 560,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Ακριβές κείμενο που αποστέλλεται στο Gemini για πρόταση τίτλου/περιγραφής.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest
                          .withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: theme.colorScheme.outlineVariant,
                      ),
                    ),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(12),
                      child: SelectableText(
                        promptText,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontFamily: 'Consolas',
                          fontFamilyFallback: const [
                            'Courier New',
                            'monospace',
                          ],
                          height: 1.45,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: promptText));
              ScaffoldMessenger.of(dialogContext).showSnackBar(
                const SnackBar(
                  content: Text('Η προτροπή αντιγράφηκε στο πρόχειρο.'),
                  duration: Duration(seconds: 2),
                ),
              );
            },
            icon: const Icon(Icons.copy_outlined),
            label: const Text('Αντιγραφή'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Κλείσιμο'),
          ),
        ],
      );
    },
  );
}
