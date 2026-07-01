import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/file_change.dart';
import '../../models/git_commit.dart';
import '../../services/git_service.dart';
import '../../state/app_state.dart';
import '../../state/repo_state.dart';
import '../../state/settings_state.dart';
import '../../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/notifier.dart';
import '../widgets/profile_avatar.dart';
import 'repo_actions.dart';

class ChangesPanel extends StatelessWidget {
  const ChangesPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<RepoState>();
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(left: BorderSide(color: AppColors.border)),
        boxShadow: AppColors.elevation(y: 0, blur: 12, alpha: 0.12),
      ),
      child: state.selectingWip
          ? _WorkingChanges(state: state)
          : _CommitDetails(commit: state.selectedCommit),
    );
  }
}

// --------------------------------------------------------- working changes ---
/// Shown atop the working-changes panel while a merge/rebase/cherry-pick/revert
/// is paused on conflicts: states the operation, how many conflicts remain, and
/// offers Abort and (once clean) Continue.
class _ConflictBanner extends StatelessWidget {
  final RepoState state;
  const _ConflictBanner({required this.state});

  @override
  Widget build(BuildContext context) {
    final remaining = state.conflictedFiles.length;
    final clean = remaining == 0;
    final hasOp = state.operation != GitOperation.none;
    final opLabel = hasOp ? state.operation.label : 'Conflicts';
    return Container(
      margin: const EdgeInsets.fromLTRB(10, 10, 10, 0),
      padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
      decoration: BoxDecoration(
        color: (clean ? AppColors.green : AppColors.amber).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
            color: (clean ? AppColors.green : AppColors.amber)
                .withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(clean ? Icons.check_circle_outline : Icons.warning_amber_rounded,
                  size: 16, color: clean ? AppColors.green : AppColors.amber),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  clean
                      ? (hasOp
                          ? '$opLabel ready to finish — all conflicts resolved.'
                          : 'All conflicts resolved — stage and commit.')
                      : '${hasOp ? '$opLabel in progress' : 'Merge conflicts'} '
                          '— $remaining file${remaining == 1 ? '' : 's'} to resolve.',
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary),
                ),
              ),
            ],
          ),
          if (!clean) ...[
            const SizedBox(height: 4),
            Text(
              'Resolve each file with “Use ours / Use theirs”, or open it to edit '
              'the conflict markers and Mark resolved.',
              style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
            ),
          ],
          // Continue/Abort only apply to an actual in-progress operation; a bare
          // conflict (e.g. from a stash pop) is finished by staging + committing.
          if (hasOp) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                _SmallButton(
                  label: 'Abort $opLabel',
                  onTap: state.busy
                      ? null
                      : () => runRepoAction(context, state.abortOperation,
                          success: '$opLabel aborted'),
                ),
                const SizedBox(width: 8),
                _SmallButton(
                  label: 'Continue',
                  primary: true,
                  onTap: (clean && !state.busy)
                      ? () => runRepoAction(context, state.continueOperation,
                          success: '$opLabel completed')
                      : null,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _WorkingChanges extends StatelessWidget {
  final RepoState state;
  const _WorkingChanges({required this.state});

  @override
  Widget build(BuildContext context) {
    final header = Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text('${state.totalChanges} file changes on',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 12.5, color: AppColors.textSecondary)),
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Pill(state.currentBranch,
                      color: AppColors.accent,
                      icon: Icons.call_split,
                      tooltip: true),
                ),
              ],
            ),
          ),
          if (state.totalChanges > 0)
            IconAction(
              icon: Icons.delete_outline,
              tooltip: 'Discard all changes',
              color: AppColors.red,
              onTap: () => _confirmDiscardAll(context, state),
            ),
        ],
      ),
    );

    final sections = [
      _FileSection(
        title: 'Unstaged Files',
        count: state.unstaged.length,
        actionLabel: 'Stage All Changes',
        onAction: state.unstaged.isEmpty
            ? null
            : () => runRepoAction(context, state.stageAll),
        files: state.unstaged,
        staged: false,
        state: state,
      ),
      _FileSection(
        title: 'Staged Files',
        count: state.staged.length,
        actionLabel: 'Unstage All',
        onAction: state.staged.isEmpty
            ? null
            : () => runRepoAction(context, state.unstageAll),
        files: state.staged,
        staged: true,
        state: state,
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (state.inConflictState) _ConflictBanner(state: state),
        header,
        const _PathTreeToggle(),
        const Divider(height: 1),
        Expanded(
          child: LayoutBuilder(builder: (context, c) {
            // On a tall enough panel, pin the commit box at the bottom;
            // otherwise let the whole thing scroll so nothing overflows.
            if (c.maxHeight >= 420) {
              return Column(
                children: [
                  Expanded(
                    child: ListView(padding: EdgeInsets.zero, children: sections),
                  ),
                  _CommitBox(state: state),
                ],
              );
            }
            return SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [...sections, _CommitBox(state: state)],
              ),
            );
          }),
        ),
      ],
    );
  }

  Future<void> _confirmDiscardAll(
      BuildContext context, RepoState state) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Discard all changes?',
            style: TextStyle(fontSize: 16)),
        content: Text(
            'Discard local changes to all ${state.unstaged.length} unstaged '
            'tracked file(s)? This cannot be undone. Untracked files are kept.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Discard All'),
          ),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      await runRepoAction(context, state.discardAllChanges,
          success: 'Discarded all changes');
      state.closeFileDetail();
    }
  }
}

