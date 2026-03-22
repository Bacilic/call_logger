import 'package:flutter/material.dart';

/// Κοινό overlay επιλογής στηλών καταλόγου: κλικ στο σκοτεινό φόντο κλείνει,
/// πάνελ δεξιά (ίδια δομή Χρήστες / Εξοπλισμός).
class CatalogColumnSelectorShell extends StatelessWidget {
  const CatalogColumnSelectorShell({
    super.key,
    required this.onClose,
    required this.title,
    required this.listChild,
    this.maxWidth = 320,
    this.maxHeight = 420,
  });

  final VoidCallback onClose;
  final String title;
  final Widget listChild;
  final double maxWidth;
  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onClose,
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Material(
              elevation: 8,
              borderRadius: BorderRadius.circular(8),
              color: theme.colorScheme.surfaceContainerHighest,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: maxWidth,
                  maxHeight: maxHeight,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 4, 4),
                      child: Row(
                        children: [
                          Text(
                            title,
                            style: theme.textTheme.titleSmall,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const Spacer(),
                          IconButton(
                            icon: const Icon(Icons.close, size: 20),
                            tooltip: 'Κλείσιμο',
                            onPressed: onClose,
                            style: IconButton.styleFrom(
                              minimumSize: const Size(32, 32),
                              padding: EdgeInsets.zero,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Flexible(child: listChild),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
