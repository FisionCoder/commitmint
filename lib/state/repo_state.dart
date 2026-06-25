import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';

import '../models/file_change.dart';
import '../models/git_branch.dart';
import '../models/git_commit.dart';
import '../models/git_repository.dart';
import '../models/integration.dart';
import '../models/pull_request.dart';
import '../services/azure_devops_service.dart';
import '../services/commit_graph.dart';
import '../services/diff_parser.dart';
import '../services/git_service.dart';
import '../services/storage_service.dart';

/// Which content mode the per-file detail view is showing.
enum FileViewMode { diff, file }

/// Live state for one open repository tab.
class RepoState extends ChangeNotifier {
  final GitRepository repo;
  late final GitService git;
  final StorageService _storage = StorageService();

  RepoState(this.repo) {
    git = GitService(repo.path);
  }

  bool loading = true;
  bool busy = false; // a long action (pull/push) is running
  String? loadError;

  List<GitCommit> commits = [];
  List<GraphRow> graphRows = [];
  List<GitRef> localBranches = [];
  List<GitRef> remoteBranches = [];
  List<GitRef> tags = [];
  List<GitRef> stashes = [];
  String currentBranch = '';

  /// Hash of the commit HEAD points at (the current branch tip). The graph pins
  /// this to the leftmost lane and the WIP node links down to it.
  String? headHash;

  List<FileChange> unstaged = [];
  List<FileChange> staged = [];

  GitCommit? selectedCommit;
  bool selectingWip = true; // the "// WIP" working-changes row is selected

  // Graph view filters (Solo / Pin to Left).
  String? soloHash;
  String? pinnedHash;
  bool get hasGraphFilter => soloHash != null || pinnedHash != null;

  /// Controller + focus node for the branch-sidebar filter field, so a global
  /// shortcut can focus, read and clear it. Used by [BranchSidebar].
  final TextEditingController branchFilter = TextEditingController();
  final FocusNode branchFilterFocus = FocusNode();

  /// Clears the branch filter text and notifies (so the sidebar rebuilds).
  void clearBranchFilter() {
    branchFilter.clear();
    notifyListeners();
  }

  /// The branch currently hovered in the sidebar, used to highlight its
  /// associated commit rows in the graph (when that setting is enabled).
  String? hoverBranch;
  void setHoverBranch(String? b) {
    if (hoverBranch == b) return;
    hoverBranch = b;
    notifyListeners();
  }

  @override
  void dispose() {
    branchFilter.dispose();
    branchFilterFocus.dispose();
    super.dispose();
  }

  // Commit search (filters the graph to matching commits in the current tab).
  String commitSearch = '';
  bool searchVisible = false;
  bool get hasCommitSearch => commitSearch.trim().isNotEmpty;

  void openSearch() {
    if (searchVisible) return;
    searchVisible = true;
    notifyListeners();
  }

  void closeSearch() {
    if (!searchVisible && commitSearch.isEmpty) return;
    searchVisible = false;
    commitSearch = '';
    _recomputeGraph();
    notifyListeners();
  }

  void toggleSearch() => searchVisible ? closeSearch() : openSearch();

  /// Number of commits matching the active search (0 when no search).
  int get searchMatchCount => hasCommitSearch ? graphRows.length : 0;

  void setCommitSearch(String v) {
    if (v == commitSearch) return;
    commitSearch = v;
    _recomputeGraph();
    notifyListeners();
  }

  bool _matchesSearch(GitCommit c, String q) =>
      c.subject.toLowerCase().contains(q) ||
      c.author.toLowerCase().contains(q) ||
      c.authorEmail.toLowerCase().contains(q) ||
      c.hash.toLowerCase().contains(q) ||
      c.refs.any((r) => r.toLowerCase().contains(q));

  // Hidden refs (full ref names, e.g. refs/heads/foo) — excluded from the
  // graph and the sidebar lists.
  final Set<String> hiddenRefs = {};

  String fullRefName(GitRef r) {
    switch (r.kind) {
      case RefKind.localBranch:
        return 'refs/heads/${r.name}';
      case RefKind.remoteBranch:
        return 'refs/remotes/${r.name}';
      case RefKind.tag:
        return 'refs/tags/${r.name}';
      case RefKind.stash:
        return r.name;
    }
  }

  bool isHidden(GitRef r) => hiddenRefs.contains(fullRefName(r));

