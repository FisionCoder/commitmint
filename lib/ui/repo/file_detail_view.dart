import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/file_change.dart';
import '../../services/diff_parser.dart';
import '../../state/repo_state.dart';
import '../../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/notifier.dart';
import 'repo_actions.dart';

const _mono = TextStyle(
    fontFamily: 'Consolas',
    fontFamilyFallback: ['monospace'],
    fontSize: 12.5,
    height: 1.45);
const double _gutter = 46;

class FileDetailView extends StatelessWidget {
  const FileDetailView({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<RepoState>();
    final file = state.openFile;
    if (file == null) return const SizedBox.shrink();

    return Container(
      color: AppColors.surface,
      child: Column(
        children: [
          _Header(file: file),
          const Divider(height: 1),
          _SubToolbar(file: file),
          const Divider(height: 1),
          Expanded(
            child: state.editing
                ? _Editor(state: state)
                : state.fileViewMode == FileViewMode.file
                    ? _FileContent(state: state)
                    : _DiffContent(state: state, file: file),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final FileChange file;
  const _Header({required this.file});

  @override
  Widget build(BuildContext context) {
    final state = context.read<RepoState>();
    return Container(
      height: 38,
      color: AppColors.surface,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Icon(Icons.edit, size: 13, color: AppColors.amber),
          const SizedBox(width: 8),
          Expanded(
            child: Tooltip(
              message: file.path,
              child: RichText(
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
                text: TextSpan(
                  style: const TextStyle(fontSize: 13),
                  children: [
                    if (file.directory.isNotEmpty)
                      TextSpan(
                          text: '${file.directory}/',
                          style: TextStyle(color: AppColors.textMuted)),
                    TextSpan(
                        text: file.fileName,
                        style: TextStyle(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text('UTF-8',
              style: TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
          const SizedBox(width: 10),
          if (!state.openFileIsHistorical && !file.staged)
            _OutlineBtn(
              label: 'Stage File',
              color: AppColors.green,
              onTap: () => runRepoAction(context, state.stageOpenFile,
                  success: 'Staged ${file.fileName}'),
            ),
          IconAction(
            icon: Icons.close,
            tooltip: 'Close file',
            onTap: state.closeFileDetail,
          ),
        ],
      ),
    );
  }

}

class _SubToolbar extends StatelessWidget {
  final FileChange file;
  const _SubToolbar({required this.file});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<RepoState>();
    // A file viewed as of a commit is read-only: no edit/stage/unstaged toggle.
    final historical = state.openFileIsHistorical;

    final edit = _OutlineBtn(
      label: 'Edit This File',
      icon: Icons.edit_outlined,
      color: AppColors.accent,
      active: state.editing,
      onTap: () => state.setEditing(!state.editing),
    );
    final stagedToggle = _Segmented(
      options: const ['Unstaged', 'Staged'],
      selected: state.viewStaged ? 1 : 0,
      onSelect: (i) => state.setViewStaged(i == 1),
    );
    final modeToggle = _Segmented(
      options: const ['File View', 'Diff View'],
      selected: state.fileViewMode == FileViewMode.file ? 0 : 1,
      onSelect: (i) => state.setFileViewMode(
          i == 0 ? FileViewMode.file : FileViewMode.diff),
    );
    final blame = _GhostBtn('Blame', () => _notImpl(context, 'Blame'));
    final history = _GhostBtn('History', () => _notImpl(context, 'History'));

    return Container(
      height: 38,
      color: AppColors.surface,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: LayoutBuilder(builder: (context, c) {
        final wide = c.maxWidth >= 640;
        final children = <Widget>[
          if (!historical) ...[edit, wide ? const Spacer() : const SizedBox(width: 12)],
          if (!historical) ...[
            stagedToggle,
            const SizedBox(width: 10),
          ],
          modeToggle,
          wide ? const Spacer() : const SizedBox(width: 12),
          blame,
          history,
        ];
        final row = Row(children: children);
        if (wide) return row;
        return SingleChildScrollView(
            scrollDirection: Axis.horizontal, child: row);
      }),
    );
  }

  void _notImpl(BuildContext context, String what) {
    notify(context, '$what is not wired up in this build.');
  }
}

// ----------------------------------------------------------------- diff ------
class _DiffContent extends StatelessWidget {
  final RepoState state;
  final FileChange file;
  const _DiffContent({required this.state, required this.file});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<FileDiff>(
      future: state.loadOpenFileDiff(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(
              child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2)));
        }
        final diff = snap.data!;
        if (diff.isBinary) {
          return const _Empty(text: 'Binary file — no text diff to show.');
        }
        if (diff.hunks.isEmpty) {
          return _Empty(
              text: state.viewStaged
                  ? 'No staged changes for this file.'
                  : 'No unstaged changes for this file.');
        }
        return _CodeScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final hunk in diff.hunks)
                _HunkWidget(diff: diff, hunk: hunk, state: state, file: file),
            ],
          ),
        );
      },
    );
  }
}

/// A two-axis scroll region for code (diff / file / etc.): the content scrolls
/// both vertically and horizontally (so long lines aren't clipped — you can
/// scroll to see them), and text is selectable via [SelectionArea]. The child
/// is sized to its intrinsic width so row backgrounds span the full line width.
class _CodeScrollView extends StatefulWidget {
  final Widget child;
  const _CodeScrollView({required this.child});

  @override
  State<_CodeScrollView> createState() => _CodeScrollViewState();
}

class _CodeScrollViewState extends State<_CodeScrollView> {
  final _vertical = ScrollController();
  final _horizontal = ScrollController();

  @override
  void dispose() {
    _vertical.dispose();
    _horizontal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scrollbar(
      controller: _vertical,
      thumbVisibility: true,
      child: Scrollbar(
        controller: _horizontal,
        thumbVisibility: true,
        // Track the inner (horizontal, depth 1) scroll view rather than the
        // outer vertical one.
        notificationPredicate: (n) => n.depth == 1,
        child: SingleChildScrollView(
          controller: _vertical,
          child: SingleChildScrollView(
            controller: _horizontal,
            scrollDirection: Axis.horizontal,
            child: SelectionArea(
              child: IntrinsicWidth(child: widget.child),
            ),
          ),
        ),
      ),
    );
  }
}

class _HunkWidget extends StatelessWidget {
  final FileDiff diff;
  final DiffHunk hunk;
  final RepoState state;
  final FileChange file;
  const _HunkWidget({
    required this.diff,
    required this.hunk,
    required this.state,
    required this.file,
  });

  @override
  Widget build(BuildContext context) {
    final canStageHunks = !state.openFileIsHistorical &&
        file.type != ChangeType.untracked &&
        hunk.rawText.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Hunk header row. Content is clustered at the left so the hunk header
        // and its action buttons stay visible at the horizontal scroll origin.
        Container(
          color: const Color(0xFF202733),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SelectionContainer.disabled(
                child: Text(hunk.header,
                    style: _mono.copyWith(
                        color: AppColors.accentTeal, fontSize: 12)),
              ),
              if (canStageHunks) ...[
                const SizedBox(width: 12),
                if (!state.viewStaged) ...[
                  _HunkBtn(
                    label: 'Discard Hunk',
                    icon: Icons.undo,
                    color: AppColors.red,
                    onTap: () => runRepoAction(
                        context, () => state.discardHunk(diff, hunk),
                        success: 'Hunk discarded'),
                  ),
                  const SizedBox(width: 6),
                  _HunkBtn(
                    label: 'Stage Hunk',
                    icon: Icons.add,
                    color: AppColors.green,
                    onTap: () => runRepoAction(
                        context, () => state.stageHunk(diff, hunk),
                        success: 'Hunk staged'),
                  ),
                ] else
                  _HunkBtn(
                    label: 'Unstage Hunk',
                    icon: Icons.remove,
                    color: AppColors.amber,
                    onTap: () => runRepoAction(
                        context, () => state.unstageHunk(diff, hunk),
                        success: 'Hunk unstaged'),
                  ),
              ],
            ],
          ),
        ),
        for (final line in hunk.lines) _DiffLineRow(line: line),
      ],
    );
  }
}

