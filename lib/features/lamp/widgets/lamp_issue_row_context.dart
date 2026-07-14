import '../../../core/database/old_database/lamp_issue_resolution_models.dart';

/// Γραμμές «Στοιχεία εγγραφής» από τα rowContext* metadata της πρότασης.
List<String> lampProposalRowContextLines(LampIssueResolutionProposal proposal) {
  final metadata = proposal.metadata;
  String? text(String key) {
    final value = metadata[key]?.toString().trim();
    if (value == null || value.isEmpty || value == 'null') return null;
    return value;
  }

  final lines = <String>[];
  final code = text('rowContextCode');
  final description = text('rowContextDescription');
  if (code != null || description != null) {
    lines.add('Εξοπλισμός: ${code ?? '-'} · ${description ?? '-'}');
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
  final officeId = text('rowContextOfficeId');
  final officeLabel = text('rowContextOfficeLabel');
  if (officeId != null || officeLabel != null) {
    lines.add('Τμήμα/Γραφείο: ${officeId ?? '-'} · ${officeLabel ?? '-'}');
  }
  final ownerId = text('rowContextOwnerId');
  final ownerLabel = text('rowContextOwnerLabel');
  if (ownerId != null || ownerLabel != null) {
    lines.add('Υπάλληλος: ${ownerId ?? '-'} · ${ownerLabel ?? '-'}');
  }
  final modelId = text('rowContextModelId');
  final modelLabel = text('rowContextModelLabel');
  if (modelId != null || modelLabel != null) {
    lines.add('Μοντέλο: ${modelId ?? '-'} · ${modelLabel ?? '-'}');
  }
  final contractId = text('rowContextContractId');
  final contractLabel = text('rowContextContractLabel');
  if (contractId != null || contractLabel != null) {
    lines.add('Συμβόλαιο: ${contractId ?? '-'} · ${contractLabel ?? '-'}');
  }
  return lines;
}
