import 'calls_field_groups.dart';

/// Derived screen mode helpers (compact / expanded).
extension CallsScreenMode on CallsFieldGroups {
  /// Alias for [isExpanded] — at least one field group is active.
  bool get isExpandedMode => isExpanded;

  /// Alias for [isCompact] — no field groups active.
  bool get isCompactMode => isCompact;
}
