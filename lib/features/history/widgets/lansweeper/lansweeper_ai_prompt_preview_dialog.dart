import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/widgets/dialog_snackbar_scope.dart';

/// Διάλογος προεπισκόπησης της τελικής προτροπής Gemini (μετά αντικατάσταση placeholders).
Future<void> showLansweeperAiPromptPreviewDialog(
  BuildContext context, {
  required String promptText,
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => _LansweeperAiPromptPreviewDialog(
      promptText: promptText,
    ),
  );
}

class _LansweeperAiPromptPreviewDialog extends StatefulWidget {
  const _LansweeperAiPromptPreviewDialog({required this.promptText});

  final String promptText;

  @override
  State<_LansweeperAiPromptPreviewDialog> createState() =>
      _LansweeperAiPromptPreviewDialogState();
}

class _LansweeperAiPromptPreviewDialogState
    extends State<_LansweeperAiPromptPreviewDialog> with DialogSnackbarHost {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final maxHeight = MediaQuery.sizeOf(context).height * 0.62;
    return DialogSnackbarScope(
      messengerKey: dialogMessengerKey,
      child: Center(
        child: AlertDialog(
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
                    'Ακριβές κείμενο που αποστέλλεται στην Τεχνητή Νοημοσύνη για πρόταση τίτλου/περιγραφής.',
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
                          widget.promptText,
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
                Clipboard.setData(ClipboardData(text: widget.promptText));
                showDialogSnackBar(
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
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Κλείσιμο'),
            ),
          ],
        ),
      ),
    );
  }
}
