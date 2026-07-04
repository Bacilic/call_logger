import 'package:flutter/material.dart';

/// Κοινή «Κάρτα Ενότητας» — ενιαία συνταγή για όλες τις κάρτες της εφαρμογής:
/// εικονίδιο σε απαλό χρωματιστό πλακίδιο + τίτλος + προαιρετικά trailing
/// στοιχεία, και από κάτω το περιεχόμενο.
///
/// Χρησιμοποιείται ώστε όλες οι κάρτες να μοιράζονται ίδιες γωνίες,
/// εσωτερικά περιθώρια και τυπογραφία (κοινή οπτική γλώσσα).
class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    this.icon,
    this.title,
    this.trailing,
    this.accent,
    this.hugContent = false,
    this.contentPadding = const EdgeInsets.fromLTRB(16, 12, 16, 16),
    required this.child,
  });

  /// Εικονίδιο κεφαλίδας (προαιρετικό — εμφανίζεται μόνο με [title]).
  final IconData? icon;

  /// Τίτλος κεφαλίδας. Αν λείπει, η κάρτα αποδίδει μόνο το περιεχόμενο.
  final String? title;

  /// Στοιχεία δεξιά της κεφαλίδας (π.χ. μενού ⋮, κουμπί ενέργειας).
  final Widget? trailing;

  /// Χρωματική πινελιά κεφαλίδας — προεπιλογή το primary του θέματος.
  final Color? accent;

  /// `true`: η κάρτα αγκαλιάζει το περιεχόμενό της (το trailing κολλά στον
  /// τίτλο). `false`: η κεφαλίδα απλώνεται και το trailing πάει τέρμα δεξιά.
  final bool hugContent;

  /// Εσωτερικό περιθώριο του περιεχομένου.
  final EdgeInsetsGeometry contentPadding;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accentColor = accent ?? theme.colorScheme.primary;

    return Card(
      margin: EdgeInsets.zero,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 12, 0),
              child: Row(
                mainAxisSize: hugContent ? MainAxisSize.min : MainAxisSize.max,
                children: [
                  if (icon != null) ...[
                    Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: accentColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(icon, size: 18, color: accentColor),
                    ),
                    const SizedBox(width: 10),
                  ],
                  Flexible(
                    child: Text(
                      title!,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (trailing != null) ...[
                    if (hugContent) const SizedBox(width: 12) else const Spacer(),
                    trailing!,
                  ],
                ],
              ),
            ),
          Padding(
            padding: contentPadding,
            child: child,
          ),
        ],
      ),
    );
  }
}
