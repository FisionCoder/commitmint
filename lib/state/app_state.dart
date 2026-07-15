import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../models/git_repository.dart';
import '../models/integration.dart';
import '../services/storage_service.dart';
import 'repo_state.dart';

enum TabKind { launchpad, integrations, repo }

class AppTab {
  final TabKind kind;
  final String? repoId;
  const AppTab(this.kind, {this.repoId});

  Map<String, dynamic> toJson() => {'kind': kind.name, 'repoId': repoId};

  static AppTab? fromJson(Map<String, dynamic> json) {
    final kind = TabKind.values.firstWhere(
      (k) => k.name == json['kind'],
      orElse: () => TabKind.launchpad,
    );
    return AppTab(kind, repoId: json['repoId'] as String?);
  }
}

/// Top-level application state: saved repos, Azure instances, and open tabs.
class AppState extends ChangeNotifier {
  final StorageService _storage = StorageService();

  List<GitRepository> repositories = [];
  List<Integration> integrations = [];

  final Map<String, RepoState> _repoStates = {};

  List<AppTab> tabs = [const AppTab(TabKind.launchpad)];
  int activeTabIndex = 0;

  AppTab get activeTab => tabs[activeTabIndex];

  // Persistent author → colour-slot map, so each author keeps the same avatar
  // colour across sessions (and across repos).
  final Map<String, int> _authorSlots = {};
  int _nextSlot = 0;
  bool _colorsSaveScheduled = false;

  Future<void> init() async {
    repositories = await _storage.loadRepositories();
    integrations = await _storage.loadIntegrations();

    _authorSlots.addAll(await _storage.loadAuthorColors());
    _nextSlot = _authorSlots.values.isEmpty
        ? 0
        : _authorSlots.values.reduce((a, b) => a > b ? a : b) + 1;

    // Honor the "Remember tabs" setting: skip restoring saved repo tabs when off.
    final settings = await _storage.loadSettings();
    final rememberTabs = settings['rememberTabs'] as bool? ?? true;
    _restoreTabs(rememberTabs ? await _storage.loadTabs() : const {});
    notifyListeners();
  }

  // ----------------------------------------------------- author colours ----
  /// A stable, distinct colour for an author. The slot is assigned once and
  /// persisted, so it's identical on every restart (golden-angle hue spacing).
  Color colorForAuthor(String name, String email) {
    var key = (email.trim().isNotEmpty ? email : name).toLowerCase().trim();
    if (key.isEmpty) key = '?';
    var slot = _authorSlots[key];
    if (slot == null) {
      slot = _nextSlot++;
      _authorSlots[key] = slot;
      _scheduleSaveColors();
    }
    final hue = (slot * 137.508) % 360.0; // golden angle → well-separated
    final sat = (0.58 + (slot % 4) * 0.07).clamp(0.0, 1.0);
    final light = (0.52 + (slot % 3) * 0.05).clamp(0.0, 1.0);
    return HSLColor.fromAHSL(1, hue, sat, light).toColor();
  }

  void _scheduleSaveColors() {
    if (_colorsSaveScheduled) return;
    _colorsSaveScheduled = true;
    Future.microtask(() {
      _colorsSaveScheduled = false;
      _storage.saveAuthorColors(_authorSlots);
    });
  }

  // ------------------------------------------------------ tab persistence ---
  void _restoreTabs(Map<String, dynamic> data) {
    final rawTabs = (data['tabs'] as List?) ?? const [];
    final restored = <AppTab>[];
    for (final t in rawTabs) {
      final tab = AppTab.fromJson(t as Map<String, dynamic>);
      if (tab == null) continue;
      // Drop repo tabs whose repository no longer exists.
      if (tab.kind == TabKind.repo &&
          !repositories.any((r) => r.id == tab.repoId)) {
        continue;
      }
      restored.add(tab);
    }
    // Always keep a single Launchpad as the first tab.
    restored.removeWhere((t) => t.kind == TabKind.launchpad);
    tabs = [const AppTab(TabKind.launchpad), ...restored];
    final savedActive = (data['active'] as num?)?.toInt() ?? 0;
    activeTabIndex = savedActive.clamp(0, tabs.length - 1);
  }

  void _persistTabs() {
    _storage.saveTabs({
      'tabs': tabs.map((t) => t.toJson()).toList(),
      'active': activeTabIndex,
    });
  }

  RepoState repoState(String repoId) {
    return _repoStates.putIfAbsent(repoId, () {
      final repo = repositories.firstWhere((r) => r.id == repoId);
      final state = RepoState(repo)..refreshAll();
      return state;
    });
  }

