import 'package:call_logger/core/database/database_init_progress_provider.dart';
import 'package:call_logger/core/init/startup_journal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Η πρόοδος της βάσης και το ημερολόγιο εκκίνησης είναι η ΙΔΙΑ αλήθεια σε δύο
/// μορφές. Αυτά τα τεστ φυλάνε τη μετάφραση: κάθε `setStep` που βλέπει ο
/// χρήστης ως βήμα οφείλει να γίνει ακριβώς μία γραμμή.
void main() {
  late ProviderContainer container;
  late DatabaseInitProgressNotifier notifier;
  late StartupJournal journal;

  setUp(() {
    journal = StartupJournal.instance..reset();
    container = ProviderContainer();
    notifier = container.read(databaseInitProgressProvider.notifier);
  });

  tearDown(() => container.dispose());

  List<String> labels() => journal.steps.value.map((s) => s.label).toList();

  test('κάθε βήμα γίνεται μία γραμμή, με σειρά', () {
    notifier.setStep('Έλεγχος διαδρομής');
    notifier.setStep('Έλεγχος αρχείων εφαρμογής');
    notifier.setStep('Έλεγχος υγείας βάσης');

    expect(labels(), [
      'Έλεγχος διαδρομής',
      'Έλεγχος αρχείων εφαρμογής',
      'Έλεγχος υγείας βάσης',
    ]);
  });

  test('το προηγούμενο βήμα κλείνει μόλις ξεκινά το επόμενο', () {
    notifier.setStep('Έλεγχος διαδρομής');
    notifier.setStep('Έλεγχος υγείας βάσης');

    expect(journal.steps.value.first.status, StartupStepStatus.ok);
    expect(journal.steps.value.first.duration, isNotNull);
    expect(journal.steps.value.last.status, StartupStepStatus.running);
  });

  test('η αντίστροφη μέτρηση ενημερώνει μία γραμμή, δεν προσθέτει πέντε', () {
    for (var s = 5; s >= 1; s--) {
      notifier.setStep(databaseOpenCountdownLabel(s), secondsRemaining: s);
    }

    expect(journal.steps.value, hasLength(1));
    expect(labels().single, databaseOpenCountdownLabel(1));
    expect(journal.steps.value.single.status, StartupStepStatus.running);
  });

  test('μετά την αντίστροφη μέτρηση, νέο βήμα ανοίγει κανονικά γραμμή', () {
    notifier.setStep(databaseOpenCountdownLabel(5), secondsRemaining: 5);
    notifier.setStep(databaseOpenCountdownLabel(4), secondsRemaining: 4);
    notifier.setStep('Επικύρωση δομής πινάκων');

    expect(labels(), [
      databaseOpenCountdownLabel(4),
      'Επικύρωση δομής πινάκων',
    ]);
  });

  test('η σφραγίδα ολοκλήρωσης κλείνει το τρέχον χωρίς νέα γραμμή', () {
    notifier.setStep('Έλεγχος υγείας βάσης');
    notifier.setStep(
      'Η αρχικοποίηση ολοκληρώθηκε',
      clearSecondsRemaining: true,
      kind: StartupStepKind.completed,
    );

    expect(labels(), ['Έλεγχος υγείας βάσης']);
    expect(journal.steps.value.single.status, StartupStepStatus.ok);
    expect(journal.hasFailure, isFalse);
  });

  test('η σφραγίδα αποτυχίας σημαδεύει το βήμα που έσκασε', () {
    notifier.setStep('Άνοιγμα βάσης δεδομένων');
    notifier.setStep(
      'Αποτυχία αρχικοποίησης',
      clearSecondsRemaining: true,
      kind: StartupStepKind.failed,
    );

    expect(journal.steps.value, hasLength(1));
    expect(journal.steps.value.single.status, StartupStepStatus.failed);
    expect(journal.hasFailure, isTrue);
  });

  test('η επαναδοκιμή δεν διπλογράφει: το reset αδειάζει και τη λαβή', () {
    notifier.setStep('Έλεγχος διαδρομής');
    notifier.setStep('Άνοιγμα βάσης δεδομένων');

    notifier.reset();
    journal.reset();
    notifier.setStep('Έλεγχος διαδρομής');

    expect(labels(), ['Έλεγχος διαδρομής']);
  });

  test('η κατάσταση προόδου συνεχίζει να δουλεύει όπως πριν', () {
    notifier.setStep('Άνοιγμα βάσης', secondsRemaining: 5);

    expect(
      container.read(databaseInitProgressProvider).currentStep,
      'Άνοιγμα βάσης',
    );
    expect(container.read(databaseInitProgressProvider).secondsRemaining, 5);
    expect(
      container.read(databaseInitProgressProvider).isOpeningAttemptActive,
      isTrue,
    );
  });

  group('databaseOpenCountdownLabel', () {
    test('το τελευταίο δευτερόλεπτο μιλά στον ενικό', () {
      expect(
        databaseOpenCountdownLabel(1),
        'Προσπάθεια ανοίγματος βάσης σε 1 δευτερόλεπτο',
      );
    });

    test('από τα δύο και πάνω, πληθυντικός', () {
      expect(
        databaseOpenCountdownLabel(8),
        'Προσπάθεια ανοίγματος βάσης σε 8 δευτερόλεπτα',
      );
      expect(
        databaseOpenCountdownLabel(0),
        'Προσπάθεια ανοίγματος βάσης σε 0 δευτερόλεπτα',
      );
    });
  });
}
