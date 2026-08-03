// Ο αριθμός ticket ως σύνδεσμος που ανοίγει το Lansweeper στον περιηγητή.
//
// Ζει χωριστά ώστε κάθε σημείο που δείχνει αριθμό ticket να τον κάνει σύνδεσμο
// με τον ίδιο τρόπο: η στήλη κατάστασης του ιστορικού και η προειδοποίηση
// στην επεξεργασία κλήσης.

import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'lansweeper_url_rules.dart';

/// Πρόταση που περιέχει τον αριθμό ticket ως σύνδεσμο.
///
/// Ο σύνδεσμος είναι [TextSpan] με recognizer και **όχι** [WidgetSpan] με
/// πατήσιμο widget: μέσα σε παράγραφο μόνο το πρώτο δίνει «χεράκι» στα Windows
/// — το ίδιο μοτίβο με τους συνδέσμους των σημειώσεων και των εκκρεμοτήτων.
/// Ο recognizer ζει όσο το widget και απελευθερώνεται μαζί του.
///
/// Χωρίς έγκυρο πρότυπο URL ο αριθμός μένει απλό έντονο κείμενο: καλύτερα
/// ορατός αριθμός χωρίς σύνδεσμο παρά σύνδεσμος που δεν οδηγεί πουθενά.
class LansweeperTicketRichText extends StatefulWidget {
  const LansweeperTicketRichText({
    super.key,
    required this.leadingText,
    required this.ticketId,
    required this.ticketViewUrlTemplate,
    this.trailingText = '',
    this.style,
  });

  /// Το κείμενο πριν τον αριθμό — μαζί με το κενό που τον χωρίζει.
  final String leadingText;

  final String ticketId;
  final String? ticketViewUrlTemplate;

  /// Το κείμενο μετά τον αριθμό (κενό όταν η πρόταση τελειώνει εκεί).
  final String trailingText;

  final TextStyle? style;

  @override
  State<LansweeperTicketRichText> createState() =>
      _LansweeperTicketRichTextState();
}

class _LansweeperTicketRichTextState extends State<LansweeperTicketRichText> {
  TapGestureRecognizer? _recognizer;

  @override
  void dispose() {
    _recognizer?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final id = widget.ticketId.trim();
    final url = id.isEmpty
        ? null
        : LansweeperUrlRules.buildTicketViewUrl(
            widget.ticketViewUrlTemplate ?? '',
            id,
          );

    // Ο προηγούμενος recognizer δεν χρειάζεται πια: κάθε build φτιάχνει δικό του.
    _recognizer?.dispose();
    _recognizer = null;

    final InlineSpan ticketSpan;
    if (id.isEmpty) {
      ticketSpan = const TextSpan();
    } else if (url == null) {
      ticketSpan = TextSpan(
        text: '#$id',
        style: const TextStyle(fontWeight: FontWeight.w600),
      );
    } else {
      final recognizer = TapGestureRecognizer()
        ..onTap = () => unawaited(
          launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
        );
      _recognizer = recognizer;
      ticketSpan = TextSpan(
        text: '#$id',
        style: TextStyle(
          color: theme.colorScheme.primary,
          decoration: TextDecoration.underline,
          decorationColor: theme.colorScheme.primary,
          fontWeight: FontWeight.w600,
        ),
        recognizer: recognizer,
      );
    }

    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: widget.leadingText),
          ticketSpan,
          if (widget.trailingText.isNotEmpty)
            TextSpan(text: widget.trailingText),
        ],
      ),
      style: widget.style ?? theme.textTheme.bodyMedium,
    );
  }
}

class LansweeperTicketLink extends StatelessWidget {
  const LansweeperTicketLink({
    super.key,
    required this.ticketId,
    required this.url,
    this.enabled = true,
    this.style,
  });

  final String ticketId;
  final String url;

  /// Όταν [false], ο σύνδεσμος είναι αδρανής (χωρίς σύνδεση Lansweeper).
  final bool enabled;

  /// Βάση στυλ κειμένου· το χρώμα και η υπογράμμιση προστίθενται πάντα εδώ,
  /// ώστε ο σύνδεσμος να φαίνεται ίδιος όπου κι αν μπει.
  final TextStyle? style;

  static const String disabledTooltip =
      'Δεν είναι εφυκτή η σύνδεση με το Lansweeper.';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final linkColor = enabled
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurface.withValues(alpha: 0.45);
    final tooltip = enabled
        ? 'Άνοιγμα ticket #$ticketId στον περιηγητή'
        : disabledTooltip;

    return Tooltip(
      message: tooltip,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        child: InkWell(
          onTap: enabled
              ? () => unawaited(
                  launchUrl(
                    Uri.parse(url),
                    mode: LaunchMode.externalApplication,
                  ),
                )
              : null,
          borderRadius: BorderRadius.circular(4),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
            child: Text(
              '#$ticketId',
              style: (style ?? theme.textTheme.labelSmall)?.copyWith(
                color: linkColor,
                decoration: enabled ? TextDecoration.underline : null,
                decorationColor: linkColor,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