  // ----------------------------------------------------------- repos ----
  Future<void> addRepository(GitRepository repo) async {
    if (repositories.any((r) => r.path == repo.path)) {
      // Already added — just open it.
      final existing = repositories.firstWhere((r) => r.path == repo.path);
      openRepo(existing);
      return;
    }
    repositories = [...repositories, repo];
    await _storage.saveRepositories(repositories);
    notifyListeners();
    openRepo(repo);
  }

  Future<void> removeRepository(GitRepository repo) async {
    repositories = repositories.where((r) => r.id != repo.id).toList();
    _repoStates.remove(repo.id);
    tabs = tabs.where((t) => t.repoId != repo.id).toList();
    if (activeTabIndex >= tabs.length) activeTabIndex = tabs.length - 1;
    await _storage.saveRepositories(repositories);
    _persistTabs();
    notifyListeners();
  }

  // ------------------------------------------------------------ tabs ----
  void openRepo(GitRepository repo) {
    final idx = tabs.indexWhere((t) => t.repoId == repo.id);
    if (idx >= 0) {
      activeTabIndex = idx;
    } else {
      tabs = [...tabs, AppTab(TabKind.repo, repoId: repo.id)];
      activeTabIndex = tabs.length - 1;
    }
    _persistTabs();
    notifyListeners();
  }

  void openIntegrations() {
    final idx = tabs.indexWhere((t) => t.kind == TabKind.integrations);
    if (idx >= 0) {
      activeTabIndex = idx;
    } else {
      tabs = [...tabs, const AppTab(TabKind.integrations)];
      activeTabIndex = tabs.length - 1;
    }
    _persistTabs();
    notifyListeners();
  }

  void selectTab(int index) {
    activeTabIndex = index;
    _persistTabs();
    notifyListeners();
  }

  /// Cycles to the next/previous tab (wraps around).
  void selectNextTab() {
    if (tabs.length < 2) return;
    selectTab((activeTabIndex + 1) % tabs.length);
  }

  void selectPreviousTab() {
    if (tabs.length < 2) return;
    selectTab((activeTabIndex - 1 + tabs.length) % tabs.length);
  }

  /// Selects the [oneBased]-th tab (1..9); no-op if out of range.
  void selectTabNumber(int oneBased) {
    final i = oneBased - 1;
    if (i >= 0 && i < tabs.length) selectTab(i);
  }

  /// Label for a tab (used by the tabs list).
  String tabTitle(AppTab tab) {
    switch (tab.kind) {
      case TabKind.launchpad:
        return 'Home';
      case TabKind.integrations:
        return 'Integrations';
      case TabKind.repo:
        final repo = repositories.where((r) => r.id == tab.repoId);
        return repo.isEmpty ? 'Repository' : repo.first.name;
    }
  }

  void closeTab(int index) {
    if (tabs[index].kind == TabKind.launchpad) return; // keep launchpad
    tabs = [...tabs]..removeAt(index);
    if (activeTabIndex >= tabs.length) activeTabIndex = tabs.length - 1;
    if (activeTabIndex < 0) activeTabIndex = 0;
    _persistTabs();
    notifyListeners();
  }

  /// Moves the tab at [from] so it takes the slot at [to] (drag-to-reorder).
  /// The launchpad stays pinned at index 0; the active tab follows its content.
  void reorderTab(int from, int to) {
    if (from == to) return;
    if (from <= 0 || from >= tabs.length) return; // never move Home
    to = to.clamp(1, tabs.length - 1); // never displace Home at index 0
    final active = tabs[activeTabIndex];
    final list = [...tabs];
    final moved = list.removeAt(from);
    list.insert(to, moved);
    tabs = list;
    activeTabIndex = tabs.indexOf(active).clamp(0, tabs.length - 1);
    _persistTabs();
    notifyListeners();
  }

  // --------------------------------------------------- integrations ----
  /// Saved integrations of a given provider.
  List<Integration> integrationsOf(ProviderType p) =>
      integrations.where((i) => i.provider == p).toList();

  Future<void> addIntegration(Integration instance, String secret) async {
    integrations = [
      ...integrations.where((a) => a.id != instance.id),
      instance,
    ];
    await _storage.saveIntegrations(integrations);
    await _storage.savePat(instance.id, secret);
    notifyListeners();
  }

  Future<void> removeIntegration(Integration instance) async {
    integrations = integrations.where((a) => a.id != instance.id).toList();
    await _storage.saveIntegrations(integrations);
    await _storage.deletePat(instance.id);
    notifyListeners();
  }

  Future<String?> secretFor(String instanceId) => _storage.readPat(instanceId);
}
