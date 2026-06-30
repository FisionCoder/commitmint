import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/file_change.dart';
import '../../state/layout_state.dart';
import '../../state/repo_state.dart';
import '../widgets/common.dart';
import 'branch_sidebar.dart';
import 'changes_panel.dart';
import 'commit_graph_view.dart';
import 'conflict_resolution_view.dart';
import 'file_detail_view.dart';
import 'repo_toolbar.dart';
import 'terminal_panel.dart';

class RepoView extends StatelessWidget {
  const RepoView({super.key});

  @override
  Widget build(BuildContext context) {
    final fileOpen = context.select<RepoState, bool>((s) => s.isFileOpen);
    // A conflicted open file gets the dedicated resolution editor instead of
    // the raw-marker diff view.
    final openConflicted = context.select<RepoState, bool>(
        (s) => s.openFile?.type == ChangeType.conflicted);
    final terminalVisible =
        context.select<RepoState, bool>((s) => s.terminalVisible);
    final repoPath = context.read<RepoState>().repo.path;
    final layout = context.watch<LayoutState>();
    final openPath = context.select<RepoState, String?>((s) => s.openFile?.path);
    final center = !fileOpen
        ? const CommitGraphView()
        : (openConflicted
            ? ConflictResolutionView(key: ValueKey('conflict:$openPath'))
            : const FileDetailView());

    const centerMin = 360.0;
    final collapsed = layout.sidebarCollapsed;
    final leftWidth =
        collapsed ? CollapsedSidebar.width : layout.sidebarWidth;

    final panesArea = LayoutBuilder(builder: (context, c) {
      final minTotal = leftWidth +
          centerMin +
          (layout.changesPanelVisible ? layout.changesPanelWidth : 0.0);

      final panes = Row(
        // Stretch panes to full height so the changes/commit-details panel
        // fills the column (its content is top-aligned, not centered).
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (collapsed)
            const CollapsedSidebar()
          else ...[
            SizedBox(
                width: layout.sidebarWidth, child: const BranchSidebar()),
            ResizeHandle(
              onDelta: (dx) =>
                  layout.setSidebarWidth(layout.sidebarWidth + dx),
              onEnd: layout.persist,
            ),
          ],
          Expanded(child: center),
          if (layout.changesPanelVisible) ...[
            ResizeHandle(
              onDelta: (dx) =>
                  layout.setChangesPanelWidth(layout.changesPanelWidth - dx),
              onEnd: layout.persist,
            ),
            SizedBox(
                width: layout.changesPanelWidth, child: const ChangesPanel()),
          ],
        ],
      );

      if (c.maxWidth >= minTotal) return panes;

      // Too narrow to fit all panes — scroll the whole layout instead of
      // crushing the center pane into overflow.
      return Scrollbar(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: minTotal,
            height: c.maxHeight,
            child: panes,
          ),
        ),
      );
    });

    return Column(
      children: [
        const RepoToolbar(),
        Expanded(
          child: terminalVisible
              ? LayoutBuilder(builder: (context, c) {
                  // Reserve a minimum for the graph/panes area and a minimum for
                  // the terminal. The terminal yields space first when the window
                  // is short, so the panes above never overflow.
                  const handleH = 6.0;
                  const panesMin = 160.0;
                  const terminalMin = 100.0;
                  final avail = c.maxHeight - handleH;
                  // Cap the terminal so panes keep [panesMin]; never below
                  // [terminalMin], and never taller than the space available.
                  final cap = (avail - panesMin)
                      .clamp(terminalMin, avail.clamp(terminalMin, double.infinity));
                  final termH = layout.terminalHeight.clamp(terminalMin, cap);
                  return Column(
                    children: [
                      Expanded(child: panesArea),
                      ResizeHandle(
                        vertical: true,
                        onDelta: (dy) => layout
                            .setTerminalHeight(layout.terminalHeight - dy),
                        onEnd: layout.persist,
                      ),
                      SizedBox(
                        height: termH,
                        child: TerminalPanel(workingDirectory: repoPath),
                      ),
                    ],
                  );
                })
              : panesArea,
        ),
      ],
    );
  }
}
