import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../features/history/models/lansweeper_submit_progress.dart';
import 'lansweeper_api_uri.dart';
import 'lansweeper_asset_target.dart';
import 'lansweeper_text_format.dart';
import 'lansweeper_ticket_requester_fields.dart';
import 'lansweeper_ticket_submit_config.dart';
import 'lansweeper_ticket_texts.dart';
import 'settings_service.dart';

typedef LansweeperRawPoster =
    Future<LansweeperRawResponse> Function(
      String action,
      Map<String, String> fields,
    );

/// GET προς το API (π.χ. `SearchUsers`) — οι παράμετροι μπαίνουν στο URL.
typedef LansweeperRawGetter =
    Future<LansweeperRawResponse> Function(
      String action,
      Map<String, String> params,
    );

class LansweeperRawResponse {
  const LansweeperRawResponse(this.statusCode, this.body);

  final int statusCode;
  final String body;
}

class LansweeperSyncException implements Exception {
  const LansweeperSyncException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Ρύθμιση/είσοδος αποτυχημένη πριν την κλήση API — δεν πρέπει να ενημερώνει κατάσταση κλήσης.
class LansweeperSyncPrecheckException implements Exception {
  const LansweeperSyncPrecheckException(this.message);

  final String message;

  @override
  String toString() => message;
}

class LansweeperWorkflowRequest {
  const LansweeperWorkflowRequest({
    required this.autoSubject,
    required this.title,
    required this.problem,
    required this.solution,
    required this.agentUsername,
    required this.config,
    required this.customFieldValues,
    this.durationSeconds,
    this.targetState,
    this.existingTicketId,
    this.requesterUsername,
    this.assetTargets = const [],
    this.lastSentTexts,
  });

  /// Τίτλος/πρόβλημα που έστειλε η εφαρμογή την τελευταία φορά στο
  /// [existingTicketId]. Σε υπάρχον αίτημα ξαναστέλνονται μόνο όσα διαφέρουν
  /// από αυτά· `null` = «δεν ξέρουμε», και τότε δεν στέλνεται κανένα.
  final LansweeperTicketTexts? lastSentTexts;

  /// Το θέμα που παίρνει το αίτημα όταν ο χρήστης δεν έγραψε δικό του [title].
  ///
  /// Έτοιμο κείμενο, όχι οντότητα: η ροή δεν χρειάζεται να ξέρει αν πίσω της
  /// στέκεται κλήση ή εκκρεμότητα — μόνο τι θα γραφτεί στο `Subject`. Όποιος
  /// την καλεί εγγυάται ότι δεν είναι κενό.
  final String autoSubject;

  final String title;
  final String problem;
  final String solution;
  final String agentUsername;

  /// Πόση ώρα κράτησε η **εργασία**, όταν αυτό έχει νόημα να σταλεί.
  ///
  /// `null` σημαίνει «μη σταλεί καθόλου» — το αίτημα φεύγει χωρίς γραμμή
  /// χρόνου, όχι με μηδενικό χρόνο. Η ροή **δεν μαντεύει ποτέ** τιμή όταν
  /// λείπει: η κλήση κρατά χρόνο εργασίας και τον δίνει, ενώ η εκκρεμότητα
  /// κρατά χρόνο **αναμονής** (μια αλλαγή καλωδίου μπορεί να περιμένει τρεις
  /// μέρες για μισή ώρα δουλειάς) και δεν έχει τίποτα χρήσιμο να δώσει.
  final int? durationSeconds;
  final LansweeperTicketSubmitConfig config;
  final Map<String, String> customFieldValues;
  final String? targetState;
  final String? existingTicketId;

  /// Ταυτότητα Lansweeper του υπαλλήλου που κάλεσε (`τομέας\όνομα` ή email).
  /// Κενή/null = ο αιτών μένει ο πράκτορας, όπως πριν.
  final String? requesterUsername;

  /// Στόχοι `AddAsset` — ένας για κάθε διαφορετικό εξοπλισμό των εγγραφών
  /// που ενώνονται στο αίτημα. Κενή = χωρίς σύνδεση εξοπλισμού.
  final List<LansweeperAssetTarget> assetTargets;
}

class LansweeperWorkflowResult {
  const LansweeperWorkflowResult({
    required this.success,
    required this.message,
    this.ticketId,
    this.ticketCreated = false,
    this.completedSteps = const [],
    this.warnings = const [],
    this.failedStep,
    this.rawPayloads,
    this.ticketNotFound = false,
    this.ticketTexts,
  });

  final bool success;

  /// Τι γράφει πια το αίτημα στον τίτλο και στην περιγραφή, όσο το ξέρει η
  /// ροή: ό,τι στάλθηκε τώρα, αλλιώς ό,τι είχε σταλεί πριν. `null` = άγνωστο.
  /// Ο καλών το καταγράφει, ώστε η επόμενη αποστολή να ξέρει τι άλλαξε.
  final LansweeperTicketTexts? ticketTexts;
  final String? ticketId;

  /// `true` όταν η ροή πήγε να συνεχίσει σε αίτημα που **προϋπήρχε** και το
  /// Lansweeper απάντησε ότι δεν υπάρχει — συνήθως επειδή σβήστηκε από εκεί.
  ///
  /// Ξεχωρίζει από κάθε άλλη αποτυχία επειδή έχει άλλη διέξοδο: η επανάληψη
  /// θα ξαναχτυπήσει στο ίδιο κενό, ενώ ένα νέο αίτημα λύνει το πρόβλημα. Την
  /// απόφαση για νέο αίτημα την παίρνει ο χρήστης, όχι η ροή — το ίδιο μήνυμα
  /// βγαίνει και από λάθος αριθμό.
  final bool ticketNotFound;

