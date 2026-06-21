import 'dart:convert';

/// Ποια κάρτες της οθόνης κλήσεων εμφανίζονται (ρύθμιση χρήστη).
class CallsScreenCardsVisibility {
  const CallsScreenCardsVisibility({
    this.showUserCard = true,
    this.showMapCard = true,
    this.showEmployeeRecentCard = true,
    this.showEquipmentRecentPanel = true,
    this.showGlobalRecentCard = true,
  });

  final bool showUserCard;

  /// Mini map card visibility (renamed from [showEquipmentCard]).
  final bool showMapCard;
  final bool showEmployeeRecentCard;
  final bool showEquipmentRecentPanel;
  final bool showGlobalRecentCard;

  /// Backward-compatible alias.
  bool get showEquipmentCard => showMapCard;

  static const CallsScreenCardsVisibility defaults =
      CallsScreenCardsVisibility();

  int get enabledCount => [
    showUserCard,
    showMapCard,
    showEmployeeRecentCard,
    showEquipmentRecentPanel,
    showGlobalRecentCard,
  ].where((e) => e).length;

  CallsScreenCardsVisibility copyWith({
    bool? showUserCard,
    bool? showMapCard,
    bool? showEquipmentCard,
    bool? showEmployeeRecentCard,
    bool? showEquipmentRecentPanel,
    bool? showGlobalRecentCard,
  }) {
    return CallsScreenCardsVisibility(
      showUserCard: showUserCard ?? this.showUserCard,
      showMapCard: showMapCard ?? showEquipmentCard ?? this.showMapCard,
      showEmployeeRecentCard:
          showEmployeeRecentCard ?? this.showEmployeeRecentCard,
      showEquipmentRecentPanel:
          showEquipmentRecentPanel ?? this.showEquipmentRecentPanel,
      showGlobalRecentCard: showGlobalRecentCard ?? this.showGlobalRecentCard,
    );
  }

  Map<String, dynamic> toJson() => {
    'u': showUserCard,
    'e': showMapCard,
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
      showMapCard: read('e', true),
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
