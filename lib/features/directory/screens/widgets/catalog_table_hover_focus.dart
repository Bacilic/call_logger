import 'package:flutter/material.dart';

/// True όταν η κύρια εστίαση είναι σε πεδίο επεξεργασίας κειμένου (π.χ. αναζήτηση).
bool catalogPrimaryFocusIsEditableTextField() {
  final primary = FocusManager.instance.primaryFocus;
  final ctx = primary?.context;
  if (ctx == null) return false;
  return ctx.findAncestorStateOfType<EditableTextState>() != null;
}

/// Εστίαση πίνακα για πλήκτρα ↑↓ μόνο όταν δεν πληκτρολογεί ο χρήστης σε TextField.
void requestCatalogTableKeyboardFocusOnHover(FocusNode tableFocus) {
  if (catalogPrimaryFocusIsEditableTextField()) return;
  if (!tableFocus.hasFocus) {
    tableFocus.requestFocus();
  }
}
