/// Ένα από τα έτοιμα σύμβολα του νέου χάρτη.
///
/// Η τιμή [key] είναι αυτή που γράφεται στη βάση· δεν αλλάζει ποτέ, ακόμη κι
/// αν αλλάξει το όνομα της τιμής στον κώδικα.
enum FloorPlanSymbol {
  /// Υπάλληλος του Καταλόγου.
  person('person', 'Άνθρωπος'),

  /// Τηλέφωνο του Καταλόγου.
  phone('phone', 'Τηλέφωνο'),

  /// Εξοπλισμός του Καταλόγου — ο Κατάλογος κρατά μόνο υπολογιστές, άρα μία
  /// οθόνη.
  computer('computer', 'Υπολογιστής'),

  printer('printer', 'Εκτυπωτής'),

  /// Γραφείο, ντουλάπα: σχεδιάζεται ως παραλληλόγραμμο με τον πραγματικό του
  /// όγκο, και πάνω του μπαίνουν τα άλλα.
  furniture('furniture', 'Έπιπλο'),

  /// Καμπίνα δικτύου (rack): παραλληλόγραμμο με τον πραγματικό της όγκο, σαν
  /// το έπιπλο, που **έχει περιεχόμενο** σε θέσεις U.
  cabinet('cabinet', 'Καμπίνα'),

  patchPanel('patch_panel', 'Patch panel'),
  networkSwitch('switch', 'Switch'),

  /// Πλάκα στον τοίχο με μία ή δύο θύρες.
  outlet('outlet', 'Πρίζα'),

  router('router', 'Router'),

  /// Τροφοδοτικό Power over Ethernet: θύρες και ρεύμα.
  poe('poe', 'POE'),

  /// Χωρίς θύρες· πιάνει θέσεις U στην καμπίνα.
  ups('ups', 'UPS');

  const FloorPlanSymbol(this.key, this.label);

  final String key;
  final String label;

  /// Τα σύμβολα που διαλέγει κανείς για ένα είδος. Άνθρωπος, τηλέφωνο και
  /// υπολογιστής ανήκουν στις εγγραφές του Καταλόγου και δεν διαλέγονται.
  static const List<FloorPlanSymbol> forKinds = [
    printer,
    furniture,
    cabinet,
    patchPanel,
    networkSwitch,
    outlet,
    router,
    poe,
    ups,
  ];

  /// Σχεδιάζεται ως παραλληλόγραμμο με μέγεθος, όχι ως εικονίδιο.
  bool get isVolume => this == furniture || this == cabinet;

  bool get isCabinet => this == cabinet;

  /// Δηλώνεται με **πλήθος θυρών** και έχει πρόσοψη (αποφάσεις 30/10/2026:
  /// patch panel, switch, router και POE).
  bool get hasPortCount =>
      this == patchPanel ||
      this == networkSwitch ||
      this == router ||
      this == poe;

  /// Μπαίνει μέσα σε καμπίνα. Κάθε είδος μπορεί (ενότητα 5 του σχεδίου),
  /// εκτός από όσα έχουν δικό τους όγκο: έπιπλο και άλλη καμπίνα.
  bool get fitsInCabinet => !isVolume;

  static FloorPlanSymbol? fromKey(String? key) {
    for (final symbol in values) {
      if (symbol.key == key) return symbol;
    }
    return null;
  }
}

/// Ένα είδος αντικειμένων του χάρτη, όπως το όρισε όποιος σχεδιάζει.
class FloorPlanObjectKind {
  const FloorPlanObjectKind({
    required this.id,
    required this.name,
    required this.symbol,
    this.hasPorts = false,
    this.showInfo = true,
  });

  final int id;
  final String name;

  /// `null` όταν το σύμβολο γράφτηκε από νεότερη έκδοση της εφαρμογής.
  final FloorPlanSymbol? symbol;

  /// Συνδέεται με καλώδιο — οι θύρες του καταγράφονται με το δίκτυο.
  final bool hasPorts;

  /// Δείχνει υπόδειξη και στοιχεία με το ποντίκι. Τα έπιπλα συνήθως όχι:
  /// είναι μέρος του χώρου, και οι καρτέλες τους θα ήταν θόρυβος.
  final bool showInfo;

  static const List<String> columns = [
    'id',
    'name',
    'symbol',
    'has_ports',
    'show_info',
  ];

  factory FloorPlanObjectKind.fromMap(Map<String, Object?> map) {
    return FloorPlanObjectKind(
      id: map['id'] as int,
      name: map['name'] as String,
      symbol: FloorPlanSymbol.fromKey(map['symbol'] as String?),
      hasPorts: (map['has_ports'] as int? ?? 0) != 0,
      showInfo: (map['show_info'] as int? ?? 1) != 0,
    );
  }
}

/// Ένα είδος μαζί με το πόσα αντικείμενα έχει και σε ποιους ορόφους — ό,τι
/// χρειάζεται το παράθυρο των ειδών για να πει αν αφαιρείται.
class FloorPlanObjectKindUsage {
  const FloorPlanObjectKindUsage({
    required this.kind,
    this.objectCount = 0,
    this.floorIds = const {},
  });

  final FloorPlanObjectKind kind;
  final int objectCount;
  final Set<int> floorIds;

  bool get inUse => objectCount > 0;
}
