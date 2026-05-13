import 'package:flutter/material.dart';

class LansweeperSyncForm extends StatelessWidget {
  const LansweeperSyncForm({
    required this.titleController,
    required this.notesController,
    super.key,
  });

  final TextEditingController titleController;
  final TextEditingController notesController;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Φόρμα καταχώρησης Lansweeper',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 10),
            TextField(
              controller: titleController,
              decoration: const InputDecoration(
                labelText: 'Τίτλος',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: notesController,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Σημειώσεις (περιγραφή ticket)',
                hintText:
                    'Καλών και εξοπλισμό συμπληρώνετε χειροκίνητα στο Lansweeper.',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
