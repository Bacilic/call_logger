import 'package:flutter/material.dart';

/// Ενημέρωση ορατότητας overlay πρότασης μετά το frame (όχι κατά το build).
/// Το `hide()` όταν το portal δεν είναι συνδεδεμένο ή είναι ήδη κρυφό σπάει assertion στο hot reload.
void scheduleOverlayPortalVisibility(
  OverlayPortalController controller,
  bool visible, {
  required bool Function() isMounted,
}) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!isMounted()) return;
    if (visible) {
      if (!controller.isShowing) controller.show();
    } else if (controller.isShowing) {
      controller.hide();
    }
  });
}
