import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/file_change.dart';
import '../../models/git_commit.dart';
import '../../services/diff_parser.dart';
import '../../services/git_service.dart';
import '../../state/repo_state.dart';
import '../../theme/app_theme.dart';
import '../widgets/common.dart';
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
            child: switch (state.fileAux) {
              FileAux.blame => _BlameContent(state: state),
              FileAux.history => _HistoryContent(state: state),
              FileAux.none => state.editing
                  ? _Editor(state: state)
                  : state.fileViewMode == FileViewMode.file
                      ? _FileContent(state: state)
                      : _DiffContent(state: state, file: file),
            },
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
          if (!state.openFileReadOnly && !file.staged)
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
    // A file viewed as of a commit or in compare mode is read-only: no
    // edit/stage/unstaged toggle.
    final historical = state.openFileReadOnly;

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
    // Unified vs side-by-side, only meaningful in the (unified) diff view.
    final splitToggle = _Segmented(
      options: const ['Unified', 'Split'],
      selected: state.diffSplit ? 1 : 0,
      onSelect: (i) => state.setDiffSplit(i == 1),
    );
    final showSplit = state.fileAux == FileAux.none &&
        !state.editing &&
        state.fileViewMode == FileViewMode.diff;
    final ignoreWs = _GhostBtn('Ignore whitespace',
        () => state.setDiffIgnoreWhitespace(!state.diffIgnoreWhitespace),
        active: state.diffIgnoreWhitespace);
    final blame = _GhostBtn('Blame',
        () => state.setFileAux(
            state.fileAux == FileAux.blame ? FileAux.none : FileAux.blame),
        active: state.fileAux == FileAux.blame);
    final history = _GhostBtn('History',
        () => state.setFileAux(
            state.fileAux == FileAux.history ? FileAux.none : FileAux.history),
        active: state.fileAux == FileAux.history);

    return Container(
      height: 38,
      color: AppColors.surface,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: LayoutBuilder(builder: (context, c) {
        final wide = c.maxWidth >= 720;
        final children = <Widget>[
          if (!historical) ...[edit, wide ? const Spacer() : const SizedBox(width: 12)],
          if (!historical) ...[
            stagedToggle,
            const SizedBox(width: 10),
          ],
          modeToggle,
          if (showSplit) ...[
            const SizedBox(width: 10),
            splitToggle,
            const SizedBox(width: 4),
            ignoreWs,
          ],
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
}

// ----------------------------------------------------------------- diff ------

/// The changed character span in a pair of (old, new) lines, computed with a
/// cheap common-prefix/suffix heuristic. Returns the sub-range `[start,end)` to
/// highlight in [old] and in [nw]; a null range means that side is unchanged.
({int s, int e})? _spanFor(String s, int prefix, int suffix) {
  final end = s.length - suffix;
  return end > prefix ? (s: prefix, e: end) : null;
}

(({int s, int e})?, ({int s, int e})?) _intraline(String a, String b) {
  if (a == b) return (null, null);
  final minLen = a.length < b.length ? a.length : b.length;
  var p = 0;
  while (p < minLen && a.codeUnitAt(p) == b.codeUnitAt(p)) {
    p++;
  }
  var suf = 0;
  while (suf < minLen - p &&
      a.codeUnitAt(a.length - 1 - suf) == b.codeUnitAt(b.length - 1 - suf)) {
    suf++;
  }
  return (_spanFor(a, p, suf), _spanFor(b, p, suf));
}

/// Builds intraline highlight ranges keyed by line index for a hunk: pairs each
/// run of deletions with the following run of additions, line by line.
Map<int, ({int s, int e})> _hunkHighlights(List<DiffLine> lines) {
  final out = <int, ({int s, int e})>{};
  var i = 0;
  while (i < lines.length) {
    if (lines[i].type == DiffLineType.deletion) {
      final dStart = i;
      while (i < lines.length && lines[i].type == DiffLineType.deletion) {
        i++;
      }
      final dEnd = i;
      final aStart = i;
      while (i < lines.length && lines[i].type == DiffLineType.addition) {
        i++;
      }
      final aEnd = i;
      final pairs =
          (dEnd - dStart) < (aEnd - aStart) ? dEnd - dStart : aEnd - aStart;
      for (var k = 0; k < pairs; k++) {
        final (oldSpan, newSpan) =
            _intraline(lines[dStart + k].text, lines[aStart + k].text);
        if (oldSpan != null) out[dStart + k] = oldSpan;
        if (newSpan != null) out[aStart + k] = newSpan;
      }
    } else {
      i++;
    }
  }
  return out;
}

/// Renders code text with an optional highlighted [span] (changed characters).
Widget _codeText(String text, Color color, {({int s, int e})? span, Color? highlight}) {
  final t = text.isEmpty ? ' ' : text;
  if (span == null || highlight == null || span.e > t.length) {
    return Text(t, style: _mono.copyWith(color: color));
  }
  return Text.rich(TextSpan(
    style: _mono.copyWith(color: color),
    children: [
      TextSpan(text: t.substring(0, span.s)),
      TextSpan(
          text: t.substring(span.s, span.e),
          style: TextStyle(backgroundColor: highlight)),
      TextSpan(text: t.substring(span.e)),
    ],
  ));
}

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
          return _BinaryDiff(state: state, file: file);
        }
        if (diff.hunks.isEmpty) {
          return _Empty(
              text: state.viewStaged
                  ? 'No staged changes for this file.'
                  : 'No unstaged changes for this file.');
        }
        if (state.diffSplit) {
          // Split view wraps long lines (no horizontal scroll), so it uses a
          // plain vertical scroller rather than the two-axis _CodeScrollView.
          return _VerticalCode(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final hunk in diff.hunks) _SplitHunk(hunk: hunk),
              ],
            ),
          );
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