  // Pull requests (Azure DevOps).
  List<PullRequest> pullRequests = [];
  bool prsLoading = false;
  String? prError;
  String prSearch = '';

  void setPrSearch(String v) {
    prSearch = v;
    notifyListeners();
  }

  Future<void> _fetchPullRequests() async {
    final remote = await git.remoteUrl();
    final parsed = AzureRemote.parse(remote);
    if (parsed == null) {
      pullRequests = [];
      prError = null;
      return;
    }
    final instances = await _storage.loadIntegrations();
    final match = instances.where((a) =>
        a.provider == ProviderType.azureDevOps &&
        a.organization.toLowerCase() == parsed.org.toLowerCase());
    if (match.isEmpty) {
      pullRequests = [];
      prError = 'Connect Azure DevOps (org "${parsed.org}") to see pull requests.';
      notifyListeners();
      return;
    }
    final instance = match.first;
    final pat = await _storage.readPat(instance.id);
    if (pat == null) {
      prError = 'No stored token for ${parsed.org}.';
      notifyListeners();
      return;
    }
    prsLoading = true;
    notifyListeners();
    try {
      pullRequests = await AzureDevOpsService.listPullRequests(parsed, pat,
          currentUser: instance.userName);
      prError = null;
    } catch (e) {
      prError = e.toString();
    } finally {
      prsLoading = false;
      notifyListeners();
    }
  }

  // Stashes hidden from the list (keyed by stash commit sha).
  final Set<String> hiddenStashShas = {};
  bool isStashHidden(GitRef s) =>
      s.targetHash != null && hiddenStashShas.contains(s.targetHash);
  void hideStash(GitRef s) {
    if (s.targetHash != null) {
      hiddenStashShas.add(s.targetHash!);
      notifyListeners();
    }
  }

  // Commit form
  String commitSummary = '';
  String commitDescription = '';
  bool amend = false;

  // Embedded terminal panel (per-tab) visibility.
  bool terminalVisible = false;
  void toggleTerminal() {
    terminalVisible = !terminalVisible;
    notifyListeners();
  }

  // Changes panel grouping: flat path list (false) vs directory tree (true).
  bool treeView = false;
  void setTreeView(bool v) {
    if (v == treeView) return;
    treeView = v;
    notifyListeners();
  }

  // File detail view (replaces the commit graph when a file is opened).
  FileChange? openFile;
  FileViewMode fileViewMode = FileViewMode.diff;
  bool viewStaged = false; // diff against the index (staged) vs working tree
  bool editing = false;
  bool get isFileOpen => openFile != null;

  int get totalChanges => unstaged.length + staged.length;
  bool get canCommit =>
      staged.isNotEmpty && commitSummary.trim().isNotEmpty && !busy;

  Future<void> refreshAll() async {
    loadError = null;
    // A repository whose folder was moved/deleted can't be read — surface a
    // clear error instead of throwing from the git subprocess.
    if (!git.workingDirExists) {
      loadError = 'Repository folder not found:\n${repo.path}';
      loading = false;
      notifyListeners();
      return;
    }
    try {
      final results = await Future.wait([
        git.currentBranch(),
        git.refs(),
        git.stashes(),
        git.log(excludeRefs: hiddenRefs.toList()),
        git.status(),
        git.stashCommits(),
      ]);
      currentBranch = results[0] as String;
      final refs = results[1] as List<GitRef>;
      stashes = results[2] as List<GitRef>;
      commits = results[3] as List<GitCommit>;
      final changes = results[4] as List<FileChange>;
      final stashNodes = results[5] as List<GitCommit>;
      commits = _mergeStashNodes(commits, stashNodes);

      // The HEAD commit (current branch tip), identified by its ref marker.
      headHash = null;
      for (final c in commits) {
        if (c.refs.any((r) => r == 'HEAD' || r.startsWith('HEAD ->'))) {
          headHash = c.hash;
          break;
        }
      }

      localBranches =
          refs.where((r) => r.kind == RefKind.localBranch).toList();
      remoteBranches =
          refs.where((r) => r.kind == RefKind.remoteBranch).toList();
      tags = refs.where((r) => r.kind == RefKind.tag).toList();

      staged = changes.where((c) => c.staged).toList();
      unstaged = changes.where((c) => !c.staged).toList();

      _recomputeGraph();
      loading = false;
    } catch (e) {
      loadError = e.toString();
      loading = false;
    }
    notifyListeners();
    // Pull requests load in the background (network) so they never block the
    // graph from rendering.
    unawaited(_fetchPullRequests());
  }

