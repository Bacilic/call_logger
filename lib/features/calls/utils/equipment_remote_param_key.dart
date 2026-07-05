/// Βοηθητικά για κλειδιά στο [EquipmentModel.remoteParams] (μόνο `<tool_id>`).
abstract final class EquipmentRemoteParamKey {
  EquipmentRemoteParamKey._();

  /// Δεσμευμένο κλειδί: id εργαλείου που καταστέλλει τα υπόλοιπα στη γραμμή κλήσης.
  static const String exclusiveToolKey = '__exclusive_tool__';

  /// Πρόθεμα για τιμή παραμέτρου που **δεν** είναι ενεργή (chip off) στη φόρμα εξοπλισμού·
  /// παραμένει στο JSON ώστε να επανέρχεται με re-enable χωρίς να θεωρείται ενεργός στόχος.
  static const String remoteParamStashPrefix = '__stash_';

  static String remoteParamStashKeyFor(String paramKey) =>
      '$remoteParamStashPrefix$paramKey';

  static bool isRemoteParamStashKey(String key) =>
      key.startsWith(remoteParamStashPrefix);

  static bool isReservedKey(String key) =>
      isRemoteParamStashKey(key) || key == exclusiveToolKey;

  static int? exclusiveToolIdFrom(Map<String, String> params) {
    final raw = params[exclusiveToolKey]?.trim();
    if (raw == null || raw.isEmpty) return null;
    return int.tryParse(raw);
  }

  static Map<String, String> withExclusiveToolId(
    Map<String, String> params,
    int? toolId,
  ) {
    final next = Map<String, String>.from(params);
    if (toolId == null) {
      next.remove(exclusiveToolKey);
    } else {
      next[exclusiveToolKey] = '$toolId';
    }
    return next;
  }

  static String? remoteParamStashRealKeyOrNull(String key) {
    if (!isRemoteParamStashKey(key)) return null;
    final rest = key.substring(remoteParamStashPrefix.length);
    return rest.isEmpty ? null : rest;
  }
}
