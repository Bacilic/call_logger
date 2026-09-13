import 'package:flutter/material.dart';

/// Μία γραμμή διαχειριζόμενου καταλόγου: όνομα, πόσα τμήματα, μετονομασία,
/// διαγραφή.
///
/// Κοινή για κτίρια και ομάδες — οι δύο κατάλογοι έχουν τον ίδιο κανόνα
/// («ο κατάλογος είναι ο κύριος, τα τμήματα ακολουθούν») και δεν υπάρχει λόγος
/// να αποκλίνει η όψη τους.
class CatalogEntryRow extends StatelessWidget {
  const CatalogEntryRow({
    required this.name,
    required this.usage,
    required this.enabled,
    required this.onRename,
    required this.onDelete,
    super.key,
  });

  final String name;
  final int usage;
  final bool enabled;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(name, style: theme.textTheme.bodyLarge)),
          Text(
            usage == 0
                ? 'κανένα τμήμα'
                : '$usage ${usage == 1 ? 'τμήμα' : 'τμήματα'}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          IconButton(
            tooltip: 'Μετονομασία',
            icon: const Icon(Icons.edit_outlined, size: 20),
            onPressed: enabled ? onRename : null,
          ),
          IconButton(
            tooltip: 'Διαγραφή',
            icon: const Icon(Icons.delete_outline, size: 20),
            onPressed: enabled ? onDelete : null,
          ),
        ],
      ),
    );
  }
}
