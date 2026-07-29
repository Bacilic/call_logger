// Μοντέλα ροής αποδέσμευσης τηλεφώνων/εξοπλισμού (χωρίς widgets/βάση).

/// Πλαίσιο αποδέσμευσης: κοινόχρηστο στοιχείο τμήματος ή προσωπικό στοιχείο χρήστη.
enum SharedAssetDisconnectMode { sharedAsset, personalPhone, personalEquipment }

/// Επιλογή στον κύριο διάλογο αποδέσμευσης κοινόχρηστου στοιχείου.
enum SharedAssetDisconnectChoice { keepInDepartment, transfer, delete }

/// Στόχος μεταφοράς (υπάρχον ή νέο τμήμα).
class SharedAssetTransferTarget {
  const SharedAssetTransferTarget.existing(this.departmentId)
    : newDepartmentName = null;

  const SharedAssetTransferTarget.createNew(this.newDepartmentName)
    : departmentId = null;

  final int? departmentId;
  final String? newDepartmentName;
}

/// Αποτέλεσμα ροής αποδέσμευσης για ένα στοιχείο.
class SharedAssetDisconnectItemResult {
  const SharedAssetDisconnectItemResult.keep()
    : choice = SharedAssetDisconnectChoice.keepInDepartment,
      transferTarget = null;

  const SharedAssetDisconnectItemResult.transfer(this.transferTarget)
    : choice = SharedAssetDisconnectChoice.transfer;

  const SharedAssetDisconnectItemResult.delete()
    : choice = SharedAssetDisconnectChoice.delete,
      transferTarget = null;

  final SharedAssetDisconnectChoice choice;
  final SharedAssetTransferTarget? transferTarget;
}

/// Συγκεντρωτικό αποτέλεσμα αποδέσμευσης πολλών στοιχείων.
class SharedAssetDisconnectBatchResult {
  const SharedAssetDisconnectBatchResult({
    this.phonesToKeep = const [],
    this.equipmentToKeep = const [],
    this.phoneTransfers = const {},
    this.equipmentTransfers = const {},
    this.phonesToDelete = const [],
    this.equipmentToDelete = const [],
    this.newDepartmentNamesToCreate = const <String>{},
  });

  final List<String> phonesToKeep;
  final List<String> equipmentToKeep;
  final Map<String, SharedAssetTransferTarget> phoneTransfers;
  final Map<String, SharedAssetTransferTarget> equipmentTransfers;
  final List<String> phonesToDelete;
  final List<String> equipmentToDelete;

  /// Ονόματα τμημάτων που πρέπει να δημιουργηθούν πριν εφαρμοστούν οι μεταφορές.
  ///
  /// Ποια στοιχεία πάνε σε ποιο τμήμα το λένε ήδη τα [phoneTransfers] και
  /// [equipmentTransfers]. Παλιότερα εδώ κρατιόταν και λίστα τηλεφώνων ανά
  /// όνομα, που όμως κανείς δεν διάβαζε — και στη διαδρομή του εξοπλισμού ήταν
  /// πάντα κενή, οπότε ο καλών δεν μπορούσε να ξεχωρίσει «κανένα τηλέφωνο»
  /// από «αφορά εξοπλισμό».
  final Set<String> newDepartmentNamesToCreate;
}
