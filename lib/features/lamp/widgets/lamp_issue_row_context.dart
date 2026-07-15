import '../../../core/database/old_database/lamp_issue_resolution_models.dart';

/// Επεξήγηση λεκτικής βαθμίδας βεβαιότητας στους οδηγούς επίλυσης.
const String lampConfidenceTooltip =
    'Πόσο σίγουρη είναι η αυτόματη ανάλυση για τη συγκεκριμένη πρόταση. '
    'Προκύπτει από την ποιότητα της αντιστοίχισης (π.χ. ακριβές ταίριασμα '
    'ονόματος = υψηλή, μερικό/ασαφές = χαμηλή).';

/// Κείμενο βεβαιότητας ή null αν είναι ονομαστική (ψευδο-πληροφορία).
String? lampConfidenceDisplay(LampIssueResolutionProposal proposal) {
  if (proposal.metadata['confidenceIsNominal'] == true) return null;
  final grade = switch (proposal.confidence) {
    < 50 => 'Χαμηλή',
    < 80 => 'Μεσαία',
    _ => 'Υψηλή',
  };
  return 'Βεβαιότητα: $grade (${proposal.confidence}%)';
}

String? _nameWithIdDisplay(String? name, String? id) {
  final hasName = name != null && name.isNotEmpty;
  final hasId = id != null && id.isNotEmpty;
  if (hasName && hasId) return '$name ($id)';
  if (hasName) return name;
  if (hasId) return id;
  return null;
}

/// Γραμμές «Στοιχεία εγγραφής» από τα rowContext* metadata της πρότασης.
List<String> lampProposalRowContextLines(LampIssueResolutionProposal proposal) {
  final metadata = proposal.metadata;
  String? text(String key) {
    final value = metadata[key]?.toString().trim();
    if (value == null || value.isEmpty || value == 'null') return null;
    return value;
  }

  final lines = <String>[];
  final equipmentDisplay = _nameWithIdDisplay(
    text('rowContextDescription'),
    text('rowContextCode'),
  );
  if (equipmentDisplay != null) {
    lines.add('Εξοπλισμός: $equipmentDisplay');
  }
  final stateName = text('rowContextStateName');
  if (stateName != null) {
    lines.add('Κατάσταση: $stateName');
  }
  final assetNo = text('rowContextAssetNo');
  final serialNo = text('rowContextSerialNo');
  if (assetNo != null || serialNo != null) {
    lines.add('Asset: ${assetNo ?? '-'} · Serial: ${serialNo ?? '-'}');
  }
  final officeDisplay = _nameWithIdDisplay(
    text('rowContextOfficeLabel'),
    text('rowContextOfficeId'),
  );
  if (officeDisplay != null) {
    lines.add('Τμήμα/Γραφείο: $officeDisplay');
  }
  final ownerDisplay = _nameWithIdDisplay(
    text('rowContextOwnerLabel'),
    text('rowContextOwnerId'),
  );
  if (ownerDisplay != null) {
    lines.add('Υπάλληλος: $ownerDisplay');
  }
  final modelDisplay = _nameWithIdDisplay(
    text('rowContextModelLabel'),
    text('rowContextModelId'),
  );
  if (modelDisplay != null) {
    lines.add('Μοντέλο: $modelDisplay');
  }
  final contractDisplay = _nameWithIdDisplay(
    text('rowContextContractLabel'),
    text('rowContextContractId'),
  );
  if (contractDisplay != null) {
    lines.add('Συμβόλαιο: $contractDisplay');
  }
  return lines;
}
