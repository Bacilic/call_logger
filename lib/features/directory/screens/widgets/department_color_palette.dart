import 'package:flutter/material.dart';

import 'department_color_picker_dialog.dart';
import 'department_palette_actions.dart';
import 'department_palette_host.dart';
import 'department_palette_store.dart';

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

bool sameDepartmentRgb(Color a, Color b) =>
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

/// Οπτική επιλογή χρώματος τμήματος· κύκλοι = προκαθορισμένα, τετράγωνα = 8 θέσεις χρήστη.
class DepartmentColorPalette extends StatelessWidget {
  const DepartmentColorPalette({
    super.key,
    required this.selected,
    required this.onColorSelected,
    this.host,
    this.focusNode,
    this.showHeading = true,
    this.compact = false,
  });

  final Color selected;
  final ValueChanged<Color> onColorSelected;
  final DepartmentPaletteHost? host;
  final FocusNode? focusNode;

  /// Αν false, δεν εμφανίζεται η επικεφαλίδα «Χρώμα» (π.χ. όταν υπάρχει εξωτερικό label).
  final bool showHeading;

  /// Μικρότερες κουκκίδες και μικρότερα κενά (π.χ. μαζική επεξεργασία).
  final bool compact;

  @override
  Widget build(BuildContext context) {
    DepartmentPaletteStore.instance.ensureLoaded();
    return ListenableBuilder(
      listenable: DepartmentPaletteStore.instance,
      builder: (context, _) => _buildContent(context),
    );
  }

  bool _isInBasePalette(Color c) =>
      kDepartmentPaletteColors.any((p) => sameDepartmentRgb(p, c));

  bool _isInCustomSlots(Color c) =>
      DepartmentPaletteStore.instance.indexOfCustomColor(c) != null;

  Future<void> _openPickerForEmptySlot(BuildContext context, int index) async {
    final picked = await showDepartmentColorPickerDialog(
      context,
      initialColor: selected,
    );
    if (picked == null || !context.mounted) return;
    final ok = await DepartmentPaletteActions.assignPickedToEmptySlot(
      context,
      index,
      picked,
    );
    if (!ok || !context.mounted) return;
    onColorSelected(picked);
  }

  Widget _buildContent(BuildContext context) {
    final theme = Theme.of(context);
    final outline = theme.colorScheme.outlineVariant;
    final swatchSize = compact ? 20.0 : 30.0;
    final wrapSpacing = compact ? 3.0 : 8.0;
    final wrapRunSpacing = compact ? 3.0 : 8.0;
    final iconSize = compact ? 12.0 : 18.0;
    final selectedBorder = compact ? 2.0 : 3.0;

    final customSlots = DepartmentPaletteStore.instance.customSlots;

    final inBase = _isInBasePalette(selected);
    final inCustom = _isInCustomSlots(selected);
    final baseColors = (!inBase && !inCustom)
        ? <Color>[selected, ...kDepartmentPaletteColors]
        : kDepartmentPaletteColors;

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
            for (final c in baseColors)
              _CircleSwatch(
                size: swatchSize,
                iconSize: iconSize,
                selectedBorderWidth: selectedBorder,
                color: c,
                selected: sameDepartmentRgb(c, selected),
                onTap: () => onColorSelected(c),
                outline: outline,
                primary: theme.colorScheme.primary,
              ),
            for (var i = 0; i < DepartmentPaletteStore.customSlotCount; i++)
              _SquareCustomSlot(
                size: swatchSize,
                iconSize: iconSize,
                selectedBorderWidth: selectedBorder,
                slotColor: customSlots[i],
                selected: customSlots[i] != null &&
                    sameDepartmentRgb(customSlots[i]!, selected),
                outline: outline,
                primary: theme.colorScheme.primary,
                onTapFilled: (color) => onColorSelected(color),
                onTapEmpty: () => _openPickerForEmptySlot(context, i),
                onClear: () => DepartmentPaletteActions.requestClearCustomSlot(
                  context,
                  i,
                  host: host,
                ),
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

class _CircleSwatch extends StatelessWidget {
  const _CircleSwatch({
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

class _SquareCustomSlot extends StatelessWidget {
  const _SquareCustomSlot({
    required this.size,
    required this.iconSize,
    required this.selectedBorderWidth,
    required this.slotColor,
    required this.selected,
    required this.outline,
    required this.primary,
    required this.onTapFilled,
    required this.onTapEmpty,
    required this.onClear,
  });

  final double size;
  final double iconSize;
  final double selectedBorderWidth;
  final Color? slotColor;
  final bool selected;
  final Color outline;
  final Color primary;
  final ValueChanged<Color> onTapFilled;
  final VoidCallback onTapEmpty;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final filled = slotColor != null;
    final color = slotColor;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: filled ? () => onTapFilled(color!) : onTapEmpty,
        onLongPress: filled
            ? () => _showDeleteColorMenu(context)
            : null,
        borderRadius: BorderRadius.circular(4),
        child: Tooltip(
          message: filled
              ? '${colorToDepartmentHex(color!)}\n'
                  'Κλικ: επιλογή · Παρατεταμένο: διαγραφή'
              : 'Κενή θέση · Κλικ για επιλογή χρώματος',
          child: Container(
            width: size,
            height: size,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              color: filled ? color : Colors.transparent,
              border: Border.all(
                color: selected
                    ? primary
                    : outline.withValues(alpha: filled ? 0.6 : 0.45),
                width: selected ? selectedBorderWidth : 1,
              ),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: primary.withValues(alpha: 0.35),
                        blurRadius: 2,
                      ),
                    ]
                  : null,
            ),
            child: selected && filled
                ? Icon(
                    Icons.check,
                    size: iconSize,
                    color: color!.computeLuminance() > 0.6
                        ? Colors.black87
                        : Colors.white,
                  )
                : null,
          ),
        ),
      ),
    );
  }

  void _showDeleteColorMenu(BuildContext context) {
    final box = context.findRenderObject() as RenderBox?;
    final offset = box?.localToGlobal(Offset.zero) ?? Offset.zero;
    final size = box?.size ?? Size.zero;
    final position = RelativeRect.fromLTRB(
      offset.dx,
      offset.dy + size.height,
      offset.dx + size.width,
      offset.dy,
    );
    showMenu<void>(
      context: context,
      position: position,
      items: [
        PopupMenuItem<void>(
          child: const Text('Διαγραφή χρώματος'),
          onTap: () {
            WidgetsBinding.instance.addPostFrameCallback((_) => onClear());
          },
        ),
      ],
    );
  }
}
