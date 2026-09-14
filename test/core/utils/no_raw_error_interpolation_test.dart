import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Αρχεία όπου τα μηνύματα προς χρήστη πρέπει να περνούν από
/// [humanizeUserFacingError] και όχι από ωμή παρεμβολή `$e`.
const _guardedRelativePaths = <String>[
  'lib/features/database/widgets/database_maintenance_sections.dart',
  'lib/features/database/widgets/database_settings_panel.dart',
  'lib/core/widgets/database_error_screen.dart',
  'lib/features/dictionary/screens/dictionary_manager_screen.dart',
  'lib/features/history/widgets/lansweeper_report_dialog.dart',
  'lib/features/history/widgets/audit_entity_side_panel.dart',
  'lib/features/history/widgets/application_audit_tab.dart',
  'lib/features/tasks/widgets/task_analytics_bottom_sheet.dart',
  'lib/features/history/screens/dashboard_screen.dart',
  'lib/features/history/screens/dashboard_filter_bar.dart',
  'lib/features/history/services/dashboard_export_launcher.dart',
  'lib/features/calls/screens/widgets/remote_connection_buttons.dart',
  'lib/features/settings/widgets/remote_tool_form/remote_tool_form_dialog.dart',
  'lib/features/history/widgets/lansweeper/ai_prompt_template_editor_dialog.dart',
  // Προστέθηκαν 14/09/2026: και τα τρία έριχναν ωμό αγγλικό SQL σε κείμενο
  // χρήστη, και κανένα δεν ήταν εδώ για να το πιάσει ο φρουρός.
  'lib/features/database/screens/database_browser_screen.dart',
  'lib/features/database/widgets/database_rename_failure_dialog.dart',
  'lib/features/database/widgets/integrity_fix_dialogs.dart',
];

/// Ωμή παρεμβολή σφάλματος σε μήνυμα χρήστη.
///
/// Δύο μορφές, και οι δύο μετρημένες στον κώδικα:
/// 1. `: $e'` ή `('$e')` — η εξαίρεση της κλειστούρας `catch`.
/// 2. `${κάτι.error}` — το σφάλμα ενός `AsyncValue` ή `AsyncSnapshot`. Αυτή
///    ξέφευγε ως τις 14/09/2026, και μαζί της τρία σημεία της περιοχής
///    «Βάση Δεδομένων» που τύπωναν τρεις σειρές αγγλικού SQL.
final _rawErrorInterpolation = RegExp(
  r": \$e'|\('\$e'\)|\$\{[A-Za-z_][A-Za-z0-9_.]*\.error[!]?\}",
);

void main() {
  // Ο φρουρός του φρουρού: ένα μοτίβο που δεν ταιριάζει πουθενά περνά
  // πράσινο για πάντα. Τα δείγματα είναι οι ΠΡΑΓΜΑΤΙΚΕΣ γραμμές που
  // βρέθηκαν στον κώδικα στις 14/09/2026.
  test('το μοτίβο πιάνει και τις δύο μορφές ωμής παρεμβολής', () {
    const caught = <String>[
      "        'Δεν ήταν δυνατή η φόρτωση στατιστικών: \${statsAsync.error}',",
      "                  'Σφάλμα: \${snap.error}',",
      "      showSnack('Αποτυχία: \$e');",
      "      messenger.showSnackBar(SnackBar(content: Text('\$e')));",
    ];
    for (final line in caught) {
      expect(
        _rawErrorInterpolation.hasMatch(line),
        isTrue,
        reason: 'Ξέφυγε ωμή παρεμβολή: $line',
      );
    }

    const allowed = <String>[
      "        Text(humanizeUserFacingError(snap.error!)),",
      "        RawErrorDetailsTile(error: statsAsync.error!),",
      "        final message = 'Ολοκληρώθηκε: \$count εγγραφές';",
    ];
    for (final line in allowed) {
      expect(
        _rawErrorInterpolation.hasMatch(line),
        isFalse,
        reason: 'Ψεύτικο εύρημα σε αθώα γραμμή: $line',
      );
    }
  });

  test('τα διαχειριστικά πάνελ δεν παρεμβάλλουν ωμό \$e σε μηνύματα χρήστη', () {
    final packageRoot = Directory.current;
    final violations = <String>[];

    for (final relative in _guardedRelativePaths) {
      final file = File(
        '${packageRoot.path}${Platform.pathSeparator}'
        '${relative.replaceAll('/', Platform.pathSeparator)}',
      );
      expect(
        file.existsSync(),
        isTrue,
        reason: 'Λείπει το αρχείο-φρουρός: $relative',
      );
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (_rawErrorInterpolation.hasMatch(lines[i])) {
          violations.add('$relative:${i + 1}: ${lines[i].trim()}');
        }
      }
    }

    expect(
      violations,
      isEmpty,
      reason:
          'Βρέθηκε ωμή παρεμβολή \$e. Χρησιμοποίησε humanizeUserFacingError.\n'
          '${violations.join('\n')}',
    );
  });
}
