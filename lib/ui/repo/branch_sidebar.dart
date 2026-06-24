import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/git_branch.dart';
import '../../models/pull_request.dart';
import '../../state/layout_state.dart';
import '../../state/repo_state.dart';
import '../../theme/app_theme.dart';
import '../widgets/common.dart';
import 'repo_actions.dart';
import 'sidebar_menus.dart';

class BranchSidebar extends StatefulWidget {
  const BranchSidebar({super.key});

  @override
  State<BranchSidebar> createState() => _BranchSidebarState();
}

class _BranchSidebarState extends State<BranchSidebar> {
  final Set<String> _expanded = {'LOCAL', 'REMOTE'};
  String _filter = '';

  void _toggle(String key) {
    setState(() {
      _expanded.contains(key) ? _expanded.remove(key) : _expanded.add(key);
    });
  }

  bool _matches(String name) =>
      _filter.isEmpty || name.toLowerCase().contains(_filter.toLowerCase());

  @override
  Widget build(BuildContext context) {
    final state = context.watch<RepoState>();
    // Filter text is driven by RepoState's controller (so a global shortcut
    // can focus and clear it).
    _filter = state.branchFilter.text;

    // Group remote branches by remote name.
    final remotes = <String, List<GitRef>>{};
    for (final r in state.remoteBranches) {
      remotes.putIfAbsent(r.remoteName ?? 'origin', () => []).add(r);
    }

    final totalVisible = state.localBranches.length +
        state.remoteBranches.length +
        state.tags.length +
        state.stashes.length;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        border: Border(right: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 10, 10, 4),
            child: Row(
              children: [
                Tooltip(
                  message: 'Collapse panel',
                  child: InkWell(
                    onTap: () =>
                        context.read<LayoutState>().toggleSidebarCollapsed(),
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(Icons.chevron_left,
                          size: 18, color: AppColors.textMuted),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text('Viewing',
                    style: TextStyle(
                        fontSize: 12, color: AppColors.textSecondary)),
                const SizedBox(width: 6),
                Text('$totalVisible',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 4, 10, 8),
            child: SizedBox(
              height: 30,
              child: TextField(
                controller: state.branchFilter,
                focusNode: state.branchFilterFocus,
                onChanged: (_) => setState(() {}),
                style: const TextStyle(fontSize: 12.5),
                decoration: const InputDecoration(
                  hintText: 'Filter (Ctrl + Alt + f)',
                  prefixIcon: Icon(Icons.search, size: 15),
                  prefixIconConstraints:
                      BoxConstraints(minWidth: 30, minHeight: 30),
                ),
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: _buildSections(context, state, remotes),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildSections(BuildContext context, RepoState state,
      Map<String, List<GitRef>> remotes) {
    final layout = context.watch<LayoutState>();
    final sections = <Widget>[];

    void add(SidebarSectionId s, IconData icon, String title, int? count,
        List<Widget> children) {
      if (!layout.sectionVisible(s)) return;
      sections.add(SidebarSection(
        icon: icon,
        title: title,
        count: count,
        expanded: _expanded.contains(title),
        onToggle: () => _toggle(title),
        onSecondaryTap: (pos) => showSectionContextMenu(
            context, state, layout, s, pos, onMaximize: () {
          setState(() {
            _expanded
              ..clear()
              ..add(title);
          });
        }),
        children: children,
      ));
    }

    add(SidebarSectionId.local, Icons.computer, 'LOCAL',
        state.localBranches.length, [
      for (final b in state.localBranches)
        if (_matches(b.name) && !state.isHidden(b))
          _BranchRow(
              branch: b,
              indent: 28,
              onSecondaryTap: (pos) =>
                  showBranchContextMenu(context, state, b, pos)),
    ]);

    add(SidebarSectionId.remote, Icons.cloud_outlined, 'REMOTE',
        state.remoteBranches.length, [
      for (final entry in remotes.entries) ...[
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 4, 8, 4),
          child: Row(
            children: [
              Icon(Icons.dns_outlined,
                  size: 13, color: AppColors.textMuted),
              const SizedBox(width: 6),
              Text(entry.key,
                  style: TextStyle(
                      fontSize: 12, color: AppColors.textSecondary)),
            ],
          ),
        ),
        for (final b in entry.value)
          if (_matches(b.name) && !state.isHidden(b))
            _BranchRow(
                branch: b,
                indent: 44,
                onSecondaryTap: (pos) =>
                    showBranchContextMenu(context, state, b, pos)),
      ],
    ]);

    add(SidebarSectionId.worktrees, Icons.account_tree_outlined, 'WORKTREES',
        null, const [_EmptyHint('No worktrees')]);

    add(SidebarSectionId.stashes, Icons.inventory_2_outlined, 'STASHES',
        state.stashes.length, [
      for (var i = 0; i < state.stashes.length; i++)
        if (!state.isStashHidden(state.stashes[i]))
          _BranchRow(
              branch: state.stashes[i],
              indent: 28,
              onSecondaryTap: (pos) => showStashContextMenu(
                  context, state, state.stashes[i], i, pos)),
    ]);

    add(SidebarSectionId.cloudPatches, Icons.science_outlined, 'CLOUD PATCHES', 0,
        const [_EmptyHint('No cloud patches')]);

    add(
        SidebarSectionId.pullRequests,
        Icons.merge_type,
        'PULL REQUESTS',
        state.pullRequests.isEmpty ? null : state.pullRequests.length,
        _prChildren(context, state));

    add(SidebarSectionId.issues, Icons.error_outline, 'ISSUES', null,
        const [_EmptyHint('No issues')]);

    add(SidebarSectionId.teams, Icons.groups_outlined, 'TEAMS', null,
        const [_EmptyHint('No teams')]);

    add(SidebarSectionId.tags, Icons.sell_outlined, 'TAGS', state.tags.length, [
      for (final t in state.tags)
        if (_matches(t.name) && !state.isHidden(t))
          _BranchRow(branch: t, indent: 28),
    ]);

    add(SidebarSectionId.submodules, Icons.folder_special_outlined, 'SUBMODULES',
        null, const [_EmptyHint('No submodules')]);

    return sections;
  }

  List<Widget> _prChildren(BuildContext context, RepoState state) {
    final children = <Widget>[
      Padding(
        padding: const EdgeInsets.fromLTRB(28, 4, 10, 6),
        child: SizedBox(
          height: 28,
          child: TextField(
            onChanged: state.setPrSearch,
            style: const TextStyle(fontSize: 12),
            decoration: const InputDecoration(
              hintText: 'Search pull requests',
              prefixIcon: Icon(Icons.search, size: 14),
              prefixIconConstraints:
                  BoxConstraints(minWidth: 28, minHeight: 28),
            ),
          ),
        ),
      ),
    ];
    if (state.prsLoading) {
      children.add(const Padding(
        padding: EdgeInsets.fromLTRB(34, 4, 10, 8),
        child: SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2)),
      ));
      return children;
    }
    final q = state.prSearch.toLowerCase();
    final filtered = state.pullRequests
        .where((p) =>
            q.isEmpty ||
            p.title.toLowerCase().contains(q) ||
            '#${p.id}'.contains(q) ||
            p.sourceBranch.toLowerCase().contains(q))
        .toList();
    if (filtered.isEmpty) {
      children.add(_EmptyHint(state.prError ?? 'No pull requests'));
      return children;
    }
    void group(String label, List<PullRequest> prs) {
      children.add(_PrGroupLabel(label: label, count: prs.length));
      for (final p in prs) {
        children.add(_PrRow(
          pr: p,
          onSecondaryTap: (pos) =>
              showPullRequestContextMenu(context, state, p, pos),
        ));
      }
    }

    final mine = filtered.where((p) => p.isMine).toList();
    final review = filtered.where((p) => p.awaitingMyReview).toList();
    if (mine.isNotEmpty) group('My Pull Requests', mine);
    if (review.isNotEmpty) group('Awaiting My Review', review);
    group('All Pull Requests', filtered);
    return children;
  }

}

/// A muted hint shown inside an empty sidebar section.
class _EmptyHint extends StatelessWidget {
  final String text;
  const _EmptyHint(this.text);
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(34, 2, 10, 6),
      child: Text(text,
          style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
    );
  }
}

class _PrGroupLabel extends StatelessWidget {
  final String label;
  final int count;
  const _PrGroupLabel({required this.label, required this.count});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 6, 10, 4),
      child: Row(
        children: [
          Icon(Icons.expand_more, size: 14, color: AppColors.textMuted),
          const SizedBox(width: 4),
          Expanded(
            child: Text(label,
                style: TextStyle(
                    fontSize: 12, color: AppColors.textSecondary)),
          ),
          Text('$count',
              style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
        ],
      ),
    );
  }
}

