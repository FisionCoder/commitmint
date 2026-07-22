// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart';

import '../../models/git_commit.dart';
import '../../services/git_service.dart';
import '../../state/repo_state.dart';
import '../../theme/app_theme.dart';
import 'repo_actions.dart';

/// Opens the interactive-rebase planner for the commits from [base] (exclusive)
/// up to HEAD, pre-populated from [range] (oldest first). Executes the plan on
/// confirm; conflicts pause the rebase for the normal conflict banner.
Future<void> showInteractiveRebaseDialog(BuildContext context, RepoState state,
    String? base, List<GitCommit> range) {
  return showDialog<void>(
    context: context,
    builder: (_) => _InteractiveRebaseDialog(state: state, base: base, range: range),
  );
}

class _InteractiveRebaseDialog extends StatefulWidget {
  final RepoState state;
  final String? base;
  final List<GitCommit> range;
  const _InteractiveRebaseDialog(
      {required this.state, required this.base, required this.range});

  @override
  State<_InteractiveRebaseDialog> createState() =>
      _InteractiveRebaseDialogState();
}

class _InteractiveRebaseDialogState extends State<_InteractiveRebaseDialog> {
  late List<RebaseStep> _steps;

  @override
  void initState() {
    super.initState();
    _steps = [
      for (final c in widget.range)
        RebaseStep(
            sha: c.hash, subject: c.subject, action: RebaseAction.pick),
    ];
  }

  Color _actionColor(RebaseAction a) => switch (a) {
        RebaseAction.pick => AppColors.textPrimary,
        RebaseAction.reword => AppColors.accentTeal,
        RebaseAction.squash => AppColors.amber,
        RebaseAction.fixup => AppColors.amber,
        RebaseAction.drop => AppColors.red,
      };

  String _label(RebaseAction a) => switch (a) {
        RebaseAction.pick => 'Pick',
        RebaseAction.reword => 'Reword',
        RebaseAction.squash => 'Squash',
        RebaseAction.fixup => 'Fixup',
        RebaseAction.drop => 'Drop',
      };

  Future<void> _editMessage(int i) async {
    final s = _steps[i];
    final msg = await promptText(context,
        title: 'Reword commit',
        hint: 'commit message',
        initial: s.newMessage ?? s.subject,
        confirm: 'Save');
    if (msg != null && msg.trim().isNotEmpty) {
      setState(() => _steps[i] =
          s.copyWith(action: RebaseAction.reword, newMessage: msg.trim()));
    }
  }

  void _run() {
    final kept = _steps.where((s) => s.action != RebaseAction.drop).toList();
    if (kept.isEmpty) return;
    Navigator.of(context).pop();
    runRepoAction(
      context,
      () => widget.state.runInteractiveRebase(widget.base, _steps),
      success: 'Rebase complete',
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: Row(
        children: [
          Icon(Icons.account_tree_outlined, size: 18, color: AppColors.accent),
          const SizedBox(width: 10),
          const Text('Interactive Rebase', style: TextStyle(fontSize: 16)),
        ],
      ),
      content: SizedBox(
        width: 620,
        height: 460,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Reorder (drag) and choose an action per commit. Oldest is at the '
              'top. Squash/Fixup fold a commit into the one above it.',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppColors.border),
                ),
                child: ReorderableListView.builder(
                  buildDefaultDragHandles: false,
                  itemCount: _steps.length,
                  onReorderItem: (oldI, newI) {
                    setState(() {
                      final s = _steps.removeAt(oldI);
                      _steps.insert(newI, s);
                    });
                  },
                  itemBuilder: (context, i) {
                    final s = _steps[i];
                    final dropped = s.action == RebaseAction.drop;
                    return Padding(
                      key: ValueKey(s.sha),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      child: Row(
                        children: [
                          ReorderableDragStartListener(
                            index: i,
                            child: Icon(Icons.drag_indicator,
                                size: 18, color: AppColors.textMuted),
                          ),
                          const SizedBox(width: 6),
                          SizedBox(
                            width: 108,
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<RebaseAction>(
                                value: s.action,
                                isDense: true,
                                dropdownColor: AppColors.surfaceRaised,
                                style: TextStyle(
                                    fontSize: 12.5,
                                    color: _actionColor(s.action),
                                    fontWeight: FontWeight.w600),
                                items: [
                                  for (final a in RebaseAction.values)
                                    DropdownMenuItem(
                                      value: a,
                                      child: Text(_label(a),
                                          style: TextStyle(
                                              color: _actionColor(a))),
                                    ),
                                ],
                                onChanged: (a) async {
                                  if (a == null) return;
                                  setState(() => _steps[i] = s.copyWith(
                                      action: a,
                                      newMessage:
                                          a == RebaseAction.reword ? s.newMessage : null));
                                  if (a == RebaseAction.reword) {
                                    await _editMessage(i);
                                  }
                                },
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              s.newMessage ?? s.subject,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                decoration: dropped
                                    ? TextDecoration.lineThrough
                                    : null,
                                color: dropped
                                    ? AppColors.textMuted
                                    : AppColors.textPrimary,
                              ),
                            ),
                          ),
                          if (s.action == RebaseAction.reword)
                            IconButton(
                              icon: Icon(Icons.edit_outlined,
                                  size: 15, color: AppColors.accentTeal),
                              tooltip: 'Edit message',
                              onPressed: () => _editMessage(i),
                            ),
                          Text(s.sha.substring(0, 7),
                              style: TextStyle(
                                  fontFamily: 'Consolas',
                                  fontSize: 11,
                                  color: AppColors.textMuted)),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('Cancel', style: TextStyle(color: AppColors.textSecondary)),
        ),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: AppColors.accent),
          onPressed: _run,
          icon: const Icon(Icons.play_arrow, size: 16),
          label: const Text('Start Rebase'),
        ),
      ],
    );
  }
}
