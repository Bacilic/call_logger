import 'package:flutter/services.dart';

/// Βοηθητικά για στόχο VNC: IPv4 χωρίς πρόθεμα `PC`, κανονικοποίηση `,` → `.` (πληκτρολόγιο EL).
abstract final class VncRemoteTarget {
  VncRemoteTarget._();

  static final RegExp _ipv4 = RegExp(
    r'^((25[0-5]|2[0-4]\d|[01]?\d\d?)\.){3}(25[0-5]|2[0-4]\d|[01]?\d\d?)$',
  );
  static final RegExp _equipmentCodeDigits = RegExp(r'^\d{3,6}$');
  static final RegExp _hostStartingWithLetter = RegExp(
    r'^[A-Za-z][A-Za-z0-9.-]*$',
  );

  /// Επιστρέφει έγκυρη IPv4 μετά από `,` → `.` αν το [raw] είναι IPv4· αλλιώς null.
  static String? tryParseIpv4Host(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return null;
    final normalized = t.replaceAll(',', '.');
    if (!_ipv4.hasMatch(normalized)) return null;
    return normalized;
  }

  /// Επιστρέφει έγκυρο host για VNC:
  /// - IPv4 그대로
  /// - 3..6 ψηφία -> `prefix + code`
  /// - host που ξεκινά με γράμμα -> 그대로 (χωρίς prefix)
  /// αλλιώς null.
  static String? resolveValidVncHost(
    String raw, {
    String prefix = 'PC',
  }) {
    final t = raw.trim();
    if (t.isEmpty) return null;
    final ip = tryParseIpv4Host(t);
    if (ip != null) return ip;
    if (_equipmentCodeDigits.hasMatch(t)) return '$prefix$t';
    if (_hostStartingWithLetter.hasMatch(t)) return t;
    return null;
  }

  /// Στόχος VNC για ελεύθερο κείμενο εξοπλισμού: IPv4 χωρίς `PC`, αλλιώς `PC` + trim.
  static String hostForUnknownEquipmentText(String equipmentText) {
    return resolveValidVncHost(equipmentText) ?? 'Άγνωστο';
  }
}

/// Αντικαθιστά `,` με `.` στο πεδίο εξοπλισμού (numpad «τελεία» σε ελληνικό locale).
final class CommaToDotDecimalSeparatorFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final newText = newValue.text.replaceAll(',', '.');
    if (newText == newValue.text) return newValue;
    return TextEditingValue(
      text: newText,
      selection: newValue.selection,
      composing: newValue.composing,
    );
  }
}
