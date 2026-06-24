import 'package:flutter/material.dart';

/// Συγχρονίζει controller ← state μόνο όταν το πεδίο δεν έχει εστίαση.
///
/// Κατά το πληκτρολόγηση ο controller προηγείται του provider· rebuild (π.χ. hover
/// πίνακα) δεν πρέπει να τον αντικαθιστά με παλιό [query].
void syncCatalogSearchControllerFromState({
  required TextEditingController controller,
  required FocusNode focusNode,
  required String query,
}) {
  if (focusNode.hasFocus) return;
  if (controller.text == query) return;
  controller.value = TextEditingValue(
    text: query,
    selection: TextSelection.collapsed(offset: query.length),
  );
}

/// Καθαρισμός αναζήτησης από κουμπί × — controller και provider μαζί.
void clearCatalogSearchField({
  required TextEditingController controller,
  required void Function(String) setSearchQuery,
}) {
  controller.clear();
  setSearchQuery('');
}
