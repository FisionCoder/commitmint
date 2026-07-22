import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/git_branch.dart';
import '../../models/git_commit.dart';
import '../../services/commit_graph.dart';
import '../../state/app_state.dart';
import '../../state/layout_state.dart';
import '../../state/repo_state.dart';
import '../../state/settings_state.dart';
import '../../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/mint_leaf.dart';
import '../widgets/profile_avatar.dart';
import 'commit_context_menu.dart';
import 'repo_actions.dart';
import 'sidebar_menus.dart';

const double _rowHeight = 28;
const double _minMessageWidth = 140;
const double _rowHPad = 12;
const double _trailingWidth = 24;
const double _cellLeftPad = 10; // left inset for column text (header + rows)
const double _authorColWidth = 156;
const double _shaColWidth = 86;

TextStyle get _monoSha => TextStyle(
    fontFamily: 'Consolas',
    fontFamilyFallback: const ['monospace'],
    fontSize: 11.5,
    color: AppColors.textMuted);

/// Geometry of the commit graph (normal vs compact).
class _GraphGeom {
  final double laneWidth, laneStart, avatarSize, dotRadius;
  const _GraphGeom(
      this.laneWidth, this.laneStart, this.avatarSize, this.dotRadius);
  double laneX(int lane) => laneStart + lane * laneWidth;
}

const _normalGeom = _GraphGeom(22, 16, 22, 4.5);
const _compactGeom = _GraphGeom(13, 9, 15, 3.5);

/// Computed per-build column layout, threaded into the rows.
class _GraphLayout {
  final LayoutState layout;
  final _GraphGeom geom;
  final double branchW, graphWidth, dateW, authorW, shaW;
  const _GraphLayout({
    required this.layout,
    required this.geom,
    required this.branchW,
    required this.graphWidth,
    required this.dateW,
    required this.authorW,
    required this.shaW,
  });
}

/// Lays out the visible columns in order, with the message column (or a spacer
/// when it is hidden) as the flexible filler.
List<Widget> _columns(
  _GraphLayout gl, {
  required Widget branch,
  required Widget graph,
  required Widget message,
  required Widget author,
  required Widget date,
  required Widget sha,
  required Widget trailing,
}) {
  final layout = gl.layout;
  return [
    if (layout.showBranch) SizedBox(width: gl.branchW, child: branch),
    if (layout.showGraph) SizedBox(width: gl.graphWidth, child: graph),
    if (layout.showMessage) Expanded(child: message) else const Spacer(),
    if (layout.showAuthor) SizedBox(width: gl.authorW, child: author),
    if (layout.showDate) SizedBox(width: gl.dateW, child: date),
    if (layout.showSha) SizedBox(width: gl.shaW, child: sha),
    trailing,
  ];
}

Color _laneColor(int colorIndex) =>
    AppColors.lanes[colorIndex % AppColors.lanes.length];

class CommitGraphView extends StatefulWidget {
  const CommitGraphView({super.key});

  @override
  State<CommitGraphView> createState() => _CommitGraphViewState();
}

class _CommitGraphViewState extends State<CommitGraphView> {
  final MenuController _menu = MenuController();
  final GlobalKey _anchorKey = GlobalKey();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  GitCommit? _menuCommit;

  /// Which menu the shared anchor shows: the trimmed commit menu, or the fuller
  /// branch menu (opened by right-clicking a branch pill). [_menuBranchRef] is
  /// the clicked branch's short name for the branch menu.
  bool _branchMenu = false;
  String? _menuBranchRef;

