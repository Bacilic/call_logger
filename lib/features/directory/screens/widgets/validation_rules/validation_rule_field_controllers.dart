import 'package:flutter/widgets.dart';

import '../../../models/catalog_validation_rules.dart';

/// Ένα πεδίο της οθόνης: το κείμενό του και η εστίασή του μαζί.
///
/// Η εστίαση δεν είναι διακοσμητική — πάνω της κρέμεται η αποθήκευση: η τιμή
/// γράφεται όταν ο χρήστης φύγει από το πεδίο. Ζώντας δίπλα στον controller,
/// δεν γίνεται να προστεθεί το ένα και να ξεχαστεί το άλλο.
class ValidationRuleField {
  final TextEditingController controller = TextEditingController();
  final FocusNode focusNode = FocusNode();

  set text(String value) => controller.text = value;

  void dispose() {
    controller.dispose();
    focusNode.dispose();
  }
}

/// Τα πεδία κειμένου των ρυθμιζόμενων κανόνων, σε ένα αντικείμενο.
///
/// Ήταν επτά ξεχωριστοί controllers στην οθόνη, με επτά δημιουργίες, επτά
/// αναθέσεις και επτά `dispose()` — κάθε νέος ρυθμιζόμενος κανόνας απαιτούσε
/// να θυμηθείς και τα τρία σημεία. Εδώ ξεχνιέται μόνο ένα πράγμα, και ο
/// μεταγλωττιστής το λέει.
class ValidationRuleFieldControllers {
  final ValidationRuleField internalDigits = ValidationRuleField();
  final ValidationRuleField externalDigits = ValidationRuleField();
  final ValidationRuleField prefixFrom = ValidationRuleField();
  final ValidationRuleField prefixTo = ValidationRuleField();
  final ValidationRuleField equipmentMin = ValidationRuleField();
  final ValidationRuleField equipmentMax = ValidationRuleField();
  final ValidationRuleField allowedSymbols = ValidationRuleField();

  Iterable<ValidationRuleField> get _all => [
    internalDigits,
    externalDigits,
    prefixFrom,
    prefixTo,
    equipmentMin,
    equipmentMax,
    allowedSymbols,
  ];

  /// Γεμίζει τα πεδία από τους αποθηκευμένους κανόνες.
  void fillFrom(CatalogValidationRules rules) {
    internalDigits.text = '${rules.internalPhoneDigits}';
    externalDigits.text = '${rules.externalPhoneDigits}';
    prefixFrom.text = '${rules.internalPrefixFrom}';
    prefixTo.text = '${rules.internalPrefixTo}';
    equipmentMin.text = '${rules.equipmentMinDigits}';
    equipmentMax.text = '${rules.equipmentMaxDigits}';
    allowedSymbols.text = rules.personNameAllowedSymbols;
  }

  void dispose() {
    for (final field in _all) {
      field.dispose();
    }
  }
}
