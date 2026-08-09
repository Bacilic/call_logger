/// Τα δύο συνδεδεμένα πεδία τοποθέτησης: γραφείο και υπάλληλος.
///
/// Το δεύτερο ξεκλειδώνει μόλις οριστεί το πρώτο και ομαδοποιεί τους
/// υπαλλήλους σε γραφείο / τμήμα / υπόλοιπη βάση. Το φίλτρο **βοηθά, δεν
/// κλειδώνει**: ο σωστός κάτοχος μπορεί να ανήκει αλλού και βρίσκεται
/// γράφοντας το όνομά του.
///
/// Το πλήθος εξοπλισμών δείχνει ποιος χρεώνεται τι — στη Λάμπα είναι συνήθως
/// ο διευθυντής ή η προϊσταμένη του τμήματος. Μηδέν εξοπλισμοί εδώ **δεν**
/// σημαίνει σκουπίδι, γι' αυτό δεν μπαίνει το εικονίδιο ασύνδετου που
/// χρησιμοποιούν οι υποψήφιοι ταύτισης ονόματος.
library;

import 'package:flutter/material.dart';

import '../../../core/database/old_database/lamp_placement_catalog.dart';

class LampPlacementFields extends StatefulWidget {
  const LampPlacementFields({
    super.key,
    required this.catalog,
    required this.officeId,
    required this.ownerId,
    required this.onChanged,
  });

  final LampPlacementCatalog catalog;
  final int? officeId;
  final int? ownerId;
  final void Function({int? officeId, int? ownerId}) onChanged;

  @override
  State<LampPlacementFields> createState() => _LampPlacementFieldsState();
}

class _LampPlacementFieldsState extends State<LampPlacementFields> {
  // Controllers και focus nodes ζουν στο state: αν φτιάχνονταν στο build, ο
  // χρήστης θα έχανε την εστίαση σε κάθε πληκτρολόγηση.
  final TextEditingController _officeController = TextEditingController();
  final TextEditingController _ownerController = TextEditingController();
  final FocusNode _officeFocus = FocusNode();
  final FocusNode _ownerFocus = FocusNode();

  @override
  void dispose() {
    _officeController.dispose();
    _ownerController.dispose();
    _officeFocus.dispose();
    _ownerFocus.dispose();
    super.dispose();
  }

  void _selectOffice(LampPlacementOffice office) {
    // Αλλαγή γραφείου μηδενίζει τον υπάλληλο: οι ομάδες ξαναχτίζονται και ο
    // προηγούμενος μπορεί να μην ανήκει πια πουθενά κοντά.
    _ownerController.clear();
    widget.onChanged(officeId: office.id, ownerId: null);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selectedOffice = widget.catalog.officeById(widget.officeId);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Autocomplete<LampPlacementOffice>(
            key: const Key('lamp_placement_office_field'),
            textEditingController: _officeController,
            focusNode: _officeFocus,
            displayStringForOption: (office) => office.label,
            optionsBuilder: (value) =>
                widget.catalog.searchOffices(value.text),
            onSelected: _selectOffice,
            optionsViewBuilder: (context, select, options) => _OptionsPanel(
              theme: theme,
              minWidth: 340,
              itemCount: options.length,
              itemBuilder: (context, index) {
                final office = options.elementAt(index);
                return ListTile(
                  dense: true,
                  title: Text(office.label),
                  onTap: () => select(office),
                );
              },
            ),
            fieldViewBuilder: (context, controller, focusNode, onSubmitted) =>
                TextField(
                  controller: controller,
                  focusNode: focusNode,
                  onSubmitted: (_) => onSubmitted(),
                  decoration: const InputDecoration(
                    labelText: 'Γραφείο ή τμήμα',
                    hintText: 'Πληκτρολογήστε…',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          // Το πεδίο υπάρχει πάντα, κλειδωμένο ή όχι: υπό όρους αντικατάσταση
          // widget θα ξαναέφτιαχνε το autocomplete και θα έσπαγε την εστίαση.
          child: Autocomplete<LampPlacementOwner>(
            key: const Key('lamp_placement_owner_field'),
            textEditingController: _ownerController,
            focusNode: _ownerFocus,
            displayStringForOption: (owner) => owner.label,
            optionsBuilder: (value) => selectedOffice == null
                ? const Iterable<LampPlacementOwner>.empty()
                : widget.catalog
                      .flattenedOwnerOptions(
                        officeId: selectedOffice.id,
                        query: value.text,
                      )
                      .map((entry) => entry.owner),
            onSelected: (owner) => widget.onChanged(
              officeId: selectedOffice?.id,
              ownerId: owner.id,
            ),
            optionsViewBuilder: (context, select, options) {
              // Οι τίτλοι ομάδων ξαναϋπολογίζονται πάνω στην ίδια σειρά: η
              // λίστα μένει επίπεδη για το πληκτρολόγιο, ομαδοποιημένη στο μάτι.
              final titleByOwnerId = <int, String?>{
                if (selectedOffice != null)
                  for (final entry in widget.catalog.flattenedOwnerOptions(
                    officeId: selectedOffice.id,
                    query: _ownerController.text,
                  ))
                    entry.owner.id: entry.groupTitle,
              };
              return _OptionsPanel(
                theme: theme,
                minWidth: 380,
                itemCount: options.length,
                itemBuilder: (context, index) {
                  final owner = options.elementAt(index);
                  final tile = ListTile(
                    dense: true,
                    title: Text(owner.label),
                    trailing: Text(
                      owner.equipmentCountText,
                      style: theme.textTheme.bodySmall,
                    ),
                    onTap: () => select(owner),
                  );
                  final groupTitle = titleByOwnerId[owner.id];
                  if (groupTitle == null) return tile;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        color: theme.colorScheme.surfaceContainerHighest,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 4,
                        ),
                        child: Text(
                          groupTitle,
                          style: theme.textTheme.labelSmall,
                        ),
                      ),
                      tile,
                    ],
                  );
                },
              );
            },
            fieldViewBuilder: (context, controller, focusNode, onSubmitted) =>
                TextField(
                  controller: controller,
                  focusNode: focusNode,
                  enabled: selectedOffice != null,
                  onSubmitted: (_) => onSubmitted(),
                  decoration: InputDecoration(
                    labelText: 'Υπάλληλος (προαιρετικό)',
                    hintText: selectedOffice == null
                        ? 'Διαλέξτε πρώτα γραφείο'
                        : 'Πληκτρολογήστε…',
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
          ),
        ),
      ],
    );
  }
}

class _OptionsPanel extends StatelessWidget {
  const _OptionsPanel({
    required this.theme,
    required this.minWidth,
    required this.itemCount,
    required this.itemBuilder,
  });

  final ThemeData theme;
  final double minWidth;
  final int itemCount;
  final Widget Function(BuildContext context, int index) itemBuilder;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topLeft,
      child: Material(
        elevation: 4,
        color: theme.colorScheme.surface,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: 300, minWidth: minWidth),
          child: ListView.builder(
            padding: EdgeInsets.zero,
            shrinkWrap: true,
            itemCount: itemCount,
            itemBuilder: itemBuilder,
          ),
        ),
      ),
    );
  }
}
