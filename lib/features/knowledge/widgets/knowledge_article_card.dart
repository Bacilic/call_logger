import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/knowledge_article.dart';

/// Μία συνταγή της Βάσης Γνώσης σε μορφή κάρτας.
///
/// Το σύμπτωμα μπαίνει πάνω και με πλάγια γραφή: είναι ο τρόπος που ακούγεται
/// το πρόβλημα στο τηλέφωνο, άρα εκείνο αναγνωρίζει κανείς πρώτο όταν σαρώνει
/// τη λίστα ψάχνοντας «το έχω ξαναδεί αυτό».
class KnowledgeArticleCard extends StatelessWidget {
  const KnowledgeArticleCard({
    super.key,
    required this.article,
    this.onEdit,
    this.onDelete,
  });

  final KnowledgeArticle article;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  static String usageLabel(int timesUsed, String? lastUsedAt) {
    if (timesUsed <= 0) return 'δεν έχει χρησιμοποιηθεί ακόμη';
    final stamp = DateTime.tryParse((lastUsedAt ?? '').trim());
    final times = timesUsed == 1 ? '1 φορά' : '$timesUsed φορές';
    if (stamp == null) return 'χρησιμοποιήθηκε $times';
    return 'χρησιμοποιήθηκε $times · τελευταία ${DateFormat('dd/MM/yyyy').format(stamp)}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    article.title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (article.categoryName != null &&
                    article.categoryName!.trim().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Chip(
                      label: Text(article.categoryName!),
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                    ),
                  ),
                if (onEdit != null)
                  IconButton(
                    tooltip: 'Επεξεργασία',
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit_outlined, size: 20),
                  ),
                if (onDelete != null)
                  IconButton(
                    tooltip: 'Διαγραφή',
                    onPressed: onDelete,
                    icon: Icon(
                      Icons.delete_outline,
                      size: 20,
                      color: theme.colorScheme.error,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              article.symptom,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontStyle: FontStyle.italic,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 10),
            Text(article.solution, style: theme.textTheme.bodyMedium),
            if (article.tagList.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final tag in article.tagList)
                    Chip(
                      label: Text(tag),
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      labelStyle: theme.textTheme.bodySmall,
                    ),
                ],
              ),
            ],
            const SizedBox(height: 8),
            Text(
              usageLabel(article.timesUsed, article.lastUsedAt),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
