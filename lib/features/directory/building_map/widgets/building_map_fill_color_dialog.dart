import 'package:flutter/material.dart';

import '../../screens/widgets/department_color_palette.dart';

/// Διάλογος επιλογής χρώματος γεμίσματος περιοχής τμήματος στον χάρτη (υπάρχουσα παλέτα).
Future<Color?> showBuildingMapFillColorPicker(
  BuildContext context, {
  required Color initialColor,
}) {
  return showDialog<Color>(
    context: context,
    builder: (ctx) {
      Color pick = initialColor;
      return AlertDialog(
        title: const Text('Χρώμα περιοχής στο χάρτη'),
        content: StatefulBuilder(
          builder: (context, setLocal) {
            return SingleChildScrollView(
              child: DepartmentColorPalette(
                selected: pick,
                showHeading: false,
                compact: true,
                onColorSelected: (c) => setLocal(() => pick = c),
              ),
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Άκυρο'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, pick),
            child: const Text('OK'),
          ),
        ],
      );
    },
  );
}