  @override
  void initState() {
    super.initState();
    // Repaint the search field border when focus enters/leaves it.
    _searchFocus.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _openMenu(GitCommit commit, Offset globalPosition) {
    // Stash (WIP) nodes get the dedicated stash menu, not the commit menu.
    if (commit.isStash) {
      final state = context.read<RepoState>();
      final ref = state.stashes.firstWhere(
        (s) => s.targetHash == commit.hash,
        orElse: () => GitRef(name: commit.subject, kind: RefKind.stash),
      );
      showStashContextMenu(
          context, state, ref, commit.stashIndex ?? 0, globalPosition);
      return;
    }
    setState(() {
      _menuCommit = commit;
      _branchMenu = false;
      _menuBranchRef = null;
    });
    _openAt(globalPosition);
  }

  /// Opens the branch menu for a right-clicked branch pill.
  void _openBranchMenu(String branchRef, GitCommit commit, Offset globalPosition) {
    setState(() {
      _menuCommit = commit;
      _branchMenu = true;
      _menuBranchRef = branchRef;
    });
    _openAt(globalPosition);
  }

  void _openAt(Offset globalPosition) {
    final box = _anchorKey.currentContext?.findRenderObject() as RenderBox?;
    final local = box?.globalToLocal(globalPosition) ?? globalPosition;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _menu.open(position: local);
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<RepoState>();
    final layout = context.watch<LayoutState>();

    if (state.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.loadError != null) {
      return _ErrorView(message: state.loadError!);
    }

    // If search was closed elsewhere (e.g. the toolbar toggle), reset the
    // field so reopening starts blank.
    if (!state.searchVisible && _searchController.text.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !context.read<RepoState>().searchVisible) {
          _searchController.clear();
        }
      });
    }

    final geom = layout.compactGraph ? _compactGeom : _normalGeom;
    final maxLane =
        state.graphRows.fold<int>(0, (m, r) => r.maxLane > m ? r.maxLane : m);
    final graphWidth = (geom.laneStart * 2 + maxLane * geom.laneWidth)
        .clamp(layout.compactGraph ? 40.0 : 90.0, 600.0);

    final body = LayoutBuilder(builder: (context, constraints) {
      // Hard (non-shrinkable) space: graph lanes + trailing gear + padding.
      final fixedHard =
          (layout.showGraph ? graphWidth : 0.0) + _trailingWidth + _rowHPad * 2;
      final budget =
          (constraints.maxWidth - fixedHard).clamp(0.0, double.infinity);
      // Reserve room for the message column, then let the fixed-text columns
      // (branch/date/author/sha) share what's left — shrinking proportionally
      // when cramped so the row never overflows.
      final msgReserve =
          layout.showMessage ? (budget < _minMessageWidth ? budget : _minMessageWidth) : 0.0;
      final shrinkBudget = (budget - msgReserve).clamp(0.0, double.infinity);

      var branchW = layout.showBranch ? layout.branchColWidth : 0.0;
      var dateW = layout.showDate ? layout.dateColWidth : 0.0;
      var authorW = layout.showAuthor ? _authorColWidth : 0.0;
      var shaW = layout.showSha ? _shaColWidth : 0.0;
      final shrinkables = branchW + dateW + authorW + shaW;
      if (shrinkables > shrinkBudget && shrinkables > 0) {
        final scale = shrinkBudget / shrinkables;
        branchW *= scale;
        dateW *= scale;
        authorW *= scale;
        shaW *= scale;
      }

      final gl = _GraphLayout(
          layout: layout,
          geom: geom,
          branchW: branchW,
          graphWidth: graphWidth,
          dateW: dateW,
          authorW: authorW,
          shaW: shaW);

      final branchBoundary = _rowHPad + branchW;
      final dateLeft = constraints.maxWidth -
          _rowHPad -
          _trailingWidth -
          shaW -
          dateW;

      // Static full-height separators between non-resizable columns, so each
      // column (e.g. Graph and Commit message) reads as its own column. The
      // branch and date boundaries instead carry interactive resize handles.
      final authorLeft = dateLeft - authorW;
      final shaLeft =
          constraints.maxWidth - _rowHPad - _trailingWidth - shaW;
      Widget divider(double left) => Positioned(
            left: left,
            top: 0,
            bottom: 0,
            child: Container(width: 1, color: AppColors.border),
          );

      return Column(
        children: [
          if (state.searchVisible) _searchBar(state),
          Expanded(
            child: Stack(children: [
          Column(
            children: [
              if (state.hasGraphFilter) _FilterBanner(state: state),
              _headerRow(gl),
              const Divider(height: 1),
              Expanded(
                child: state.hasCommitSearch && state.graphRows.isEmpty
                    ? const _NoResults()
                    : Builder(builder: (context) {
                        // The "// WIP" row is a working-tree pseudo-row, not a
                        // commit — hide it while a commit search is active.
                        final showWip = !state.hasCommitSearch;
                        final base = showWip ? 1 : 0;
                        return ListView.builder(
                          itemCount: state.graphRows.length + base,
                          itemExtent: _rowHeight,
                          itemBuilder: (context, index) {
                            if (showWip && index == 0) {
                              return _WipRow(gl: gl, state: state);
                            }
                            final rowIndex = index - base;
                            final row = state.graphRows[rowIndex];
                            return _CommitRow(
                              gl: gl,
                              row: row,
                              selected:
                                  state.selectedCommit?.hash == row.commit.hash,
                              alt: rowIndex.isOdd,
                              onTap: () => state.selectCommit(row.commit),
                              onContextMenu: _openMenu,
                              onBranchMenu: _openBranchMenu,
                              highlight: state.commitSearch,
                            );
                          },
                        );
                      }),
              ),
              if (!state.hasCommitSearch && state.mayHaveMoreCommits)
                _LoadMoreBar(state: state),
            ],
          ),
          // Separator after the Graph column (between Graph and the next column).
          if (layout.showGraph) divider(_rowHPad + branchW + graphWidth),
          if (layout.showAuthor) divider(authorLeft),
          if (layout.showSha) divider(shaLeft),
          // Full-height column resize handles for the resizable columns.
          if (layout.showBranch)
            Positioned(
              left: branchBoundary - 3,
              top: 0,
              bottom: 0,
              child: ResizeHandle(
                onDelta: (dx) =>
                    layout.setBranchColWidth(layout.branchColWidth + dx),
                onEnd: layout.persist,
              ),
            ),
          if (layout.showDate)
            Positioned(
              left: dateLeft - 3,
              top: 0,
              bottom: 0,
              child: ResizeHandle(
                onDelta: (dx) =>
                    layout.setDateColWidth(layout.dateColWidth - dx),
                onEnd: layout.persist,
              ),
            ),
          ]),
        ),
        ],
      );
    });

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyF, control: true):
            _toggleSearch,
        if (state.searchVisible)
          const SingleActivator(LogicalKeyboardKey.escape): () {
            _searchController.clear();
            context.read<RepoState>().closeSearch();
          },
      },
      child: Focus(
        autofocus: true,
        child: Container(
          color: AppColors.surface,
          // The MenuAnchor's anchor is kept to a zero-size point (top-left) so
          // a left-click anywhere over the graph body counts as "outside" the
          // menu and dismisses it. (If the body were the anchor child, taps on
          // it would be treated as inside the menu's tap region.)
          child: Stack(
            children: [
              body,
              MenuAnchor(
                controller: _menu,
                consumeOutsideTap: true,
                style: commitMenuStyle,
                menuChildren: _menuCommit == null
                    ? const <Widget>[]
                    : (_branchMenu && _menuBranchRef != null
                        ? buildBranchMenuChildren(context, state, _menuCommit!,
                            branchRef: _menuBranchRef!)
                        : buildCommitMenuChildren(context, state, _menuCommit!)),
                child: SizedBox.shrink(key: _anchorKey),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Toggles the search bar: dismiss it if showing, otherwise open and focus it.
  void _toggleSearch() {
    final state = context.read<RepoState>();
    if (state.searchVisible) {
      _searchController.clear();
      state.closeSearch();
      return;
    }
    state.openSearch();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _searchFocus.requestFocus();
      _searchController.selection = TextSelection(
          baseOffset: 0, extentOffset: _searchController.text.length);
    });
  }

  /// Slim search bar above the column headers. Filters the graph live to
  /// commits whose message, author, SHA or branch matches the query.
  Widget _searchBar(RepoState state) {
    final hasText = state.hasCommitSearch;
    final matches = state.searchMatchCount;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.borderSubtle)),
      ),
      padding: const EdgeInsets.fromLTRB(_rowHPad, 6, _rowHPad, 6),
      child: SizedBox(
        height: 30,
        // No nested box/border — the field sits flat inside the bar.
        child: Row(
          children: [
            Icon(Icons.search, size: 15, color: AppColors.textMuted),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _searchController,
                focusNode: _searchFocus,
                autofocus: true,
                style: TextStyle(
                    fontSize: 13, color: AppColors.textPrimary),
                cursorColor: AppColors.accent,
                decoration: InputDecoration.collapsed(
                  hintText: 'Search commits — message, author, SHA, branch',
                  hintStyle:
                      TextStyle(fontSize: 13, color: AppColors.textMuted),
                ),
                onChanged: state.setCommitSearch,
              ),
            ),
            if (hasText) ...[
              const SizedBox(width: 8),
              Text(
                matches == 0
                    ? 'No matches'
                    : '$matches match${matches == 1 ? '' : 'es'}',
                style: TextStyle(
                    fontSize: 11.5, color: AppColors.textMuted),
              ),
            ],
            const SizedBox(width: 6),
            InkWell(
              // Closes the search (clears the query and hides the bar).
              onTap: () {
                _searchController.clear();
                state.closeSearch();
              },
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: EdgeInsets.all(2),
                child:
                    Icon(Icons.close, size: 15, color: AppColors.textSecondary),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _headerRow(_GraphLayout gl) {
    Widget h(String t) => Padding(
          padding: const EdgeInsets.only(left: _cellLeftPad),
          child: Text(t,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 10.5,
                  letterSpacing: 0.7,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textMuted)),
        );
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.fromLTRB(_rowHPad, 3, _rowHPad, 3),
      child: Row(
        children: _columns(
          gl,
          branch: h('BRANCH / TAG'),
          graph: h('GRAPH'),
          message: h('COMMIT MESSAGE'),
          author: h('AUTHOR'),
          date: h('COMMIT DATE / TIME'),
          sha: h('SHA'),
          trailing: SizedBox(
            width: _trailingWidth,
            child: _ColumnSettingsButton(layout: gl.layout),
          ),
        ),
      ),
    );
  }
}