class _PathTreeToggle extends StatelessWidget {
  const _PathTreeToggle();
  @override
  Widget build(BuildContext context) {
    final state = context.watch<RepoState>();
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 12, 10),
      child: Row(
        children: [
          Icon(Icons.swap_vert, size: 16, color: AppColors.textMuted),
          const Spacer(),
          _ToggleChip(
            icon: Icons.list,
            label: 'Path',
            active: !state.treeView,
            onTap: () => state.setTreeView(false),
          ),
          const SizedBox(width: 6),
          _ToggleChip(
            icon: Icons.account_tree_outlined,
            label: 'Tree',
            active: state.treeView,
            onTap: () => state.setTreeView(true),
          ),
        ],
      ),
    );
  }
}

class _ToggleChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _ToggleChip(
      {required this.icon,
      required this.label,
      required this.active,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: active ? AppColors.surfaceRaised : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
              color: active ? AppColors.border : Colors.transparent),
        ),
        child: Row(children: [
          Icon(icon,
              size: 13,
              color: active ? AppColors.textPrimary : AppColors.textMuted),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  fontSize: 12,
                  color: active ? AppColors.textPrimary : AppColors.textMuted)),
        ]),
      ),
    );
  }
}

class _FileSection extends StatefulWidget {
  final String title;
  final int count;
  final String actionLabel;
  final VoidCallback? onAction;
  final List<FileChange> files;
  final bool staged;
  final RepoState state;

  const _FileSection({
    required this.title,
    required this.count,
    required this.actionLabel,
    required this.onAction,
    required this.files,
    required this.staged,
    required this.state,
  });

  @override
  State<_FileSection> createState() => _FileSectionState();
}

class _FileSectionState extends State<_FileSection> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          hoverColor: AppColors.surfaceRaised,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 10, 6),
            child: Row(
              children: [
                Icon(_expanded ? Icons.expand_more : Icons.chevron_right,
                    size: 16, color: AppColors.textMuted),
                const SizedBox(width: 2),
                Expanded(
                  child: Text('${widget.title} (${widget.count})',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary)),
                ),
                const SizedBox(width: 6),
                if (widget.onAction != null)
                  _SmallButton(
                      label: widget.actionLabel, onTap: widget.onAction!),
              ],
            ),
          ),
        ),
        if (_expanded) ...[
          if (widget.files.isEmpty)
            Padding(
              padding: EdgeInsets.fromLTRB(34, 2, 10, 6),
              child: Text('—',
                  style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
            )
          else if (widget.state.treeView)
            _FileTree(
                files: widget.files,
                staged: widget.staged,
                state: widget.state)
          else
            for (final f in widget.files)
              _FileRow(file: f, staged: widget.staged, state: widget.state),
        ],
      ],
    );
  }
}

class _FileRow extends StatefulWidget {
  final FileChange file;
  final bool staged;
  final RepoState state;
  final double indent;

  /// In tree mode only the file name is shown (the folder path is implied by
  /// the parent rows); in path mode the directory prefix is shown.
  final bool nameOnly;
  const _FileRow(
      {required this.file,
      required this.staged,
      required this.state,
      this.indent = 0,
      this.nameOnly = false});