  /// `true` όταν το αίτημα δημιουργήθηκε **σε αυτή τη ροή**.
  ///
  /// `false` σημαίνει ότι το αίτημα προϋπήρχε — το άνοιξε συνάδελφος από άλλο
  /// μηχάνημα ή εμείς σε προηγούμενη αποστολή. Η διάκριση δεν είναι
  /// καλλωπισμός του μηνύματος: ορίζει ποια πεδία επιτρέπεται να γραφτούν.
  final bool ticketCreated;

  final String message;
  final List<String> completedSteps;
  final List<String> warnings;
  final String? failedStep;
  final Map<String, dynamic>? rawPayloads;
}

class _PostActionResult {
  const _PostActionResult({
    required this.success,
    required this.message,
    this.ticketId,
    this.rawPayload,
  });

  final bool success;
  final String message;
  final String? ticketId;
  final Map<String, dynamic>? rawPayload;
}

class LansweeperSyncService {
  factory LansweeperSyncService({
    SettingsService? settingsService,
    LansweeperRawPoster? poster,
    LansweeperRawGetter? getter,
  }) {
    final settings = settingsService ?? SettingsService();
    return LansweeperSyncService._(
      poster ?? _defaultPosterFor(settings),
      getter ?? _defaultGetterFor(settings),
    );
  }

  LansweeperSyncService._(this._poster, this._getter);

  final LansweeperRawPoster _poster;
  final LansweeperRawGetter _getter;

  static LansweeperRawPoster _defaultPosterFor(
    SettingsService settingsService,
  ) {
    return (action, fields) =>
        _defaultRawPoster(settingsService, action, fields);
  }

  static LansweeperRawGetter _defaultGetterFor(
    SettingsService settingsService,
  ) {
    return (action, params) =>
        _defaultRawGetter(settingsService, action, params);
  }

  /// Τα βήματα που **θα** εκτελεστούν για το [request], με τη σειρά τους.
  ///
  /// Ζει δίπλα στη ροή που τα εκτελεί επίτηδες: η οθόνη πρέπει να μπορεί να
  /// πει «βήμα 2 από 5» πριν ξεκινήσει τίποτα, και η μόνη ασφαλής πηγή γι'
  /// αυτό είναι ο κώδικας που παίρνει τις ίδιες αποφάσεις. Γραμμένο αλλού, θα
  /// απέκλινε στην πρώτη αλλαγή της ροής.
  static List<String> plannedStepKeys(LansweeperWorkflowRequest request) {
    final config = request.config;
    final existingTicketId = request.existingTicketId?.trim() ?? '';
    final creatingTicket = existingTicketId.isEmpty;
    final targetState = request.targetState?.trim() ?? '';
    return <String>[
      if ((request.requesterUsername?.trim() ?? '').isNotEmpty)
        LansweeperSubmitStepKeys.requester,
      if (creatingTicket) LansweeperSubmitStepKeys.ticket,
      if (creatingTicket && request.assetTargets.isNotEmpty)
        LansweeperSubmitStepKeys.asset,
      if (changedTicketTexts(request).any) LansweeperSubmitStepKeys.details,
      if (config.enableAddNoteStep && request.solution.trim().isNotEmpty)
        LansweeperSubmitStepKeys.note,
      if (config.enableStateUpdateStep && targetState.isNotEmpty)
        LansweeperSubmitStepKeys.state,
    ];
  }

  /// Τίτλος και πρόβλημα όπως θα γραφτούν στο αίτημα από αυτό το [request].
  static LansweeperTicketTexts ticketTextsOf(
    LansweeperWorkflowRequest request,
  ) {
    final title = request.title.trim();
    return LansweeperTicketTexts(
      subject: title.isNotEmpty ? title : request.autoSubject.trim(),
      problem: request.problem.trim(),
    );
  }

  /// Ποια από τα κείμενα ενός **υπάρχοντος** αιτήματος άλλαξαν από την
  /// προηγούμενη αποστολή.
  ///
  /// Μία πηγή για το πλάνο της οθόνης και για τη ροή που στέλνει: αν
  /// απέκλιναν, η πορεία θα έδειχνε βήμα που δεν έτρεξε ή θα έκρυβε βήμα που
  /// έτρεξε. Νέο αίτημα ή άγνωστη προηγούμενη αποστολή: τίποτα.
  static ({bool subject, bool problem, bool any}) changedTicketTexts(
    LansweeperWorkflowRequest request,
  ) {
    const none = (subject: false, problem: false, any: false);
    final existing = request.existingTicketId?.trim() ?? '';
    final previous = request.lastSentTexts;
    if (existing.isEmpty || previous == null) return none;
    final current = ticketTextsOf(request);
    final subject = current.subject != previous.subject.trim();
    final problem = current.problem != previous.problem.trim();
    return (subject: subject, problem: problem, any: subject || problem);
  }

