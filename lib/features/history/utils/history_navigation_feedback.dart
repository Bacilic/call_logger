import 'package:flutter/material.dart';

import '../providers/history_provider.dart';

/// Ανακοινώνει ποια φίλτρα του Ιστορικού έπαψαν να ισχύουν μετά από μετάβαση.
///
/// Ο [messenger] κρατιέται από τον καλούντα **πριν** την πλοήγηση: μετά από
/// αυτήν το widget που ξεκίνησε τη μετάβαση μπορεί να μην υπάρχει πια, οπότε ένα
/// `ScaffoldMessenger.of(context)` εκείνη τη στιγμή θα έσκαγε.
void showHistoryFiltersClearedSnackBar(
  ScaffoldMessengerState messenger,
  List<String> cleared,
) {
  final message = historyFiltersClearedMessage(cleared);
  if (message == null) return;
  messenger.showSnackBar(SnackBar(content: Text(message)));
}
