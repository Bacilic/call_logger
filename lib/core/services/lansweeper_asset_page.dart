/// Η σελίδα μιας συσκευής στο Lansweeper (`asset.aspx?AssetID=…`).
///
/// Ο αριθμός (AssetID) δεν τον δίνει κανένα API που φτάνει η εφαρμογή: το
/// Helpdesk API δίνει μόνο όνομα και IP, και το Data API ζει στο νέφος της
/// Lansweeper. Γι' αυτό τον γράφει ο χρήστης — συνήθως επικολλώντας ολόκληρη
/// τη διεύθυνση της σελίδας, από την οποία κρατιέται μόνο ο αριθμός.
///
/// Ο διακομιστής **δεν** είναι δεύτερη ρύθμιση: είναι ο ίδιος με του URL
/// προβολής ticket, ώστε όταν αλλάξει να αλλάζει σε ένα σημείο.
library;

/// Ό,τι έγραψε ο χρήστης στο πεδίο του αριθμού, κριμένο.
///
/// - κενό → `(id: null, error: null)`: δεν συνδέεται σελίδα·
/// - αριθμός ή διεύθυνση με `AssetID=` → `(id: 1084, error: null)`·
/// - οτιδήποτε άλλο → `(id: null, error: <μήνυμα>)`.
typedef LansweeperAssetIdInput = ({int? id, String? error});

const String kLansweeperAssetIdError =
    'Γράψτε τον αριθμό ή επικολλήστε τη διεύθυνση της σελίδας '
    '(…asset.aspx?AssetID=1084).';

final RegExp _assetIdParam = RegExp(r'assetid=(\d+)', caseSensitive: false);
final RegExp _digitsOnly = RegExp(r'^\d+$');

LansweeperAssetIdInput parseLansweeperAssetId(String text) {
  final t = text.trim();
  if (t.isEmpty) return (id: null, error: null);
  final raw = _digitsOnly.hasMatch(t) ? t : _assetIdParam.firstMatch(t)?[1];
  final id = raw == null ? null : int.tryParse(raw);
  if (id == null || id <= 0) return (id: null, error: kLansweeperAssetIdError);
  return (id: id, error: null);
}

/// Η διεύθυνση της σελίδας της συσκευής [assetId], στον ίδιο διακομιστή με το
/// [ticketViewUrlTemplate]. Ό,τι υπάρχει πριν από το `/helpdesk/` κρατιέται
/// (εγκατάσταση σε υποφάκελο). `null` όταν το πρότυπο δεν είναι διεύθυνση
/// http(s) — καλύτερα κανένας σύνδεσμος παρά σύνδεσμος που δεν οδηγεί πουθενά.
String? lansweeperAssetPageUrl(String ticketViewUrlTemplate, int assetId) {
  if (assetId <= 0) return null;
  final t = ticketViewUrlTemplate
      .trim()
      .replaceAll('{tid}', '0')
      .replaceAll('[id_ticket]', '0');
  final uri = Uri.tryParse(t);
  if (uri == null || uri.host.isEmpty) return null;
  if (uri.scheme != 'http' && uri.scheme != 'https') return null;
  final path = uri.path;
  final helpdesk = path.toLowerCase().indexOf('/helpdesk/');
  final base = helpdesk < 0 ? '' : path.substring(0, helpdesk);
  return Uri(
    scheme: uri.scheme,
    host: uri.host,
    port: uri.hasPort ? uri.port : null,
    path: '$base/asset.aspx',
    query: 'AssetID=$assetId',
  ).toString();
}
