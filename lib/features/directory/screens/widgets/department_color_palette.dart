import 'package:flutter/material.dart';

/// Μετατροπή αποθηκευμένου hex (π.χ. `#1976D2`) σε [Color].
Color? tryParseDepartmentHex(String? s) {
  if (s == null) return null;
  var h = s.trim();
  if (h.isEmpty) return null;
  if (h.startsWith('#')) h = h.substring(1);
  if (h.length == 6) {
    final v = int.tryParse(h, radix: 16);
    if (v != null) return Color(0xFF000000 | v);
  }
  return null;
}

/// Αποθήκευση στη βάση ως `#RRGGBB` (κεφαλαία).
String colorToDepartmentHex(Color c) {
  final r = (c.r * 255.0).round().clamp(0, 255);
  final g = (c.g * 255.0).round().clamp(0, 255);
  final b = (c.b * 255.0).round().clamp(0, 255);
  return '#${r.toRadixString(16).padLeft(2, '0')}'
      '${g.toRadixString(16).padLeft(2, '0')}'
      '${b.toRadixString(16).padLeft(2, '0')}'
      .toUpperCase();
}

bool _sameRgb(Color a, Color b) =>
    colorToDepartmentHex(a) == colorToDepartmentHex(b);

/// Προκαθορισμένη παλέτα (Material-τύπου, κατάλληλη για desktop).
const List<Color> kDepartmentPaletteColors = [
  Color(0xFFEF5350),
  Color(0xFFEC407A),
  Color(0xFFAB47BC),
  Color(0xFF7E57C2),
  Color(0xFF5C6BC0),
  Color(0xFF42A5F5),
  Color(0xFF29B6F6),
  Color(0xFF26C6DA),
  Color(0xFF26A69A),
  Color(0xFF66BB6A),
  Color(0xFF9CCC65),
  Color(0xFFD4E157),
  Color(0xFFFFEE58),
  Color(0xFFFFCA28),
  Color(0xFFFFA726),
  Color(0xFFFF7043),
  Color(0xFF8D6E63),
  Color(0xFF78909C),
  Color(0xFF1976D2),
  Color(0xFF0D47A1),
  Color(0xFF37474F),
  Color(0xFF616161),
  Color(0xFF212121),
  Color(0xFFBDBDBD),
  Color(0xFFFFFFFF),
];

/// Οπτική επιλογή χρώματος τμήματος· το hex (αν χρειάζεται) μπαίνει στη γονική φόρμα.
class DepartmentColorPalette extends StatelessWidget {
  const DepartmentColorPalette({
    super.key,
    required this.selected,
    required this.onColorSelected,
    this.focusNode,
    this.showHeading = true,
    this.compact = false,
  });

  final Color selected;
  final ValueChanged<Color> onColorSelected;
  final FocusNode? focusNode;

  /// Αν false, δεν εμφανίζεται η επικεφαλίδα «Χρώμα» (π.χ. όταν υπάρχει εξωτερικό label).
  final bool showHeading;

  /// Μικρότερες κουκκίδες και μικρότερα κενά (π.χ. μαζική επεξεργασία).
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final outline = theme.colorScheme.outlineVariant;
    final swatchSize = compact ? 20.0 : 30.0;
    final wrapSpacing = compact ? 3.0 : 8.0;
    final wrapRunSpacing = compact ? 3.0 : 8.0;
    final iconSize = compact ? 12.0 : 18.0;
    final selectedBorder = compact ? 2.0 : 3.0;

    final inPalette =
        kDepartmentPaletteColors.any((c) => _sameRgb(c, selected));
    final colors = inPalette
        ? kDepartmentPaletteColors
        : <Color>[selected, ...kDepartmentPaletteColors];

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showHeading) ...[
          Text(
            'Χρώμα',
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.onSurface,
            ),
          ),
          SizedBox(height: compact ? 6 : 8),
        ],
        Wrap(
          spacing: wrapSpacing,
          runSpacing: wrapRunSpacing,
          children: [
            for (final c in colors)
              _Swatch(
                size: swatchSize,
                iconSize: iconSize,
                selectedBorderWidth: selectedBorder,
                color: c,
                selected: _sameRgb(c, selected),
                onTap: () => onColorSelected(c),
                outline: outline,
                primary: theme.colorScheme.primary,
              ),
          ],
        ),
      ],
    );

    if (focusNode != null) {
      return Focus(
        focusNode: focusNode,
        child: body,
      );
    }
    return body;
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.size,
    required this.iconSize,
    required this.selectedBorderWidth,
    required this.color,
    required this.selected,
    required this.onTap,
    required this.outline,
    required this.primary,
  });

  final double size;
  final double iconSize;
  final double selectedBorderWidth;
  final Color color;
  final bool selected;
  final VoidCallback onTap;
  final Color outline;
  final Color primary;

  @override
  Widget build(BuildContext context) {
    final isLight = color.computeLuminance() > 0.85;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Tooltip(
          message: colorToDepartmentHex(color),
          child: Container(
            width: size,
            height: size,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
              border: Border.all(
                color: selected
                    ? primary
                    : (isLight ? outline : outline.withValues(alpha: 0.5)),
                width: selected ? selectedBorderWidth : 1,
              ),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: primary.withValues(alpha: 0.35),
                        blurRadius: size > 22 ? 4 : 2,
                        spreadRadius: 0,
                      ),
                    ]
                  : null,
            ),
            child: selected
                ? Icon(
                    Icons.check,
                    size: iconSize,
                    color: color.computeLuminance() > 0.6
                        ? Colors.black87
                        : Colors.white,
                  )
                : null,
          ),
        ),
      ),
    );
  }
}
