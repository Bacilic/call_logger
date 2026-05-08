import 'dart:convert';

import 'package:flutter/material.dart';

class SyncHistoryList extends StatelessWidget {
  const SyncHistoryList({required this.links, super.key});

  final List<Map<String, dynamic>> links;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Ιστορικό tickets',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            if (links.isEmpty)
              const Text('Δεν υπάρχει ιστορικό για την επιλεγμένη κλήση.')
            else
              ...links.take(6).map((row) {
                final externalId =
                    (row['external_id'] as String?)?.trim() ?? '-';
                final createdAt = (row['created_at'] as String?)?.trim() ?? '-';
                final metadata = _readMetadata(row['metadata']);
                final mode = metadata['mode']?.toString().trim() ?? '';
                final comment = metadata['comment']?.toString().trim() ?? '';
                return ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text('Ticket: $externalId'),
                  subtitle: Text(
                    [
                      'Χρόνος: $createdAt',
                      if (mode.isNotEmpty) 'Τρόπος: $mode',
                      if (comment.isNotEmpty) 'Σχόλιο: $comment',
                    ].join('\n'),
                  ),
                );
              }),
          ],
        ),
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
