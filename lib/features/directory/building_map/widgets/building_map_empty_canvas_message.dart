import 'package:flutter/material.dart';

class BuildingMapEmptyCanvasMessage extends StatelessWidget {
  const BuildingMapEmptyCanvasMessage({
    super.key,
    required this.viewMode,
  });

  /// Αν true: μήνυμα προβολής· αν false: μήνυμα επεξεργασίας (χωρίς κατόψεις).
  final bool viewMode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final message = viewMode
        ? 'Δεν έχει σχεδιαστεί ακόμα κανένας χάρτης. Μεταβείτε σε λειτουργία επεξεργασίας για να ξεκινήσετε τη σχεδίαση'
        : 'Δεν υπάρχουν κατόψεις - Προσθέστε όροφο στο κτίριό σας';
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
            letterSpacing: 0.15,
            height: 1.4,
          ),
        ),
      ),
    );
  }
}
