import 'package:flutter/material.dart';

import '../../../../core/utils/name_parser.dart';
import '../../provider/smart_entity_selector_provider.dart';

/// Οπτική ανατροφοδότηση: πώς θα ερμηνευτεί το κείμενο Καλούντα (Όνομα / Επώνυμο).
class CallerNameParseHint extends StatelessWidget {
  const CallerNameParseHint({
    super.key,
    required this.header,
    required this.theme,
  });

  final SmartEntitySelectorState header;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    if (header.selectedCaller != null) return const SizedBox.shrink();
    if (header.isUnknownCaller) return const SizedBox.shrink();
    final text = header.callerDisplayText.trim();
    if (text.isEmpty) return const SizedBox.shrink();

    final parsed = NameParserUtility.parse(text);
    final style = theme.textTheme.bodySmall ?? const TextStyle();
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: RichText(
        textScaler: TextScaler.noScaling,
        text: TextSpan(
          style: style.copyWith(color: theme.colorScheme.onSurface),
          children: [
            TextSpan(
              text: 'Όνομα: ${parsed.firstName} ',
              style: style.copyWith(color: theme.colorScheme.primary),
            ),
            TextSpan(
              text: '- Επώνυμο: ${parsed.lastName}',
              style: style.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
