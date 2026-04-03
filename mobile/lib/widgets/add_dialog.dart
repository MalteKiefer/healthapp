import 'package:flutter/material.dart';

/// Shows a Material 3 modal bottom sheet form for adding records.
Future<T?> showAddSheet<T>({
  required BuildContext context,
  required String title,
  required Widget content,
  String confirmLabel = 'Add',
  VoidCallback? onConfirm,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      builder: (ctx, scrollCtrl) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
        ),
        child: ListView(
          controller: scrollCtrl,
          children: [
            const SizedBox(height: 8),
            Text(title, style: Theme.of(ctx).textTheme.titleLarge),
            const SizedBox(height: 20),
            content,
            const SizedBox(height: 16),
            FilledButton(
              onPressed: onConfirm,
              child: Text(confirmLabel),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Legacy dialog wrapper kept for backward compatibility.
class AddDialog extends StatelessWidget {
  final String title;
  final Widget content;
  final String confirmLabel;
  final VoidCallback? onConfirm;

  const AddDialog({
    super.key,
    required this.title,
    required this.content,
    this.confirmLabel = 'Add',
    this.onConfirm,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(title),
      content: SingleChildScrollView(child: content),
      actions: [
        OutlinedButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: onConfirm,
          child: Text(confirmLabel),
        ),
      ],
    );
  }
}
