import 'package:flutter/material.dart';

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
        TextButton(
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

Future<T?> showAddDialog<T>({
  required BuildContext context,
  required String title,
  required Widget content,
  String confirmLabel = 'Add',
  VoidCallback? onConfirm,
}) {
  return showDialog<T>(
    context: context,
    builder: (_) => AddDialog(
      title: title,
      content: content,
      confirmLabel: confirmLabel,
      onConfirm: onConfirm,
    ),
  );
}