  @override
  State<_FileRow> createState() => _FileRowState();
}

class _FileRowState extends State<_FileRow> {
  bool _hover = false;

  Color get _statusColor => _changeColor(widget.file.type);

  @override
  Widget build(BuildContext context) {
    final f = widget.file;
    final isOpen = widget.state.openFile?.path == f.path &&
        widget.state.openFile?.staged == f.staged;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: () => widget.state.openFileDetail(f),
        child: Container(
        color: isOpen
            ? AppColors.selectionRow
            : (_hover ? AppColors.surfaceRaised : Colors.transparent),
        padding: EdgeInsets.fromLTRB(14 + widget.indent, 4, 8, 4),
        child: Row(
          children: [
            Icon(Icons.insert_drive_file_outlined,
                size: 14, color: _statusColor),
            const SizedBox(width: 6),
            Expanded(
              child: Tooltip(
                message: f.path,
                child: RichText(
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  text: TextSpan(
                    style: const TextStyle(fontSize: 12.5),
                    children: [
                      if (!widget.nameOnly && f.directory.isNotEmpty)
                        TextSpan(
                            text: '${f.directory}/',
                            style:
                                TextStyle(color: AppColors.textMuted)),
                      TextSpan(
                          text: f.fileName,
                          style:
                              TextStyle(color: AppColors.textPrimary)),
                    ],
                  ),
                ),
              ),
            ),
            if (f.type == ChangeType.conflicted) ...[
              // Conflict resolution actions (always visible so they're
              // discoverable, not just on hover).
              _RowIcon(
                icon: Icons.west,
                tooltip: 'Use ours (current branch)',
                onTap: () =>
                    runRepoAction(context, () => widget.state.resolveUsingOurs(f)),
              ),
              _RowIcon(
                icon: Icons.east,
                tooltip: 'Use theirs (incoming)',
                onTap: () => runRepoAction(
                    context, () => widget.state.resolveUsingTheirs(f)),
              ),
              _RowIcon(
                icon: Icons.check,
                tooltip: 'Mark resolved (stage)',
                onTap: () =>
                    runRepoAction(context, () => widget.state.markResolved(f)),
              ),
            ] else if (_hover) ...[
              if (widget.staged)
                _RowIcon(
                  icon: Icons.remove,
                  tooltip: 'Unstage',
                  onTap: () =>
                      runRepoAction(context, () => widget.state.unstageFile(f)),
                )
              else ...[
                _RowIcon(
                  icon: Icons.undo,
                  tooltip: 'Discard changes',
                  onTap: () => _confirmDiscard(context, f),
                ),
                _RowIcon(
                  icon: Icons.add,
                  tooltip: 'Stage',
                  onTap: () =>
                      runRepoAction(context, () => widget.state.stageFile(f)),
                ),
              ],
            ] else
              Container(
                width: 16,
                alignment: Alignment.center,
                child: Text(f.statusLetter,
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: _statusColor)),
              ),
          ],
        ),
      ),
      ),
    );
  }

  void _confirmDiscard(BuildContext context, FileChange f) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Discard changes?', style: TextStyle(fontSize: 16)),
        content: Text('Discard local changes to ${f.fileName}? '
            'This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      runRepoAction(context, () => widget.state.discard(f));
    }
  }
}

// ------------------------------------------------------------- tree view ----
/// A directory node in the changes tree. [path] is the full path from the root
/// ('' for the root node itself).
class _Folder {
  final String path;
  final Map<String, _Folder> dirs = {};
  final List<FileChange> files = [];
  _Folder(this.path);

  String get name => path.contains('/') ? path.split('/').last : path;
  int get count =>
      files.length + dirs.values.fold(0, (s, d) => s + d.count);
}

/// Renders the changed files grouped into a collapsible directory tree.
class _FileTree extends StatefulWidget {
  final List<FileChange> files;
  final bool staged;
  final RepoState state;
  const _FileTree(
      {required this.files, required this.staged, required this.state});

  @override
  State<_FileTree> createState() => _FileTreeState();
}

class _FileTreeState extends State<_FileTree> {
  final Set<String> _expanded = {};

