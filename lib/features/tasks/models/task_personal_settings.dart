/// Οι **προσωπικές** ρυθμίσεις του διαλόγου εκκρεμοτήτων — ισχύουν μόνο για
/// τον χρήστη που είναι συνδεδεμένος, σε αντίθεση με το ωράριο, τις αναβολές
/// και το αυτόματο κλείσιμο, που είναι κοινά για όλους τους συναδέλφους.
///
/// Ζουν σε πρόχειρο όπως και τα κοινά: τίποτα δεν γράφεται πριν από το
/// «Αποθήκευση», και η «Ακύρωση» τα αφήνει όπως ήταν.
class TaskPersonalSettings {
  const TaskPersonalSettings({
    required this.notifyHandovers,
    required this.showBadge,
    required this.printPreview,
  });

  final bool notifyHandovers;
  final bool showBadge;
  final bool printPreview;

  TaskPersonalSettings copyWith({
    bool? notifyHandovers,
    bool? showBadge,
    bool? printPreview,
  }) {
    return TaskPersonalSettings(
      notifyHandovers: notifyHandovers ?? this.notifyHandovers,
      showBadge: showBadge ?? this.showBadge,
      printPreview: printPreview ?? this.printPreview,
    );
  }

  /// Τι άλλαξε από το [initial], σε γλώσσα χρήστη — για την ερώτηση «θα
  /// χαθούν οι ακόλουθες αλλαγές» και για την ενεργοποίηση του «Αποθήκευση».
  List<String> changesFrom(TaskPersonalSettings initial) {
    String yesNo(bool v) => v ? 'Ναι' : 'Όχι';
    return [
      if (notifyHandovers != initial.notifyHandovers)
        'Ειδοποίηση όταν κάποιος αγγίξει εκκρεμότητά μου: '
            '${yesNo(initial.notifyHandovers)} -> ${yesNo(notifyHandovers)}',
      if (showBadge != initial.showBadge)
        'Μετρητής στο μενού Εκκρεμοτήτων: '
            '${yesNo(initial.showBadge)} -> ${yesNo(showBadge)}',
      if (printPreview != initial.printPreview)
        'Προεπισκόπηση πριν την εκτύπωση: '
            '${yesNo(initial.printPreview)} -> ${yesNo(printPreview)}',
    ];
  }
}
