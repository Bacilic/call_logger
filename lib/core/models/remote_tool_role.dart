/// Ρόλος εργαλείου απομακρυσμένης σύνδεσης (στήλη `remote_tools.role`).
enum ToolRole {
  vnc,
  rdp,
  anydesk,
  generic,
}

extension ToolRoleDb on ToolRole {
  /// Τιμή για SQLite / JSON.
  String get dbValue => switch (this) {
        ToolRole.vnc => 'vnc',
        ToolRole.rdp => 'rdp',
        ToolRole.anydesk => 'anydesk',
        ToolRole.generic => 'generic',
      };
}

extension ToolRoleShortLabel on ToolRole {
  /// Σύντομη ετικέτα για εμφάνιση σε λίστες / badges.
  String get shortLabel => switch (this) {
        ToolRole.vnc => 'VNC',
        ToolRole.rdp => 'RDP',
        ToolRole.anydesk => 'AnyDesk',
        ToolRole.generic => 'Γενικό',
      };
}

/// Από τιμή βάσης· άγνωστο/κενό → [ToolRole.generic].
ToolRole toolRoleFromDb(Object? raw) {
  final s = raw?.toString().trim().toLowerCase() ?? '';
  return switch (s) {
    'vnc' => ToolRole.vnc,
    'rdp' => ToolRole.rdp,
    'anydesk' => ToolRole.anydesk,
    'generic' => ToolRole.generic,
    _ => ToolRole.generic,
  };
}
