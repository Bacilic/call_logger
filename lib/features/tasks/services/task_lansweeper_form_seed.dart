import '../models/task.dart';

/// Με τι ανοίγει η φόρμα αποστολής όταν τη γεννά μια εκκρεμότητα.
///
/// Καθαρή μετάφραση, χωρίς διεπαφή: η αντιστοίχιση «ποιο πεδίο της
/// εκκρεμότητας γίνεται ποιο πεδίο του αιτήματος» είναι απόφαση που αξίζει να
/// διαβάζεται και να ελέγχεται μόνη της.
class TaskLansweeperFormSeed {
  const TaskLansweeperFormSeed({
    required this.title,
    required this.problem,
    required this.solution,
  });

  /// Το θέμα του αιτήματος.
  final String title;

  /// Η περιγραφή του αιτήματος.
  final String problem;

  /// Η σημείωση που θα μπει στο αίτημα.
  final String solution;
}

/// Ένα προς ένα, σε αντίθεση με την κλήση.
///
/// Η κλήση δεν έχει δικό της τίτλο, οπότε η φόρμα της φτιάχνει έναν αυτόματο
/// («[Medico] #344») και στριμώχνει τον τίτλο μαζί με την περιγραφή στο ίδιο
/// πεδίο. Η εκκρεμότητα έχει και τα τρία πεδία, και το καθένα πάει στη θέση
/// του: **τίτλος → θέμα, περιγραφή → πρόβλημα, σημειώσεις λύσης → λύση.**
///
/// Ο τίτλος είναι το μόνο που δεν μένει ποτέ κενό: εκκρεμότητα χωρίς τίτλο δεν
/// γράφεται από τη φόρμα, αλλά παλιά εγγραφή μπορεί να έχει μείνει άδεια, και
/// τότε το αίτημα θα έφευγε χωρίς θέμα.
TaskLansweeperFormSeed seedLansweeperFormFromTask(Task task) {
  final title = task.title.trim();
  return TaskLansweeperFormSeed(
    title: title.isEmpty ? 'Εκκρεμότητα #${task.id}' : title,
    problem: (task.description ?? '').trim(),
    solution: (task.solutionNotes ?? '').trim(),
  );
}
