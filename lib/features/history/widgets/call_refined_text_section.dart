import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/widgets/resizable_text_area.dart';
import '../../../core/widgets/spell_check_controller.dart';
import '../../calls/models/call_refined_source.dart';

/// Η ενότητα «Καθαρό κείμενο» της καρτέλας κλήσης: αναλυτική περιγραφή + λύση.
///
/// Τα πεδία δεν γεννιούνται εδώ — γεννιούνται στη φόρμα Lansweeper, όπου το
/// κείμενο γράφεται έτσι κι αλλιώς. Εδώ διαβάζονται και διορθώνονται, γι' αυτό
/// και μένουν κρυμμένα όσο είναι κενά: σε κλήσεις που δεν πήγαν ποτέ σε ticket
/// δύο άδεια πλαίσια είναι σκέτος θόρυβος, επαναλαμβανόμενος σε κάθε άνοιγμα.
class CallRefinedTextSection extends StatelessWidget {
  const CallRefinedTextSection({
    super.key,
    required this.problemController,
    required this.solutionController,
    required this.expanded,
    required this.onExpand,
    this.refinedSource,
    this.refinedAt,
  });

  final SpellCheckController problemController;
  final SpellCheckController solutionController;

  /// Η ενότητα είναι ανοιχτή. Κλειστή σημαίνει «δεν υπάρχει καθαρό κείμενο και
  /// δεν ζητήθηκε να γραφτεί».
  final bool expanded;
  final VoidCallback onExpand;

  final String? refinedSource;
  final String? refinedAt;

  /// «από ΤΝ · 15/07 13:24» — κενό όταν λείπουν και τα δύο στοιχεία.
  static String provenanceLabel({String? source, String? refinedAt}) {
    final parts = <String>[];
    final sourceLabel = CallRefinedSource.label(source);
    if (sourceLabel.isNotEmpty) parts.add(sourceLabel);
    final stamp = DateTime.tryParse((refinedAt ?? '').trim());
    if (stamp != null) parts.add(DateFormat('dd/MM HH:mm').format(stamp));
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (!expanded) {
      return OutlinedButton.icon(
        onPressed: onExpand,
        icon: const Icon(Icons.add, size: 18),
        label: const Text('Προσθήκη αναλυτικής περιγραφής και λύσης'),
        style: OutlinedButton.styleFrom(
          foregroundColor: theme.colorScheme.onSurfaceVariant,
          side: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      );
    }

    final provenance = provenanceLabel(
      source: refinedSource,
      refinedAt: refinedAt,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(
              Icons.auto_awesome_outlined,
              size: 16,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 8),
            Text('Καθαρό κείμενο', style: theme.textTheme.labelLarge),
            const SizedBox(width: 12),
            Expanded(child: Divider(color: theme.colorScheme.outlineVariant)),
            if (provenance.isNotEmpty) ...[
              const SizedBox(width: 12),
              Text(
                provenance,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 12),
        ResizableTextArea(
          controller: problemController,
          minLines: 2,
          decoration: const InputDecoration(
            labelText: 'Αναλυτική περιγραφή προβλήματος',
            border: OutlineInputBorder(),
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: 12),
        ResizableTextArea(
          controller: solutionController,
          minLines: 2,
          decoration: const InputDecoration(
            labelText: 'Λύση',
            border: OutlineInputBorder(),
            alignLabelWithHint: true,
          ),
        ),
      ],
    );
  }
}
