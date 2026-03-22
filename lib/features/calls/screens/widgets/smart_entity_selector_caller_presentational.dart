part of 'smart_entity_selector_widget.dart';

/// Οπτική ανατροφοδότηση: πώς θα ερμηνευτεί το κείμενο Καλούντα (Όνομα / Επώνυμο).
class _CallerParseHint extends StatelessWidget {
  const _CallerParseHint({required this.header, required this.theme});

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
