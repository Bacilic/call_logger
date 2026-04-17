import 'dart:convert';

/// Ποια κάρτες της οθόνης κλήσεων εμφανίζονται (ρύθμιση χρήστη).
class CallsScreenCardsVisibility {
  const CallsScreenCardsVisibility({
    this.showUserCard = true,
    this.showEquipmentCard = true,
    this.showEmployeeRecentCard = true,
    this.showEquipmentRecentPanel = true,
    this.showGlobalRecentCard = true,
  });

  final bool showUserCard;
  final bool showEquipmentCard;
  final bool showEmployeeRecentCard;
  final bool showEquipmentRecentPanel;
  final bool showGlobalRecentCard;

  static const CallsScreenCardsVisibility defaults =
      CallsScreenCardsVisibility();

  int get enabledCount => [
    showUserCard,
    showEquipmentCard,
    showEmployeeRecentCard,
    showEquipmentRecentPanel,
    showGlobalRecentCard,
  ].where((e) => e).length;

  CallsScreenCardsVisibility copyWith({
    bool? showUserCard,
    bool? showEquipmentCard,
    bool? showEmployeeRecentCard,
    bool? showEquipmentRecentPanel,
    bool? showGlobalRecentCard,
  }) {
    return CallsScreenCardsVisibility(
      showUserCard: showUserCard ?? this.showUserCard,
      showEquipmentCard: showEquipmentCard ?? this.showEquipmentCard,
      showEmployeeRecentCard:
          showEmployeeRecentCard ?? this.showEmployeeRecentCard,
      showEquipmentRecentPanel:
          showEquipmentRecentPanel ?? this.showEquipmentRecentPanel,
      showGlobalRecentCard: showGlobalRecentCard ?? this.showGlobalRecentCard,
    );
  }

  Map<String, dynamic> toJson() => {
    'u': showUserCard,
    'e': showEquipmentCard,
    'er': showEmployeeRecentCard,
    'ep': showEquipmentRecentPanel,
    'g': showGlobalRecentCard,
  };

  static CallsScreenCardsVisibility fromJson(Map<String, dynamic>? json) {
    if (json == null) return defaults;
    bool read(String k, bool def) {
      final v = json[k];
      if (v is bool) return v;
      return def;
    }

    return CallsScreenCardsVisibility(
      showUserCard: read('u', true),
      showEquipmentCard: read('e', true),
      showEmployeeRecentCard: read('er', true),
      showEquipmentRecentPanel: read('ep', true),
      showGlobalRecentCard: read('g', true),
    );
  }

  static CallsScreenCardsVisibility fromJsonString(String? raw) {
    if (raw == null || raw.trim().isEmpty) return defaults;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return fromJson(decoded);
      }
      if (decoded is Map) {
        return fromJson(Map<String, dynamic>.from(decoded));
      }
    } catch (_) {}
    return defaults;
  }

  String toJsonString() => jsonEncode(toJson());
}
