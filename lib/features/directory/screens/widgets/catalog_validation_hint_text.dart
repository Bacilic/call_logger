import 'package:flutter/material.dart';

/// Κίτρινη υπόδειξη κανόνα επικύρωσης κάτω από πεδίο φόρμας.
///
/// Προειδοποίηση, όχι σφάλμα: δεν εμποδίζει την αποθήκευση και δεν
/// χρησιμοποιεί το κόκκινο των validators. Με `hint == null` δεν πιάνει χώρο.
class CatalogValidationHintText extends StatelessWidget {
  const CatalogValidationHintText({super.key, required this.hint});

  final String? hint;

  @override
  Widget build(BuildContext context) {
    final text = hint;
    if (text == null || text.isEmpty) return const SizedBox.shrink();
    final color = Colors.orange.shade800;
    return Padding(
      padding: const EdgeInsets.only(top: 4, left: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, size: 14, color: color),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 12, color: color),
            ),
          ),
        ],
      ),
    );
  }
}
