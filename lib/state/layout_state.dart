import 'package:flutter/foundation.dart';

import '../services/storage_service.dart';

/// Identifies a toggleable commit-graph column.
enum GraphColumn { branch, graph, message, author, date, sha }

/// Sections of the left sidebar that can be shown/hidden.
enum SidebarSectionId {
  local,
  remote,
  worktrees,
  stashes,
  cloudPatches,
  pullRequests,
  issues,
  teams,
  tags,
  submodules,
}

/// User-adjustable layout: resizable panel/column widths plus which commit-graph
/// columns are visible and the compact/smart display modes. Persisted so the
/// layout survives restarts.
class LayoutState extends ChangeNotifier {
  final StorageService _storage = StorageService();

  double sidebarWidth = 250;
  double changesPanelWidth = 340;
  double branchColWidth = 168;
  double dateColWidth = 168;
  double providerRailWidth = 280;
  double terminalHeight = 240;

  // Column visibility (defaults match the classic layout).
  bool showBranch = true;
  bool showGraph = true;
  bool showMessage = true;
  bool showAuthor = false;
  bool showDate = true;
  bool showSha = false;

  // Display modes.
  bool compactGraph = false;
  bool smartBranch = false;

  // Whether the branch sidebar is collapsed to a narrow icon rail.
  bool sidebarCollapsed = false;

  // Whether the right-hand commit details / changes panel is shown.
  bool changesPanelVisible = true;

  // Which sidebar sections are visible.
  final Map<SidebarSectionId, bool> _sections = {
    SidebarSectionId.local: true,
    SidebarSectionId.remote: true,
    SidebarSectionId.worktrees: false,
    SidebarSectionId.stashes: true,
    SidebarSectionId.cloudPatches: true,
    SidebarSectionId.pullRequests: true,
    SidebarSectionId.issues: true,
    SidebarSectionId.teams: true,
    SidebarSectionId.tags: true,
    SidebarSectionId.submodules: false,
  };

  bool sectionVisible(SidebarSectionId s) => _sections[s] ?? true;

  LayoutState() {
    _load();
  }

  bool isVisible(GraphColumn c) {
    switch (c) {
      case GraphColumn.branch:
        return showBranch;
      case GraphColumn.graph:
        return showGraph;
      case GraphColumn.message:
        return showMessage;
      case GraphColumn.author:
        return showAuthor;
      case GraphColumn.date:
        return showDate;
      case GraphColumn.sha:
        return showSha;
    }
  }

  Future<void> _load() async {
    final m = await _storage.loadLayout();
    double readD(String k, double fallback) {
      final v = m[k];
      return v is num ? v.toDouble() : fallback;
    }

    bool readB(String k, bool fallback) {
      final v = m[k];
      return v is bool ? v : fallback;
    }

    sidebarWidth = readD('sidebar', sidebarWidth);
    changesPanelWidth = readD('changes', changesPanelWidth);
    branchColWidth = readD('branchCol', branchColWidth);
    dateColWidth = readD('dateCol', dateColWidth);
    providerRailWidth = readD('rail', providerRailWidth);
    terminalHeight = readD('terminal', terminalHeight);

    showBranch = readB('showBranch', showBranch);
    showGraph = readB('showGraph', showGraph);
    showMessage = readB('showMessage', showMessage);
    showAuthor = readB('showAuthor', showAuthor);
    showDate = readB('showDate', showDate);
    showSha = readB('showSha', showSha);
    compactGraph = readB('compactGraph', compactGraph);
    smartBranch = readB('smartBranch', smartBranch);
    sidebarCollapsed = readB('sidebarCollapsed', sidebarCollapsed);
    changesPanelVisible = readB('changesPanelVisible', changesPanelVisible);
    final sec = m['sections'];
    if (sec is Map) {
      for (final s in SidebarSectionId.values) {
        final v = sec[s.name];
        if (v is bool) _sections[s] = v;
      }
    }
    notifyListeners();
  }

  void _persist() {
    _storage.saveLayout({
      'sidebar': sidebarWidth,
      'changes': changesPanelWidth,
      'branchCol': branchColWidth,
      'dateCol': dateColWidth,
      'rail': providerRailWidth,
      'terminal': terminalHeight,
      'showBranch': showBranch,
      'showGraph': showGraph,
      'showMessage': showMessage,
      'showAuthor': showAuthor,
      'showDate': showDate,
      'showSha': showSha,
      'compactGraph': compactGraph,
      'smartBranch': smartBranch,
      'sidebarCollapsed': sidebarCollapsed,
      'changesPanelVisible': changesPanelVisible,
      'sections': {for (final e in _sections.entries) e.key.name: e.value},
    });
  }

  void toggleSection(SidebarSectionId s) {
    _sections[s] = !sectionVisible(s);
    _persist();
    notifyListeners();
  }

  void toggleSidebarCollapsed() {
    sidebarCollapsed = !sidebarCollapsed;
    _persist();
    notifyListeners();
  }

  void toggleChangesPanel() {
    changesPanelVisible = !changesPanelVisible;
    _persist();
    notifyListeners();
  }

  void setSidebarWidth(double v) {
    sidebarWidth = v.clamp(170, 560);
    notifyListeners();
  }

  void setChangesPanelWidth(double v) {
    changesPanelWidth = v.clamp(240, 680);
    notifyListeners();
  }

  void setBranchColWidth(double v) {
    branchColWidth = v.clamp(0, 420);
    notifyListeners();
  }

  void setDateColWidth(double v) {
    dateColWidth = v.clamp(60, 360);
    notifyListeners();
  }

  void setProviderRailWidth(double v) {
    providerRailWidth = v.clamp(190, 520);
    notifyListeners();
  }

  void setTerminalHeight(double v) {
    terminalHeight = v.clamp(120, 600);
    notifyListeners();
  }

  void toggleColumn(GraphColumn c) {
    switch (c) {
      case GraphColumn.branch:
        showBranch = !showBranch;
        break;
      case GraphColumn.graph:
        showGraph = !showGraph;
        break;
      case GraphColumn.message:
        showMessage = !showMessage;
        break;
      case GraphColumn.author:
        showAuthor = !showAuthor;
        break;
      case GraphColumn.date:
        showDate = !showDate;
        break;
      case GraphColumn.sha:
        showSha = !showSha;
        break;
    }
    _persist();
    notifyListeners();
  }

  void setCompactGraph(bool v) {
    compactGraph = v;
    _persist();
    notifyListeners();
  }

  void setSmartBranch(bool v) {
    smartBranch = v;
    _persist();
    notifyListeners();
  }

  void resetColumnsToDefault() {
    showBranch = true;
    showGraph = true;
    showMessage = true;
    showAuthor = false;
    showDate = true;
    showSha = false;
    compactGraph = false;
    smartBranch = false;
    branchColWidth = 168;
    dateColWidth = 168;
    _persist();
    notifyListeners();
  }

  void resetColumnsToCompact() {
    showBranch = false;
    showGraph = true;
    showMessage = true;
    showAuthor = false;
    showDate = true;
    showSha = false;
    compactGraph = true;
    smartBranch = true;
    dateColWidth = 132;
    _persist();
    notifyListeners();
  }

  /// Call on drag end to write the current sizes to disk.
  void persist() => _persist();
}
