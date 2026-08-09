import 'package:call_logger/core/database/audit_diff_helper.dart';
import 'package:flutter_test/flutter_test.dart';

/// Τα κλειδιά που γράφονται όντως στο `old/new_values_json` του audit.
///
/// Η λίστα βγήκε από τα δεδομένα μιας πραγματικής βάσης και από τα σημεία που
/// καλούν το `AuditService.log`. Όταν προστίθεται νέο πεδίο σε καταγραφή,
/// μπαίνει κι εδώ — και το τεστ απαιτεί να αποκτήσει ελληνική ετικέτα.
const List<String> _auditFieldKeys = [
  'affected_ids',
  'anydesk_id',
  'building',
  'call_id',
  'caller_id',
  'caller_text',
  'category_id',
  'category_text',
  'code_equipment',
  'color',
  'comment',
  'content',
  'custom_ip',
  'cutoff',
  'date',
  'default_remote_tool',
  'department_id',
  'department_label',
  'department_text',
  'description',
  'destination',
  'due_date',
  'duration',
  'email',
  'equipment_code',
  'equipment_id',
  'equipment_text',
  'fields',
  'first_name',
  'floor_id',
  'integrity_fix',
  'is_deleted',
  'is_priority',
  'issue',
  'issue_refined',
  'lansweeper_last_sync_at',
  'lansweeper_main_ticket_id',
  'lansweeper_state',
  'last_name',
  'linked_equipment',
  'linked_phone_numbers',
  'linked_user_id',
  'linked_users',
  'location',
  'map_floor',
  'missed_deadline',
  'name',
  'name_key',
  'notes',
  'origin',
  'outcome',
  'output_path',
  'path',
  'phone',
  'phone_associated',
  'phone_id',
  'phone_text',
  'phones',
  'previous_renamed_to',
  'priority',
  'remote_params',
  'removed',
  'rows_deleted',
  'rows_merged',
  'scheduled_time',
  'selected_ids_count',
  'skip_reason',
  'solution',
  'solution_notes',
  'status',
  'symptom',
  'table',
  'tags',
  'time',
  'title',
  'topic',
  'trigger',
  'trigger_el',
  'type',
  'user_id',
  'user_text',
  'via',
];

/// Λατινικά που επιτρέπονται μέσα σε ελληνική ετικέτα: κύρια ονόματα και όροι
/// που ο χρήστης ξέρει έτσι.
final RegExp _allowedLatin = RegExp(
  r'^(email|AnyDesk|anydesk|Lansweeper|lansweeper)$',
);

final RegExp _latinWord = RegExp(r'[A-Za-z]+');

Iterable<String> _foreignWords(String label) =>
    _latinWord.allMatches(label).map((m) => m.group(0)!).where(
      (w) => !_allowedLatin.hasMatch(w),
    );

void main() {
  group('Ελληνικές ετικέτες πεδίων ιστορικού', () {
    test('κάθε πεδίο έχει ονομαστική ετικέτα, όχι το αγγλικό κλειδί του', () {
      final missing = <String>[];
      for (final key in _auditFieldKeys) {
        final label = AuditDiffHelper.fieldTitleLabel('', key);
        if (label == AuditDiffHelper.humanizeFieldKey(key) && key != 'email') {
          missing.add(key);
        }
      }

      expect(
        missing,
        isEmpty,
        reason:
            'Πεδία χωρίς ελληνική ετικέτα — εμφανίζονται ως «${missing.map(AuditDiffHelper.humanizeFieldKey).join('», «')}» '
            'στο Ιστορικό Εφαρμογής.',
      );
    });

    test('κάθε πεδίο έχει ετικέτα γενικής πτώσης', () {
      final missing = [
        for (final key in _auditFieldKeys)
          if (AuditDiffHelper.fieldDetailLabel('', key) ==
                  AuditDiffHelper.humanizeFieldKey(key) &&
              key != 'email')
            key,
      ];

      expect(missing, isEmpty);
    });

    test('κάθε πεδίο έχει ετικέτα αναζήτησης', () {
      final missing = [
        for (final key in _auditFieldKeys)
          if (AuditDiffHelper.fieldSearchLabel('', key) ==
                  AuditDiffHelper.humanizeFieldKey(key) &&
              key != 'email')
            key,
      ];

      expect(missing, isEmpty);
    });

    test('καμία ετικέτα δεν κουβαλά αγγλικές λέξεις', () {
      final offenders = <String>[];
      for (final key in _auditFieldKeys) {
        for (final label in [
          AuditDiffHelper.fieldTitleLabel('', key),
          AuditDiffHelper.fieldDetailLabel('', key),
          AuditDiffHelper.fieldSearchLabel('', key),
        ]) {
          for (final word in _foreignWords(label)) {
            offenders.add('$key → «$label» ($word)');
          }
        }
      }

      expect(offenders, isEmpty);
    });

    test('οι ονομαστικές ετικέτες ξεκινούν πεζά — μπαίνουν μέσα σε πρόταση', () {
      final capitalized = <String>[];
      for (final key in _auditFieldKeys) {
        final label = AuditDiffHelper.fieldTitleLabel('', key);
        if (label.isEmpty) continue;
        final first = label.substring(0, 1);
        if (first != first.toLowerCase()) capitalized.add('$key → $label');
      }

      expect(capitalized, isEmpty);
    });

    test('το κλειδί που γράφει το audit για τον κωδικό είναι το equipment_code',
        () {
      expect(
        AuditDiffHelper.fieldTitleLabel('user', 'equipment_code'),
        'κωδικός εξοπλισμού',
      );
      // Το όνομα της στήλης μένει ως συνώνυμο για τις ήδη γραμμένες εγγραφές.
      expect(
        AuditDiffHelper.fieldTitleLabel('user', 'code_equipment'),
        'κωδικός εξοπλισμού',
      );
    });
  });

  group('Διπλή καταγραφή του ίδιου εξοπλισμού', () {
    test('μένει ο κωδικός και φεύγει το id — μία αλλαγή, όχι δύο', () {
      const keys = {'equipment_id', 'equipment_code'};

      // Ο κωδικός («3180») είναι ό,τι αναγνωρίζει ο χρήστης· το id («114») δεν
      // λύνεται σε όνομα από κανέναν resolver.
      expect(
        AuditDiffHelper.shouldSkipDerivativeField('equipment_code', keys),
        isFalse,
      );
      expect(
        AuditDiffHelper.shouldSkipDerivativeField('equipment_id', keys),
        isTrue,
      );
    });

    test('μόνο του το id εμφανίζεται κανονικά — δεν υπάρχει κωδικός να το πει',
        () {
      expect(
        AuditDiffHelper.shouldSkipDerivativeField('equipment_id', {
          'equipment_id',
        }),
        isFalse,
      );
    });

    test('μόνος του ο κωδικός εμφανίζεται κανονικά', () {
      expect(
        AuditDiffHelper.shouldSkipDerivativeField('equipment_code', {
          'equipment_code',
        }),
        isFalse,
      );
    });
  });
}