  /// [onStep] ανακοινώνει το βήμα που **ξεκινά** — τα κλειδιά είναι αυτά του
  /// [plannedStepKeys]. Καθαρή ενημέρωση οθόνης: αν λείπει, η ροή τρέχει
  /// ακριβώς όπως πριν.
  Future<LansweeperWorkflowResult> submitTicketWorkflow(
    LansweeperWorkflowRequest request, {
    void Function(String stepKey)? onStep,
  }) async {
    if (request.agentUsername.trim().isEmpty) {
      throw const LansweeperSyncPrecheckException(
        'Ο πράκτορας API (AgentUsername) είναι υποχρεωτικός.',
      );
    }

    final completedSteps = <String>[];
    final warnings = <String>[];
    final rawPayloads = <String, dynamic>{};
    final config = request.config;
    final durationSeconds = request.durationSeconds;

    // Ο αιτών του εισιτηρίου. Ξεκινά ως ο πράκτορας (σημερινή συμπεριφορά)
    // και γίνεται ο υπάλληλος ΜΟΝΟ αν το SearchUsers τον επιβεβαιώσει: άγνωστο
    // email στο AddTicket δεν αποτυγχάνει — δημιουργεί σιωπηλά ψευτο-χρήστη
    // στο helpdesk, ενώ άγνωστο όνομα χαλά ολόκληρη τη δημιουργία.
    final agent = request.agentUsername.trim();
    var requester = agent;
    final candidateRequester = request.requesterUsername?.trim() ?? '';
    if (candidateRequester.isNotEmpty) {
      onStep?.call(LansweeperSubmitStepKeys.requester);
      if (await _requesterExistsInLansweeper(candidateRequester)) {
        requester = candidateRequester;
      } else {
        warnings.add(
          'Ο αιτών «$candidateRequester» δεν βρέθηκε στο Lansweeper· '
          'αιτών καταχωρήθηκε ο πράκτορας.',
        );
      }
    }

    var ticketId = request.existingTicketId?.trim();
    if (ticketId != null && ticketId.isEmpty) {
      ticketId = null;
    }

    // Ποιος άνοιξε το αίτημα, εμείς τώρα ή κάποιος πριν από εμάς. Κρατιέται
    // ΠΡΙΝ γεμίσει το `ticketId` από τη δημιουργία, αλλιώς η διάκριση χάνεται.
    final ticketCreatedHere = ticketId == null;

    if (ticketId == null) {
      final baseFields = <String, String>{
        'Subject': request.title.trim().isNotEmpty
            ? request.title.trim()
            : request.autoSubject.trim(),
        'Description': lansweeperHtmlText(request.problem.trim()),
        if (config.ticketType.trim().isNotEmpty)
          'Type': config.ticketType.trim(),
        if (config.priority.trim().isNotEmpty)
          'Priority': config.priority.trim(),
        if (config.team.trim().isNotEmpty) 'Team': config.team.trim(),
        'CustomFields': _encodeCustomFields(config, request.customFieldValues),
      };

      onStep?.call(LansweeperSubmitStepKeys.ticket);
      var addResult = await _postAction('AddTicket', <String, String>{
        ...baseFields,
        ..._ticketIdentityFields(requester, agent),
      });
      rawPayloads['AddTicket'] = addResult.rawPayload;

      if (!addResult.success && requester != agent) {
        // Δεύτερο δίχτυ: ο προ-έλεγχος δεν εγγυάται ότι το `AddTicket` θα
        // δεχτεί την ταυτότητα. Ο χρήστης μπορεί να έπαψε να υπάρχει ανάμεσα
        // στα δύο βήματα, ή το `AddTicket` να απορρίπτει ταυτότητα που το
        // `SearchUsers` βρίσκει. Το αίτημα δεν χάνεται — ξαναστέλνεται όπως πριν.
        //
        // Πυροδοτείται σε ΚΑΘΕ αποτυχία, όχι μόνο σε αποτυχία ταυτότητας: αν
        // έφταιγε άλλο πεδίο (τύπος, προτεραιότητα, custom fields) η δεύτερη
        // απόπειρα θα αποτύχει κι αυτή — χωρίς ζημιά, αφού η πρώτη δεν
        // δημιούργησε εισιτήριο.
        //
        // Ο παλιός λόγος που έγραφε εδώ («το SearchUsers ταιριάζει και μερικώς,
        // άρα βρίσκει χωρίς ακριβή αντιστοιχία») ΔΕΝ ισχύει: μετρήθηκε στο
        // ζωντανό API (20/08/2026) ότι το `Username` θέλει ακριβές ταίριασμα —
        // το «aimat» δεν βρίσκει τον «aimat1». Η τεκμηρίωση του Lansweeper
        // γράφει «or part of the username» και κάνει λάθος.
        warnings.add(
          'Η δημιουργία με αιτούντα «$requester» απέτυχε· '
          'αιτών καταχωρήθηκε ο πράκτορας.',
        );
        requester = agent;
        addResult = await _postAction('AddTicket', <String, String>{
          ...baseFields,
          ..._ticketIdentityFields(requester, agent),
        });
        rawPayloads['AddTicket(retry)'] = addResult.rawPayload;
      }

      if (!addResult.success) {
        return LansweeperWorkflowResult(
          success: false,
          message: addResult.message,
          completedSteps: completedSteps,
          warnings: warnings,
          failedStep: 'AddTicket',
          rawPayloads: rawPayloads,
        );
      }

      ticketId = addResult.ticketId;
      if (ticketId == null || ticketId.isEmpty) {
        return LansweeperWorkflowResult(
          success: false,
          message: addResult.message,
          completedSteps: completedSteps,
          warnings: warnings,
          failedStep: 'AddTicket',
          rawPayloads: rawPayloads,
        );
      }

      completedSteps.add('AddTicket');

      // Ένα βήμα στην οθόνη για όλους τους εξοπλισμούς· ο καθένας συνδέεται
      // χωριστά, και όποιος αποτύχει γίνεται προειδοποίηση χωρίς να
      // σταματήσει τους υπόλοιπους.
      final assetTargets = request.assetTargets;
      if (assetTargets.isNotEmpty) {
        onStep?.call(LansweeperSubmitStepKeys.asset);
        for (final target in assetTargets) {
          await _attachAssetStep(
            ticketId: ticketId,
            target: target,
            completedSteps: completedSteps,
            warnings: warnings,
            rawPayloads: rawPayloads,
          );
        }
      }
    }

    final resolvedTicketId = ticketId;

    // Τι γράφει το αίτημα μετά από αυτή τη ροή, όσο το ξέρουμε. Αίτημα που
    // γεννήθηκε τώρα έχει τα κείμενα της φόρμας· σε υπάρχον ισχύει ό,τι
    // είχε σταλεί πριν, μέχρι να ενημερωθεί παρακάτω.
    var knownTexts = ticketCreatedHere
        ? ticketTextsOf(request)
        : request.lastSentTexts;

    final changed = changedTicketTexts(request);
    if (changed.any) {
      final current = ticketTextsOf(request);
      final detailsFields = <String, String>{
        'TicketID': resolvedTicketId,
        if (changed.subject) 'Subject': current.subject,
        if (changed.problem) 'Description': lansweeperHtmlText(current.problem),
        ..._followUpIdentityFields(
          requester: requester,
          agent: agent,
          ticketCreatedHere: ticketCreatedHere,
        ),
      };

      onStep?.call(LansweeperSubmitStepKeys.details);
      final detailsResult = await _postAction('EditTicket', detailsFields);
      rawPayloads['EditTicket(details)'] = detailsResult.rawPayload;

      if (detailsResult.success ||
          _isNothingUpdatedMessage(detailsResult.message)) {
        // «Nothing has been updated»: το αίτημα γράφει ήδη αυτά τα κείμενα —
        // π.χ. τα διόρθωσε κάποιος με τον ίδιο τρόπο μέσα στο Lansweeper.
        completedSteps.add('EditTicket(details)');
        knownTexts = current;
      } else if (isTicketNotFoundMessage(detailsResult.message)) {
        return LansweeperWorkflowResult(
          success: false,
          message: detailsResult.message,
          ticketId: resolvedTicketId,
          completedSteps: completedSteps,
          warnings: warnings,
          failedStep: 'EditTicket',
          rawPayloads: rawPayloads,
          ticketNotFound: true,
          ticketTexts: knownTexts,
        );
      } else {
        // Η λύση και η κατάσταση αξίζουν περισσότερο από τον τίτλο: η ροή
        // συνεχίζει, και τα κείμενα μένουν «αστάλτα» ώστε η επόμενη
        // αποστολή να τα ξαναδοκιμάσει.
        warnings.add(
          'Ο τίτλος/η περιγραφή του αιτήματος δεν ενημερώθηκαν: '
          '${detailsResult.message}',
        );
      }
    }

    if (config.enableAddNoteStep && request.solution.trim().isNotEmpty) {
      final noteFields = <String, String>{
        'TicketID': resolvedTicketId,
        'Text': lansweeperHtmlText(
          _buildNoteText(
            request.solution,
            durationSeconds,
            includeTime: config.includeNoteTime,
          ),
        ),
        'Type': config.noteType,
        ..._requesterFields(request.agentUsername),
      };

      onStep?.call(LansweeperSubmitStepKeys.note);
      final noteResult = await _postAction('AddNote', noteFields);
      rawPayloads['AddNote'] = noteResult.rawPayload;

      if (noteResult.success) {
        completedSteps.add('AddNote');
      } else if (!ticketCreatedHere &&
          isTicketNotFoundMessage(noteResult.message)) {
        // Η εφεδρεία γράφει στο ίδιο αίτημα· πάνω σε αίτημα που δεν υπάρχει
        // θα αποτύχει με το ίδιο μήνυμα και θα έκρυβε την πραγματική αιτία.
        return LansweeperWorkflowResult(
          success: false,
          message: noteResult.message,
          ticketId: resolvedTicketId,
          completedSteps: completedSteps,
          warnings: warnings,
          failedStep: 'AddNote',
          rawPayloads: rawPayloads,
          ticketNotFound: true,
          ticketTexts: knownTexts,
        );
      } else {
        final fallbackDescription = buildTicketDescription(
          notes: request.problem,
          solution: request.solution,
          durationSeconds: durationSeconds,
        );
        final fallbackFields = <String, String>{
          'TicketID': resolvedTicketId,
          'Description': lansweeperHtmlText(fallbackDescription),
          ..._followUpIdentityFields(
            requester: requester,
            agent: agent,
            ticketCreatedHere: ticketCreatedHere,
          ),
        };
        final fallbackResult = await _postAction('EditTicket', fallbackFields);
        rawPayloads['EditTicket(fallback)'] = fallbackResult.rawPayload;

        if (fallbackResult.success) {
          completedSteps.add('EditTicket(fallback)');
          // Η περιγραφή γράφει πια πρόβλημα ΚΑΙ λύση· αυτό είναι το μέτρο
          // της επόμενης σύγκρισης, όχι το σκέτο πρόβλημα.
          final subject = knownTexts?.subject;
          if (subject != null) {
            knownTexts = LansweeperTicketTexts(
              subject: subject,
              problem: fallbackDescription.trim(),
            );
          }
          warnings.add(
            'Η σημείωση απέτυχε· η λύση καταχωρήθηκε στην περιγραφή του ticket.',
          );
        } else {
          return LansweeperWorkflowResult(
            success: false,
            message: noteResult.message,
            ticketId: resolvedTicketId,
            completedSteps: completedSteps,
            warnings: warnings,
            failedStep: 'AddNote',
            rawPayloads: rawPayloads,
            ticketTexts: knownTexts,
          );
        }
      }
    }

    final targetState = request.targetState?.trim() ?? '';
    if (config.enableStateUpdateStep && targetState.isNotEmpty) {
      final stateFields = <String, String>{
        'TicketID': resolvedTicketId,
        'State': targetState,
        ..._followUpIdentityFields(
          requester: requester,
          agent: agent,
          ticketCreatedHere: ticketCreatedHere,
        ),
      };

      onStep?.call(LansweeperSubmitStepKeys.state);
      final stateResult = await _postAction('EditTicket', stateFields);
      rawPayloads['EditTicket(state)'] = stateResult.rawPayload;

      // Αίτημα ήδη στην κατάσταση που ζητήθηκε: το Lansweeper απαντά
      // Success=false, αλλά ο σκοπός του βήματος έχει επιτευχθεί.
      if (stateResult.success ||
          isAlreadyInStateResponse(stateResult.rawPayload, targetState)) {
        completedSteps.add('EditTicket(state)');
      } else {
        return LansweeperWorkflowResult(
          success: false,
          message: stateResult.message,
          ticketId: resolvedTicketId,
          completedSteps: completedSteps,
          warnings: warnings,
          failedStep: 'EditTicket',
          rawPayloads: rawPayloads,
          ticketNotFound:
              !ticketCreatedHere &&
              isTicketNotFoundMessage(stateResult.message),
          ticketTexts: knownTexts,
        );
      }
    }

    return LansweeperWorkflowResult(
      success: true,
      message: _workflowSuccessMessage(completedSteps),
      ticketId: resolvedTicketId,
      ticketCreated: ticketCreatedHere,
      completedSteps: completedSteps,
      warnings: warnings,
      rawPayloads: rawPayloads,
      ticketTexts: knownTexts,
    );
  }