String _relative(DateTime? d) {
  if (d == null) return '';
  final diff = DateTime.now().difference(d);
  if (diff.inDays >= 365) return '${(diff.inDays / 365).floor()} years ago';
  if (diff.inDays >= 30) return '${(diff.inDays / 30).floor()} months ago';
  if (diff.inDays >= 1) return '${diff.inDays} days ago';
  if (diff.inHours >= 1) return '${diff.inHours} hours ago';
  if (diff.inMinutes >= 1) return '${diff.inMinutes} minutes ago';
  return 'just now';
}

class _PrRow extends StatefulWidget {
  final PullRequest pr;
  final void Function(Offset globalPosition) onSecondaryTap;
  const _PrRow({required this.pr, required this.onSecondaryTap});

  @override
  State<_PrRow> createState() => _PrRowState();
}

class _PrRowState extends State<_PrRow> {
  bool _hover = false;

  InlineSpan _detail() {
    final pr = widget.pr;
    final df = DateFormat('MMM d, y');
    final muted = TextStyle(color: AppColors.textSecondary, fontSize: 12.5);
    final hl = TextStyle(
        color: AppColors.accent, fontSize: 12.5, fontWeight: FontWeight.w500);
    final created = pr.created;
    final updated = pr.updated;
    return TextSpan(style: muted, children: [
      TextSpan(
          text: '${pr.title}  #${pr.id}\n\n',
          style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w600)),
      TextSpan(text: '${pr.authorName} wants to merge '),
      TextSpan(text: pr.sourceBranch, style: hl),
      const TextSpan(text: ' into '),
      TextSpan(text: pr.targetBranch, style: hl),
      if (pr.assignees.isNotEmpty)
        TextSpan(text: '\n\nAssignees: ${pr.assignees.join(', ')}'),
      if (created != null)
        TextSpan(text: '\n\nOpened: ${df.format(created)} (${_relative(created)})'),
      if (updated != null)
        TextSpan(text: '\nUpdated: ${df.format(updated)} (${_relative(updated)})'),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final pr = widget.pr;
    return Tooltip(
      richMessage: _detail(),
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onSecondaryTapDown: (d) => widget.onSecondaryTap(d.globalPosition),
          child: Container(
            color: _hover ? AppColors.surfaceRaised : Colors.transparent,
            padding: const EdgeInsets.fromLTRB(44, 5, 8, 5),
            child: Row(
              children: [
                Icon(Icons.check, size: 13, color: AppColors.green),
                const SizedBox(width: 6),
                Expanded(
                  child: Text('#${pr.id} ${pr.title}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 12.5, color: AppColors.textSecondary)),
                ),
                if (_hover)
                  Icon(Icons.more_vert,
                      size: 14, color: AppColors.textMuted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Narrow icon-rail shown when the branch sidebar is collapsed.
class CollapsedSidebar extends StatelessWidget {
  const CollapsedSidebar({super.key});

  static const double width = 56;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<RepoState>();
    final layout = context.read<LayoutState>();
    void expand() => layout.toggleSidebarCollapsed();

    return Container(
      width: width,
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        border: Border(right: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          Center(
            child: Tooltip(
              message: 'Expand panel',
              child: InkWell(
                onTap: expand,
                customBorder: const CircleBorder(),
                child: Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceRaised,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.chevron_right,
                      size: 18, color: AppColors.textSecondary),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(top: 6),
              children: [
                _RailItem(
                    icon: Icons.computer,
                    count: state.localBranches.length,
                    tooltip: 'Local',
                    onTap: expand),
                _RailItem(
                    icon: Icons.cloud_outlined,
                    count: state.remoteBranches.length,
                    tooltip: 'Remote',
                    onTap: expand),
                _RailItem(
                    icon: Icons.inventory_2_outlined,
                    count: state.stashes.length,
                    tooltip: 'Stashes',
                    onTap: expand),
                _RailItem(
                    icon: Icons.sell_outlined,
                    count: state.tags.length,
                    tooltip: 'Tags',
                    onTap: expand),
                _RailItem(
                    icon: Icons.merge_type,
                    tooltip: 'Pull requests',
                    onTap: expand),
                _RailItem(
                    icon: Icons.error_outline,
                    tooltip: 'Issues',
                    onTap: expand),
                _RailItem(
                    icon: Icons.groups_outlined,
                    tooltip: 'Teams',
                    onTap: expand),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RailItem extends StatefulWidget {
  final IconData icon;
  final int? count;
  final String tooltip;
  final VoidCallback onTap;
  const _RailItem(
      {required this.icon,
      required this.tooltip,
      required this.onTap,
      this.count});

  @override
  State<_RailItem> createState() => _RailItemState();
}

class _RailItemState extends State<_RailItem> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: Container(
            color: _hover ? AppColors.surfaceRaised : Colors.transparent,
            padding: const EdgeInsets.symmetric(vertical: 9),
            child: Column(
              children: [
                Icon(widget.icon, size: 18, color: AppColors.textSecondary),
                if (widget.count != null) ...[
                  const SizedBox(height: 2),
                  Text('${widget.count}',
                      style: TextStyle(
                          fontSize: 11, color: AppColors.textMuted)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BranchRow extends StatefulWidget {
  final GitRef branch;
  final double indent;
  final void Function(Offset globalPosition)? onSecondaryTap;
  const _BranchRow(
      {required this.branch, required this.indent, this.onSecondaryTap});

  @override
  State<_BranchRow> createState() => _BranchRowState();
}

class _BranchRowState extends State<_BranchRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final state = context.read<RepoState>();
    final b = widget.branch;
    final isCheckoutable = b.kind == RefKind.localBranch ||
        b.kind == RefKind.remoteBranch;

    return MouseRegion(
      onEnter: (_) {
        setState(() => _hover = true);
        if (isCheckoutable) state.setHoverBranch(b.displayName);
      },
      onExit: (_) {
        setState(() => _hover = false);
        if (state.hoverBranch == b.displayName) state.setHoverBranch(null);
      },
      cursor:
          isCheckoutable ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: !isCheckoutable
            ? null
            : () => runRepoAction(
                  context,
                  () => state.checkout(
                      b.kind == RefKind.remoteBranch ? b.displayName : b.name),
                  success: 'Checked out ${b.displayName}',
                ),
        onSecondaryTapDown: widget.onSecondaryTap == null
            ? null
            : (d) => widget.onSecondaryTap!(d.globalPosition),
        child: Container(
          color: b.isCurrent
              ? AppColors.selectionRow
              : (_hover ? AppColors.surfaceRaised : Colors.transparent),
          padding: EdgeInsets.only(
              left: widget.indent, right: 8, top: 5, bottom: 5),
          child: Row(
            children: [
              if (b.isCurrent)
                Icon(Icons.check, size: 13, color: AppColors.green)
              else
                Icon(
                  b.kind == RefKind.stash
                      ? Icons.inventory_2_outlined
                      : b.kind == RefKind.tag
                          ? Icons.sell_outlined
                          : Icons.call_split,
                  size: 12,
                  color: AppColors.textMuted,
                ),
              const SizedBox(width: 7),
              Expanded(
                child: TruncatedText(
                  b.displayName,
                  tooltipText: b.name,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: b.isCurrent
                        ? AppColors.textPrimary
                        : AppColors.textSecondary,
                    fontWeight:
                        b.isCurrent ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ),
              if (b.ahead > 0) ...[
                Icon(Icons.arrow_upward,
                    size: 10, color: AppColors.green),
                Text('${b.ahead}',
                    style: TextStyle(
                        fontSize: 10.5, color: AppColors.green)),
                const SizedBox(width: 4),
              ],
              if (b.behind > 0) ...[
                Icon(Icons.arrow_downward,
                    size: 10, color: AppColors.amber),
                Text('${b.behind}',
                    style: TextStyle(
                        fontSize: 10.5, color: AppColors.amber)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
