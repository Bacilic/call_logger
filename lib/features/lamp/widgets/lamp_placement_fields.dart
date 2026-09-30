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
///
/// Ο υπάλληλος είναι **υποχρεωτικός**: στη Λάμπα κάθε εξοπλισμός χρεώνεται σε
/// πρόσωπο. Όποιος δεν υπάρχει ακόμη στη βάση (ήρθε στο νοσοκομείο αργότερα)
/// δημιουργείται από εδώ, με χωριστό επώνυμο και όνομα.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/database/old_database/lamp_issue_resolution_models.dart';
import '../../../core/database/old_database/lamp_placement_catalog.dart';
import '../../../core/utils/run_after_next_frame.dart';

/// Ό,τι έχει συμπληρωθεί ως τώρα στα πεδία τοποθέτησης.
class LampPlacementDraft {
  const LampPlacementDraft({
    this.officeId,
    this.ownerId,
    this.creatingOwner = false,
    this.newOwnerLastName = '',
    this.newOwnerFirstName = '',
  });

  final int? officeId;

  /// Υπάρχων υπάλληλος, **διαλεγμένος** από τη λίστα. Κείμενο που απλώς
  /// γράφτηκε στο πεδίο δεν μετρά.
  final int? ownerId;

  /// Ο χρήστης διάλεξε «Νέος υπάλληλος» και συμπληρώνει επώνυμο και όνομα.
  final bool creatingOwner;
  final String newOwnerLastName;
  final String newOwnerFirstName;

  /// Η απόφαση προς εφαρμογή· `null` όσο λείπει γραφείο ή υπάλληλος.
  LampPlacementInput? toInput() {
    final office = officeId;
    if (office == null) return null;
    if (creatingOwner) {
      final lastName = newOwnerLastName.trim();
      final firstName = newOwnerFirstName.trim();
      if (lastName.isEmpty || firstName.isEmpty) return null;
      return LampPlacementInput(
        officeId: office,
        newOwnerLastName: lastName,
        newOwnerFirstName: firstName,
      );
    }
    final owner = ownerId;
    if (owner == null) return null;
    return LampPlacementInput(officeId: office, ownerId: owner);
  }

  LampPlacementDraft copyWith({
    int? officeId,
    int? Function()? ownerId,
    bool? creatingOwner,
    String? newOwnerLastName,
    String? newOwnerFirstName,
  }) {
    return LampPlacementDraft(
      officeId: officeId ?? this.officeId,
      ownerId: ownerId != null ? ownerId() : this.ownerId,
      creatingOwner: creatingOwner ?? this.creatingOwner,
      newOwnerLastName: newOwnerLastName ?? this.newOwnerLastName,
      newOwnerFirstName: newOwnerFirstName ?? this.newOwnerFirstName,
    );
  }
}

class LampPlacementFields extends StatefulWidget {
  const LampPlacementFields({
    super.key,
    required this.catalog,
    required this.draft,
    required this.onChanged,
  });

  final LampPlacementCatalog catalog;
  final LampPlacementDraft draft;
  final ValueChanged<LampPlacementDraft> onChanged;

  @override
  State<LampPlacementFields> createState() => _LampPlacementFieldsState();
}

/// Η γραμμή «Νέος υπάλληλος» στο τέλος της λίστας. Ξεχωρίζει με ταυτότητα
/// αντικειμένου, όχι με το id: κανένας πραγματικός υπάλληλος δεν είναι αυτό.
const LampPlacementOwner _newOwnerOption = LampPlacementOwner(id: -1, name: '');

class _LampPlacementFieldsState extends State<LampPlacementFields> {
  // Controllers και focus nodes ζουν στο state: αν φτιάχνονταν στο build, ο
  // χρήστης θα έχανε την εστίαση σε κάθε πληκτρολόγηση.
  final TextEditingController _officeController = TextEditingController();
  final TextEditingController _ownerController = TextEditingController();
  final TextEditingController _lastNameController = TextEditingController();
  final TextEditingController _firstNameController = TextEditingController();
  final FocusNode _officeFocus = FocusNode();
  final FocusNode _ownerFocus = FocusNode();
  final FocusNode _lastNameFocus = FocusNode();

  @override
  void dispose() {
    _officeController.dispose();
    _ownerController.dispose();
    _lastNameController.dispose();
    _firstNameController.dispose();
    _officeFocus.dispose();
    _ownerFocus.dispose();
    _lastNameFocus.dispose();
    super.dispose();
  }

  void _selectOffice(LampPlacementOffice office) {
    // Αλλαγή γραφείου μηδενίζει τον υπάλληλο: οι ομάδες ξαναχτίζονται και ο
    // προηγούμενος μπορεί να μην ανήκει πια πουθενά κοντά. Ο νέος υπάλληλος
    // που γράφεται μένει — θα μπει στο γραφείο που ισχύει τη στιγμή της
    // εφαρμογής.
    if (!widget.draft.creatingOwner) _ownerController.clear();
    widget.onChanged(
      widget.draft.copyWith(officeId: office.id, ownerId: () => null),
    );
  }