  /// Σύνδεση εξοπλισμού στο νεοδημιουργημένο ticket. Αποτυχία = προειδοποίηση,
  /// ποτέ αποτυχία ροής: το εισιτήριο υπάρχει ήδη και είναι σωστό.
  Future<void> _attachAssetStep({
    required String ticketId,
    required LansweeperAssetTarget target,
    required List<String> completedSteps,
    required List<String> warnings,
    required Map<String, dynamic> rawPayloads,
  }) async {
    final fields = <String, String>{
      'TicketID': ticketId,
      if (target.kind == LansweeperAssetTargetKind.ipAddress)
        'IPAddress': target.value
      else
        'AssetName': target.value,
    };
    try {
      final result = await _postAction('AddAsset', fields);
      // Ένα κλειδί ανά εξοπλισμό: με δεύτερο μηχάνημα, κοινό κλειδί θα έσβηνε
      // την απάντηση του πρώτου από το διαγνωστικό.
      final payloadKey = rawPayloads.containsKey('AddAsset')
          ? 'AddAsset(${target.value})'
          : 'AddAsset';
      rawPayloads[payloadKey] = result.rawPayload;
      if (result.success) {
        if (!completedSteps.contains('AddAsset')) {
          completedSteps.add('AddAsset');
        }
      } else {
        warnings.add(
          'Ο εξοπλισμός «${target.value}» δεν συνδέθηκε στο αίτημα: '
          '${result.message}',
        );
      }
    } on LansweeperSyncException catch (e) {
      warnings.add(
        'Ο εξοπλισμός «${target.value}» δεν συνδέθηκε στο αίτημα: '
        '${e.message}',
      );
    }
  }

