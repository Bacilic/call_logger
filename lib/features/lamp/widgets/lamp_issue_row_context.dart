import '../../../core/database/old_database/lamp_data_issue_type_labels.dart';
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

bool _isSkipSentinel(LampIssueResolutionOption option) =>
    option.id == '__skip_open__';

bool _isClearOrDisconnectOption(LampIssueResolutionOption option) {
  if (option.proposedId != null) return false;
  if (option.action == LampIssueResolutionAction.createNew) return false;
  if (_isSkipSentinel(option)) return false;

  final operation =
      (option.metadata['operation']?.toString() ?? '').toLowerCase();
  if (operation.contains('null') || operation.contains('clear')) {
    return true;
  }
  // π.χ. update_equipment_fk με ρητό proposedId: null στα metadata
  if (option.metadata.containsKey('proposedId') &&
      option.metadata['proposedId'] == null) {
    return true;
  }
  return false;
}

String _equipmentCodePrefix(LampIssueResolutionProposal proposal) {
  final row = proposal.row?.toString() ?? '-';
  final description = proposal.metadata['rowContextDescription']
      ?.toString()
      .trim();
  if (description != null &&
      description.isNotEmpty &&
      description != 'null') {
    return 'Κωδικός $row ($description)';
  }
  return 'Κωδικός $row';
}

/// Ζωντανή γραμμή συνέπειας για την επιλεγμένη ενέργεια χειροκίνητου ελέγχου.
String lampResolutionConsequenceLine(
  LampIssueResolutionProposal proposal,
  LampIssueResolutionOption? selectedOption, {
  String? textInput,
}) {
  if (selectedOption == null) {
    return 'Δεν έχει επιλεγεί ενέργεια.';
  }
  if (_isSkipSentinel(selectedOption)) {
    return 'Επιλεγμένη ενέργεια: Παράλειψη — η εγγραφή μένει ανοιχτή';
  }

  final fieldLabel = lampDataIssueColumnDisplayLabel(proposal.column);

  if (selectedOption.action == LampIssueResolutionAction.createNew) {
    final label = selectedOption.label.trim();
    final trimmedInput = textInput?.trim();
    if (selectedOption.requiresTextInput &&
        trimmedInput != null &&
        trimmedInput.isNotEmpty) {
      return '→ Δημιουργία: $label · $trimmedInput';
    }
    return '→ Δημιουργία: $label';
  }

  if (_isClearOrDisconnectOption(selectedOption)) {
    return '→ Εκκαθάριση/Αποσύνδεση $fieldLabel';
  }

  final optionLabel = selectedOption.label.trim();
  return 'Επιλεγμένη ενέργεια: ${_equipmentCodePrefix(proposal)} → '
      '$fieldLabel: $optionLabel';
}