  void _selectOwner(LampPlacementOwner owner) {
    if (identical(owner, _newOwnerOption)) {
      widget.onChanged(
        widget.draft.copyWith(ownerId: () => null, creatingOwner: true),
      );
      // Τα δύο κουτάκια εμφανίζονται στο επόμενο καρέ· η εστίαση πάει εκεί.
      unawaited(runAfterNextFrame(_lastNameFocus.requestFocus));
      return;
    }
    widget.onChanged(
      widget.draft.copyWith(ownerId: () => owner.id, creatingOwner: false),
    );
  }

  /// Όποιος αλλάζει το κείμενο μετά την επιλογή δεν έχει πια διαλέξει κανέναν:
  /// το όνομα στο πεδίο και ο υπάλληλος που θα γραφτεί πρέπει να συμφωνούν.
  void _ownerTextEdited(String _) {
    if (widget.draft.ownerId == null) return;
    widget.onChanged(widget.draft.copyWith(ownerId: () => null));
  }

  /// Τι λέει το πεδίο κάτω από τον υπάλληλο, ανάλογα με το τι λείπει.
  String? _ownerHelper(bool hasOffice) {
    if (!hasOffice) return null;
    final draft = widget.draft;
    if (draft.ownerId != null || draft.creatingOwner) return null;
    if (_ownerController.text.trim().isNotEmpty) {
      return 'Διαλέξτε από τη λίστα ή «Νέος υπάλληλος» — '
          'όνομα χωρίς επιλογή δεν αποθηκεύεται';
    }
    return 'Υποχρεωτικό — συνήθως ο προϊστάμενος ή ο διευθυντής του τμήματος';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final draft = widget.draft;
    final selectedOffice = widget.catalog.officeById(draft.officeId);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
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
                fieldViewBuilder:
                    (context, controller, focusNode, onSubmitted) => TextField(
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
              // Το πεδίο υπάρχει πάντα, κλειδωμένο ή όχι: υπό όρους
              // αντικατάσταση widget θα ξαναέφτιαχνε το autocomplete και θα
              // έσπαγε την εστίαση.
              child: Autocomplete<LampPlacementOwner>(
                key: const Key('lamp_placement_owner_field'),
                textEditingController: _ownerController,
                focusNode: _ownerFocus,
                displayStringForOption: (owner) =>
                    identical(owner, _newOwnerOption)
                    ? _ownerController.text
                    : owner.label,
                optionsBuilder: (value) {
                  if (selectedOffice == null) {
                    return const Iterable<LampPlacementOwner>.empty();
                  }
                  return <LampPlacementOwner>[
                    ...widget.catalog
                        .flattenedOwnerOptions(
                          officeId: selectedOffice.id,
                          query: value.text,
                        )
                        .map((entry) => entry.owner),
                    // Όποιος ήρθε στο νοσοκομείο μετά δεν είναι στη λίστα:
                    // η διέξοδος εμφανίζεται μόλις γραφτεί κάτι.
                    if (value.text.trim().isNotEmpty) _newOwnerOption,
                  ];
                },
                onSelected: _selectOwner,
                optionsViewBuilder: (context, select, options) {
                  // Οι τίτλοι ομάδων ξαναϋπολογίζονται πάνω στην ίδια σειρά:
                  // η λίστα μένει επίπεδη για το πληκτρολόγιο, ομαδοποιημένη
                  // στο μάτι.
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
                      if (identical(owner, _newOwnerOption)) {
                        return ListTile(
                          key: const Key('lamp_placement_new_owner_option'),
                          dense: true,
                          leading: const Icon(Icons.person_add_alt_1_outlined),
                          title: const Text('Νέος υπάλληλος…'),
                          subtitle: const Text(
                            'Δεν υπάρχει στη λίστα — συμπληρώστε επώνυμο '
                            'και όνομα',
                          ),
                          onTap: () => select(owner),
                        );
                      }
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
                fieldViewBuilder:
                    (context, controller, focusNode, onSubmitted) => TextField(
                      controller: controller,
                      focusNode: focusNode,
                      enabled: selectedOffice != null,
                      onChanged: _ownerTextEdited,
                      onSubmitted: (_) => onSubmitted(),
                      decoration: InputDecoration(
                        labelText: 'Υπάλληλος',
                        hintText: selectedOffice == null
                            ? 'Διαλέξτε πρώτα γραφείο'
                            : 'Πληκτρολογήστε…',
                        helperText: _ownerHelper(selectedOffice != null),
                        helperMaxLines: 2,
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
              ),
            ),
          ],
        ),
        if (draft.creatingOwner) ...[
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  key: const Key('lamp_placement_new_owner_last_name'),
                  controller: _lastNameController,
                  focusNode: _lastNameFocus,
                  onChanged: (text) => widget.onChanged(
                    widget.draft.copyWith(newOwnerLastName: text),
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Επώνυμο νέου υπαλλήλου',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  key: const Key('lamp_placement_new_owner_first_name'),
                  controller: _firstNameController,
                  onChanged: (text) => widget.onChanged(
                    widget.draft.copyWith(newOwnerFirstName: text),
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Όνομα νέου υπαλλήλου',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
            ],
          ),
        ],
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
