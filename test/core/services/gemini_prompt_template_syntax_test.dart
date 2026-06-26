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
Κατηγορία: {Κατηγορία}''';
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
      const template = 'Κατηγορία: {Κατηγορίαα}';
      final validation = GeminiPromptTemplateSyntax.validate(template);
      expect(validation.isValid, isFalse);
      expect(validation.errors.first, contains('{Κατηγορία}'));
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