class _HunkWidget extends StatefulWidget {
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
  State<_HunkWidget> createState() => _HunkWidgetState();
}

class _HunkWidgetState extends State<_HunkWidget> {
  /// Indices (into hunk.lines) the user has selected for line-level staging.
  final Set<int> _selected = {};

  void _toggle(int i) => setState(() {
        _selected.contains(i) ? _selected.remove(i) : _selected.add(i);
      });

  bool _selectable(DiffLine l) =>
      l.type == DiffLineType.addition || l.type == DiffLineType.deletion;

  Future<void> _act(Future<void> Function() action, String msg) async {
    await runRepoAction(context, action, success: msg);
    if (mounted) setState(_selected.clear);
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final diff = widget.diff;
    final hunk = widget.hunk;
    // A whitespace-ignored diff isn't a faithful patch, so staging from it is
    // disabled while "Ignore whitespace" is on.
    final canStageHunks = !state.openFileReadOnly &&
        !state.diffIgnoreWhitespace &&
        widget.file.type != ChangeType.untracked &&
        hunk.rawText.isNotEmpty;
    final highlights = _hunkHighlights(hunk.lines);
    final hasSel = _selected.isNotEmpty;
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
                if (hasSel) ...[
                  // Line-level actions (act on the selected lines only).
                  _HunkBtn(
                    label: '${!state.viewStaged ? "Stage" : "Unstage"} '
                        '${_selected.length} line(s)',
                    icon: !state.viewStaged ? Icons.add : Icons.remove,
                    color:
                        !state.viewStaged ? AppColors.green : AppColors.amber,
                    onTap: () => _act(
                        () => !state.viewStaged
                            ? state.stageLines(diff, hunk, _selected)
                            : state.unstageLines(diff, hunk, _selected),
                        '${!state.viewStaged ? "Staged" : "Unstaged"} '
                            '${_selected.length} line(s)'),
                  ),
                  if (!state.viewStaged) ...[
                    const SizedBox(width: 6),
                    _HunkBtn(
                      label: 'Discard ${_selected.length} line(s)',
                      icon: Icons.undo,
                      color: AppColors.red,
                      onTap: () => _act(
                          () => state.discardLines(diff, hunk, _selected),
                          'Discarded ${_selected.length} line(s)'),
                    ),
                  ],
                  const SizedBox(width: 6),
                  _HunkBtn(
                    label: 'Clear',
                    icon: Icons.close,
                    color: AppColors.textMuted,
                    onTap: () => setState(_selected.clear),
                  ),
                ] else if (!state.viewStaged) ...[
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
        for (var i = 0; i < hunk.lines.length; i++)
          _DiffLineRow(
            line: hunk.lines[i],
            highlight: highlights[i],
            selected: _selected.contains(i),
            onToggle: canStageHunks && _selectable(hunk.lines[i])
                ? () => _toggle(i)
                : null,
          ),
      ],
    );
  }
}

class _DiffLineRow extends StatelessWidget {
  final DiffLine line;

  /// The changed character range within [line], if any (word-level diff).
  final ({int s, int e})? highlight;

  /// Whether this line is picked for line-level staging.
  final bool selected;

