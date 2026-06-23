import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/layout_state.dart';
import '../../state/repo_state.dart';
import '../widgets/common.dart';
import 'branch_sidebar.dart';
import 'changes_panel.dart';
import 'commit_graph_view.dart';
import 'file_detail_view.dart';
import 'repo_toolbar.dart';
import 'terminal_panel.dart';

class RepoView extends StatelessWidget {
  const RepoView({super.key});

  @override
  Widget build(BuildContext context) {
    final fileOpen = context.select<RepoState, bool>((s) => s.isFileOpen);
    final terminalVisible =
        context.select<RepoState, bool>((s) => s.terminalVisible);
    final repoPath = context.read<RepoState>().repo.path;
    final layout = context.watch<LayoutState>();
    final center =
        fileOpen ? const FileDetailView() : const CommitGraphView();

    const centerMin = 360.0;
    final collapsed = layout.sidebarCollapsed;
    final leftWidth =
        collapsed ? CollapsedSidebar.width : layout.sidebarWidth;

    final panesArea = LayoutBuilder(builder: (context, c) {
      final minTotal = leftWidth +
          centerMin +
          (layout.changesPanelVisible ? layout.changesPanelWidth : 0.0);

      final panes = Row(
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
          child: Column(
            children: [
              Expanded(child: panesArea),
              if (terminalVisible) ...[
                ResizeHandle(
                  vertical: true,
                  onDelta: (dy) =>
                      layout.setTerminalHeight(layout.terminalHeight - dy),
                  onEnd: layout.persist,
                ),
                SizedBox(
                  height: layout.terminalHeight,
                  child: TerminalPanel(workingDirectory: repoPath),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