/// The gear button that opens the column-visibility / layout menu.
class _ColumnSettingsButton extends StatelessWidget {
  final LayoutState layout;
  const _ColumnSettingsButton({required this.layout});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Column settings',
      child: InkWell(
        onTapDown: (d) => _open(context, d.globalPosition),
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: EdgeInsets.all(4),
          child: Icon(Icons.settings, size: 14, color: AppColors.textSecondary),
        ),
      ),
    );
  }

  Future<void> _open(BuildContext context, Offset pos) async {
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    CheckedPopupMenuItem<String> check(
            String value, String label, bool checked) =>
        CheckedPopupMenuItem<String>(
          value: value,
          checked: checked,
          padding: EdgeInsets.zero,
          child: Text(label, style: const TextStyle(fontSize: 13.5)),
        );
    PopupMenuItem<String> plain(String value, String label) =>
        PopupMenuItem<String>(
          value: value,
          height: 38,
          child: Text(label, style: const TextStyle(fontSize: 13.5)),
        );

    final sel = await showMenu<String>(
      context: context,
      color: AppColors.surfaceRaised,
      position: RelativeRect.fromRect(
          pos & const Size(1, 1), Offset.zero & overlay.size),
      constraints: const BoxConstraints(minWidth: 250),
      items: [
        check('branch', 'Branch / Tag', layout.showBranch),
        check('graph', 'Graph', layout.showGraph),
        check('message', 'Commit message', layout.showMessage),
        check('author', 'Author', layout.showAuthor),
        check('date', 'Date / Time', layout.showDate),
        check('sha', 'Sha', layout.showSha),
        const PopupMenuDivider(),
        check('compact', 'Compact Graph Column', layout.compactGraph),
        check('smart', 'Smart Branch Visibility', layout.smartBranch),
        const PopupMenuDivider(),
        plain('reset_default', 'Reset columns to default layout'),
        plain('reset_compact', 'Reset columns to compact layout'),
      ],
    );
    switch (sel) {
      case 'branch':
        layout.toggleColumn(GraphColumn.branch);
        break;
      case 'graph':
        layout.toggleColumn(GraphColumn.graph);
        break;
      case 'message':
        layout.toggleColumn(GraphColumn.message);
        break;
      case 'author':
        layout.toggleColumn(GraphColumn.author);
        break;
      case 'date':
        layout.toggleColumn(GraphColumn.date);
        break;
      case 'sha':
        layout.toggleColumn(GraphColumn.sha);
        break;
      case 'compact':
        layout.setCompactGraph(!layout.compactGraph);
        break;
      case 'smart':
        layout.setSmartBranch(!layout.smartBranch);
        break;
      case 'reset_default':
        layout.resetColumnsToDefault();
        break;
      case 'reset_compact':
        layout.resetColumnsToCompact();
        break;
    }
  }
}

