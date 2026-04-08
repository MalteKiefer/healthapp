import 'package:flutter/material.dart';
import '../core/i18n/translations.dart';

/// Shows a delete confirmation dialog with a translated [titleKey] and [bodyKey].
///
/// Returns `true` when the user confirms the deletion, `false` or `null` otherwise.
Future<bool> showDeleteConfirmDialog(
  BuildContext context, {
  required String titleKey,
  required String bodyKey,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(T.tr(titleKey)),
      content: Text(T.tr(bodyKey)),
      actions: [
        OutlinedButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(T.tr('common.cancel')),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(ctx).colorScheme.error,
          ),
          child: Text(T.tr('common.delete')),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}