  /// Inserts stash (WIP) nodes into the date-ordered [base] commit list, placed
  /// just above the commit each was stashed on. A stash whose base commit isn't
  /// visible (unreachable / beyond the log limit) becomes a parentless node so
  /// no connector line dangles to the bottom of the graph.
  List<GitCommit> _mergeStashNodes(
      List<GitCommit> base, List<GitCommit> stashNodes) {
    if (stashNodes.isEmpty) return base;
    final visible = {for (final c in base) c.hash};
    final result = List<GitCommit>.from(base);
    for (final s in stashNodes) {
      final baseHash = s.parents.isEmpty ? null : s.parents.first;
      final node = (baseHash != null && visible.contains(baseHash))
          ? s
          : GitCommit(
              hash: s.hash,
              parents: const [],
              author: s.author,
              authorEmail: s.authorEmail,
              date: s.date,
              subject: s.subject,
              body: s.body,
              refs: const [],
              isStash: true,
              stashIndex: s.stashIndex,
            );
      // Position by date, but never below its own base commit.
      var insertAt = result.length;
      for (var i = 0; i < result.length; i++) {
        if (result[i].date.isBefore(s.date)) {
          insertAt = i;
          break;
        }
      }
      if (baseHash != null) {
        final bi = result.indexWhere((c) => c.hash == baseHash);
        if (bi >= 0 && bi < insertAt) insertAt = bi;
      }
      result.insert(insertAt, node);
    }
    return result;
  }

  void _recomputeGraph() {
    var visible = commits;
    if (soloHash != null) visible = _ancestorsOf(soloHash!);
    final q = commitSearch.trim().toLowerCase();
    if (q.isNotEmpty) {
      visible = visible.where((c) => _matchesSearch(c, q)).toList();
    }
    // An explicit Solo/Pin tip wins (solid); otherwise pin the current branch's
    // HEAD to the leftmost lane as a dashed "HEAD pointer" spine so the WIP node
    // links down to the active branch.
    String? pin = pinnedHash;
    var dashed = false;
    if (pin == null && headHash != null) {
      pin = headHash;
      dashed = true;
    }
    graphRows =
        CommitGraph.layout(visible, pinnedTip: pin, pinnedDashed: dashed);
  }

  /// Commits reachable from [hash] (itself + all ancestors) within [commits].
  List<GitCommit> _ancestorsOf(String hash) {
    final byHash = {for (final c in commits) c.hash: c};
    final keep = <String>{};
    final stack = <String>[hash];
    while (stack.isNotEmpty) {
      final h = stack.removeLast();
      if (!keep.add(h)) continue;
      final c = byHash[h];
      if (c != null) stack.addAll(c.parents);
    }
    return commits.where((c) => keep.contains(c.hash)).toList();
  }

  void soloCommit(String hash) {
    soloHash = hash;
    _recomputeGraph();
    notifyListeners();
  }

  void pinToLeft(String hash) {
    pinnedHash = hash;
    _recomputeGraph();
    notifyListeners();
  }

  void clearGraphFilter() {
    soloHash = null;
    pinnedHash = null;
    _recomputeGraph();
    notifyListeners();
  }

  void selectCommit(GitCommit? c) {
    selectedCommit = c;
    selectingWip = false;
    notifyListeners();
  }

  void selectWip() {
    selectingWip = true;
    selectedCommit = null;
    notifyListeners();
  }

  // ------------------------------------------------------- file detail view ---
  void openFileDetail(FileChange f) {
    openFile = f;
    viewStaged = f.staged;
    fileViewMode = FileViewMode.diff;
    editing = false;
    notifyListeners();
  }

  void closeFileDetail() {
    openFile = null;
    editing = false;
    notifyListeners();
  }

  void setFileViewMode(FileViewMode m) {
    fileViewMode = m;
    editing = false;
    notifyListeners();
  }

  void setViewStaged(bool staged) {
    viewStaged = staged;
    notifyListeners();
  }

  void setEditing(bool v) {
    editing = v;
    notifyListeners();
  }