  /// Πεδία ταυτότητας για AddTicket/EditTicket: όταν αιτών == πράκτορας, η
  /// σημερινή μορφή (ίδια τιμή παντού)· αλλιώς αιτών και πράκτορας χωριστά.
  /// Πεδία ταυτότητας για τη **δημιουργία** του αιτήματος.
  ///
  /// Μόνο εδώ επιτρέπεται να γραφτεί αιτών: το αίτημα γεννιέται τώρα, άρα η
  /// επιλογή της φόρμας μας είναι η μόνη που υπάρχει.
  Map<String, String> _ticketIdentityFields(String requester, String agent) {
    if (requester == agent) {
      return lansweeperAgentAsMatchingRequesterFields(agent);
    }
    return lansweeperRequesterAndAgentFields(
      requester: requester,
      agent: agent,
    );
  }

  /// Πεδία ταυτότητας για κάθε βήμα **μετά** τη δημιουργία (`EditTicket`).
  ///
  /// CONTRACT: η ταυτότητα του αιτούντα γράφεται μόνο τη στιγμή που
  /// δημιουργούμε εμείς το αίτημα· κάθε βήμα πάνω σε αίτημα που προϋπήρχε το
  /// αφήνει ανέπαφο.
  ///
  /// - **Αίτημα δικό μας, μόλις δημιουργημένο:** ο αιτών ξανα-στέλνεται. Χωρίς
  ///   αυτό το `EditTicket` του κλεισίματος τον γυρίζει σιωπηλά στον πράκτορα.
  /// - **Αίτημα που προϋπήρχε:** το άνοιξε συνάδελφος από άλλο μηχάνημα ή εμείς
  ///   σε προηγούμενη αποστολή. Ο αιτών **δεν** στέλνεται καθόλου — αλλιώς η
  ///   επιλογή εκείνου αντικαθίσταται από τη δική μας φόρμα, και η αλλοίωση
  ///   φεύγει εκτός εφαρμογής (το Lansweeper είναι αυτό που βλέπει η
  ///   προϊσταμένη· από εδώ δεν διορθώνεται).
  ///
  /// Η **ανάθεση** πράκτορα περνά και στις δύο περιπτώσεις σε όποιον το δουλεύει
  /// τώρα — αυτός το κλείνει, αυτός φαίνεται υπεύθυνος.
  ///
  /// Η παράμετρος είναι υποχρεωτική επίτηδες: ο καλών δεν μπορεί να ξεχάσει τη
  /// διάκριση, γιατί ο κώδικας δεν μεταγλωττίζεται χωρίς αυτήν.
  Map<String, String> _followUpIdentityFields({
    required String requester,
    required String agent,
    required bool ticketCreatedHere,
  }) {
    if (!ticketCreatedHere) {
      return lansweeperAgentOnlyFields(agent);
    }
    return _ticketIdentityFields(requester, agent);
  }