  _Folder _build() {
    final root = _Folder('');
    for (final f in widget.files) {
      final parts = f.path.split('/');
      var node = root;
      for (var i = 0; i < parts.length - 1; i++) {
        final seg = parts[i];
        final childPath = node.path.isEmpty ? seg : '${node.path}/$seg';
        node = node.dirs.putIfAbsent(seg, () => _Folder(childPath));
      }
      node.files.add(f);
    }
    return root;
  }

  void _collectFolders(_Folder f, Set<String> out) {
    for (final d in f.dirs.values) {
      out.add(d.path);
      _collectFolders(d, out);
    }
  }

  @override
  Widget build(BuildContext context) {
    final root = _build();
    final allFolders = <String>{};
    _collectFolders(root, allFolders);
    final allExpanded =
        allFolders.isNotEmpty && _expanded.containsAll(allFolders);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (allFolders.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(34, 2, 10, 4),
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: () => setState(() {
                  if (allExpanded) {
                    _expanded.clear();
                  } else {
                    _expanded.addAll(allFolders);
                  }
                }),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(allExpanded ? 'Collapse All' : 'Expand All',
                      style: TextStyle(
                          fontSize: 12, color: AppColors.textSecondary)),
                ),
              ),
            ),
          ),
        ..._render(root, 0),
      ],
    );
  }

  List<Widget> _render(_Folder folder, int depth) {
    final widgets = <Widget>[];
    final dirNames = folder.dirs.keys.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    for (final name in dirNames) {
      final d = folder.dirs[name]!;
      final expanded = _expanded.contains(d.path);
      widgets.add(_folderRow(d, depth, expanded));
      if (expanded) widgets.addAll(_render(d, depth + 1));
    }
    final files = [...folder.files]
      ..sort((a, b) =>
          a.fileName.toLowerCase().compareTo(b.fileName.toLowerCase()));
    for (final f in files) {
      widgets.add(_FileRow(
        file: f,
        staged: widget.staged,
        state: widget.state,
        indent: depth * 16.0,
        nameOnly: true,
      ));
    }
    return widgets;
  }

  Widget _folderRow(_Folder d, int depth, bool expanded) {
    return InkWell(
      onTap: () => setState(
          () => expanded ? _expanded.remove(d.path) : _expanded.add(d.path)),
      hoverColor: AppColors.surfaceRaised,
      child: Padding(
        padding: EdgeInsets.fromLTRB(14 + depth * 16.0, 4, 8, 4),
        child: Row(
          children: [
            Icon(expanded ? Icons.expand_more : Icons.chevron_right,
                size: 16, color: AppColors.textMuted),
            const SizedBox(width: 4),
            Expanded(
              child: Text(d.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 12.5, color: AppColors.textSecondary)),
            ),
            const SizedBox(width: 6),
            Icon(Icons.edit, size: 13, color: AppColors.amber),
            const SizedBox(width: 4),
            Text('${d.count}',
                style: TextStyle(
                    fontSize: 12, color: AppColors.textSecondary)),
          ],
        ),
      ),
    );
  }
}

class _RowIcon extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  const _RowIcon(
      {required this.icon, required this.tooltip, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(3),
        child: Padding(
          padding: const EdgeInsets.all(3),
          child: Icon(icon, size: 15, color: AppColors.textSecondary),
        ),
      ),
    );
  }
}

class _SmallButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final bool primary;
  const _SmallButton(
      {required this.label, required this.onTap, this.primary = false});

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final fg = primary
        ? (enabled ? Colors.white : AppColors.textMuted)
        : (enabled ? AppColors.textSecondary : AppColors.textMuted);
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: primary && enabled
                ? AppColors.accent
                : AppColors.surfaceRaised,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: AppColors.border),
          ),
          child: Text(label, style: TextStyle(fontSize: 11.5, color: fg)),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------- commit box ----
class _CommitBox extends StatefulWidget {
  final RepoState state;
  const _CommitBox({required this.state});

  @override
  State<_CommitBox> createState() => _CommitBoxState();
}

class _CommitBoxState extends State<_CommitBox> {
  final _summary = TextEditingController();
  final _description = TextEditingController();

  @override
  void initState() {
    super.initState();
    _summary.text = widget.state.commitSummary;
    _description.text = widget.state.commitDescription;
  }