  /// Toggles line-level selection (null when the line isn't selectable).
  final VoidCallback? onToggle;
  const _DiffLineRow({
    required this.line,
    this.highlight,
    this.selected = false,
    this.onToggle,
  });

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
    // Clicking the (non-selectable) gutter toggles line-level selection.
    final gutter = SelectionContainer.disabled(
      child: MouseRegion(
        cursor: onToggle != null
            ? SystemMouseCursors.click
            : MouseCursor.defer,
        child: GestureDetector(
          onTap: onToggle,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 3,
                child: selected
                    ? Container(color: AppColors.accent)
                    : const SizedBox.shrink(),
              ),
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
      ),
    );
    return Container(
      color: selected ? AppColors.accent.withValues(alpha: 0.14) : bg,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          gutter,
          Padding(
            padding: const EdgeInsets.only(right: 24),
            child: _codeText(
              line.text,
              AppColors.textPrimary,
              span: highlight,
              highlight: line.type == DiffLineType.addition
                  ? AppColors.green.withValues(alpha: 0.30)
                  : line.type == DiffLineType.deletion
                      ? AppColors.red.withValues(alpha: 0.30)
                      : null,
            ),
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

/// A vertical-only scroll region with selectable text (used by the split diff,
/// which wraps long lines instead of scrolling horizontally).
class _VerticalCode extends StatefulWidget {
  final Widget child;
  const _VerticalCode({required this.child});
  @override
  State<_VerticalCode> createState() => _VerticalCodeState();
}

class _VerticalCodeState extends State<_VerticalCode> {
  final _v = ScrollController();
  @override
  void dispose() {
    _v.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scrollbar(
      controller: _v,
      thumbVisibility: true,
      child: SingleChildScrollView(
        controller: _v,
        child: SelectionArea(child: widget.child),
      ),
    );
  }
}

// -------------------------------------------------------- side-by-side diff ---
class _SplitHunk extends StatelessWidget {
  final DiffHunk hunk;
  const _SplitHunk({required this.hunk});

  @override
  Widget build(BuildContext context) {
    // Build aligned (old, new) row pairs from the unified hunk.
    final rows = <(DiffLine?, DiffLine?, ({int s, int e})?, ({int s, int e})?)>[];
    final lines = hunk.lines;
    var i = 0;
    while (i < lines.length) {
      final t = lines[i].type;
      if (t == DiffLineType.meta) {
        i++;
        continue;
      }
      if (t == DiffLineType.context) {
        rows.add((lines[i], lines[i], null, null));
        i++;
        continue;
      }
      final dels = <DiffLine>[];
      while (i < lines.length && lines[i].type == DiffLineType.deletion) {
        dels.add(lines[i]);
        i++;
      }
      final adds = <DiffLine>[];
      while (i < lines.length && lines[i].type == DiffLineType.addition) {
        adds.add(lines[i]);
        i++;
      }
      final n = dels.length > adds.length ? dels.length : adds.length;
      for (var k = 0; k < n; k++) {
        final d = k < dels.length ? dels[k] : null;
        final a = k < adds.length ? adds[k] : null;
        ({int s, int e})? ds, asp;
        if (d != null && a != null) {
          final (o, nw) = _intraline(d.text, a.text);
          ds = o;
          asp = nw;
        }
        rows.add((d, a, ds, asp));
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SelectionContainer.disabled(
          child: Container(
            color: const Color(0xFF202733),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            child: Text(hunk.header,
                style:
                    _mono.copyWith(color: AppColors.accentTeal, fontSize: 12)),
          ),
        ),
        for (final r in rows)
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: _cell(r.$1, r.$3, isOld: true)),
                Container(width: 1, color: AppColors.border),
                Expanded(child: _cell(r.$2, r.$4, isOld: false)),
              ],
            ),
          ),
      ],
    );
  }

  Widget _cell(DiffLine? line, ({int s, int e})? span, {required bool isOld}) {
    if (line == null) {
      return const ColoredBox(color: Color(0x11000000), child: SizedBox.expand());
    }
    final changed = line.type != DiffLineType.context;
    final base = isOld ? AppColors.red : AppColors.green;
    return Container(
      color: changed ? base.withValues(alpha: 0.12) : Colors.transparent,
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectionContainer.disabled(
            child: Container(
              width: 40,
              padding: const EdgeInsets.only(right: 8),
              alignment: Alignment.topRight,
              child: Text('${(isOld ? line.oldNo : line.newNo) ?? ''}',
                  style: _mono.copyWith(
                      color: AppColors.textMuted, fontSize: 11.5)),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: _codeText(line.text, AppColors.textPrimary,
                span: changed ? span : null,
                highlight: changed ? base.withValues(alpha: 0.30) : null),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------- binary/image ---
class _BinaryDiff extends StatelessWidget {
  final RepoState state;
  final FileChange file;
  const _BinaryDiff({required this.state, required this.file});

  static const _imageExts = {
    'png', 'jpg', 'jpeg', 'gif', 'bmp', 'webp', 'ico'
  };

  @override
  Widget build(BuildContext context) {
    final ext = file.path.contains('.')
        ? file.path.split('.').last.toLowerCase()
        : '';
    // Preview the working-tree image (the common "I changed an image" case).
    if (!state.openFileIsHistorical && _imageExts.contains(ext)) {
      final abs = '${state.repo.path}${Platform.pathSeparator}'
          '${file.path.replaceAll('/', Platform.pathSeparator)}';
      final f = File(abs);
      if (f.existsSync()) {
        return Container(
          color: AppColors.background,
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Text('Image preview (working tree)',
                  style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
              const SizedBox(height: 12),
              Expanded(
                child: InteractiveViewer(
                  child: Image.file(f, fit: BoxFit.contain,
                      errorBuilder: (_, _, _) =>
                          const _Empty(text: 'Could not render image.')),
                ),
              ),
            ],
          ),
        );
      }
    }
    return _Empty(
        text: ext.isEmpty
            ? 'Binary file — no text diff to show.'
            : 'Binary (.$ext) file — no text diff to show.');
  }
}

// -------------------------------------------------------------------- blame ---
class _BlameContent extends StatelessWidget {
  final RepoState state;
  const _BlameContent({required this.state});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<BlameLine>>(
      future: state.loadBlame(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(
              child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2)));
        }
        final lines = snap.data!;
        if (lines.isEmpty) {
          return const _Empty(text: 'No blame information for this file.');
        }
        // Alternate a subtle background whenever the commit changes, so runs of
        // lines from the same commit read as one group.
        final shaded = List<bool>.filled(lines.length, false);
        var toggle = false;
        String? prev;
        for (var i = 0; i < lines.length; i++) {
          if (lines[i].sha != prev) {
            toggle = !toggle;
            prev = lines[i].sha;
          }
          shaded[i] = toggle;
        }
        return _CodeScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < lines.length; i++)
                _BlameRow(line: lines[i], shaded: shaded[i]),
            ],
          ),
        );
      },
    );
  }
}

