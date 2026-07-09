/// Ελληνικές ετικέτες για `issue_type` στο `data_issues` και στην αναφορά ελέγχου ακεραιότητας.
String lampDataIssueTypeDisplayLabel(String issueType) {
  switch (issueType) {
    case 'non_numeric_fk':
      return 'Μη αριθμητικό Κλειδί Αναφοράς';
    case 'unknown_id':
      return 'Ασύμβατο Αναγνωριστικό';
    case 'duplicate_asset_no':
      return 'Διπλότυποι αριθμοί παγίου';
    case 'duplicate_model_serial':
      return 'Διπλότυποι συνδυασμοί μοντέλου / σειριακού';
    case 'set_master_self_reference':
      return 'Κύριος εξοπλισμός που δείχνει στον ίδιο εξοπλισμό';
    case 'set_master_missing_target':
      return 'Κύριος εξοπλισμός χωρίς υπαρκτό στόχο';
    case 'set_master_cycle':
      return 'Κύκλοι ιεραρχίας Κύριου εξοπλισμού';
    case 'network_no_hostname':
      return 'Δίκτυο · Χωρίς όνομα υπολογιστή (μόνο IP)';
    case 'network_hostname_unmatched':
      return 'Δίκτυο · Αναντιστοίχιστο όνομα υπολογιστή';
    case 'network_duplicate_hostname':
      return 'Δίκτυο · Διπλότυπο όνομα υπολογιστή';
    case 'network_code_not_found':
      return 'Δίκτυο · Ανύπαρκτος κωδικός εξοπλισμού';
    case 'network_ip_in_comments':
      return 'Δίκτυο · IP μέσα στα σχόλια (προς επιβεβαίωση)';
    case 'network_model_mismatch':
      return 'Δίκτυο · Ασυμφωνία μοντέλου (γράφτηκε, προς επιθεώρηση)';
    case 'network_sheet_invalid':
      return 'Δίκτυο · Μη έγκυρο φύλλο network';
    case 'network_duplicate_ip':
      return 'Δίκτυο · Διπλή διεύθυνση IP';
    case 'network_duplicate_name':
      return 'Δίκτυο · Διπλό όνομα υπολογιστή στη βάση';
    case 'network_invalid_ip':
      return 'Δίκτυο · Μη έγκυρη μορφή IP';
    case 'network_name_code_mismatch':
      return 'Δίκτυο · Όνομα που δεν ταιριάζει με τον κωδικό';
    default:
      return issueType;
  }
}