  @override
  void dispose() {
    _summary.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _cloudPatch(BuildContext context) async {
    final patch = await widget.state.git.workingPatch();
    if (!context.mounted) return;
    if (patch.trim().isEmpty) {
      notify(context, 'No tracked changes to share as a patch.',
          duration: const Duration(seconds: 2));
      return;
    }
    await Clipboard.setData(ClipboardData(text: patch));
    if (!context.mounted) return;
    notify(context, 'Cloud Patch copied to clipboard',
        icon: Icons.cloud_done_outlined,
        iconColor: AppColors.green,
        duration: const Duration(seconds: 2));
  }

  SpellCheckConfiguration? _spell(bool enabled) => enabled
      ? SpellCheckConfiguration(spellCheckService: DefaultSpellCheckService())
      : null;

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final spell = _spell(context.watch<SettingsState>().enableSpellChecking);
    final remaining = 72 - _summary.text.length;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.adjust, size: 14, color: AppColors.textSecondary),
              const SizedBox(width: 6),
              Text('Commit',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary)),
              const Spacer(),
              IconAction(
                icon: Icons.download,
                tooltip: 'Stash',
                color: state.totalChanges > 0
                    ? AppColors.textSecondary
                    : AppColors.textMuted,
                onTap: state.totalChanges > 0 && !state.busy
                    ? () => runRepoAction(context, state.stashPush,
                        success: 'Changes stashed')
                    : null,
              ),
              IconAction(
                icon: Icons.cloud_outlined,
                tooltip: 'Cloud Patch',
                color: state.totalChanges > 0
                    ? AppColors.textSecondary
                    : AppColors.textMuted,
                onTap: state.totalChanges > 0 ? () => _cloudPatch(context) : null,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: Checkbox(
                  value: state.amend,
                  onChanged: (v) => state.setAmend(v ?? false),
                  side: BorderSide(color: AppColors.border),
                ),
              ),
              const SizedBox(width: 8),
              Text('Amend previous commit',
                  style: TextStyle(
                      fontSize: 12.5, color: AppColors.textSecondary)),
            ],
          ),
          const SizedBox(height: 8),
          Stack(
            children: [
              TextField(
                controller: _summary,
                spellCheckConfiguration: spell,
                onChanged: (v) {
                  state.setCommitSummary(v);
                  setState(() {});
                },
                decoration: const InputDecoration(hintText: 'Commit summary'),
              ),
              Positioned(
                right: 8,
                top: 10,
                child: Text('$remaining',
                    style: TextStyle(
                        fontSize: 11,
                        color: remaining < 0
                            ? AppColors.red
                            : AppColors.textMuted)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _description,
            spellCheckConfiguration: spell,
            onChanged: state.setCommitDescription,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(hintText: 'Description'),
          ),
          const SizedBox(height: 12),
          GradientButton(
            onPressed: state.canCommit
                ? () => runRepoAction(context, state.doCommit,
                    success: 'Commit created')
                : null,
            child: Text(
              state.staged.isEmpty
                  ? 'Stage Changes to Commit'
                  : 'Commit ${state.staged.length} file(s)'
                      '${state.currentBranch.isNotEmpty ? " to ${state.currentBranch}" : ""}',
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------- commit details ---
class _CommitDetails extends StatefulWidget {
  final GitCommit? commit;
  const _CommitDetails({required this.commit});

  @override
  State<_CommitDetails> createState() => _CommitDetailsState();
}

class _CommitDetailsState extends State<_CommitDetails> {
  bool _editing = false;
  final _subject = TextEditingController();
  final _description = TextEditingController();

  @override
  void didUpdateWidget(_CommitDetails old) {
    super.didUpdateWidget(old);
    // Leave edit mode when a different commit is selected.
    if (old.commit?.hash != widget.commit?.hash) _editing = false;
  }

  @override
  void dispose() {
    _subject.dispose();
    _description.dispose();
    super.dispose();
  }

  void _startEdit(GitCommit c) {
    _subject.text = c.subject;
    _description.text = c.body;
    setState(() => _editing = true);
  }

  Future<void> _submit(BuildContext context, GitCommit c) async {
    final state = context.read<RepoState>();
    await runRepoAction(
      context,
      () => state.editCommitMessage(c.hash, _subject.text, _description.text),
      success: 'Commit message updated',
    );
    if (mounted) setState(() => _editing = false);
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.commit;
    if (c == null) {
      return Center(
        child: Text('Select a commit',
            style: TextStyle(color: AppColors.textMuted)),
      );
    }
    final state = context.read<RepoState>();
    final settings = context.watch<SettingsState>();
    DateFormat wordFmt;
    try {
      wordFmt = DateFormat(settings.dateWordFormat, settings.effectiveLocale);
    } catch (_) {
      wordFmt = DateFormat('EEE, MMM d yyyy • h:mm a', settings.effectiveLocale);
    }
    final showBody =
        settings.commitDescriptionVisibility != DescriptionVisibility.never;
    // Stashes/WIP nodes aren't editable commits.
    final editable = !c.isStash;
    return SingleChildScrollView(
      child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_editing)
                _editor(context, c)
              else ...[
                _MessageDisplay(
                  text: c.subject,
                  style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary),
                  editable: editable,
                  onEdit: () => _startEdit(c),
                ),
                if (c.body.isNotEmpty && showBody) ...[
                  const SizedBox(height: 8),
                  _MessageDisplay(
                    text: c.body,
                    style: TextStyle(
                        fontSize: 12.5,
                        height: 1.4,
                        color: AppColors.textSecondary),
                    editable: editable,
                    onEdit: () => _startEdit(c),
                  ),
                ],
              ],
              const SizedBox(height: 14),
              Row(
                children: [
                  AuthorAvatar(
                    name: c.author,
                    email: c.authorEmail,
                    size: 26,
                    fallbackColor: context
                        .read<AppState>()
                        .colorForAuthor(c.author, c.authorEmail),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(c.author,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 12.5, color: AppColors.textPrimary)),
                  ),
                  if (c.authorEmail.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(c.authorEmail,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 12, color: AppColors.textMuted)),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 6),
              _detail(Icons.schedule, wordFmt.format(c.date), null),
              const SizedBox(height: 6),
              _detail(Icons.tag, c.shortHash, c.isMerge ? 'merge commit' : null),
            ],
          ),
        ),
        const Divider(height: 1),
        FutureBuilder<List<FileChange>>(
          future: state.git.commitFiles(c.hash),
          builder: (context, snap) {
            if (!snap.hasData) {
              return const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(
                      child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))));
            }
            return _CommitFiles(files: snap.data!, commitHash: c.hash);
          },
        ),
      ],
      ),
    );
  }

  Widget _editor(BuildContext context, GitCommit c) {
    final canSave = _subject.text.trim().isNotEmpty && !context.read<RepoState>().busy;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _subject,
          onChanged: (_) => setState(() {}),
          style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary),
          decoration: const InputDecoration(hintText: 'Summary'),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _description,
          minLines: 3,
          maxLines: 8,
          style: TextStyle(fontSize: 12.5, color: AppColors.textPrimary),
          decoration: const InputDecoration(hintText: 'Description'),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            FilledButton(
              onPressed: canSave ? () => _submit(context, c) : null,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.accent,
                disabledBackgroundColor: AppColors.surfaceRaised,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              ),
              child: const Text('Update Message', style: TextStyle(fontSize: 12.5)),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: () => setState(() => _editing = false),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.red,
                side: BorderSide(color: AppColors.red.withValues(alpha: 0.6)),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              ),
              child: const Text('Cancel', style: TextStyle(fontSize: 12.5)),
            ),
          ],
        ),
      ],
    );
  }

  Widget _detail(IconData icon, String main, String? sub) {
    return Row(
      children: [
        Icon(icon, size: 14, color: AppColors.textMuted),
        const SizedBox(width: 8),
        Flexible(
          child: Text(main,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 12.5, color: AppColors.textPrimary)),
        ),
        if (sub != null) ...[
          const SizedBox(width: 6),
          Flexible(
            child: Text(sub,
                overflow: TextOverflow.ellipsis,
                style:
                    TextStyle(fontSize: 12, color: AppColors.textMuted)),
          ),
        ],
      ],
    );
  }
}

