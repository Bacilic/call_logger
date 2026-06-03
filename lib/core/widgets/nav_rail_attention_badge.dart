import 'package:flutter/material.dart';

/// Μικρό ορθογώνιο σήμα προσοχής για [NavigationRail]: κίτρινο τετράγωνο, μαύρο «!».
///
/// Όχι τριγωνικό `Icons.warning_amber_*` — σκόπιμα ορθογώνιο όπως στο σχέδιο UI.
class NavRailAttentionBadge extends StatelessWidget {
  const NavRailAttentionBadge({super.key, this.size = 14});

  final double size;

  static const Color _badgeYellow = Color(0xFFFFC107);

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _badgeYellow,
        borderRadius: BorderRadius.circular(2),
        border: Border.all(color: Colors.black87, width: 0.6),
      ),
      child: SizedBox(
        width: size,
        height: size,
        child: Center(
          child: Text(
            '!',
            style: TextStyle(
              color: Colors.black,
              fontSize: size * 0.78,
              fontWeight: FontWeight.w900,
              height: 1,
            ),
          ),
        ),
      ),
    );
  }
}
