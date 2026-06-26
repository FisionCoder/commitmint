import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/file_change.dart';
import '../../models/git_commit.dart';
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
            if (_hover) ...[
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
  final VoidCallback onTap;
  const _SmallButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.surfaceRaised,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: AppColors.border),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 11.5, color: AppColors.textSecondary)),
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
class _CommitDetails extends StatelessWidget {
  final GitCommit? commit;
  const _CommitDetails({required this.commit});

  @override
  Widget build(BuildContext context) {
    final c = commit;
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
    return SingleChildScrollView(
      child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(c.subject,
                  style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary)),
              if (c.body.isNotEmpty && showBody) ...[
                const SizedBox(height: 8),
                Text(c.body,
                    style: TextStyle(
                        fontSize: 12.5,
                        height: 1.4,
                        color: AppColors.textSecondary)),
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
            return _CommitFiles(files: snap.data!);
          },
        ),
      ],
      ),
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
  const _CommitFiles({required this.files});

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
    return [for (final f in sorted) _CommitFileRow(file: f, label: f.path)];
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
      out.add(_CommitFileRow(file: f, label: f.fileName, indent: depth * 16.0));
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

/// A read-only file row in the commit files browser (status letter + name).
class _CommitFileRow extends StatefulWidget {
  final FileChange file;
  final String label;
  final double indent;
  const _CommitFileRow(
      {required this.file, required this.label, this.indent = 0});

  @override
  State<_CommitFileRow> createState() => _CommitFileRowState();
}

class _CommitFileRowState extends State<_CommitFileRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final color = _changeColor(widget.file.type);
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Container(
        color: _hover ? AppColors.surfaceRaised : Colors.transparent,
        padding: EdgeInsets.fromLTRB(14 + widget.indent, 4, 12, 4),
        child: Row(
          children: [
            Icon(Icons.insert_drive_file_outlined, size: 14, color: color),
            const SizedBox(width: 7),
            Expanded(
              child: TruncatedText(
                widget.label,
                tooltipText: widget.file.path,
                style: TextStyle(fontSize: 12.5, color: AppColors.textPrimary),
              ),
            ),
            const SizedBox(width: 6),
            Text(widget.file.statusLetter,
                style: TextStyle(
                    fontSize: 11, fontWeight: FontWeight.bold, color: color)),
          ],
        ),
      ),
    );
  }
}