class _WipRow extends StatefulWidget {
  final _GraphLayout gl;
  final RepoState state;
  const _WipRow({required this.gl, required this.state});

  @override
  State<_WipRow> createState() => _WipRowState();
}

class _WipRowState extends State<_WipRow> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focus = FocusNode();

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _commit() async {
    final state = widget.state;
    final msg = _controller.text.trim();
    if (msg.isEmpty || state.totalChanges == 0 || state.busy) return;
    await runRepoAction(context, () => state.commitWip(msg),
        success: 'Commit created');
    _controller.clear();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final gl = widget.gl;
    final selected = state.selectingWip;
    final count = state.totalChanges;
    final canCommit = count > 0 && _controller.text.trim().isNotEmpty;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
      onTap: () => state.selectWip(),
      child: Container(
        color: selected ? AppColors.selectionRow : AppColors.surface,
        padding: const EdgeInsets.symmetric(horizontal: _rowHPad),
        child: Row(
          children: _columns(
            gl,
            branch: const SizedBox.shrink(),
            graph: _WipNode(geom: gl.geom, graphWidth: gl.graphWidth),
            message: Padding(
              padding: const EdgeInsets.only(left: _cellLeftPad),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      focusNode: _focus,
                      onTap: state.selectWip,
                      onChanged: (_) => setState(() {}),
                      onSubmitted: (_) => _commit(),
                      textInputAction: TextInputAction.done,
                      style: TextStyle(
                          fontSize: 13, color: AppColors.textPrimary),
                      cursorColor: AppColors.accent,
                      decoration: InputDecoration.collapsed(
                        hintText: count > 0
                            ? '// WIP — message + Enter to commit'
                            : '// WIP',
                        hintStyle: TextStyle(
                            fontSize: 13,
                            fontStyle: FontStyle.italic,
                            color: AppColors.textSecondary),
                      ),
                    ),
                  ),
                  if (canCommit) ...[
                    const SizedBox(width: 6),
                    Tooltip(
                      message: 'Commit $count file(s) (Enter)',
                      child: InkWell(
                        onTap: _commit,
                        borderRadius: BorderRadius.circular(4),
                        child: Padding(
                          padding: EdgeInsets.all(2),
                          child: Icon(Icons.check_circle,
                              size: 16, color: AppColors.green),
                        ),
                      ),
                    ),
                  ],
                  if (count > 0) ...[
                    const SizedBox(width: 8),
                    Icon(Icons.edit, size: 13, color: AppColors.amber),
                    const SizedBox(width: 4),
                    Text('$count',
                        style: TextStyle(
                            fontSize: 12, color: AppColors.textSecondary)),
                    const SizedBox(width: 8),
                  ],
                ],
              ),
            ),
            author: const SizedBox.shrink(),
            date: const SizedBox.shrink(),
            sha: const SizedBox.shrink(),
            trailing: const SizedBox(width: _trailingWidth),
          ),
        ),
      ),
      ),
    );
  }
}

class _CommitRow extends StatefulWidget {
  final _GraphLayout gl;
  final GraphRow row;
  final bool selected;
  final VoidCallback onTap;
  final void Function(GitCommit commit, Offset globalPosition) onContextMenu;

  /// Opens the branch menu for a right-clicked branch pill in this row.
  final void Function(String branchRef, GitCommit commit, Offset globalPosition)
      onBranchMenu;

  /// Active search query — matching spans in the message are highlighted.
  final String highlight;

  /// Odd rows get a faint tint for readability (zebra striping).
  final bool alt;

  const _CommitRow({
    required this.gl,
    required this.row,
    required this.selected,
    required this.onTap,
    required this.onContextMenu,
    required this.onBranchMenu,
    this.highlight = '',
    this.alt = false,
  });

  @override
  State<_CommitRow> createState() => _CommitRowState();
}

class _CommitRowState extends State<_CommitRow> {
  bool _hover = false;
  // The branch ref the cursor is currently over (set by branch pills in
  // _refLabels), so a right-click can open the branch menu instead of the
  // commit menu. Null when the cursor isn't over a branch pill.
  String? _hoverBranchRef;

  /// Builds a DateFormat from a user-supplied pattern + locale, falling back to
  /// a safe default if the pattern is invalid.
  static DateFormat _fmt(String pattern, String fallback, String? locale) {
    try {
      return DateFormat(pattern, locale);
    } catch (_) {
      return DateFormat(fallback, locale);
    }
  }

