/// Ένα από τα έτοιμα σύμβολα του νέου χάρτη.
///
/// Η τιμή [key] είναι αυτή που γράφεται στη βάση· δεν αλλάζει ποτέ, ακόμη κι
/// αν αλλάξει το όνομα της τιμής στον κώδικα.
///
/// Για κάμερες δεν υπάρχει σύμβολο, επίτηδες: δεν ανήκουν στο τμήμα
/// πληροφορικής (απόφαση Διευθυντή, 30/10/2026). Το καταγραφικό τους (NVR)
/// όμως έχει, γιατί πιάνει θέση σε καμπίνα (απόφαση 13/11/2026).
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
  ups('ups', 'UPS'),

  /// Τα είδη της καμπίνας διακομιστών και του δικτύου (απόφαση 13/11/2026):
  /// συσκευές με θύρες και IP.
  firewall('firewall', 'Firewall'),
  server('server', 'Διακομιστής'),
  storage('storage', 'Αποθήκευση (NAS / SAN)'),
  nvr('nvr', 'NVR (καταγραφικό καμερών)'),

  /// Οργανωτής καλωδίων: πιάνει U ανάμεσα στα patch panel, χωρίς θύρες και
  /// IP — υπάρχει για να μη φαίνεται «ελεύθερο» ένα πιασμένο U.
  cableManager('cable_manager', 'Οργανωτής καλωδίων'),

  /// Σκάλα ή κατακόρυφος αγωγός: από εκεί περνά η διαδρομή προς άλλον όροφο.
  riser('riser', 'Σκάλα / αγωγός');

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
    firewall,
    server,
    storage,
    nvr,
    cableManager,
    riser,
  ];

  /// Σχεδιάζεται ως παραλληλόγραμμο με μέγεθος, όχι ως εικονίδιο.
  bool get isVolume => this == furniture || this == cabinet;

  bool get isCabinet => this == cabinet;

  bool get isOutlet => this == outlet;

  /// Δηλώνεται με **πλήθος θυρών** και έχει πρόσοψη (αποφάσεις 30/10/2026:
  /// patch panel, switch, router και POE· 13/11/2026: firewall, διακομιστής,
  /// αποθήκευση και NVR).
  bool get hasPortCount =>
      this == patchPanel ||
      this == networkSwitch ||
      this == router ||
      this == poe ||
      this == firewall ||
      this == server ||
      this == storage ||
      this == nvr;

  /// Μπαίνει μέσα σε καμπίνα. Κάθε είδος μπορεί (απόφαση Διευθυντή),
  /// εκτός από όσα έχουν δικό τους όγκο (έπιπλο, άλλη καμπίνα) και τη σκάλα ή
  /// τον αγωγό, που είναι μέρος του κτιρίου.
  bool get fitsInCabinet => !isVolume && this != riser;

  /// Ό,τι είναι μέρος του χώρου (έπιπλο, καμπίνα, σκάλα / αγωγός) ή απλό
  /// εξάρτημα της καμπίνας (οργανωτής καλωδίων) δεν συνδέεται ποτέ με
  /// καλώδιο: το παράθυρο των ειδών δεν δείχνει καν τις επιλογές θυρών και
  /// IP (αποφάσεις 13/11/2026).
  bool get hasCableSettings =>
      !isVolume && this != riser && this != cableManager;

  /// Αν ένα νέο είδος με αυτό το σύμβολο ξεκινά με θύρες: όλα όσα συνδέονται
  /// με καλώδιο (απόφαση 13/11/2026).
  bool get defaultHasPorts => hasCableSettings;

  /// Αν ένα νέο είδος με αυτό το σύμβολο ξεκινά με IP και όνομα Lansweeper
  /// (αποφάσεις 13/11/2026). Όχι: ό,τι δεν είναι συσκευή δικτύου (έπιπλο,
  /// καμπίνα, σκάλα), ό,τι είναι παθητικό (patch panel, πρίζα) και ό,τι δεν
  /// συνδέεται με καλώδιο (UPS). Ο χρήστης το αλλάζει ανά είδος.
  ///
  /// Ο ίδιος κανόνας, ως κλειδιά της βάσης, στην αναβάθμιση v78.
  bool get defaultHasNetwork => canHaveNetwork && this != ups;

  /// Μπορεί να έχει IP και όνομα Lansweeper. Όχι ό,τι δεν συνδέεται με
  /// καλώδιο, και όχι τα παθητικά (patch panel, πρίζα): περνά καλώδιο, αλλά
  /// δεν έχουν δική τους διεύθυνση (απόφαση 13/11/2026).
  bool get canHaveNetwork =>
      hasCableSettings && this != patchPanel && this != outlet;

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
    this.hasNetwork = true,
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

  /// Οι συσκευές του έχουν IP και όνομα Lansweeper — αλλιώς τα πεδία δεν
  /// φαίνονται στα στοιχεία τους.
  final bool hasNetwork;

  static const List<String> columns = [
    'id',
    'name',
    'symbol',
    'has_ports',
    'show_info',
    'has_network',
  ];

  factory FloorPlanObjectKind.fromMap(Map<String, Object?> map) {
    return FloorPlanObjectKind(
      id: map['id'] as int,
      name: map['name'] as String,
      symbol: FloorPlanSymbol.fromKey(map['symbol'] as String?),
      hasPorts: (map['has_ports'] as int? ?? 0) != 0,
      showInfo: (map['show_info'] as int? ?? 1) != 0,
      hasNetwork: (map['has_network'] as int? ?? 1) != 0,
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
