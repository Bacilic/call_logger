import 'package:flutter/material.dart';

import '../utils/linkable_text_parser.dart';

/// Το όνομα του υπολογιστή μιας διαδρομής δικτύου (`\\ΟΝΟΜΑ\κοινόχρηστο`)·
/// null όταν η διαδρομή δεν έχει όνομα υπολογιστή.
String? uncServerName(String path) {
  final withoutPrefix = path.replaceAll('/', r'\').replaceFirst(r'\\', '');
  final end = withoutPrefix.indexOf(r'\');
  final name = end < 0 ? withoutPrefix : withoutPrefix.substring(0, end);
  return name.isEmpty ? null : name;
}

/// Ρωτά πριν ανοίξει σύνδεσμος ή διαδρομή από σημείωση, δείχνοντας ολόκληρο
/// τον προορισμό. true μόνο με ρητό «Άνοιγμα»· Esc ή κλικ έξω = άκυρο.
Future<bool> showLinkOpenConfirmationDialog(
  BuildContext context, {
  required String target,
  required LinkableTextKind kind,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) =>
        _LinkOpenConfirmationDialog(target: target, kind: kind),
  );
  return confirmed ?? false;
}

class _LinkOpenConfirmationDialog extends StatelessWidget {
  const _LinkOpenConfirmationDialog({required this.target, required this.kind});

  final String target;
  final LinkableTextKind kind;

  String get _title => switch (kind) {
    LinkableTextKind.url => 'Άνοιγμα ιστοσελίδας;',
    LinkableTextKind.uncPath => 'Σύνδεση σε υπολογιστή του δικτύου;',
    LinkableTextKind.localPath => 'Άνοιγμα διαδρομής;',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final server = kind == LinkableTextKind.uncPath
        ? uncServerName(target)
        : null;
    return AlertDialog(
      title: Text(_title),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelectableText(
              target,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontFamily: 'monospace',
              ),
            ),
            if (server != null) ...[
              const SizedBox(height: 12),
              Text(
                'Μόλις πατήσεις «Άνοιγμα», ο υπολογιστής σου θα συνδεθεί '
                'στο «$server».',
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Ακύρωση'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Άνοιγμα'),
        ),
      ],
    );
  }
}