class _BlameRow extends StatelessWidget {
  final BlameLine line;
  final bool shaded;
  const _BlameRow({required this.line, required this.shaded});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: shaded ? AppColors.surfaceRaised.withValues(alpha: 0.25) : null,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectionContainer.disabled(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Tooltip(
                  message:
                      '${line.shortSha}  ${line.author}\n${line.summary}',
                  child: Container(
                    width: 78,
                    padding: const EdgeInsets.only(left: 8, right: 8),
                    child: Text(line.shortSha,
                        overflow: TextOverflow.ellipsis,
                        style: _mono.copyWith(
                            color: AppColors.accentTeal, fontSize: 11.5)),
                  ),
                ),
                Container(
                  width: 120,
                  padding: const EdgeInsets.only(right: 10),
                  child: Text(line.author,
                      overflow: TextOverflow.ellipsis,
                      style: _mono.copyWith(
                          color: AppColors.textMuted, fontSize: 11.5)),
                ),
                Container(
                  width: _gutter,
                  padding: const EdgeInsets.only(right: 8),
                  alignment: Alignment.centerRight,
                  child: Text('${line.lineNo}',
                      style: _mono.copyWith(
                          color: AppColors.textMuted, fontSize: 11.5)),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Padding(
            padding: const EdgeInsets.only(right: 24),
            child: Text(line.content.isEmpty ? ' ' : line.content,
                style: _mono.copyWith(color: AppColors.textPrimary)),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------- file history ---
class _HistoryContent extends StatelessWidget {
  final RepoState state;
  const _HistoryContent({required this.state});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<GitCommit>>(
      future: state.loadFileHistory(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(
              child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2)));
        }
        final commits = snap.data!;
        if (commits.isEmpty) {
          return const _Empty(text: 'No history for this file.');
        }
        final fmt = DateFormat('yyyy-MM-dd HH:mm');
        return ListView.builder(
          itemCount: commits.length,
          itemBuilder: (context, i) {
            final c = commits[i];
            return InkWell(
              onTap: () {
                // Show this file as it was in the selected commit.
                final f = state.openFile;
                if (f != null) state.openCommitFile(c.hash, f);
              },
              child: Container(
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                        color: AppColors.border.withValues(alpha: 0.5)),
                  ),
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 62,
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(c.shortHash,
                          style: _mono.copyWith(
                              color: AppColors.accentTeal, fontSize: 11.5)),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(c.subject,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 13,
                                  color: AppColors.textPrimary)),
                          const SizedBox(height: 3),
                          Text('${c.author}  ·  ${fmt.format(c.date)}',
                              style: TextStyle(
                                  fontSize: 11.5, color: AppColors.textMuted)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
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
  final bool active;
  const _GhostBtn(this.label, this.onTap, {this.active = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          foregroundColor: active ? AppColors.accent : AppColors.textSecondary,
          backgroundColor:
              active ? AppColors.accent.withValues(alpha: 0.12) : null,
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
