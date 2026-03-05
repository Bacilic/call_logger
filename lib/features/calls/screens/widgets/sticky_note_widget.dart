import 'package:flutter/material.dart';

/// Οπτική ένδειξη επισήμανσης (sticky note) όταν ο χρήστης έχει notes.
class StickyNoteWidget extends StatelessWidget {
  const StickyNoteWidget({super.key, required this.notes});

  final String notes;

  @override
  Widget build(BuildContext context) {
    if (notes.trim().isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.amber.shade100,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.note, color: Colors.amber.shade800, size: 22),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              notes,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: Colors.amber.shade900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