/// Commit subject/description text that reveals an edit affordance on hover and
/// enters edit mode when clicked (used in the commit details panel).
class _MessageDisplay extends StatefulWidget {
  final String text;
  final TextStyle style;
  final bool editable;
  final VoidCallback onEdit;
  const _MessageDisplay({
    required this.text,
    required this.style,
    required this.editable,
    required this.onEdit,
  });

  @override
  State<_MessageDisplay> createState() => _MessageDisplayState();
}

class _MessageDisplayState extends State<_MessageDisplay> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final content = Text(widget.text, style: widget.style);
    if (!widget.editable) return content;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Tooltip(
        message: 'Click to edit message',
        waitDuration: const Duration(milliseconds: 500),
        child: GestureDetector(
          onTap: widget.onEdit,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 4),
            decoration: BoxDecoration(
              color: _hover ? AppColors.surfaceRaised : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: content),
                if (_hover) ...[
                  const SizedBox(width: 6),
                  Icon(Icons.edit_outlined,
                      size: 13, color: AppColors.textMuted),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Status colour for a file change (shared by working + commit views).
Color _changeColor(ChangeType t) {
  switch (t) {
    case ChangeType.added:
    case ChangeType.untracked:
      return AppColors.green;
    case ChangeType.deleted:
      return AppColors.red;
    case ChangeType.renamed:
      return AppColors.accent;
    case ChangeType.conflicted:
    case ChangeType.modified:
      return AppColors.amber;
  }
}

/// The files-changed browser shown in the commit details panel: a count
/// header, a Path/Tree toggle and sort control, then either a flat path list
/// or a collapsible directory tree (with per-folder counts and expand/collapse
/// all).
class _CommitFiles extends StatefulWidget {
  final List<FileChange> files;
  final String commitHash;
  const _CommitFiles({required this.files, required this.commitHash});

  @override
  State<_CommitFiles> createState() => _CommitFilesState();
}

class _CommitFilesState extends State<_CommitFiles> {
  final Set<String> _collapsed = {}; // collapsed folder paths (default expanded)
  bool _descending = false;

  int _cmp(String a, String b) {
    final r = a.toLowerCase().compareTo(b.toLowerCase());
    return _descending ? -r : r;
  }

  @override
  Widget build(BuildContext context) {
    final files = widget.files;
    if (files.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Text('No file changes',
            style: TextStyle(fontSize: 12.5, color: AppColors.textMuted)),
      );
    }
    final state = context.watch<RepoState>();
    final tree = state.treeView;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 12, 6),
          child: Row(
            children: [
              Icon(Icons.edit, size: 13, color: AppColors.amber),
              const SizedBox(width: 6),
              Text('${files.length} file${files.length == 1 ? '' : 's'} changed',
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary)),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 12, 8),
          child: Row(
            children: [
              Tooltip(
                message: _descending ? 'Sort Z→A' : 'Sort A→Z',
                child: InkWell(
                  onTap: () => setState(() => _descending = !_descending),
                  borderRadius: BorderRadius.circular(4),
                  child: Padding(
                    padding: const EdgeInsets.all(2),
                    child: Icon(Icons.swap_vert,
                        size: 16, color: AppColors.textMuted),
                  ),
                ),
              ),
              const Spacer(),
              _ToggleChip(
                icon: Icons.list,
                label: 'Path',
                active: !tree,
                onTap: () => state.setTreeView(false),
              ),
              const SizedBox(width: 6),
              _ToggleChip(
                icon: Icons.account_tree_outlined,
                label: 'Tree',
                active: tree,
                onTap: () => state.setTreeView(true),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        if (tree) ..._treeChildren(files) else ..._pathChildren(files),
        const SizedBox(height: 8),
      ],
    );
  }

  // ---- path (flat) view ----
  List<Widget> _pathChildren(List<FileChange> files) {
    final sorted = [...files]..sort((a, b) => _cmp(a.path, b.path));
    return [
      for (final f in sorted)
        _CommitFileRow(
            file: f, label: f.path, commitHash: widget.commitHash)
    ];
  }

  // ---- tree view ----
  _Folder _buildTree(List<FileChange> files) {
    final root = _Folder('');
    for (final f in files) {
      final parts = f.path.split('/');
      var node = root;
      for (var i = 0; i < parts.length - 1; i++) {
        final seg = parts[i];
        final childPath = node.path.isEmpty ? seg : '${node.path}/$seg';
        node = node.dirs.putIfAbsent(seg, () => _Folder(childPath));
      }
      node.files.add(f);
    }
    return root;
  }

  void _collectFolders(_Folder f, Set<String> out) {
    for (final d in f.dirs.values) {
      out.add(d.path);
      _collectFolders(d, out);
    }
  }

  List<Widget> _treeChildren(List<FileChange> files) {
    final root = _buildTree(files);
    final all = <String>{};
    _collectFolders(root, all);
    final allExpanded = all.isNotEmpty && _collapsed.isEmpty;
    final widgets = <Widget>[];
    if (all.isNotEmpty) {
      widgets.add(Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 10, 4),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: () => setState(() {
              if (allExpanded) {
                _collapsed.addAll(all);
              } else {
                _collapsed.clear();
              }
            }),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(allExpanded ? 'Collapse All' : 'Expand All',
                  style:
                      TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            ),
          ),
        ),
      ));
    }
    widgets.addAll(_renderDir(root, 0));
    return widgets;
  }

  List<Widget> _renderDir(_Folder folder, int depth) {
    final out = <Widget>[];
    final dirNames = folder.dirs.keys.toList()..sort(_cmp);
    for (final name in dirNames) {
      final d = folder.dirs[name]!;
      final expanded = !_collapsed.contains(d.path);
      out.add(_folderRow(d, depth, expanded));
      if (expanded) out.addAll(_renderDir(d, depth + 1));
    }
    final files = [...folder.files]..sort((a, b) => _cmp(a.fileName, b.fileName));
    for (final f in files) {
      out.add(_CommitFileRow(
          file: f,
          label: f.fileName,
          commitHash: widget.commitHash,
          indent: depth * 16.0));
    }
    return out;
  }

  Widget _folderRow(_Folder d, int depth, bool expanded) {
    return InkWell(
      onTap: () => setState(
          () => expanded ? _collapsed.add(d.path) : _collapsed.remove(d.path)),
      hoverColor: AppColors.surfaceRaised,
      child: Padding(
        padding: EdgeInsets.fromLTRB(14 + depth * 16.0, 4, 12, 4),
        child: Row(
          children: [
            Icon(expanded ? Icons.expand_more : Icons.chevron_right,
                size: 16, color: AppColors.textMuted),
            const SizedBox(width: 2),
            Icon(expanded ? Icons.folder_open : Icons.folder_outlined,
                size: 13, color: AppColors.accentTeal),
            const SizedBox(width: 7),
            Expanded(
              child: Text(d.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
            ),
            const SizedBox(width: 6),
            Icon(Icons.edit, size: 12, color: AppColors.amber),
            const SizedBox(width: 4),
            Text('${d.count}',
                style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
          ],
        ),
      ),
    );
  }
}

/// A file row in the commit files browser (status letter + name). Clicking it
/// opens the file's diff/content as of that commit.
class _CommitFileRow extends StatefulWidget {
  final FileChange file;
  final String label;
  final String commitHash;
  final double indent;
  const _CommitFileRow(
      {required this.file,
      required this.label,
      required this.commitHash,
      this.indent = 0});

  @override
  State<_CommitFileRow> createState() => _CommitFileRowState();
}

class _CommitFileRowState extends State<_CommitFileRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<RepoState>();
    final color = _changeColor(widget.file.type);
    final isOpen = state.openFileIsHistorical &&
        state.openFileCommit == widget.commitHash &&
        state.openFile?.path == widget.file.path;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: () =>
            state.openCommitFile(widget.commitHash, widget.file),
        child: Container(
          color: isOpen
              ? AppColors.selectionRow
              : (_hover ? AppColors.surfaceRaised : Colors.transparent),
          padding: EdgeInsets.fromLTRB(14 + widget.indent, 4, 12, 4),
          child: Row(
            children: [
              Icon(Icons.insert_drive_file_outlined, size: 14, color: color),
              const SizedBox(width: 7),
              Expanded(
                child: TruncatedText(
                  widget.label,
                  tooltipText: widget.file.path,
                  style:
                      TextStyle(fontSize: 12.5, color: AppColors.textPrimary),
                ),
              ),
              const SizedBox(width: 6),
              Text(widget.file.statusLetter,
                  style: TextStyle(
                      fontSize: 11, fontWeight: FontWeight.bold, color: color)),
            ],
          ),
        ),
      ),
    );
  }
}
