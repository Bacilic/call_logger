/// Τα πεδία δημιουργίας σύμβασης: όνομα, προμηθευτής, κατηγορία.
///
/// Το όνομα έρχεται προσυμπληρωμένο από την ωμή τιμή — «30236» — γιατί αυτό
/// είναι το μόνο που ξέρει η βάση για τη σύμβαση που λείπει.
///
/// Ο προμηθευτής και η κατηγορία **διαλέγονται από τους υπάρχοντες**, δεν
/// γράφονται ελεύθερα: η Λάμπα δεν έχει χωριστούς πίνακες γι' αυτούς, οπότε
/// ελεύθερο κείμενο θα δημιουργούσε δεύτερη ορθογραφία του ίδιου προμηθευτή
/// χωρίς κανέναν να το εμποδίσει.
library;

import 'package:flutter/material.dart';

import '../../../core/database/old_database/lamp_placement_catalog.dart';

class LampContractFields extends StatefulWidget {
  const LampContractFields({
    super.key,
    required this.catalog,
    required this.nameController,
    required this.supplierId,
    required this.categoryId,
    required this.onChanged,
  });

  final LampPlacementCatalog catalog;
  final TextEditingController nameController;
  final int? supplierId;
  final int? categoryId;
  final void Function({int? supplierId, int? categoryId}) onChanged;

  @override
  State<LampContractFields> createState() => _LampContractFieldsState();
}

class _LampContractFieldsState extends State<LampContractFields> {
  final TextEditingController _supplierController = TextEditingController();
  final FocusNode _supplierFocus = FocusNode();

  @override
  void dispose() {
    _supplierController.dispose();
    _supplierFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final categories = widget.catalog.contractCategories;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: const Key('lamp_contract_name_field'),
          controller: widget.nameController,
          decoration: const InputDecoration(
            labelText: 'Όνομα σύμβασης',
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Autocomplete<LampContractLookupEntry>(
                key: const Key('lamp_contract_supplier_field'),
                textEditingController: _supplierController,
                focusNode: _supplierFocus,
                displayStringForOption: (entry) => entry.label,
                optionsBuilder: (value) =>
                    widget.catalog.searchSuppliers(value.text),
                onSelected: (entry) =>
                    widget.onChanged(supplierId: entry.id,
                        categoryId: widget.categoryId),
                optionsViewBuilder: (context, select, options) => Align(
                  alignment: Alignment.topLeft,
                  child: Material(
                    elevation: 4,
                    color: theme.colorScheme.surface,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxHeight: 280,
                        minWidth: 340,
                      ),
                      child: ListView.builder(
                        padding: EdgeInsets.zero,
                        shrinkWrap: true,
                        itemCount: options.length,
                        itemBuilder: (context, index) {
                          final entry = options.elementAt(index);
                          return ListTile(
                            dense: true,
                            title: Text(entry.name),
                            onTap: () => select(entry),
                          );
                        },
                      ),
                    ),
                  ),
                ),
                fieldViewBuilder:
                    (context, controller, focusNode, onSubmitted) => TextField(
                      controller: controller,
                      focusNode: focusNode,
                      onSubmitted: (_) => onSubmitted(),
                      decoration: const InputDecoration(
                        labelText: 'Προμηθευτής (προαιρετικό)',
                        hintText: 'Πληκτρολογήστε…',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              // Πέντε σταθερές κατηγορίες: λίστα, όχι αναζήτηση.
              child: DropdownButtonFormField<int?>(
                key: const Key('lamp_contract_category_field'),
                initialValue: widget.categoryId,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Κατηγορία (προαιρετικό)',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: <DropdownMenuItem<int?>>[
                  const DropdownMenuItem<int?>(
                    value: null,
                    child: Text('—'),
                  ),
                  for (final category in categories)
                    DropdownMenuItem<int?>(
                      value: category.id,
                      child: Text(
                        category.name,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (value) => widget.onChanged(
                  supplierId: widget.supplierId,
                  categoryId: value,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
