import 'package:flutter/material.dart';

import 'version_level_label.dart';

/// Παράσημο αναβάθμισης: εξάγωνο με τον αριθμό επιπέδου και, από κάτω, την
/// πλήρη ετικέτα έκδοσης.
///
/// Κάθε δημοσίευση κοστίζει δουλειά — το παράσημο τη γιορτάζει. Ο μεγάλος
/// αριθμός είναι το «επίπεδο» (δες [versionLevelLabel]) και προσαρμόζει το
/// μέγεθός του ώστε να χωρά όσα ψηφία κι αν αποκτήσει με τα χρόνια.
class UpdateLevelBadge extends StatelessWidget {
  const UpdateLevelBadge({super.key, required this.version});

  /// Ετικέτα έκδοσης της νέας κυκλοφορίας, π.χ. `0.34.0`.
  final String version;

  /// Χρυσό «παρασήμου»: δεν προέρχεται από το [ColorScheme] επίτηδες — είναι
  /// χρώμα γιορτής, όχι ρόλος διεπαφής, και πρέπει να ξεχωρίζει από το μωβ.
  static const Color _rimGold = Color(0xFFEF9F27);
  static const Color _arrowGold = Color(0xFFFAC775);

  static const double _hexWidth = 76;
  static const double _hexHeight = 84;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final level = versionLevelLabel(version);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: _hexWidth,
          height: _hexHeight,
          child: CustomPaint(
            painter: _LevelHexPainter(
              fill: scheme.primary,
              rim: _rimGold,
              arrow: _arrowGold,
            ),
            child: Center(
              child: Padding(
                // Το τρίγωνο ανόδου πιάνει την κορυφή· ο αριθμός κατεβαίνει
                // λίγο ώστε να κάθεται οπτικά στο κέντρο του εξαγώνου.
                padding: const EdgeInsets.only(top: 14),
                child: Text(
                  level,
                  key: const Key('update_level_badge_level'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: scheme.onPrimary,
                    fontSize: versionLevelFontSize(level),
                    fontWeight: FontWeight.w700,
                    height: 1,
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'v$version',
          key: const Key('update_level_badge_version'),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _LevelHexPainter extends CustomPainter {
  const _LevelHexPainter({
    required this.fill,
    required this.rim,
    required this.arrow,
  });

  final Color fill;
  final Color rim;
  final Color arrow;

  /// Κορυφές εξαγώνου ως ποσοστά του πλαισίου (κορυφή πάνω, «pointy-top»).
  static const List<Offset> _corners = [
    Offset(0.5, 0.0),
    Offset(0.93, 0.25),
    Offset(0.93, 0.75),
    Offset(0.5, 1.0),
    Offset(0.07, 0.75),
    Offset(0.07, 0.25),
  ];

  Path _hexPath(Size size, double scale) {
    final center = Offset(size.width / 2, size.height / 2);
    final path = Path();
    for (var i = 0; i < _corners.length; i++) {
      final corner = Offset(
        _corners[i].dx * size.width,
        _corners[i].dy * size.height,
      );
      final scaled = center + (corner - center) * scale;
      i == 0 ? path.moveTo(scaled.dx, scaled.dy) : path.lineTo(scaled.dx, scaled.dy);
    }
    return path..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    // Το περίγραμμα ζωγραφίζεται μισό μέσα στο σχήμα, ώστε να μη βγαίνει έξω
    // από το δεσμευμένο πλαίσιο και κόβεται.
    final body = _hexPath(size, 0.94);
    canvas.drawPath(body, Paint()..color = fill);
    canvas.drawPath(
      body,
      Paint()
        ..color = rim
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeJoin = StrokeJoin.round,
    );

    // Εσωτερικό περίγραμμα: δίνει βάθος «σφραγίδας» χωρίς σκιά ή ντεγκραντέ.
    canvas.drawPath(
      _hexPath(size, 0.72),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.22)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    // Τρίγωνο ανόδου — το σήμα «ανέβηκες επίπεδο».
    final arrowPath = Path()
      ..moveTo(size.width * 0.42, size.height * 0.30)
      ..lineTo(size.width * 0.5, size.height * 0.19)
      ..lineTo(size.width * 0.58, size.height * 0.30)
      ..close();
    canvas.drawPath(arrowPath, Paint()..color = arrow);
  }

  @override
  bool shouldRepaint(_LevelHexPainter oldDelegate) =>
      oldDelegate.fill != fill ||
      oldDelegate.rim != rim ||
      oldDelegate.arrow != arrow;
}
