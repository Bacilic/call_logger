import 'package:call_logger/core/services/gemini_ticket_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('GeminiPromptTemplateSyntax.stripEmptyOptionalBlocks', () {
    test('αφαιρεί block όταν το placeholder είναι κενό', () {
      const template = '''
Υπάλληλος: {Υπάλληλος}.
{@Εξοπλισμός}Εξοπλισμός: {Εξοπλισμός}. {@/Εξοπλισμός}
Πρόβλημα: {Πρόβλημα}''';

      final result = GeminiPromptTemplateSyntax.stripEmptyOptionalBlocks(
        template,
        const {'{Εξοπλισμός}'},
      );

      expect(result, contains('Υπάλληλος: {Υπάλληλος}.'));
      expect(result, isNot(contains('Εξοπλισμός')));
      expect(result, isNot(contains('{@')));
      expect(result, contains('Πρόβλημα: {Πρόβλημα}'));
    });

    test('κρατά block όταν το placeholder δεν είναι κενό', () {
      const template =
          '{@Λύση}Λύση: {Λύση}. {@/Λύση}';
      final result = GeminiPromptTemplateSyntax.stripEmptyOptionalBlocks(
        template,
        const <String>{},
      );
      expect(result, template);
    });
  });

  group('GeminiPromptTemplateSyntax.validate', () {
    test('επιτρέπει σωστό template με blocks', () {
      const template = '''
{@Εξοπλισμός}Εξοπλισμός: {Εξοπλισμός}. {@/Εξοπλισμός}
Κατηγορία: {Κατηγορία}
Απάντησε σε JSON: {"title":"...","description":"...","solution":"..."}''';
      final validation = GeminiPromptTemplateSyntax.validate(template);
      expect(validation.isValid, isTrue);
    });

    test('εντοπίζει αναντιστοιχία block', () {
      const template = '{@Εξοπλισμός}κείμενο {@/Τμήμα}';
      final validation = GeminiPromptTemplateSyntax.validate(template);
      expect(validation.isValid, isFalse);
      expect(validation.errors.join(' '), contains('Αναντιστοιχία'));
    });

    test('προτείνει διόρθωση σε λάθος placeholder', () {
      const template = '''
Κατηγορία: {Κατηγορίαα}
Απάντησε σε JSON: {"title":"...","description":"...","solution":"..."}''';
      final validation = GeminiPromptTemplateSyntax.validate(template);
      expect(validation.isValid, isFalse);
      expect(
        validation.errors.any((e) => e.contains('{Κατηγορία}')),
        isTrue,
      );
    });

    test('δεν θεωρεί άγνωστο placeholder το block JSON απάντησης', () {
      const template = '''
Δημιούργησε τίτλο και περιγραφή.
Απάντησε ΜΟΝΟ σε JSON: {"title":"...","description":"...","solution":"..."}''';

      final validation = GeminiPromptTemplateSyntax.validate(template);

      expect(
        validation.errors,
        isNot(contains(startsWith('Άγνωστο placeholder'))),
        reason: 'Το JSON blueprint δεν πρέπει να εμφανίζεται ως άγνωστο placeholder',
      );
    });

    test('επιτρέπει τα τρία κλειδιά JSON σε τυχαία σειρά', () {
      const template = '''
Απάντησε σε JSON με "solution":"...", "title":"...", "description":"..."''';

      final validation = GeminiPromptTemplateSyntax.validate(template);

      expect(
        validation.errors.where(
          (e) => e.contains('Λείπει το πεδίο') || e.contains('οδηγίες μορφής JSON'),
        ),
        isEmpty,
      );
    });

    test('αναφέρει ονομαστικά τα κλειδιά που λείπουν', () {
      const template = '''
Απάντησε σε JSON: {"title":"...","description":"..."}''';

      final validation = GeminiPromptTemplateSyntax.validate(template);

      expect(validation.isValid, isFalse);
      expect(
        validation.errors.any((e) => e.contains('`solution`')),
        isTrue,
      );
      expect(
        validation.errors.any((e) => e.contains('λύση')),
        isTrue,
      );
    });

    test('εντοπίζει πλήρη απουσία οδηγιών JSON', () {
      const template = 'Δημιούργησε τίτλο και περιγραφή για ticket.';

      final validation = GeminiPromptTemplateSyntax.validate(template);

      expect(validation.isValid, isFalse);
      expect(
        validation.errors.first,
        contains('δεν περιλαμβάνει οδηγίες μορφής JSON'),
      );
    });

    test('εντοπίζει διπλή οδηγία JSON απάντησης', () {
      const template = '''
Δημιούργησε τίτλο και περιγραφή.
Απάντησε σε JSON: {"title":"...","description":"...","solution":"..."}
Επανάλαβε: {"title":"...","description":"...","solution":"..."}''';

      final validation = GeminiPromptTemplateSyntax.validate(template);

      expect(validation.isValid, isFalse);
      expect(
        validation.errors.any((e) => e.contains('περισσότερες από μία οδηγίες μορφής JSON')),
        isTrue,
      );
    });

    test(
      'προειδοποιεί για ξένο placeholder μέσα σε block διαφορετικού ονόματος',
      () {
        const template = '''
{@Εξοπλισμός}Εξοπλισμός: {Εξοπλισμός}.{Τμήμα} {@/Εξοπλισμός}
Απάντησε σε JSON: {"title":"...","description":"...","solution":"..."}''';

        final validation = GeminiPromptTemplateSyntax.validate(template);

        expect(validation.isValid, isTrue);
        expect(validation.errors, isEmpty);
        expect(
          validation.warnings.any((w) => w.contains('{Τμήμα}')),
          isTrue,
          reason: 'Το {Τμήμα} μέσα στο block {Εξοπλισμός} πρέπει να προειδοποιεί',
        );
      },
    );

    test(
      'δεν προειδοποιεί για εμφωλιασμένο block διαφορετικού ονόματος',
      () {
        const template = '''
{@Εξοπλισμός}Εξοπλισμός: {Εξοπλισμός}. {@Τμήμα}Τμήμα: {Τμήμα}. {@/Τμήμα}{@/Εξοπλισμός}
Απάντησε σε JSON: {"title":"...","description":"...","solution":"..."}''';

        final validation = GeminiPromptTemplateSyntax.validate(template);

        expect(validation.isValid, isTrue);
        expect(validation.errors, isEmpty);
        expect(validation.warnings, isEmpty);
      },
    );

    test('εντοπίζει επανειλημμένο άνοιγμα του ίδιου block', () {
      const template = '''
{@Εξοπλισμός}Εξωτερικό {@Εξοπλισμός}Εσωτερικό {@/Εξοπλισμός}{@/Εξοπλισμός}
Απάντησε σε JSON: {"title":"...","description":"...","solution":"..."}''';

      final validation = GeminiPromptTemplateSyntax.validate(template);

      expect(validation.isValid, isFalse);
      expect(
        validation.errors.any((e) => e.contains('ανοίγει ξανά')),
        isTrue,
      );
    });

    test('εντοπίζει block που δεν κλείνει (regression)', () {
      const template = '''
{@Εξοπλισμός}Εξοπλισμός: {Εξοπλισμός}.
Απάντησε σε JSON: {"title":"...","description":"...","solution":"..."}''';

      final validation = GeminiPromptTemplateSyntax.validate(template);

      expect(validation.isValid, isFalse);
      expect(
        validation.errors.any((e) => e.contains('δεν κλείνει')),
        isTrue,
      );
    });
  });

  group('GeminiTicketService.buildPrompt', () {
    test('δεν περιλαμβάνει κενά blocks στην τελική προτροπή', () {
      final prompt = GeminiTicketService.buildPrompt(
        promptTemplate: '''
Υπάλληλος: {Υπάλληλος}. Τμήμα: {Τμήμα}.
{@Εξοπλισμός}Εξοπλισμός: {Εξοπλισμός}. {@/Εξοπλισμός}
{@Κατηγορία}Κατηγορία: {Κατηγορία}. {@/Κατηγορία}
Πρόβλημα: {Πρόβλημα}
{@Λύση}Λύση: {Λύση}. {@/Λύση}''',
        callerText: 'Μαρία',
        equipmentText: '',
        departmentText: 'Ιατρός',
        category: '',
        issue: 'Θέλει κωδικούς',
        titleText: 'Τίτλος',
        notesText: '',
        solutionText: '',
      );

      expect(prompt, contains('Υπάλληλος: Μαρία'));
      expect(prompt, contains('Τμήμα: Ιατρός'));
      expect(prompt, contains('Πρόβλημα: Θέλει κωδικούς'));
      expect(prompt, isNot(contains('Εξοπλισμός')));
      expect(prompt, isNot(contains('Κατηγορία')));
      expect(prompt, isNot(contains('Λύση')));
      expect(prompt, isNot(contains('{@')));
    });

    test('αφαιρεί tags blocks όταν τα placeholders έχουν τιμή', () {
      final prompt = GeminiTicketService.buildPrompt(
        promptTemplate: '''
Δημιούργησε τίτλο και περιγραφή για ticket helpdesk στο Lansweeper.

{@Υπάλληλος}Υπάλληλος: {Υπάλληλος}. {@/Υπάλληλος}
{@Εξοπλισμός}Εξοπλισμός: {Εξοπλισμός}. {@/Εξοπλισμός}
{@Τμήμα}Τμήμα: {Τμήμα}. {@/Τμήμα}

{@Πρόβλημα}Πρόβλημα: {Πρόβλημα}. {@/Πρόβλημα}''',
        callerText: 'Άγνωστος',
        equipmentText: '3917',
        departmentText: 'Αξονικός',
        category: '',
        issue: 'Ρύθμιση αξονικού',
        titleText: '',
        notesText: '',
        solutionText: '',
      );

      expect(prompt, contains('Υπάλληλος: Άγνωστος'));
      expect(prompt, contains('Εξοπλισμός: 3917'));
      expect(prompt, contains('Τμήμα: Αξονικός'));
      expect(prompt, contains('Πρόβλημα: Ρύθμιση αξονικού'));
      expect(prompt, isNot(contains('{@')));
    });
  });
}