  /// Προ-έλεγχος `SearchUsers`: υπάρχει ο χρήστης στο Lansweeper;
  ///
  /// Κάθε αμφιβολία (σφάλμα δικτύου, μη-JSON, Count=0) μετρά ως «όχι» — το
  /// κόστος του λάθους είναι ασύμμετρο: άγνωστο email θα δημιουργούσε
  /// ψευτο-χρήστη, άγνωστο όνομα θα χαλούσε τη δημιουργία του ticket.
  Future<bool> _requesterExistsInLansweeper(String identity) async {
    try {
      final response = await _getter(
        'SearchUsers',
        lansweeperSearchUsersParamsFor(identity),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return false;
      }
      final payload = _tryDecodeJson(response.body);
      if (!_payloadSuccess(payload)) return false;
      final count = payload?['Count'];
      if (count is num) return count > 0;
      if (count is String) return (int.tryParse(count.trim()) ?? 0) > 0;
      return false;
    } on Exception {
      return false;
    }
  }

  Future<_PostActionResult> _postAction(
    String action,
    Map<String, String> fields,
  ) async {
    try {
      final response = await _poster(action, fields);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw LansweeperSyncException(
          'Αποτυχία API (${response.statusCode}): ${response.body}',
        );
      }

      final payload = _tryDecodeJson(response.body);
      final success = _payloadSuccess(payload);
      final message = _payloadMessage(payload) ?? 'Η απάντηση παραλήφθηκε.';
      final ticketId = _payloadTicketId(payload);

      return _PostActionResult(
        success: success,
        message: message,
        ticketId: ticketId,
        rawPayload: payload,
      );
    } on LansweeperSyncException {
      rethrow;
    } on SocketException catch (e) {
      throw LansweeperSyncException('Σφάλμα δικτύου: $e');
    } on TimeoutException {
      throw const LansweeperSyncException(
        'Timeout κατά την επικοινωνία με το Lansweeper API.',
      );
    }
  }

  /// URL του API για το [action], με το κλειδί και τυχόν [extraQueryParams].
  static Future<Uri> _apiActionUri(
    SettingsService settingsService,
    String action, {
    Map<String, String> extraQueryParams = const {},
  }) async {
    final apiUrl =
        (await settingsService.remoteLansweeper.getLansweeperApiUrl())
            ?.trim() ??
        '';
    final apiKey =
        (await settingsService.remoteLansweeper.getLansweeperApiKey())
            ?.trim() ??
        '';
    final result = buildLansweeperApiActionUri(
      apiUrl: apiUrl,
      apiKey: apiKey,
      action: action,
      extraQueryParams: extraQueryParams,
    );
    final uri = result.uri;
    if (uri != null) return uri;

    // Εδώ μιλάμε για ρύθμιση της βάσης, όχι για πεδίο οθόνης.
    throw switch (result.problem!) {
      LansweeperApiUriProblem.missingUrl => const LansweeperSyncException(
        'Δεν έχει οριστεί Lansweeper API URL.',
      ),
      LansweeperApiUriProblem.missingKey => const LansweeperSyncException(
        'Δεν έχει οριστεί Lansweeper API key.',
      ),
      LansweeperApiUriProblem.invalidUrl => LansweeperSyncException(
        'Μη έγκυρο Lansweeper API URL: $apiUrl',
      ),
    };
  }