  /// Loads and parses the diff for the currently open file.
  Future<FileDiff> loadOpenFileDiff() async {
    final f = openFile;
    if (f == null) return const FileDiff(headerLines: [], hunks: [], isEmpty: true);
    if (f.type == ChangeType.untracked && !viewStaged) {
      final content = await git.readFileContent(f.path);
      return DiffParser.forNewFile(f.path, content);
    }
    final raw = await git.rawFileDiff(f.path, staged: viewStaged);
    return DiffParser.parse(raw);
  }

  Future<String> loadOpenFileContent() async {
    final f = openFile;
    if (f == null) return '';
    return git.readFileContent(f.path);
  }

  Future<void> stageHunk(FileDiff diff, DiffHunk hunk) async {
    await git.applyPatch(diff.patchFor(hunk), cached: true);
    await _afterMutation();
  }

  Future<void> unstageHunk(FileDiff diff, DiffHunk hunk) async {
    await git.applyPatch(diff.patchFor(hunk), cached: true, reverse: true);
    await _afterMutation();
  }

  Future<void> discardHunk(FileDiff diff, DiffHunk hunk) async {
    await git.applyPatch(diff.patchFor(hunk), reverse: true);
    await _afterMutation();
  }

  Future<void> saveOpenFile(String content) async {
    final f = openFile;
    if (f == null) return;
    await git.writeFileContent(f.path, content);
    editing = false;
    await _afterMutation();
  }

  Future<void> stageOpenFile() async {
    final f = openFile;
    if (f == null) return;
    await git.stage(f.path);
    await _afterMutation();
  }

  void setCommitSummary(String v) {
    commitSummary = v;
    notifyListeners();
  }

  void setCommitDescription(String v) {
    commitDescription = v;
  }

  void setAmend(bool v) {
    amend = v;
    notifyListeners();
  }

  Future<void> _afterMutation() async {
    final changes = await git.status();
    staged = changes.where((c) => c.staged).toList();
    unstaged = changes.where((c) => !c.staged).toList();
    notifyListeners();
  }

  Future<void> stageFile(FileChange f) async {
    await git.stage(f.path);
    await _afterMutation();
  }

  Future<void> unstageFile(FileChange f) async {
    await git.unstage(f.path);
    await _afterMutation();
  }

  Future<void> stageAll() async {
    await git.stageAll();
    await _afterMutation();
  }

  Future<void> unstageAll() async {
    await git.unstageAll();
    await _afterMutation();
  }

  Future<void> discard(FileChange f) async {
    await git.discard(f.path);
    await _afterMutation();
  }

  Future<void> discardAllChanges() async {
    await git.discardAllChanges();
    await _afterMutation();
  }

  Future<void> doCommit() async {
    await git.commit(commitSummary,
        description: commitDescription, amend: amend);
    commitSummary = '';
    commitDescription = '';
    amend = false;
    await refreshAll();
  }

  /// Quick commit from the inline WIP row. Commits the staged files; if nothing
  /// is staged yet it stages all current changes first, so a single Enter on
  /// the WIP row commits the working tree (GitKraken-style). No-op when there's
  /// nothing to commit.
  Future<void> commitWip(String summary) {
    return _runAction(() async {
      final msg = summary.trim();
      if (msg.isEmpty || totalChanges == 0) return;
      if (staged.isEmpty) await git.stageAll();
      await git.commit(msg);
      commitSummary = '';
      commitDescription = '';
    });
  }

  Future<T> _runAction<T>(Future<T> Function() action) async {
    busy = true;
    notifyListeners();
    try {
      return await action();
    } finally {
      busy = false;
      await refreshAll();
    }
  }

  /// Resolves an `Authorization: Basic …` header from the stored PAT of the
  /// Azure DevOps instance matching this repo's remote, so pull/push/fetch
  /// authenticate without the interactive Git Credential Manager. Returns null
  /// for non-Azure remotes or when no matching token is stored.
  Future<String?> _remoteAuthHeader() async {
    final remote = await git.remoteUrl();
    final parsed = AzureRemote.parse(remote);
    if (parsed == null) return null;
    final instances = await _storage.loadIntegrations();
    final match = instances.where((a) =>
        a.provider == ProviderType.azureDevOps &&
        a.organization.toLowerCase() == parsed.org.toLowerCase());
    if (match.isEmpty) return null;
    final pat = await _storage.readPat(match.first.id);
    if (pat == null || pat.isEmpty) return null;
    final token = base64.encode(utf8.encode(':$pat'));
    return 'Authorization: Basic $token';
  }

