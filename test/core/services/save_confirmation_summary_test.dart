import 'package:call_logger/core/models/remote_tool.dart';
import 'package:call_logger/core/models/remote_tool_role.dart';
import 'package:call_logger/core/services/save_confirmation_summary.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('buildSaveConfirmationMessage', () {
    test('νέα εγγραφή τμήματος', () {
      final message = buildSaveConfirmationMessage(
        entityType: 'department',
        entityLabel: 'Πληροφορική',
        oldMap: const {},
        newMap: const {'name': 'Πληροφορική', 'color': '#1976D2'},
        isNew: true,
      );

      expect(message, 'Δημιουργήθηκε τμήμα «Πληροφορική»');
    });

    test('επεξεργασία με μία αλλαγή χρώματος τμήματος — ονομαστική ετικέτα', () {
      final message = buildSaveConfirmationMessage(
        entityType: 'department',
        entityLabel: 'Πληροφορική',
        oldMap: const {'name': 'Πληροφορική', 'color': '#1976D2'},
        newMap: const {'name': 'Πληροφορική', 'color': '#EF5350'},
        isNew: false,
      );

      expect(
        message,
        'Αποθηκεύτηκε — τμήμα «Πληροφορική»\n'
        'χρώμα: Μπλε #1976D2 → Κόκκινο #EF5350',
      );
    });

    test('επεξεργασία με 6 αλλαγές — περικοπή σε 4 + υπόλοιπες', () {
      final message = buildSaveConfirmationMessage(
        entityType: 'department',
        entityLabel: 'Πληροφορική',
        oldMap: const {
          'color': '#1976D2',
          'building': 'Α',
          'notes': 'παλιά',
          'map_x': 10.0,
          'map_y': 20.0,
          'map_rotation': 0.0,
        },
        newMap: const {
          'color': '#EF5350',
          'building': 'Β',
          'notes': 'νέα',
          'map_x': 50.0,
          'map_y': 60.0,
          'map_rotation': 90.0,
        },
        isNew: false,
      );

      final lines = message.split('\n');
      expect(lines.first, 'Αποθηκεύτηκε — τμήμα «Πληροφορική»');
      expect(lines, hasLength(6));
      expect(lines.last, '… και 2 ακόμη αλλαγές');
    });

    test('αποθήκευση χωρίς αλλαγές', () {
      final message = buildSaveConfirmationMessage(
        entityType: 'department',
        entityLabel: 'Πληροφορική',
        oldMap: const {'name': 'Πληροφορική', 'color': '#1976D2'},
        newMap: const {'name': 'Πληροφορική', 'color': '#1976D2'},
        isNew: false,
      );

      expect(message, kSaveConfirmationNoChangesMessage);
    });

    test('κλειδί μόνο στο oldMap — δεν παράγει γραμμή αλλαγής', () {
      final message = buildSaveConfirmationMessage(
        entityType: 'department',
        entityLabel: 'Πληροφορική',
        oldMap: const {'name': 'Πληροφορική', 'building': 'Κτίριο Α'},
        newMap: const {'name': 'Πληροφορική'},
        isNew: false,
      );

      expect(message, kSaveConfirmationNoChangesMessage);
    });

    test('λίστα phones — τιμές χωρισμένες με κόμμα', () {
      final message = buildSaveConfirmationMessage(
        entityType: 'user',
        entityLabel: 'Γιάννης Παπαδόπουλος',
        oldMap: const {'phones': ['2531', '2839']},
        newMap: const {'phones': ['2531']},
        isNew: false,
      );

      expect(
        message,
        'Αποθηκεύτηκε — υπάλληλος «Γιάννης Παπαδόπουλος»\n'
        'phones: 2531, 2839 → 2531',
      );
    });

    test('επεξεργασία κλήσης — αλλαγή θέματος και διάρκειας', () {
      final message = buildSaveConfirmationMessage(
        entityType: 'call',
        entityLabel: '#123',
        oldMap: const {
          'issue': 'Παλιό θέμα',
          'duration': 5,
        },
        newMap: const {
          'issue': 'Νέο θέμα',
          'duration': 10,
        },
        isNew: false,
      );

      expect(
        message,
        'Αποθηκεύτηκε — κλήση «#123»\n'
        'θέμα: Παλιό θέμα → Νέο θέμα\n'
        'Διάρκεια: 5 → 10',
      );
    });

    test('επεξεργασία εκκρεμότητας — αλλαγή τίτλου και προθεσμίας', () {
      final message = buildSaveConfirmationMessage(
        entityType: 'task',
        entityLabel: 'Εκτύπωση',
        oldMap: const {
          'title': 'Παλιός τίτλος',
          'due_date': '2026-01-01T10:00:00.000',
        },
        newMap: const {
          'title': 'Νέος τίτλος',
          'due_date': '2026-02-01T10:00:00.000',
        },
        isNew: false,
      );

      expect(
        message,
        'Αποθηκεύτηκε — εκκρεμότητα «Εκτύπωση»\n'
        'προθεσμία: 2026-01-01T10:00:00.000 → 2026-02-01T10:00:00.000\n'
        'τίτλος: Παλιός τίτλος → Νέος τίτλος',
      );
    });
  });

  group('buildRemoteToolSaveMessage', () {
    test('ελληνικές ετικέτες και σύνοψη ορισμάτων χωρίς JSON', () {
      const oldTool = RemoteTool(
        id: 1,
        name: 'VNC Viewer',
        role: ToolRole.vnc,
        executablePath: r'C:\vnc.exe',
        sortOrder: 1,
        isActive: true,
        arguments: [
          RemoteToolArgument(value: '{TARGET}', isActive: true),
        ],
        testTargetIp: '10.0.0.1',
      );
      const newTool = RemoteTool(
        id: 1,
        name: 'VNC Viewer',
        role: ToolRole.vnc,
        executablePath: r'C:\vnc.exe',
        sortOrder: 2,
        isActive: true,
        arguments: [
          RemoteToolArgument(value: '{TARGET}', isActive: true),
          RemoteToolArgument(value: '{FILE}', isActive: true),
        ],
        testTargetIp: '10.0.0.1',
        suggestedValuesJson: '[]',
        iconAssetKey: 'vnc',
      );

      final message = buildRemoteToolSaveMessage(
        oldTool: oldTool,
        newTool: newTool,
      );

      expect(message, contains('Αποθηκεύτηκε — εργαλείο «VNC Viewer»'));
      expect(message, contains('Ορίσματα: {TARGET} → {TARGET}, {FILE}'));
      expect(message, isNot(contains('arguments_json')));
      expect(message, isNot(contains('sort_order')));
      expect(message, isNot(contains('icon_asset_key')));
    });

    test('αλλαγή ρόλου — ελληνική ετικέτα ρόλου', () {
      const oldTool = RemoteTool(
        id: 2,
        name: 'Γενικό',
        role: ToolRole.generic,
        executablePath: r'C:\tool.exe',
        sortOrder: 0,
        isActive: true,
      );
      const newTool = RemoteTool(
        id: 2,
        name: 'Γενικό',
        role: ToolRole.rdp,
        executablePath: r'C:\tool.exe',
        sortOrder: 0,
        isActive: true,
      );

      final message = buildRemoteToolSaveMessage(
        oldTool: oldTool,
        newTool: newTool,
      );

      expect(
        message,
        'Αποθηκεύτηκε — εργαλείο «Γενικό»\n'
        'Ρόλος: Κανένα – Χωρίς αυτόματο στόχο → RDP Hostname/IP',
      );
    });
  });
}