  static Future<LansweeperRawResponse> _defaultRawPoster(
    SettingsService settingsService,
    String action,
    Map<String, String> fields,
  ) async {
    final uri = await _apiActionUri(settingsService, action);

    final client = HttpClient();
    try {
      final httpRequest = await client
          .postUrl(uri)
          .timeout(const Duration(seconds: 20));
      httpRequest.headers.set(
        HttpHeaders.contentTypeHeader,
        'application/x-www-form-urlencoded',
      );
      httpRequest.write(Uri(queryParameters: fields).query);
      final response = await httpRequest.close().timeout(
        const Duration(seconds: 20),
      );
      final body = await response.transform(utf8.decoder).join();
      return LansweeperRawResponse(response.statusCode, body);
    } finally {
      client.close(force: true);
    }
  }

  /// GET για ενέργειες ανάγνωσης (`SearchUsers`) — παράμετροι στο URL.
  static Future<LansweeperRawResponse> _defaultRawGetter(
    SettingsService settingsService,
    String action,
    Map<String, String> params,
  ) async {
    final uri = await _apiActionUri(
      settingsService,
      action,
      extraQueryParams: params,
    );

    final client = HttpClient();
    try {
      final httpRequest = await client
          .getUrl(uri)
          .timeout(const Duration(seconds: 20));
      final response = await httpRequest.close().timeout(
        const Duration(seconds: 20),
      );
      final body = await response.transform(utf8.decoder).join();
      return LansweeperRawResponse(response.statusCode, body);
    } finally {
      client.close(force: true);
    }
  }

  String _encodeCustomFields(
    LansweeperTicketSubmitConfig config,
    Map<String, String> values,
  ) {
    final customFields = <Map<String, String>>[];
    for (final field in config.customFields) {
      final value = values[field.id] ?? field.defaultValue;
      customFields.add({'name': field.apiName, 'value': value});
    }
    return jsonEncode({'customFields': customFields});
  }

  String _buildNoteText(
    String solution,
    int? durationSeconds, {
    required bool includeTime,
  }) {
    final text = solution.trim();
    if (!includeTime || durationSeconds == null) return text;
    return '$text\n\nΧρόνος: ${formatCallDurationLabel(durationSeconds)}';
  }

  Map<String, String> _requesterFields(String agentUsername) =>
      lansweeperAgentAsMatchingRequesterFields(agentUsername);

  String _workflowSuccessMessage(List<String> completedSteps) {
    if (completedSteps.isEmpty) {
      return 'Η ροή ολοκληρώθηκε.';
    }
    return 'Ολοκληρώθηκαν: ${completedSteps.join(', ')}.';
  }

  /// Λέει το μήνυμα του Lansweeper ότι το αίτημα δεν υπάρχει;
  ///
  /// Το API δεν δίνει κωδικό σφάλματος, μόνο κείμενο — και το ίδιο κείμενο
  /// επιστρέφουν και το `AddNote` («…The creation was unsuccessful») και το
  /// `EditTicket` («…The update was unsuccessful»). Γι' αυτό ταιριάζει μόνο η
  /// κοινή αρχή, χωρίς διάκριση πεζών-κεφαλαίων.
  static bool isTicketNotFoundMessage(String? message) =>
      (message ?? '').toLowerCase().contains('no ticket found');

  /// Λέει η απάντηση του `EditTicket` ότι το αίτημα είναι ΗΔΗ στην
  /// [targetState];
  ///
  /// Το Lansweeper απαντά «Nothing has been updated.» με Success=false όταν
  /// δεν βρίσκει τίποτα να αλλάξει (αίτημα 18308, 23/10/2026). Το μήνυμα μόνο
  /// του δεν αρκεί — θα μπορούσε να αγνοήθηκε η κατάσταση για άλλο λόγο· γι'
  /// αυτό επιβεβαιώνεται και η `State` που επιστρέφει το σώμα.
  static bool isAlreadyInStateResponse(
    Map<String, dynamic>? payload,
    String targetState,
  ) {
    final message = payload?['Message'];
    if (message is! String || !_isNothingUpdatedMessage(message)) {
      return false;
    }
    final state = payload?['State'];
    return state is String &&
        state.trim().toLowerCase() == targetState.trim().toLowerCase();
  }

  /// Η απάντηση του `EditTicket` όταν δεν βρήκε τίποτα να αλλάξει.
  static bool _isNothingUpdatedMessage(String message) =>
      message.toLowerCase().contains('nothing has been updated');

  /// Ο τίτλος που γεννά μόνη της η εφαρμογή όταν κανείς δεν έγραψε δικό του.
  ///
  /// **Μία πηγή** για δύο ερωτήσεις: με τι προσυμπληρώνεται το πεδίο, και —
  /// στην αποθήκευση προς την κλήση — ποιος τίτλος είναι αυτόματος και άρα δεν
  /// αξίζει να κατέβει στην Περιγραφή. Δύο υλοποιήσεις θα απαντούσαν κάποτε
  /// διαφορετικά, και τότε ο έλεγχος «είναι αυτόματος;» θα αστοχούσε σιωπηλά,
  /// γεμίζοντας τις περιγραφές με «Κλήση #344».
  static String autoTicketTitle({required String category, required int? id}) {
    final trimmed = category.trim();
    final suffix = id != null ? ' #$id' : '';
    return trimmed.isEmpty ? 'Κλήση$suffix' : '[$trimmed]$suffix';
  }

