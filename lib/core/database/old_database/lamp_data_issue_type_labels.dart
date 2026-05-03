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
    default:
      return issueType;
  }
}
