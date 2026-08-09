import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Παιδί που δεν συμμετέχει στον υπολογισμό «φυσικού» πλάτους του γονέα.
///
/// Οι διάλογοι του Material μετρούν το πλάτος τους από το μονόγραμμο πλάτος
/// κάθε παιδιού (IntrinsicWidth). Ένα μακρύ ελεύθερο κείμενο θα τους τέντωνε
/// αντί να αναδιπλωθεί — το ίδιο πρόβλημα που είχε η ένδειξη απόκλισης της
/// τοποθεσίας πριν μεταφερθεί στο helper του πεδίου. Τυλιγμένο εδώ, το παιδί
/// παίρνει το πλάτος που ορίζουν τα υπόλοιπα παιδιά του διαλόγου και διπλώνει
/// μέσα σε αυτό.
class IntrinsicWidthOptOut extends SingleChildRenderObjectWidget {
  const IntrinsicWidthOptOut({super.key, super.child});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderIntrinsicWidthOptOut();
}

class _RenderIntrinsicWidthOptOut extends RenderProxyBox {
  @override
  double computeMinIntrinsicWidth(double height) => 0;

  @override
  double computeMaxIntrinsicWidth(double height) => 0;
}
