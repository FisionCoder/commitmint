import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// Runs a repo action future, showing a snackbar on success/failure.
Future<void> runRepoAction(
  BuildContext context,
  Future<void> Function() action, {
  String? success,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    await action();
    if (success != null) {
      messenger.showSnackBar(SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: AppColors.green, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(success,
                  style: const TextStyle(
                      color: AppColors.textPrimary, fontSize: 13.5)),
            ),
          ],
        ),
        backgroundColor: AppColors.surfaceRaised,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ));
    }
  } catch (e) {
    messenger.showSnackBar(SnackBar(
      content: Row(
        children: [
          const Icon(Icons.error, color: Colors.white, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(e.toString(),
                style: const TextStyle(color: Colors.white, fontSize: 13.5)),
          ),
        ],
      ),
      backgroundColor: AppColors.red.withValues(alpha: 0.95),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 4),
    ));
  }
}

/// Simple text-input dialog (used for new branch name).
Future<String?> promptText(
  BuildContext context, {
  required String title,
  required String hint,
  String confirm = 'OK',
  String? initial,
}) {
  final controller = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.surface,
      title: Text(title, style: const TextStyle(fontSize: 16)),
      content: SizedBox(
        width: 360,
        child: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(hintText: hint),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel')),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, controller.text),
          child: Text(confirm),
        ),
      ],
    ),
  );
}
