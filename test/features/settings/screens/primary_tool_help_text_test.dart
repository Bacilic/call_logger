// Unit test: κείμενο βοήθειας «Κύριο κουμπί» απομακρυσμένης.
//
//   flutter test test/features/settings/screens/primary_tool_help_text_test.dart

import 'package:call_logger/core/models/remote_tool.dart';
import 'package:call_logger/core/models/remote_tool_role.dart';
import 'package:call_logger/features/settings/screens/primary_tool_help_text.dart';
import 'package:flutter_test/flutter_test.dart';

RemoteTool _tool({
  required int id,
  required String name,
  required ToolRole role,
}) {
  return RemoteTool(
    id: id,
    name: name,
    role: role,
    executablePath: r'C:\tool.exe',
    sortOrder: id,
    isActive: true,
  );
}

void main() {
  group('PrimaryToolHelpText.build', () {
    test(
      'με VNC και generic: παράδειγμα έχει πρώτα το μη-VNC, μετά το VNC',
      () {
        final text = PrimaryToolHelpText.build([
          _tool(id: 1, name: 'UltraVNC', role: ToolRole.vnc),
          _tool(id: 2, name: 'Δοκιμαστικό', role: ToolRole.generic),
        ]);
        expect(text, contains('Παράδειγμα'));
        expect(text, contains('«Δοκιμαστικό»'));
        expect(text, contains('«UltraVNC»'));
        final aIndex = text.indexOf('«Δοκιμαστικό»');
        final bIndex = text.indexOf('«UltraVNC»');
        expect(aIndex, lessThan(bIndex));
      },
    );

    test('με ένα μόνο εργαλείο δεν προσθέτει Παράδειγμα', () {
      final text = PrimaryToolHelpText.build([
        _tool(id: 1, name: 'ΜόνοΈνα', role: ToolRole.rdp),
      ]);
      expect(text, isNot(contains('Παράδειγμα')));
    });

    test('χωρίς VNC χρησιμοποιεί τα δύο ονόματα χωρίς σφάλμα', () {
      final text = PrimaryToolHelpText.build([
        _tool(id: 1, name: 'RDP Alpha', role: ToolRole.rdp),
        _tool(id: 2, name: 'AnyDesk Beta', role: ToolRole.anydesk),
      ]);
      expect(text, contains('Παράδειγμα'));
      expect(text, contains('«RDP Alpha»'));
      expect(text, contains('«AnyDesk Beta»'));
    });

    test('βασικό κείμενο περιέχει πάντα τα κλειδιά επεξήγησης', () {
      final withExample = PrimaryToolHelpText.build([
        _tool(id: 1, name: 'A', role: ToolRole.rdp),
        _tool(id: 2, name: 'B', role: ToolRole.vnc),
      ]);
      final withoutExample = PrimaryToolHelpText.build([
        _tool(id: 1, name: 'A', role: ToolRole.rdp),
      ]);
      for (final text in [withExample, withoutExample]) {
        expect(text, contains('παρακάμπτοντας'));
        expect(text, contains('διαθέσιμο για τον συγκεκριμένο εξοπλισμό'));
      }
    });
  });
}
