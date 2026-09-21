import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

import '../../../core/widgets/draggable_dialog_shell.dart';
import '../models/task.dart';
import '../services/task_print_launcher.dart';
import '../services/task_print_document.dart';

/// Δείχνει το φύλλο πριν τυπωθεί, και τυπώνει από εκεί.
///
/// **Γιατί υπάρχει:** το παράθυρο εκτύπωσης των Windows κρατά χώρο για
/// προεπισκόπηση, αλλά τον γεμίζει μόνο όταν η εφαρμογή υλοποιεί το παλιό
/// μοντέλο XPS — αλλιώς γράφει «Αυτή η εφαρμογή δεν υποστηρίζει προεπισκόπηση
/// εκτύπωσης». Αντί να κυνηγήσουμε εκείνο το μονοπάτι μέσα σε native κώδικα,
/// η προεπισκόπηση γίνεται εδώ, όπου φαίνεται **το ίδιο** PDF που θα σταλεί.
///
/// Ό,τι δεν αφορά αυτή τη δουλειά μένει κλειστό: ούτε αλλαγή μεγέθους σελίδας
/// (το φύλλο είναι Α4 και δεν έχει λόγο να μην είναι), ούτε προσανατολισμός,
/// ούτε κοινοποίηση.
Future<void> showTaskPrintPreviewDialog(
  BuildContext context, {
  required Task task,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => TaskPrintPreviewDialog(task: task),
  );
}

class TaskPrintPreviewDialog extends StatelessWidget {
  const TaskPrintPreviewDialog({required this.task, super.key});

  final Task task;

  @override
  Widget build(BuildContext context) {
    return DraggableDialogShell(
      title: Text('Προεπισκόπηση · ${taskPrintFileName(task)}'),
      builder: (titleHandle) => AlertDialog(
        title: titleHandle,
        contentPadding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        content: SizedBox(
          width: 740,
          height: 640,
          child: PdfPreview(
            build: (_) => buildTaskSheetBytes(task),
            initialPageFormat: PdfPageFormat.a4,
            canChangePageFormat: false,
            canChangeOrientation: false,
            canDebug: false,
            allowSharing: false,
            // Το έτοιμο κουμπί του πακέτου ανοίγει το παλιό «Παράμετροι
            // εκτύπωσης» και δεν δέχεται ρύθμιση γι' αυτό — μπαίνει δικό μας.
            allowPrinting: false,
            actions: [
              PdfPreviewAction(
                icon: const Icon(Icons.print),
                onPressed: (context, build, format) async {
                  final messenger = ScaffoldMessenger.of(context);
                  final navigator = Navigator.of(context);
                  final printed = await sendSheetToPrinter(
                    messenger: messenger,
                    task: task,
                    bytes: await build(format),
                  );
                  if (printed) navigator.pop();
                },
              ),
            ],
            pdfFileName: taskPrintFileName(task),
            loadingWidget: const Center(child: CircularProgressIndicator()),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Κλείσιμο'),
          ),
        ],
      ),
    );
  }
}