  Future<void> pull() => _runAction(() async {
        await git.pull(authHeader: await _remoteAuthHeader());
      });
  Future<void> push() => _runAction(() async {
        await git.push(authHeader: await _remoteAuthHeader());
      });
  Future<void> fetch() => _runAction(() async {
        await git.fetch(authHeader: await _remoteAuthHeader());
      });
  Future<void> checkout(String branch) =>
      _runAction(() => git.checkout(branch));
  Future<void> createBranch(String name) =>
      _runAction(() => git.createBranch(name));
  Future<void> stashPush() => _runAction(() => git.stashPush());
  Future<void> stashPop() => _runAction(() => git.stashPop());

  // ---- commit context-menu operations ----
  Future<void> checkoutCommit(String sha) =>
      _runAction(() => git.checkoutCommit(sha));
  Future<void> createBranchAt(String name, String sha) =>
      _runAction(() => git.createBranchAt(name, sha));
  Future<void> resetTo(String sha, String mode) =>
      _runAction(() => git.resetTo(sha, mode));
  Future<void> revertCommit(String sha) =>
      _runAction(() => git.revertCommit(sha));
  Future<void> amendMessage(String message) =>
      _runAction(() => git.amendMessage(message));
  Future<void> dropCommit(String sha) =>
      _runAction(() => git.dropCommit(sha));
  Future<void> setUpstreamToTracking() => _runAction(
      () => git.setUpstream(currentBranch, 'origin/$currentBranch'));
  Future<void> renameBranch(String oldName, String newName) =>
      _runAction(() => git.renameBranch(oldName, newName));
  Future<void> deleteBranch(String name, {bool force = false}) =>
      _runAction(() => git.deleteBranch(name, force: force));
  Future<void> deleteRemoteBranch(String remote, String name) =>
      _runAction(() => git.deleteRemoteBranch(remote, name));
  Future<void> createTag(String name, String sha) =>
      _runAction(() => git.createTag(name, sha));
  Future<void> createAnnotatedTag(String name, String message, String sha) =>
      _runAction(() => git.createAnnotatedTag(name, message, sha));
  Future<void> applyPatchFile(String path) =>
      _runAction(() => git.applyPatchFile(path));
  Future<void> worktreeAdd(String path, String ref) =>
      _runAction(() => git.worktreeAdd(path, ref));
  Future<void> moveCommitDown(String sha) =>
      _runAction(() => git.moveCommitDown(sha, currentBranch));

  // ---- branch context-menu operations ----
  Future<void> merge(String branch) => _runAction(() => git.merge(branch));
  Future<void> rebaseOnto(String branch) =>
      _runAction(() => git.rebaseOnto(branch));
  Future<void> interactiveRebase(String branch) =>
      _runAction(() => git.interactiveRebase(branch));
  Future<void> cherryPick(String sha) =>
      _runAction(() => git.cherryPick(sha));

  // ---- stash context-menu operations ----
  Future<void> stashApply(int index) =>
      _runAction(() => git.stashApply(index));
  Future<void> stashPopAt(int index) =>
      _runAction(() => git.stashPopAt(index));
  Future<void> stashDrop(int index) => _runAction(() => git.stashDrop(index));
  Future<void> editStashMessage(int index, String message) =>
      _runAction(() => git.editStashMessage(index, message));

  // ---- hiding refs (branches/tags) ----
  void hideRef(GitRef r) {
    hiddenRefs.add(fullRefName(r));
    refreshAll();
  }

  void showRef(GitRef r) {
    hiddenRefs.remove(fullRefName(r));
    refreshAll();
  }

  void hideAllLocal() {
    for (final b in localBranches) {
      hiddenRefs.add(fullRefName(b));
    }
    refreshAll();
  }

  void showAllLocal() {
    hiddenRefs.removeWhere((r) => r.startsWith('refs/heads/'));
    refreshAll();
  }

  void hideAllRemote() {
    for (final b in remoteBranches) {
      hiddenRefs.add(fullRefName(b));
    }
    refreshAll();
  }

  void showAllRemote() {
    hiddenRefs.removeWhere((r) => r.startsWith('refs/remotes/'));
    refreshAll();
  }
}
