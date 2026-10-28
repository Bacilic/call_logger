import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../services/app_restart.dart';

/// Η λωρίδα της νεκρής σύνδεσης: η βάση απαντά, η σύνδεση της εφαρμογής όχι.
///
/// Δική της λωρίδα, και όχι η κόκκινη του χαμένου φακέλου: εκεί η αναμονή
/// έχει νόημα, εδώ ΟΧΙ. Η σύνδεση που κράτησε η εφαρμογή δεν ζωντανεύει ποτέ
/// — μετρήθηκε πάνω από είκοσι λεπτά — οπότε ένα «περίμενε να επανέλθει το
/// δίκτυο» θα ήταν υπόσχεση που δεν πρόκειται να τηρηθεί. Η μόνη διέξοδος
/// είναι η επανεκκίνηση, γι' αυτό η λέξη της είναι και το κουμπί της.
class StaleConnectionBanner extends StatefulWidget {
  const StaleConnectionBanner({super.key, this.onRestart});

  /// Τι κάνει ο σύνδεσμος «Επανεκκινήστε». Αντικαθίσταται στα τεστ· στην
  /// εφαρμογή είναι η κανονική επανεκκίνηση, που κλείνει όπως με το «Χ».
  final Future<void> Function()? onRestart;

  @override
  State<StaleConnectionBanner> createState() => _StaleConnectionBannerState();
}

class _StaleConnectionBannerState extends State<StaleConnectionBanner> {
  late final TapGestureRecognizer _restartTap = TapGestureRecognizer()
    ..onTap = _restart;

  @override
  void dispose() {
    _restartTap.dispose();
    super.dispose();
  }

  Future<void> _restart() async {
    try {
      await (widget.onRestart ?? restartApplication)();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Η αυτόματη επανεκκίνηση δεν ήταν δυνατή. Κλείστε και ανοίξτε ξανά την εφαρμογή.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelLarge?.copyWith(
      color: Colors.black87,
      fontWeight: FontWeight.w600,
    );
    return Material(
      color: Colors.deepOrange.shade300,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          children: [
            const Icon(
              Icons.link_off_outlined,
              size: 20,
              color: Colors.black87,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text.rich(
                key: const ValueKey('database_stale_connection_banner'),
                TextSpan(
                  style: style,
                  children: [
                    const TextSpan(
                      text:
                          'Η σύνδεση με τη βάση χάθηκε μετά από διακοπή του '
                          'δικτύου και ΔΕΝ επανέρχεται μόνη της. Ο φάκελος '
                          'απαντά κανονικά — φταίει η σύνδεση αυτής της '
                          'εφαρμογής. ',
                    ),
                    TextSpan(
                      text: 'Επανεκκινήστε',
                      style: style?.copyWith(
                        fontWeight: FontWeight.w800,
                        decoration: TextDecoration.underline,
                      ),
                      mouseCursor: SystemMouseCursors.click,
                      recognizer: _restartTap,
                    ),
                    const TextSpan(
                      text:
                          ' την εφαρμογή · Εν τω μεταξύ ό,τι γράψατε μπορεί '
                          'να μην αποθηκεύτηκε.',
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
