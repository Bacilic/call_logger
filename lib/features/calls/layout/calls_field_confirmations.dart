/// Tracks which header fields were confirmed (blur / submit / list selection).
/// Separate from raw typing state in [SmartEntitySelectorState].
class CallsFieldConfirmations {
  const CallsFieldConfirmations({
    this.phone = false,
    this.equipment = false,
    this.department = false,
    this.caller = false,
  });

  final bool phone;
  final bool equipment;
  final bool department;
  final bool caller;

  static const CallsFieldConfirmations empty = CallsFieldConfirmations();

  bool get anyConfirmed => phone || equipment || department || caller;

  CallsFieldConfirmations copyWith({
    bool? phone,
    bool? equipment,
    bool? department,
    bool? caller,
    bool clearAll = false,
  }) {
    if (clearAll) return CallsFieldConfirmations.empty;
    return CallsFieldConfirmations(
      phone: phone ?? this.phone,
      equipment: equipment ?? this.equipment,
      department: department ?? this.department,
      caller: caller ?? this.caller,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CallsFieldConfirmations &&
          phone == other.phone &&
          equipment == other.equipment &&
          department == other.department &&
          caller == other.caller;

  @override
  int get hashCode => Object.hash(phone, equipment, department, caller);
}