  /// Whether this row's commit carries the branch currently hovered in the
  /// sidebar (matching local/remote/HEAD ref forms).
  bool _isAssociated(GitCommit commit, String? branch) {
    if (branch == null) return false;
    return commit.refs.any((r) =>
        r == branch || r.endsWith('/$branch') || r == 'HEAD -> $branch');
  }

  @override
  Widget build(BuildContext context) {
    final gl = widget.gl;
    final commit = widget.row.commit;
    final settings = context.watch<SettingsState>();
    final repo = context.watch<RepoState>();
    final locale = settings.effectiveLocale;
    final dateFmt = _fmt(settings.dateTimeFormat, 'MM/dd/yyyy @ h:mm a', locale);
    final verboseFmt =
        _fmt(settings.dateVerboseFormat, 'EEEE, MMMM d, y · h:mm a', locale);
    final authorColor =
        context.read<AppState>().colorForAuthor(commit.author, commit.authorEmail);

    final associated = settings.highlightAssociatedRows &&
        _isAssociated(commit, repo.hoverBranch);
    final bg = widget.selected
        ? AppColors.selectionRow
        : (associated
            ? AppColors.selection
            : (_hover
                ? AppColors.surfaceRaised.withValues(alpha: 0.5)
                : (widget.alt
                    ? AppColors.surfaceRaised.withValues(alpha: 0.04)
                    : Colors.transparent)));

    // The full-height message cell. The "ghost" hover popover (gated by the UI
    // setting) is attached here only, so it appears solely over the commit
    // message column — not the whole row.
    Widget messageCell = SizedBox(
      height: _rowHeight,
      child: Align(
        alignment: Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.only(left: _cellLeftPad),
          child: _HighlightedText(
            commit.subject,
            widget.highlight,
            TextStyle(fontSize: 13, color: AppColors.textPrimary),
          ),
        ),
      ),
    );
    if (settings.showGhostHover) {
      messageCell = Tooltip(
        waitDuration: const Duration(milliseconds: 450),
        padding: const EdgeInsets.all(12),
        margin: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: AppColors.surfaceRaised,
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(6),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 14,
                offset: const Offset(0, 4)),
          ],
        ),
        richMessage: _commitTooltip(commit, authorColor),
        child: messageCell,
      );
    }

    final row = Container(
      margin: const EdgeInsets.symmetric(vertical: 1),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      padding: const EdgeInsets.symmetric(horizontal: _rowHPad),
      child: Row(
        children: _columns(
          gl,
              branch: Padding(
                padding: const EdgeInsets.only(left: _cellLeftPad),
                child: _refLabels(commit, gl,
                    (gl.branchW - _cellLeftPad).clamp(0.0, 420.0)),
              ),
              graph: Container(
                // Subtle wash of the commit's branch (lane) colour.
                color: _laneColor(widget.row.dotColor).withValues(alpha: 0.10),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _GraphRowPainter(widget.row, gl.geom),
                        size: Size(gl.graphWidth, _rowHeight),
                      ),
                    ),
                    Positioned(
                      left: gl.geom.laneX(widget.row.dotLane) -
                          gl.geom.avatarSize / 2,
                      top: (_rowHeight - gl.geom.avatarSize) / 2,
                      child: commit.isStash
                          ? _StashNode(
                              size: gl.geom.avatarSize,
                              color: _laneColor(widget.row.dotColor))
                          : AuthorAvatar(
                              name: commit.author,
                              email: commit.authorEmail,
                              size: gl.geom.avatarSize,
                              fallbackColor: authorColor,
                            ),
                    ),
                  ],
                ),
              ),
              message: messageCell,
              author: commit.isStash
                  ? const SizedBox.shrink()
                  : Padding(
                      padding: const EdgeInsets.only(left: _cellLeftPad),
                      child: Row(
                        children: [
                          AuthorAvatar(
                              name: commit.author,
                              email: commit.authorEmail,
                              size: 15,
                              fallbackColor: authorColor),
                          const SizedBox(width: 6),
                          Expanded(
                            child: TruncatedText(
                              commit.author,
                              style: TextStyle(
                                  fontSize: 12.5,
                                  color: AppColors.textSecondary),
                            ),
                          ),
                        ],
                      ),
                    ),
              date: Padding(
                padding: const EdgeInsets.only(left: _cellLeftPad),
                child: TruncatedText(
                  dateFmt.format(commit.date),
                  style: TextStyle(
                      fontSize: 12, color: AppColors.textMuted),
                  tooltipText: verboseFmt.format(commit.date),
                ),
              ),
              sha: commit.isStash
                  ? const SizedBox.shrink()
                  : Padding(
                      padding: const EdgeInsets.only(left: _cellLeftPad),
                      child: TruncatedText(commit.shortHash,
                          style: _monoSha, tooltipText: commit.hash),
                    ),
              trailing: const SizedBox(width: _trailingWidth),
            ),
          ),
        );

    final interactive = MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        onSecondaryTapDown: (details) {
          widget.onTap();
          final branchRef = _hoverBranchRef;
          if (branchRef != null) {
            widget.onBranchMenu(branchRef, commit, details.globalPosition);
          } else {
            widget.onContextMenu(commit, details.globalPosition);
          }
        },
        child: row,
      ),
    );
    return interactive;
  }

  /// Hover block: the full commit subject, body and author/sha/date header.
  InlineSpan _commitTooltip(GitCommit commit, Color authorColor) {
    final dateFmt = DateFormat('EEE, MMM d yyyy · h:mm a');
    return TextSpan(children: [
      WidgetSpan(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(commit.subject,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary)),
              if (commit.body.trim().isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(commit.body.trim(),
                    style: TextStyle(
                        fontSize: 12.5,
                        height: 1.4,
                        color: AppColors.textSecondary)),
              ],
              const SizedBox(height: 10),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!commit.isStash)
                    AuthorAvatar(
                        name: commit.author,
                        email: commit.authorEmail,
                        size: 16,
                        fallbackColor: authorColor),
                  if (!commit.isStash) const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      commit.isStash
                          ? '${commit.shortHash}  ·  ${dateFmt.format(commit.date)}'
                          : '${commit.author}  ·  ${commit.shortHash}  ·  ${dateFmt.format(commit.date)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 11.5, color: AppColors.textMuted),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ]);
  }

  Widget _refLabels(GitCommit commit, _GraphLayout gl, double width) {
    var refs = commit.refs;
    // Smart Branch Visibility: hide remote-tracking labels to reduce clutter.
    if (gl.layout.smartBranch) {
      refs = refs
          .where((r) =>
              r.startsWith('HEAD -> ') ||
              r.startsWith('tag: ') ||
              (!r.contains('/') && r != 'HEAD'))
          .toList();
    }
    final maxPills = (width / 84).floor().clamp(0, 2);
    if (refs.isEmpty || maxPills == 0) return const SizedBox.shrink();
    final pills = <Widget>[];
    for (final ref in refs.take(maxPills)) {
      var name = ref;
      var color = AppColors.accent;
      IconData? icon = Icons.call_split;
      // The branch to check out when this pill is double-clicked (null = not
      // checkoutable, e.g. tags or the bare HEAD pointer).
      String? checkout;
      // Whether this pill is a local branch (a valid drag-and-drop target that
      // can be checked out without detaching HEAD).
      var isLocalBranch = false;
      if (ref.startsWith('HEAD -> ')) {
        name = ref.substring('HEAD -> '.length);
        color = AppColors.green;
        icon = Icons.check;
        checkout = name;
        isLocalBranch = true;
      } else if (ref == 'HEAD') {
        color = AppColors.green;
        icon = Icons.adjust;
      } else if (ref.startsWith('tag: ')) {
        name = ref.substring('tag: '.length);
        color = AppColors.amber;
        icon = Icons.sell_outlined;
      } else if (ref.contains('/')) {
        color = AppColors.textMuted;
        icon = Icons.cloud_outlined;
        // Remote ref (e.g. origin/feat/x) -> check out the branch (feat/x).
        checkout = ref.substring(ref.indexOf('/') + 1);
      } else {
        checkout = ref; // bare local branch
        isLocalBranch = true;
      }
      final pill = Pill(name, color: color, icon: icon, tooltip: true);
      Widget cell;
      if (checkout == null) {
        cell = pill;
      } else {
        // Track which branch pill the cursor is over so the row's right-click
        // can open the branch menu for it (avoids fragile nested-gesture
        // competition with the row's context menu).
        final interactive = MouseRegion(
          cursor: SystemMouseCursors.click,
          // Pass the pill's full ref (e.g. `origin/feat/x`) so the branch menu
          // can label/act on the remote-tracking ref.
          onEnter: (_) => _hoverBranchRef = name,
          onExit: (_) {
            if (_hoverBranchRef == name) _hoverBranchRef = null;
          },
          child: GestureDetector(
            onDoubleTap: () => runRepoAction(
              context,
              () => context.read<RepoState>().checkout(checkout!),
              success: 'Checked out $checkout',
            ),
            child: pill,
          ),
        );
        // Draggable: this pill can be dragged onto a local branch to
        // merge/rebase/reset. Feedback is a floating copy of the pill.
        final draggable = Draggable<_BranchDrag>(
          data: _BranchDrag(name),
          dragAnchorStrategy: pointerDragAnchorStrategy,
          feedback: Material(
            color: Colors.transparent,
            child: Pill(name, color: color, icon: icon),
          ),
          childWhenDragging: Opacity(opacity: 0.4, child: interactive),
          child: interactive,
        );
        // Local branches are also drop targets.
        cell = isLocalBranch
            ? DragTarget<_BranchDrag>(
                onWillAcceptWithDetails: (d) => d.data.ref != name,
                onAcceptWithDetails: (d) =>
                    _onBranchDrop(d.data.ref, checkout!, d.offset),
                builder: (context, cand, rejected) => Stack(
                  clipBehavior: Clip.none,
                  children: [
                    draggable,
                    if (cand.isNotEmpty)
                      Positioned.fill(
                        child: IgnorePointer(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              border: Border.all(color: AppColors.accent, width: 1.5),
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              )
            : draggable;
      }
      pills.add(Flexible(
        child: Padding(padding: const EdgeInsets.only(right: 4), child: cell),
      ));
    }
    return Row(children: pills);
  }

  /// Shows the drop-action popover when branch [source] is dropped onto local
  /// branch [target].
  Future<void> _onBranchDrop(String source, String target, Offset pos) async {
    if (source == target) return;
    final state = context.read<RepoState>();
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final sel = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
          pos & const Size(1, 1), Offset.zero & overlay.size),
      color: AppColors.surfaceRaised,
      items: [
        PopupMenuItem(value: 'merge', child: Text('Merge $source into $target')),
        PopupMenuItem(
            value: 'rebase', child: Text('Rebase $target onto $source')),
        PopupMenuItem(
            value: 'reset',
            child: Text('Reset $target to $source',
                style: TextStyle(color: AppColors.red))),
      ],
    );
    if (sel == null || !mounted) return;
    switch (sel) {
      case 'merge':
        return runRepoAction(context, () => state.dragMerge(target, source),
            success: 'Merged $source into $target');
      case 'rebase':
        return runRepoAction(context, () => state.dragRebase(target, source),
            success: 'Rebased $target onto $source');
      case 'reset':
        final ok = await _confirmReset(target, source);
        if (ok && mounted) {
          return runRepoAction(
              context, () => state.dragReset(target, source, 'hard'),
              success: 'Reset $target to $source');
        }
    }
  }

  Future<bool> _confirmReset(String target, String source) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Hard reset?', style: TextStyle(fontSize: 16)),
        content: Text('Reset "$target" to "$source" and discard any changes '
            'after it? This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    return ok == true;
  }
}

/// Payload for dragging a branch pill in the graph.
class _BranchDrag {
  final String ref;
  const _BranchDrag(this.ref);
}

/// Paints the graph segment for a single commit row.
class _GraphRowPainter extends CustomPainter {
  final GraphRow row;
  final _GraphGeom geom;
  _GraphRowPainter(this.row, this.geom);

  @override
  void paint(Canvas canvas, Size size) {
    final top = 0.0;
    final mid = size.height / 2;
    final bottom = size.height;

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round;

    final outByHash = <String, int>{};
    final outColor = <int, int>{};
    final outStash = <int, bool>{};
    for (final l in row.outgoing) {
      outByHash[l.hash] = l.lane;
      outColor[l.lane] = l.color;
      outStash[l.lane] = l.stash;
    }

    for (final l in row.incoming) {
      paint.color = _laneColor(l.color);
      if (l.hash == row.commit.hash) {
        _connector(canvas, geom.laneX(l.lane), top, geom.laneX(row.dotLane),
            mid, paint, l.stash);
      } else {
        final outLane = outByHash[l.hash];
        if (outLane != null) {
          _connector(canvas, geom.laneX(l.lane), top, geom.laneX(outLane),
              bottom, paint, l.stash);
        }
      }
    }

    for (final p in row.commit.parents) {
      final lane = row.commit.parentLanes[p];
      if (lane == null) continue;
      paint.color = _laneColor(outColor[lane] ?? row.dotColor);
      // A line into a stash's base commit (or out of a stash node) is dashed.
      final dashed = row.commit.isStash || (outStash[lane] ?? false);
      _connector(canvas, geom.laneX(row.dotLane), mid, geom.laneX(lane),
          bottom, paint, dashed);
    }
    // The node itself is the author avatar / stash widget overlaid on top.
  }

  void _connector(Canvas canvas, double x1, double y1, double x2, double y2,
      Paint paint, bool dashed) {
    final Path path;
    if (x1 == x2) {
      path = Path()
        ..moveTo(x1, y1)
        ..lineTo(x2, y2);
    } else {
      path = Path()
        ..moveTo(x1, y1)
        ..cubicTo(x1, (y1 + y2) / 2, x2, (y1 + y2) / 2, x2, y2);
    }
    if (!dashed) {
      canvas.drawPath(path, paint);
      return;
    }
    // Butt caps read cleaner than round for dashes.
    final dash = Paint()
      ..color = paint.color
      ..style = PaintingStyle.stroke
      ..strokeWidth = paint.strokeWidth
      ..strokeCap = StrokeCap.butt;
    for (final metric in path.computeMetrics()) {
      var dist = 0.0;
      while (dist < metric.length) {
        final next = (dist + 3.0).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(dist, next), dash);
        dist = next + 3.0;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _GraphRowPainter old) =>
      old.row != row || old.geom != geom;
}

/// The stash (WIP) node: a tray glyph in a dashed, rounded, lane-coloured box.
class _StashNode extends StatelessWidget {
  final double size;
  final Color color;
  const _StashNode({required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DashedBoxPainter(color),
      child: SizedBox(
        width: size,
        height: size,
        child: Center(
          child: Icon(Icons.inventory_2_outlined,
              size: size * 0.6, color: color),
        ),
      ),
    );
  }
}

class _DashedBoxPainter extends CustomPainter {
  final Color color;
  _DashedBoxPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
        (Offset.zero & size).deflate(0.75), const Radius.circular(5));
    canvas.drawRRect(
        rrect,
        Paint()
          ..color = color.withValues(alpha: 0.16)
          ..style = PaintingStyle.fill);
    final border = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.butt;
    final path = Path()..addRRect(rrect);
    for (final m in path.computeMetrics()) {
      var d = 0.0;
      while (d < m.length) {
        final n = (d + 2.5).clamp(0.0, m.length);
        canvas.drawPath(m.extractPath(d, n), border);
        d = n + 2.0;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBoxPainter old) => old.color != color;
}

/// The WIP (working-tree) node: a faded mint leaf inside a dotted circle, with
/// a dotted lane line dropping to the first real commit below.
class _WipNode extends StatelessWidget {
  final _GraphGeom geom;
  final double graphWidth;
  const _WipNode({required this.geom, required this.graphWidth});

  @override
  Widget build(BuildContext context) {
    final d = geom.avatarSize;
    final cx = geom.laneX(0);
    final leaf = d * 0.62;
    return SizedBox(
      width: graphWidth,
      height: _rowHeight,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(child: CustomPaint(painter: _WipNodePainter(geom))),
          Positioned(
            left: cx - leaf / 2,
            top: (_rowHeight - leaf) / 2,
            // Faded so it reads as a placeholder/uncommitted node.
            child: Opacity(
                opacity: 0.5, child: MintLeafLogo(size: leaf, background: false)),
          ),
        ],
      ),
    );
  }
}

class _WipNodePainter extends CustomPainter {
  final _GraphGeom geom;
  _WipNodePainter(this.geom);

  @override
  void paint(Canvas canvas, Size size) {
    final cx = geom.laneX(0);
    final cy = size.height / 2;
    final r = geom.avatarSize / 2;
    final color = _laneColor(0); // mint lane

    // Faint circular wash behind the leaf.
    canvas.drawCircle(
        Offset(cx, cy),
        r,
        Paint()
          ..color = color.withValues(alpha: 0.10)
          ..style = PaintingStyle.fill);

    final stroke = Paint()
      ..color = color.withValues(alpha: 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3
      ..strokeCap = StrokeCap.round;

    // Dotted circle border.
    final circle = Path()
      ..addOval(Rect.fromCircle(center: Offset(cx, cy), radius: r));
    _dash(canvas, circle, stroke, on: 1.6, off: 2.6);

    // Dotted line dropping from the bottom of the circle to the row bottom.
    final line = Path()
      ..moveTo(cx, cy + r)
      ..lineTo(cx, size.height);
    _dash(canvas, line, stroke, on: 2.0, off: 3.0);
  }

  void _dash(Canvas canvas, Path path, Paint paint,
      {required double on, required double off}) {
    for (final m in path.computeMetrics()) {
      var d = 0.0;
      while (d < m.length) {
        final n = (d + on).clamp(0.0, m.length);
        canvas.drawPath(m.extractPath(d, n), paint);
        d = n + off;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _WipNodePainter old) => old.geom != geom;
}

/// Banner shown when a Solo/Pin graph filter is active.
class _FilterBanner extends StatelessWidget {
  final RepoState state;
  const _FilterBanner({required this.state});

  @override
  Widget build(BuildContext context) {
    final short = (state.soloHash ?? state.pinnedHash ?? '');
    final label = state.soloHash != null
        ? 'Soloing ${short.length >= 7 ? short.substring(0, 7) : short}'
        : 'Pinned ${short.length >= 7 ? short.substring(0, 7) : short} to the left';
    return Container(
      color: AppColors.selection,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          Icon(Icons.filter_alt_outlined,
              size: 14, color: AppColors.accent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(label,
                style:
                    TextStyle(fontSize: 12, color: AppColors.textPrimary)),
          ),
          InkWell(
            onTap: state.clearGraphFilter,
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.close, size: 13, color: AppColors.textSecondary),
                  SizedBox(width: 4),
                  Text('Clear',
                      style: TextStyle(
                          fontSize: 12, color: AppColors.textSecondary)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Single-line text that highlights occurrences of [query] (case-insensitive).
class _HighlightedText extends StatelessWidget {
  final String text;
  final String query;
  final TextStyle style;
  const _HighlightedText(this.text, this.query, this.style);

  @override
  Widget build(BuildContext context) {
    final q = query.trim();
    if (q.isEmpty) {
      return Text(text,
          maxLines: 1, overflow: TextOverflow.ellipsis, style: style);
    }
    final lower = text.toLowerCase();
    final ql = q.toLowerCase();
    final spans = <TextSpan>[];
    var start = 0;
    while (true) {
      final idx = lower.indexOf(ql, start);
      if (idx < 0) {
        spans.add(TextSpan(text: text.substring(start)));
        break;
      }
      if (idx > start) spans.add(TextSpan(text: text.substring(start, idx)));
      spans.add(TextSpan(
        text: text.substring(idx, idx + ql.length),
        style: TextStyle(
          color: AppColors.background,
          backgroundColor: AppColors.amber,
          fontWeight: FontWeight.w600,
        ),
      ));
      start = idx + ql.length;
    }
    return Text.rich(TextSpan(style: style, children: spans),
        maxLines: 1, overflow: TextOverflow.ellipsis);
  }
}

/// Shown in the commit list area when a search matches nothing.
/// A footer bar under the graph offering to load the next page of history.
class _LoadMoreBar extends StatelessWidget {
  final RepoState state;
  const _LoadMoreBar({required this.state});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: state.loadingMore ? null : state.loadMoreCommits,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        padding: const EdgeInsets.symmetric(vertical: 8),
        alignment: Alignment.center,
        child: state.loadingMore
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2))
            : Text('Load more commits',
                style: TextStyle(
                    fontSize: 12.5,
                    color: AppColors.accent,
                    fontWeight: FontWeight.w600)),
      ),
    );
  }
}

class _NoResults extends StatelessWidget {
  const _NoResults();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.search_off, size: 30, color: AppColors.textMuted),
          SizedBox(height: 10),
          Text('No commits match your search',
              style: TextStyle(fontSize: 13.5, color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  const _ErrorView({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, color: AppColors.red, size: 36),
            const SizedBox(height: 12),
            Text('Could not read this repository',
                style: TextStyle(fontSize: 15, color: AppColors.textPrimary)),
            const SizedBox(height: 8),
            Text(message,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 12.5, color: AppColors.textSecondary)),
          ],
        ),
      ),
    );
  }
}
