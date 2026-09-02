import 'dart:convert';

import 'package:flutter/material.dart';

import '../../services/lansweeper_submission_warnings.dart';

/// Το ιστορικό αιτημάτων της επιλεγμένης κλήσης, **αναδιπλωμένο**.
///
/// Ήταν κάρτα σε πλήρη ανάπτυξη που στη συντριπτική πλειοψηφία των κλήσεων
/// έλεγε «δεν υπάρχει ιστορικό» — κρατούσε το ύψος μιας ολόκληρης ενότητας για
/// να μην πει τίποτα. Τώρα είναι μία γραμμή που ανοίγει με κλικ όταν έχει κάτι
/// να δείξει, και μένει κλειστή —αλλά ορατή— όταν δεν έχει: η γραμμή είναι που
/// φανερώνει ότι η δυνατότητα υπάρχει.
class SyncHistoryList extends StatelessWidget {
  const SyncHistoryList({required this.links, super.key});

  final List<Map<String, dynamic>> links;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = Text('Ιστορικό tickets', style: theme.textTheme.titleSmall);

    if (links.isEmpty) {
      return Card(
        child: ListTile(
          key: const ValueKey('lansweeper_history_empty'),
          dense: true,
          enabled: false,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12),
          leading: Icon(
            Icons.history_rounded,
            size: 18,
            color: theme.disabledColor,
          ),
          title: title,
          trailing: Text(
            'κανένα',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.disabledColor,
            ),
          ),
        ),
      );
    }

    return Card(
      child: ExpansionTile(
        key: const ValueKey('lansweeper_history_expansion'),
        initiallyExpanded: false,
        dense: true,
        tilePadding: const EdgeInsets.symmetric(horizontal: 12),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        leading: const Icon(Icons.history_rounded, size: 18),
        title: title,
        subtitle: Text(
          links.length == 1 ? '1 καταχώρηση' : '${links.length} καταχωρήσεις',
          style: theme.textTheme.bodySmall,
        ),
        children: [
          ...links.take(6).map((row) {
            final externalId = (row['external_id'] as String?)?.trim() ?? '-';
            final createdAt = (row['created_at'] as String?)?.trim() ?? '-';
            final metadata = _readMetadata(row['metadata']);
            final mode = metadata['mode']?.toString().trim() ?? '';
            final comment = metadata['comment']?.toString().trim() ?? '';
            // Η ανάγνωση των προειδοποιήσεων ζει σε ένα σημείο για όλη την
            // εφαρμογή — εδώ, στο μήνυμα της καταχώρησης και στην
            // προειδοποίηση επεξεργασίας κλήσης.
            final warnings = lansweeperWarningsFromMetadata(row['metadata']);
            return ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text('Ticket: $externalId'),
              subtitle: Text(
                [
                  'Χρόνος: $createdAt',
                  if (mode.isNotEmpty) 'Τρόπος: $mode',
                  if (comment.isNotEmpty) 'Σχόλιο: $comment',
                  if (warnings.isNotEmpty)
                    'Προειδοποιήσεις: ${warnings.join(', ')}',
                ].join('\n'),
              ),
            );
          }),
        ],
      ),
    );
  }

  Map<String, dynamic> _readMetadata(Object? value) {
    final raw = value?.toString().trim() ?? '';
    if (raw.isEmpty) return const <String, dynamic>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
    return const <String, dynamic>{};
  }
}
