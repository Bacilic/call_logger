import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'lansweeper_ticket_link.dart';

enum UnsentTicketChoice { clear, retain, cancel }

enum DuplicateTicketAction { proceed, changeId, cancel }

Future<bool> showLansweeperResubmitConfirmDialog(BuildContext context) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Επαναϋποβολή'),
      content: const Text(
        'Η κλήση έχει ήδη κύριο Ticket ID. Θέλεις να γίνει νέα καταχώρηση;',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Άκυρο'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Συνέχεια'),
        ),
      ],
    ),
  );
  return confirmed == true;
}

/// Ο αριθμός γίνεται σύνδεσμος επειδή ο χρήστης καλείται να **αποφασίσει** για
/// αυτό το ticket: για να κρίνει αν το κρατά, θέλει να δει τι είναι.
Future<UnsentTicketChoice?> showLansweeperUnsentTicketChoiceDialog(
  BuildContext context, {
  required String storedTicket,
  String? ticketViewUrlTemplate,
}) {
  return showDialog<UnsentTicketChoice>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Ακαταχώρητη κλήση'),
      content: LansweeperTicketRichText(
        leadingText: 'Η κλήση έχει καταχωρηθεί με id: ',
        ticketId: storedTicket,
        ticketViewUrlTemplate: ticketViewUrlTemplate,
        trailingText: ' στο Lansweeper.\n\nΤι θέλεις να γίνει με το ticket id;',
        style: Theme.of(ctx).textTheme.bodyMedium,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(UnsentTicketChoice.cancel),
          child: const Text('Άκυρο'),
        ),
        OutlinedButton(
          onPressed: () => Navigator.of(ctx).pop(UnsentTicketChoice.clear),
          child: const Text('Μηδενισμός id'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(UnsentTicketChoice.retain),
          child: const Text('Διατήρηση id'),
        ),
      ],
    ),
  );
}

/// Ο αριθμός γίνεται σύνδεσμος επειδή η απόφαση «πρόσθεση ή αλλαγή id» απαιτεί
/// να ξέρει ο χρήστης τι περιέχει ήδη αυτό το ticket.
Future<DuplicateTicketAction> showLansweeperDuplicateTicketDialog(
  BuildContext context, {
  required int count,
  required String ticketId,
  String? ticketViewUrlTemplate,
}) async {
  final callsLabel = count == 1 ? 'άλλη κλήση' : 'άλλες κλήσεις';
  return await showDialog<DuplicateTicketAction>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Ίδιο Ticket ID'),
          content: LansweeperTicketRichText(
            leadingText: 'Υπάρχουν $count $callsLabel καταχωρημένες με ticket ',
            ticketId: ticketId,
            ticketViewUrlTemplate: ticketViewUrlTemplate,
            trailingText:
                '.\n\nΣυνήθως ένα ticket Lansweeper αντιστοιχεί σε ένα '
                'περιστατικό· πολλές κλήσεις με το ίδιο id επιτρέπονται '
                '(π.χ. ίδιος καλών / ομαδοποιημένες κλήσεις).',
            style: Theme.of(ctx).textTheme.bodyMedium,
          ),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.of(ctx).pop(DuplicateTicketAction.cancel),
              child: const Text('Άκυρο'),
            ),
            OutlinedButton(
              onPressed: () =>
                  Navigator.of(ctx).pop(DuplicateTicketAction.changeId),
              child: const Text('Αλλαγή id'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(ctx).pop(DuplicateTicketAction.proceed),
              child: const Text('Πρόσθεση'),
            ),
          ],
        ),
      ) ??
      DuplicateTicketAction.cancel;
}

Future<String?> showLansweeperOptionalTicketIdDialog(
  BuildContext context, {
  required String prefilled,
  required String title,
  String? subtitle,
}) async {
  final ticketController = TextEditingController(text: prefilled);
  try {
    return await showDialog<String?>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (subtitle != null) ...[
                Text(subtitle, style: Theme.of(ctx).textTheme.bodySmall),
                const SizedBox(height: 10),
              ],
              TextField(
                controller: ticketController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Ticket ID (προαιρετικό)',
                  hintText: 'π.χ. 17132',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: const Text('Άκυρο'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(ctx).pop(ticketController.text.trim()),
            child: const Text('Αποθήκευση'),
          ),
        ],
      ),
    );
  } finally {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ticketController.dispose();
    });
  }
}

Future<({String ticketId, String comment})?> showLansweeperManualMarkDialog(
  BuildContext context, {
  required String initialTicket,
}) async {
  final ticketController = TextEditingController(text: initialTicket);
  final commentController = TextEditingController();
  try {
    return await showDialog<({String ticketId, String comment})?>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Χειροκίνητη Σήμανση'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: ticketController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Ticket ID (προαιρετικό)',
                  hintText: 'π.χ. 17132',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: commentController,
                decoration: const InputDecoration(
                  labelText: 'Σχόλιο/Αιτιολογία (προαιρετικό)',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: const Text('Άκυρο'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop((
              ticketId: ticketController.text.trim(),
              comment: commentController.text,
            )),
            child: const Text('Αποθήκευση'),
          ),
        ],
      ),
    );
  } finally {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ticketController.dispose();
      commentController.dispose();
    });
  }
}

Future<void> showLansweeperFailureReportDialog(
  BuildContext context, {
  required String reportText,
  required VoidCallback onCopied,
}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Αναφορά αποτυχίας καταχώρησης'),
      content: SizedBox(
        width: 640,
        child: SingleChildScrollView(child: SelectableText(reportText)),
      ),
      actions: [
        TextButton(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: reportText));
            if (!ctx.mounted) return;
            onCopied();
          },
          child: const Text('Αντιγραφή αναφοράς'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Κλείσιμο'),
        ),
      ],
    ),
  );
}