  /// Ο τίτλος ενός αιτήματος που ενώνει τις εγγραφές [entries] — η μοναδική
  /// υλοποίηση, για την προσυμπλήρωση της φόρμας **και** για το μέτρο «έγραψε
  /// ο χρήστης δικό του τίτλο;» ([callTitleToPersist]).
  ///
  /// Με [useStoredTitles] μπαίνει ο αποθηκευμένος τίτλος κάθε εγγραφής· χωρίς
  /// αυτό ο τίτλος είναι ο καθαρά αυτόματος, το μέτρο σύγκρισης.
  ///
  /// Μία εγγραφή: ο τίτλος της, αλλιώς [autoTicketTitle], όπως πάντα.
  ///
  /// Πολλές εγγραφές: οι τίτλοι τους ενώνονται με « · », με τη σειρά των
  /// [entries]. Όπου λείπει τίτλος μπαίνει μόνο η κατηγορία, χωρίς αριθμό: το
  /// «[Εκτυπωτές] #412 · [Δίκτυο] #415» επαναλαμβάνει αριθμούς που το αίτημα
  /// δεν χρειάζεται. Ίδιοι τίτλοι μπαίνουν μία φορά — έτσι και ένας τίτλος που
  /// γράφτηκε ήδη ενωμένος σε όλες τις κλήσεις δεν διπλασιάζεται στην επόμενη
  /// ένωση. Χωρίς τίτλο και κατηγορία πουθενά: ο αυτόματος της πρώτης.
  static String combinedTicketTitle(
    List<({String? storedTitle, String category, int? id})> entries, {
    bool useStoredTitles = true,
  }) {
    if (entries.isEmpty) return '';
    if (entries.length == 1) {
      final only = entries.single;
      final stored = useStoredTitles ? (only.storedTitle?.trim() ?? '') : '';
      if (stored.isNotEmpty) return stored;
      return autoTicketTitle(category: only.category, id: only.id);
    }
    final parts = <String>[];
    final seen = <String>{};
    for (final entry in entries) {
      final stored = useStoredTitles ? (entry.storedTitle?.trim() ?? '') : '';
      final category = entry.category.trim();
      final part = stored.isNotEmpty
          ? stored
          : category.isNotEmpty
          ? '[$category]'
          : '';
      if (part.isEmpty) continue;
      if (seen.add(part.toLowerCase())) parts.add(part);
    }
    if (parts.isEmpty) {
      final first = entries.first;
      return autoTicketTitle(category: first.category, id: first.id);
    }
    return parts.join(' · ');
  }

  /// Ο τίτλος που αξίζει να κρατήσει η **κλήση**· `null` όταν δεν υπάρχει.
  ///
  /// **Μία πηγή για κάθε έξοδο της φόρμας.** Ο τίτλος ταξιδεύει σε τέσσερις
  /// δρόμους — άμεση καταχώρηση, επαναϋποβολή, αντιγραφή & άνοιγμα, αποθήκευση
  /// στην κλήση — και ο κανόνας «τι είναι περίληψη» πρέπει να είναι ο ίδιος και
  /// στους τέσσερις: αλλιώς το πρόσφατο ιστορικό θα έδειχνε άλλο πράγμα ανάλογα
  /// με το ποιο κουμπί πατήθηκε.
  ///
  /// **Ο αυτόματος δεν είναι περίληψη.** Το `[Medico] #344` επαναλαμβάνει την
  /// κατηγορία και τον αριθμό, που η λίστα ξέρει ήδη· αν σωζόταν, το πρόσφατο
  /// ιστορικό θα γέμιζε με την ίδια φράση τρεις φορές στη σειρά.
  static String? callTitleToPersist({
    required String title,
    required String autoTitle,
  }) {
    final trimmed = title.trim();
    if (trimmed.isEmpty || trimmed == autoTitle.trim()) return null;
    return trimmed;
  }

  static String formatCallDurationLabel(int seconds) {
    final safe = seconds < 0 ? 0 : seconds;
    final h = safe ~/ 3600;
    final m = (safe % 3600) ~/ 60;
    final s = safe % 60;
    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  static String buildTicketDescription({
    required String notes,
    required String solution,
    int? durationSeconds,
  }) {
    final notesTrim = notes.trim();
    final solutionTrim = solution.trim();
    final String body;
    if (solutionTrim.isEmpty) {
      body = notesTrim;
    } else if (notesTrim.isEmpty) {
      body = 'Λύση:\n$solutionTrim';
    } else {
      body = '$notesTrim\n\nΛύση:\n$solutionTrim';
    }
    if (durationSeconds == null) return body;
    final durationLine = 'Χρόνος: ${formatCallDurationLabel(durationSeconds)}';
    if (body.isEmpty) return durationLine;
    return '$body\n\n$durationLine';
  }

  Map<String, dynamic>? _tryDecodeJson(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
    return null;
  }

  bool _payloadSuccess(Map<String, dynamic>? payload) {
    if (payload == null) return false;
    final value = payload['Success'];
    if (value is bool) return value;
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      return normalized == 'true' || normalized == '1';
    }
    if (value is num) return value != 0;
    return false;
  }

  String? _payloadMessage(Map<String, dynamic>? payload) {
    if (payload == null) return null;
    final value = payload['Message'];
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }

  String? _payloadTicketId(Map<String, dynamic>? payload) {
    if (payload == null) return null;
    final candidates = <Object?>[
      payload['TicketID'],
      payload['TicketId'],
      payload['Ticketid'],
    ];
    for (final candidate in candidates) {
      final text = candidate?.toString().trim() ?? '';
      if (text.isNotEmpty) return text;
    }
    return null;
  }
}
