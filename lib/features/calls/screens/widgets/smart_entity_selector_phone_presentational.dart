part of 'smart_entity_selector_widget.dart';

class _PhoneHelperAndError extends StatelessWidget {
  const _PhoneHelperAndError({
    required this.header,
    required this.lookupService,
    required this.notifier,
  });

  final SmartEntitySelectorState header;
  final LookupService? lookupService;
  final SmartEntitySelectorNotifier notifier;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final int? equipmentCount;
    if (header.selectedCaller != null &&
        header.selectedPhone != null &&
        lookupService != null) {
      // Ο πρώτος χρήστης που ταιριάζει στο τηλέφωνο (search) μπορεί να είναι
      // διαφορετικός από τον επιλεγμένο καλούντα· εμφανίζουμε εξοπλισμό του επιλεγμένου.
      final callerId = header.selectedCaller!.id;
      equipmentCount = callerId != null
          ? lookupService!.findEquipmentsForUser(callerId).length
          : lookupService!.searchEquipmentsByPhone(header.selectedPhone!).length;
    } else {
      equipmentCount = null;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (equipmentCount != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              'Βρέθηκαν $equipmentCount εξοπλισμοί',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        if (header.phoneError != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: GestureDetector(
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Προς υλοποίηση...')),
                );
              },
              child: Text(
                header.phoneError!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