class _DiffLineRow extends StatelessWidget {
  final DiffLine line;
  const _DiffLineRow({required this.line});

  @override
  Widget build(BuildContext context) {
    Color bg;
    Color signColor;
    String sign;
    switch (line.type) {
      case DiffLineType.addition:
        bg = AppColors.green.withValues(alpha: 0.12);
        signColor = AppColors.green;
        sign = '+';
        break;
      case DiffLineType.deletion:
        bg = AppColors.red.withValues(alpha: 0.12);
        signColor = AppColors.red;
        sign = '-';
        break;
      case DiffLineType.meta:
        bg = Colors.transparent;
        signColor = AppColors.textMuted;
        sign = '';
        break;
      case DiffLineType.context:
        bg = Colors.transparent;
        signColor = AppColors.textMuted;
        sign = '';
        break;
    }
    if (line.type == DiffLineType.meta) {
      return SelectionContainer.disabled(
        child: Container(
          color: bg,
          padding:
              const EdgeInsets.only(left: _gutter * 2 + 18, top: 1, bottom: 1),
          child: Text('\\ ${line.text}',
              style: _mono.copyWith(
                  color: AppColors.textMuted, fontStyle: FontStyle.italic)),
        ),
      );
    }
    return Container(
      color: bg,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Line numbers and the +/- sign are non-selectable so copying a
          // selection yields just the code text.
          SelectionContainer.disabled(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _num(line.oldNo),
                _num(line.newNo),
                SizedBox(
                  width: 18,
                  child: Text(sign,
                      textAlign: TextAlign.center,
                      style: _mono.copyWith(color: signColor)),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 24),
            child: Text(line.text.isEmpty ? ' ' : line.text,
                style: _mono.copyWith(color: AppColors.textPrimary)),
          ),
        ],
      ),
    );
  }

  Widget _num(int? n) => Container(
        width: _gutter,
        padding: const EdgeInsets.only(right: 8),
        alignment: Alignment.centerRight,
        child: Text(n?.toString() ?? '',
            style: _mono.copyWith(color: AppColors.textMuted, fontSize: 11.5)),
      );
}

