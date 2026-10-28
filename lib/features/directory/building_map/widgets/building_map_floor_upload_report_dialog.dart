import 'package:flutter/material.dart';
import '../../../../core/widgets/modal_route_tracker.dart';

/// Τι έγινε στο «Ανέβασμα κατόψεων στη βάση», όροφο-όροφο.
///
/// Λέει ρητά και τι **δεν** ανέβηκε: ένας όροφος που μένει χωρίς κάτοψη σε
/// όλους τους σταθμούς πρέπει να τον μάθει ο διαχειριστής εδώ, όχι από
/// συνάδελφο που βλέπει «Η κάτοψη δεν έχει ανέβει ακόμη».
Future<void> showFloorPlanUploadReportDialog(
  BuildContext context, {
  required List<String> uploaded,
  required List<String> notFound,
  required List<String> unreadable,
}) {
  return showDialog<void>(
    context: context,
    routeSettings: readOnlyRouteSettings,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Ανέβασμα κατόψεων στη βάση'),
      content: SingleChildScrollView(
        child: Text(
          floorPlanUploadReportText(
            uploaded: uploaded,
            notFound: notFound,
            unreadable: unreadable,
          ),
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Εντάξει'),
        ),
      ],
    ),
  );
}

/// Το κείμενο της αναφοράς — χωριστά, για να ελέγχεται χωρίς οθόνη.
String floorPlanUploadReportText({
  required List<String> uploaded,
  required List<String> notFound,
  required List<String> unreadable,
}) {
  if (uploaded.isEmpty && notFound.isEmpty && unreadable.isEmpty) {
    return 'Όλες οι κατόψεις έχουν ήδη ανέβει στη βάση.';
  }
  String list(List<String> labels) => labels.map((l) => '• $l').join('\n');
  final parts = <String>[
    if (uploaded.isNotEmpty)
      'Ανέβηκαν (${uploaded.length}) — τις βλέπουν πλέον όλοι οι σταθμοί:\n'
          '${list(uploaded)}',
    if (notFound.isNotEmpty)
      'Δεν βρέθηκε εικόνα σε αυτόν τον υπολογιστή (${notFound.length}):\n'
          '${list(notFound)}',
    if (unreadable.isNotEmpty)
      'Η εικόνα δεν διαβάστηκε (${unreadable.length}):\n${list(unreadable)}',
  ];
  return parts.join('\n\n');
}
