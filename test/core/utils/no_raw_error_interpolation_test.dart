import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Αρχεία όπου τα μηνύματα προς χρήστη πρέπει να περνούν από
/// [humanizeUserFacingError] και όχι από ωμή παρεμβολή `$e`.
const _guardedRelativePaths = <String>[
  'lib/features/database/widgets/database_maintenance_panel.dart',
  'lib/features/database/widgets/database_settings_panel.dart',
  'lib/core/widgets/database_error_screen.dart',
  'lib/features/dictionary/screens/dictionary_manager_screen.dart',
  'lib/features/history/widgets/lansweeper_report_dialog.dart',
  'lib/features/history/widgets/audit_entity_side_panel.dart',
  'lib/features/history/widgets/application_audit_tab.dart',
  'lib/features/tasks/widgets/task_analytics_bottom_sheet.dart',
  'lib/features/history/screens/dashboard_screen.dart',
  'lib/features/history/screens/dashboard_filter_pane.dart',
  'lib/features/calls/screens/widgets/remote_connection_buttons.dart',
  'lib/features/settings/widgets/remote_tool_form/remote_tool_form_dialog.dart',
  'lib/features/history/widgets/lansweeper/ai_prompt_template_editor_dialog.dart',
];

/// Ωμή παρεμβολή σφάλματος σε μήνυμα χρήστη, π.χ. `: $e'` ή `('$e')`.
final _rawErrorInterpolation = RegExp(r": \$e'|\('\$e'\)");

void main() {
  test(
    'τα διαχειριστικά πάνελ δεν παρεμβάλλουν ωμό \$e σε μηνύματα χρήστη',
    () {
      final packageRoot = Directory.current;
      final violations = <String>[];

      for (final relative in _guardedRelativePaths) {
        final file = File('${packageRoot.path}${Platform.pathSeparator}'
            '${relative.replaceAll('/', Platform.pathSeparator)}');
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
    },
  );
}