// ----------------------------------------------------------- file view -------
class _FileContent extends StatelessWidget {
  final RepoState state;
  const _FileContent({required this.state});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: state.loadOpenFileContent(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(
              child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2)));
        }
        final lines = snap.data!.split('\n');
        return _CodeScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < lines.length; i++)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Line number is non-selectable so copying yields code only.
                    SelectionContainer.disabled(
                      child: Container(
                        width: _gutter,
                        padding: const EdgeInsets.only(right: 8),
                        alignment: Alignment.centerRight,
                        child: Text('${i + 1}',
                            style: _mono.copyWith(
                                color: AppColors.textMuted, fontSize: 11.5)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Padding(
                      padding: const EdgeInsets.only(right: 24),
                      child: Text(lines[i].isEmpty ? ' ' : lines[i],
                          style:
                              _mono.copyWith(color: AppColors.textPrimary)),
                    ),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }
}

// -------------------------------------------------------------- editor -------
class _Editor extends StatefulWidget {
  final RepoState state;
  const _Editor({required this.state});

  @override
  State<_Editor> createState() => _EditorState();
}

class _EditorState extends State<_Editor> {
  final _controller = TextEditingController();
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    widget.state.loadOpenFileContent().then((c) {
      if (mounted) {
        setState(() {
          _controller.text = c;
          _loaded = true;
        });
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const Center(
          child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2)));
    }
    return Column(
      children: [
        Expanded(
          child: Container(
            color: AppColors.background,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: TextField(
              controller: _controller,
              maxLines: null,
              expands: true,
              textAlignVertical: TextAlignVertical.top,
              style: _mono.copyWith(color: AppColors.textPrimary),
              decoration: const InputDecoration(
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            border: Border(top: BorderSide(color: AppColors.border)),
          ),
          padding: const EdgeInsets.all(10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => widget.state.setEditing(false),
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: () => runRepoAction(
                    context, () => widget.state.saveOpenFile(_controller.text),
                    success: 'File saved'),
                icon: const Icon(Icons.save, size: 16),
                label: const Text('Save'),
                style:
                    FilledButton.styleFrom(backgroundColor: AppColors.accent),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// --------------------------------------------------------- small widgets -----
class _Segmented extends StatelessWidget {
  final List<String> options;
  final int selected;
  final ValueChanged<int> onSelect;
  const _Segmented(
      {required this.options, required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.all(2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < options.length; i++)
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
              onTap: () => onSelect(i),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  color: selected == i ? AppColors.accent : Colors.transparent,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(options[i],
                    style: TextStyle(
                        fontSize: 12,
                        color: selected == i
                            ? Colors.white
                            : AppColors.textSecondary)),
              ),
            ),
            ),
        ],
      ),
    );
  }
}

class _OutlineBtn extends StatelessWidget {
  final String label;
  final IconData? icon;
  final Color color;
  final bool active;
  final VoidCallback onTap;
  const _OutlineBtn({
    required this.label,
    required this.color,
    required this.onTap,
    this.icon,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: icon == null
            ? const SizedBox.shrink()
            : Icon(icon, size: 13, color: color),
        label: Text(label, style: TextStyle(fontSize: 12, color: color)),
        style: OutlinedButton.styleFrom(
          backgroundColor: active ? color.withValues(alpha: 0.12) : null,
          side: BorderSide(color: color),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
    );
  }
}

class _HunkBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _HunkBtn({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(3),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: color.withValues(alpha: 0.6)),
          color: color.withValues(alpha: 0.12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(fontSize: 11.5, color: color)),
          ],
        ),
      ),
    );
  }
}

class _GhostBtn extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _GhostBtn(this.label, this.onTap);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          foregroundColor: AppColors.textSecondary,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          minimumSize: Size.zero,
        ),
        child: Text(label, style: const TextStyle(fontSize: 12.5)),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  final String text;
  const _Empty({required this.text});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(text,
          style: TextStyle(fontSize: 13, color: AppColors.textMuted)),
    );
  }
}
