import 'package:flutter/material.dart';

import '../../../../core/widgets/compact_tooltip.dart';
import '../../models/department_model.dart';
import '../../screens/widgets/department_color_palette.dart';

/// Οδηγίες για τμήμα που έχει ήδη θέση στον χάρτη — ίδιο κείμενο παντού.
const String kBuildingMapMappedDepartmentHint =
    'Το τμήμα είναι ήδη σχεδιασμένο. Μπορείς να του αλλάξεις χαρακτηριστικά με '
    'την επιλογή και επεξεργασία. Με διαγραφή το διαγράφεις από τον όροφο.';

/// Κάρτα τμήματος στο πλέγμα «Επιλογή τμήματος».
///
/// Τα ήδη σχεδιασμένα τμήματα ΔΕΝ αποδυναμώνονται — το ξεθώριασμα διαβάζεται
/// παντού αλλού στην εφαρμογή ως «ανενεργό». Φέρουν σημάδι ολοκλήρωσης, το
/// όνομά τους παίρνει το χρώμα της περιοχής τους στην κάτοψη, και από κάτω
/// γράφεται ο όροφος όπου βρίσκονται. Τα μη σχεδιασμένα φέρουν διακεκομμένο
/// περίγραμμα — η καθιερωμένη γλώσσα του «κενό, προς σχεδίαση».
class DepartmentSelectionCard extends StatelessWidget {
  const DepartmentSelectionCard({
    super.key,
    required this.department,
    required this.placementFloorLabel,
    required this.onTap,
  });

  final DepartmentModel department;

  /// Ο όροφος όπου είναι σχεδιασμένο, ή `null` όταν δεν έχει θέση.
  final String? placementFloorLabel;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mapped = department.isMapped;
    final mapColor = tryParseDepartmentHex(department.color);
    final nameColor = mapped && mapColor != null
        ? readableDepartmentTextColor(mapColor, theme)
        : theme.colorScheme.onSurface;
    final subtitle = mapped
        ? (placementFloorLabel ?? 'Σε όροφο που δεν υπάρχει')
        : 'Χωρίς θέση';

    final Widget card = Material(
      color: mapped ? theme.colorScheme.surface : Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: mapped ? BorderSide(color: theme.dividerColor) : BorderSide.none,
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                children: [
                  Icon(
                    mapped ? Icons.check_circle_outline : Icons.circle_outlined,
                    size: 16,
                    color: mapped
                        ? theme.colorScheme.primary
                        : theme.colorScheme.outline,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      department.name,
                      maxLines: 2,
                      softWrap: true,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: nameColor,
                      ),
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(left: 22),
                child: Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (!mapped) {
      return CustomPaint(
        foregroundPainter: _DashedBorderPainter(
          color: theme.colorScheme.outline.withValues(alpha: 0.8),
        ),
        child: card,
      );
    }
    return CompactTooltip(
      message: kBuildingMapMappedDepartmentHint,
      child: card,
    );
  }
}

/// Διακεκομμένο περίγραμμα «κενού πλαισίου» — το Flutter δεν προσφέρει έτοιμο.
class _DashedBorderPainter extends CustomPainter {
  const _DashedBorderPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final rect = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(8),
    );
    final metrics = (Path()..addRRect(rect)).computeMetrics();
    const dash = 4.0;
    const gap = 3.0;
    for (final metric in metrics) {
      var start = 0.0;
      while (start < metric.length) {
        final end = (start + dash).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(start, end), paint);
        start = end + gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter oldDelegate) =>
      oldDelegate.color != color;
}
