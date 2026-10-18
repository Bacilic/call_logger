// Widget test: ο σύνδεσμος της ένδειξης ανοίγει ΜΟΝΟ αυτό το κλείσιμο.
//
//   flutter test test/features/settings/widgets/shutdown_incident_notice_test.dart

import 'package:call_logger/core/services/shutdown_trace_incident.dart';
import 'package:call_logger/features/settings/widgets/shutdown_incident_dialog.dart';
import 'package:call_logger/features/settings/widgets/shutdown_incident_notice.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('«Προβολή αυτού του κλεισίματος» δείχνει τα βήματά του', (
    tester,
  ) async {
    final incident = ShutdownTraceIncident(
      occurredAt: DateTime(2026, 10, 17, 13, 19, 41),
      totalMs: 18004,
      slowestStepLabel: 'Συγχώνευση αρχείων βάσης',
      slowestStepMs: 18002,
      hadFailure: false,
      wasInterrupted: true,
      trace: '''
[2026-10-17 13:19:19] step=1 "Παράδοση συνεδρίας" START
[2026-10-17 13:19:37] step=1 "Παράδοση συνεδρίας" OK durationMs=18002
[2026-10-17 13:19:37] step=2 "Συγχώνευση αρχείων βάσης" START
[2026-10-17 13:19:39] step=2 "Συγχώνευση αρχείων βάσης" INTERRUPTED''',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ShutdownIncidentNotice(
              incident: incident,
              onShowDetails: () =>
                  showShutdownIncidentDialog(context, incident),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Προβολή αυτού του κλεισίματος'));
    await tester.pumpAndSettle();

    expect(find.text('Προηγούμενο κλείσιμο'), findsOneWidget);
    expect(find.text('Παράδοση συνεδρίας'), findsOneWidget);
    expect(find.text('18,0 δευτ.'), findsOneWidget);
    expect(find.text('διακόπηκε'), findsOneWidget);

    await tester.tap(find.text('Κλείσιμο'));
    await tester.pumpAndSettle();
    expect(find.text('Προηγούμενο κλείσιμο'), findsNothing);
  });
}
