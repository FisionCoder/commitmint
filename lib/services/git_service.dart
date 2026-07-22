import 'dart:io';

import '../models/file_change.dart';
import '../models/git_branch.dart';
import '../models/git_commit.dart';

class GitException implements Exception {
  final String message;
  GitException(this.message);
  @override
  String toString() => message;
}

/// App-wide git runtime overrides driven by Settings (SSH key / agent and
/// credential-manager behaviour). Consulted by every network git command so
/// the SSH and credential settings actually take effect without threading
/// state through every call.
class GitRuntimeConfig {
  GitRuntimeConfig._();

  /// Explicit SSH private key to use for SSH remotes (null = system default).
  static String? sshKeyPath;

  /// When true, use the system SSH agent / default keys and ignore [sshKeyPath].
  static bool useLocalAgent = false;

  /// When false, disable the OS credential manager for HTTPS operations.
  static bool useCredentialManager = true;

  /// `-c` overrides applied to every network git invocation.
  static List<String> configArgs() {
    final args = <String>[];
    final key = sshKeyPath;
    if (!useLocalAgent && key != null && key.trim().isNotEmpty) {
      // Force this key and ignore agent identities. Forward slashes work on
      // Windows OpenSSH and avoid backslash escaping issues.
      final p = key.trim().replaceAll(r'\', '/');
      args.addAll(
          ['-c', 'core.sshCommand=ssh -i "$p" -o IdentitiesOnly=yes']);
    }
    if (!useCredentialManager) {
      // Empty helper disables any configured credential manager for this call.
      args.addAll(['-c', 'credential.helper=']);
    }
    return args;
  }
}

/// A checked-out worktree of the repository (`git worktree list`).
class GitWorktree {
  final String path;

  /// Short branch name, or null when detached/bare.
  final String? branch;
  final String sha;
  final bool isMain;
  final bool bare;
  final bool detached;
  const GitWorktree({
    required this.path,
    required this.branch,
    required this.sha,
    required this.isMain,
    required this.bare,
    required this.detached,
  });
}

/// One line of `git blame` output: its content plus the commit that last
/// touched it.
class BlameLine {
  final String sha;
  final String author;
  final String summary;
  final DateTime date;
  final int lineNo;
  final String content;
  const BlameLine({
    required this.sha,
    required this.author,
    required this.summary,
    required this.date,
    required this.lineNo,
    required this.content,
  });

  String get shortSha => sha.length >= 7 ? sha.substring(0, 7) : sha;
}

/// A configured remote (`git remote`).
class GitRemote {
  final String name;
  final String fetchUrl;
  final String pushUrl;
  const GitRemote(
      {required this.name, required this.fetchUrl, required this.pushUrl});
}

/// A submodule entry (`git submodule status`).
class GitSubmodule {
  final String path;
  final String sha;

  /// `git describe` output in parentheses, if any.
  final String describe;

  /// Leading status flag: ' ' in sync, '+' checked-out differs, '-' not
  /// initialized, 'U' merge conflicts.
  final String status;
  const GitSubmodule({
    required this.path,
    required this.sha,
    required this.describe,
    required this.status,
  });

  bool get uninitialized => status == '-';
  bool get modified => status == '+';
}

/// A `git reflog` entry.
class ReflogEntry {
  final String sha;

  /// The selector, e.g. `HEAD@{2}`.
  final String selector;

  /// The action + message, e.g. `commit: fix thing` or `reset: moving to …`.
  final String subject;
  const ReflogEntry(
      {required this.sha, required this.selector, required this.subject});

  String get shortSha => sha.length >= 7 ? sha.substring(0, 7) : sha;
}

/// Per-commit action in an interactive rebase plan.
enum RebaseAction { pick, reword, edit, squash, fixup, drop }

/// One step of an interactive rebase plan (a commit + what to do with it).
class RebaseStep {
  final String sha;
  final String subject;
  final RebaseAction action;

  /// New message for a [RebaseAction.reword] step.
  final String? newMessage;
  const RebaseStep({
    required this.sha,
    required this.subject,
    required this.action,
    this.newMessage,
  });

  RebaseStep copyWith({RebaseAction? action, String? newMessage}) => RebaseStep(
        sha: sha,
        subject: subject,
        action: action ?? this.action,
        newMessage: newMessage ?? this.newMessage,
      );
}

/// A multi-step git operation that can pause on conflicts and be
/// continued/aborted.
enum GitOperation { none, merge, rebase, cherryPick, revert }

extension GitOperationLabel on GitOperation {
  String get label {
    switch (this) {
      case GitOperation.merge:
        return 'Merge';
      case GitOperation.rebase:
        return 'Rebase';
      case GitOperation.cherryPick:
        return 'Cherry-pick';
      case GitOperation.revert:
        return 'Revert';
      case GitOperation.none:
        return '';
    }
  }
}

/// Thin wrapper around the system `git` CLI.
class GitService {
  final String workingDir;
  GitService(this.workingDir);

  static const _us = '\x1f'; // unit separator
  static const _rs = '\x1e'; // record separator

  /// Whether the repository's working directory still exists on disk.
  bool get workingDirExists => Directory(workingDir).existsSync();

  Future<ProcessResult> _run(List<String> args,
      {Map<String, String>? env}) async {
    // Guard against a moved/deleted repo folder: a missing workingDirectory
    // makes Process.run throw a Win32 "directory name is invalid" error, which
    // would crash fire-and-forget callers. Fail gracefully instead.
    if (!workingDirExists) {
      return ProcessResult(
          0, 128, '', 'fatal: repository folder not found: $workingDir');
    }
    try {
      return await Process.run(
        'git',
        args,
        workingDirectory: workingDir,
        runInShell: Platform.isWindows,
        environment: env,
        stdoutEncoding: SystemEncoding(),
        stderrEncoding: SystemEncoding(),
      );
    } on ProcessException catch (e) {
      return ProcessResult(0, 128, '', 'Failed to run git: ${e.message}');
    }
  }

  /// Runs a mutating command; throws on failure with stderr.
  Future<String> _runOrThrow(List<String> args,
      {Map<String, String>? env}) async {
    final r = await _run(args, env: env);
    if (r.exitCode != 0) {
      final err = (r.stderr as String).trim();
      final out = (r.stdout as String).trim();
      throw GitException(err.isNotEmpty ? err : (out.isNotEmpty ? out : 'git ${args.join(' ')} failed'));
    }
    return r.stdout as String;
  }

  static Future<bool> isGitRepo(String path) async {
    try {
      final r = await Process.run(
        'git',
        ['rev-parse', '--is-inside-work-tree'],
        workingDirectory: path,
        runInShell: Platform.isWindows,
      );
      return r.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  Future<String> currentBranch() async {
    final r = await _run(['rev-parse', '--abbrev-ref', 'HEAD']);
    if (r.exitCode != 0) return 'HEAD';
    return (r.stdout as String).trim();
  }

  // ---------------------------------------------------------------- refs ----
  Future<List<GitRef>> refs() async {
    final fmt = [
      '%(refname)',
      '%(objectname)',
      '%(HEAD)',
      '%(upstream:short)',
      '%(upstream:track)',
    ].join(_us);
    final r = await _run([
      'for-each-ref',
      '--format=$fmt',
      'refs/heads',
      'refs/remotes',
      'refs/tags',
    ]);
    if (r.exitCode != 0) return [];

    final refs = <GitRef>[];
    for (final line in (r.stdout as String).split('\n')) {
      if (line.trim().isEmpty) continue;
      final f = line.split(_us);
      if (f.length < 5) continue;
      final fullName = f[0];
      final hash = f[1];
      final isHead = f[2] == '*';
      final upstream = f[3].isEmpty ? null : f[3];
      final track = f[4];

      var ahead = 0, behind = 0;
      final aMatch = RegExp(r'ahead (\d+)').firstMatch(track);
      final bMatch = RegExp(r'behind (\d+)').firstMatch(track);
      if (aMatch != null) ahead = int.parse(aMatch.group(1)!);
      if (bMatch != null) behind = int.parse(bMatch.group(1)!);

      if (fullName.startsWith('refs/heads/')) {
        refs.add(GitRef(
          name: fullName.substring('refs/heads/'.length),
          kind: RefKind.localBranch,
          isCurrent: isHead,
          upstream: upstream,
          ahead: ahead,
          behind: behind,
          targetHash: hash,
        ));
      } else if (fullName.startsWith('refs/remotes/')) {
        final shortName = fullName.substring('refs/remotes/'.length);
        if (shortName.endsWith('/HEAD')) continue;
        refs.add(GitRef(
          name: shortName,
          kind: RefKind.remoteBranch,
          targetHash: hash,
        ));
      } else if (fullName.startsWith('refs/tags/')) {
        refs.add(GitRef(
          name: fullName.substring('refs/tags/'.length),
          kind: RefKind.tag,
          targetHash: hash,
        ));
      }
    }
    return refs;
  }

  /// Stash entries as graph nodes (one per `stash@{N}`). Each node's `parents`
  /// is its base commit (the first parent — the HEAD it was stashed on); the
  /// internal index/untracked parents are dropped so the graph stays clean.
  Future<List<GitCommit>> stashCommits() async {
    final fmt = ['%H', '%P', '%an', '%ae', '%aI', '%gs'].join(_us);
    final r = await _run(['stash', 'list', '--format=$fmt']);
    if (r.exitCode != 0) return [];
    final out = <GitCommit>[];
    var index = 0;
    for (final line in (r.stdout as String).split('\n')) {
      if (line.trim().isEmpty) continue;
      final f = line.split(_us);
      if (f.length < 6) {
        index++;
        continue;
      }
      final allParents =
          f[1].trim().isEmpty ? <String>[] : f[1].trim().split(' ');
      final base = allParents.isEmpty ? <String>[] : [allParents.first];
      DateTime date;
      try {
        date = DateTime.parse(f[4]).toLocal();
      } catch (_) {
        date = DateTime.fromMillisecondsSinceEpoch(0);
      }
      // Trim the auto-generated ": <sha> <subject>" tail from "WIP on X: ..."
      // so the node reads "WIP on <branch>" like other Git clients.
      var msg = f[5];
      final m = RegExp(r'^(WIP on [^:]+):').firstMatch(msg);
      if (m != null) msg = m.group(1)!;
      out.add(GitCommit(
        hash: f[0],
        parents: base,
        author: f[2],
        authorEmail: f[3],
        date: date,
        subject: msg,
        body: '',
        refs: const [],
        isStash: true,
        stashIndex: index,
      ));
      index++;
    }
    return out;
  }

  Future<List<GitRef>> stashes() async {
    final r = await _run(['stash', 'list', '--format=%gd$_us%H$_us%s']);
    if (r.exitCode != 0) return [];
    final out = <GitRef>[];
    for (final line in (r.stdout as String).split('\n')) {
      if (line.trim().isEmpty) continue;
      final f = line.split(_us);
      out.add(GitRef(
        name: f.length > 2 ? f[2] : (f.isNotEmpty ? f[0] : ''),
        kind: RefKind.stash,
        targetHash: f.length > 1 ? f[1] : null,
      ));
    }
    return out;
  }

  // ------------------------------------------------------------- commits ----
  /// Field order for the commit pretty-format used by [log]/[fileHistory].
  static const _commitFmt = '%H\x1f%P\x1f%an\x1f%ae\x1f%aI\x1f%D\x1f%s\x1f%b';

  List<GitCommit> _parseCommitRecords(String out) {
    final commits = <GitCommit>[];
    for (final record in out.split(_rs)) {
      final rec = record.trim();
      if (rec.isEmpty) continue;
      final f = rec.split(_us);
      if (f.length < 7) continue;
      final parents =
          f[1].trim().isEmpty ? <String>[] : f[1].trim().split(' ');
      DateTime date;
      try {
        date = DateTime.parse(f[4]).toLocal();
      } catch (_) {
        date = DateTime.fromMillisecondsSinceEpoch(0);
      }
      final refs = f[5]
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
      commits.add(GitCommit(
        hash: f[0],
        parents: parents,
        author: f[2],
        authorEmail: f[3],
        date: date,
        subject: f[6],
        body: f.length > 7 ? f.sublist(7).join(_us).trim() : '',
        refs: refs,
      ));
    }
    return commits;
  }

  /// [excludeRefs] are full ref patterns (e.g. refs/heads/foo) to hide.
  Future<List<GitCommit>> log(
      {int limit = 400, List<String> excludeRefs = const []}) async {
    final r = await _run([
      'log',
      '--date-order',
      for (final ref in excludeRefs) '--exclude=$ref',
      '--branches',
      '--remotes',
      '--tags',
      '-n',
      '$limit',
      '--pretty=format:$_commitFmt$_rs',
    ]);
    if (r.exitCode != 0) return [];
    return _parseCommitRecords(r.stdout as String);
  }

  /// Commit hashes matching a search: by path (`git log -- <path>`) or by
  /// content change / pickaxe (`git log -S<term>`). Searches full history up to
  /// [limit].
  Future<Set<String>> searchCommits(String term,
      {required bool pathMode, int limit = 2000}) async {
    if (term.trim().isEmpty) return {};
    final args = ['log', '--format=%H', '-n', '$limit'];
    if (pathMode) {
      args.addAll(['--', term]);
    } else {
      args.add('-S$term');
    }
    final r = await _run(args);
    if (r.exitCode != 0) return {};
    return (r.stdout as String)
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet();
  }

  /// Commit history for a single file, following renames (`git log --follow`).
  Future<List<GitCommit>> fileHistory(String path, {int limit = 200}) async {
    final r = await _run([
      'log',
      '--follow',
      '-n',
      '$limit',
      '--pretty=format:$_commitFmt$_rs',
      '--',
      path,
    ]);
    if (r.exitCode != 0) return [];
    return _parseCommitRecords(r.stdout as String);
  }

  /// Per-line authorship for [path] (`git blame --line-porcelain`), optionally
  /// as of [commit].
  Future<List<BlameLine>> blame(String path, {String? commit}) async {
    final args = ['blame', '--line-porcelain'];
    if (commit != null) args.add(commit);
    args.addAll(['--', path]);
    final r = await _run(args);
    if (r.exitCode != 0) return const [];
    final out = r.stdout as String;
    final result = <BlameLine>[];
    final headerRe = RegExp(r'^([0-9a-f]{40}) \d+ (\d+)');
    var sha = '';
    var author = '';
    var summary = '';
    var time = 0;
    var lineNo = 0;
    for (final line in out.split('\n')) {
      final m = headerRe.firstMatch(line);
      if (m != null) {
        sha = m.group(1)!;
        lineNo = int.tryParse(m.group(2)!) ?? 0;
        continue;
      }
      if (line.startsWith('author ')) {
        author = line.substring('author '.length);
      } else if (line.startsWith('author-time ')) {
        time = int.tryParse(line.substring('author-time '.length).trim()) ?? 0;
      } else if (line.startsWith('summary ')) {
        summary = line.substring('summary '.length);
      } else if (line.startsWith('\t')) {
        result.add(BlameLine(
          sha: sha,
          author: author,
          summary: summary,
          date: DateTime.fromMillisecondsSinceEpoch(time * 1000),
          lineNo: lineNo,
          content: line.substring(1),
        ));
      }
    }
    return result;
  }

  // -------------------------------------------------------------- status ----
  Future<List<FileChange>> status() async {
    final r = await _run(['status', '--porcelain', '--untracked-files=all']);
    if (r.exitCode != 0) return [];
    final changes = <FileChange>[];
    for (final line in (r.stdout as String).split('\n')) {
      if (line.length < 3) continue;
      final x = line[0];
      final y = line[1];
      var path = line.substring(3).trim();
      if (path.contains(' -> ')) path = path.split(' -> ').last;
      path = _unquote(path);

      if (x == '?' && y == '?') {
        changes.add(FileChange(
            path: path, type: ChangeType.untracked, staged: false));
        continue;
      }
      if (_isConflict(x, y)) {
        changes.add(FileChange(
            path: path, type: ChangeType.conflicted, staged: false));
        continue;
      }
      if (x != ' ' && x != '?') {
        changes.add(
            FileChange(path: path, type: _mapType(x), staged: true));
      }
      if (y != ' ' && y != '?') {
        changes.add(
            FileChange(path: path, type: _mapType(y), staged: false));
      }
    }
    return changes;
  }

  bool _isConflict(String x, String y) {
    final c = '$x$y';
    return c == 'DD' ||
        c == 'AA' ||
        c == 'UU' ||
        x == 'U' ||
        y == 'U';
  }

  ChangeType _mapType(String c) {
    switch (c) {
      case 'A':
        return ChangeType.added;
      case 'D':
        return ChangeType.deleted;
      case 'R':
        return ChangeType.renamed;
      case 'C':
        return ChangeType.added;
      default:
        return ChangeType.modified;
    }
  }

  String _unquote(String s) {
    if (s.startsWith('"') && s.endsWith('"') && s.length >= 2) {
      return s.substring(1, s.length - 1).replaceAll(r'\"', '"');
    }
    return s;
  }

  /// Files touched by a single commit (`git show --name-status`).
  Future<List<FileChange>> commitFiles(String hash) async {
    final r = await _run(
        ['show', '--name-status', '--format=', '-M', '--no-color', hash]);
    if (r.exitCode != 0) return [];
    final out = <FileChange>[];
    for (final line in (r.stdout as String).split('\n')) {
      if (line.trim().isEmpty) continue;
      final parts = line.split('\t');
      if (parts.length < 2) continue;
      final code = parts[0];
      final path = _unquote(parts.last);
      ChangeType type;
      if (code.startsWith('A')) {
        type = ChangeType.added;
      } else if (code.startsWith('D')) {
        type = ChangeType.deleted;
      } else if (code.startsWith('R')) {
        type = ChangeType.renamed;
      } else {
        type = ChangeType.modified;
      }
      out.add(FileChange(path: path, type: type, staged: true));
    }
    return out;
  }

  /// Files that differ between [base] (a commit) and the working tree
  /// (`git diff --name-status <base>`), for "compare against working directory".
  Future<List<FileChange>> compareFiles(String base) async {
    final r =
        await _run(['diff', '--name-status', '-M', '--no-color', base]);
    if (r.exitCode != 0) return [];
    final out = <FileChange>[];
    for (final line in (r.stdout as String).split('\n')) {
      if (line.trim().isEmpty) continue;
      final parts = line.split('\t');
      if (parts.length < 2) continue;
      final code = parts[0];
      final path = _unquote(parts.last);
      out.add(FileChange(path: path, type: _mapType(code[0]), staged: false));
    }
    return out;
  }

  /// Unified diff of a single [path] between [base] and the working tree.
  Future<String> compareFileDiff(String base, String path) async {
    final r = await _run(['diff', '--no-color', '-M', base, '--', path]);
    return r.stdout as String;
  }

  /// Returns a unified diff for a single file (staged or working tree).
  Future<String> diff(String path, {required bool staged}) =>
      rawFileDiff(path, staged: staged);

  /// Raw unified diff for one file (`git diff [--cached] --no-color -- path`).
  Future<String> rawFileDiff(String path,
      {required bool staged, bool ignoreWhitespace = false}) async {
    final args = [
      'diff',
      if (staged) '--cached',
      if (ignoreWhitespace) '-w',
      '--no-color',
      '--',
      path,
    ];
    final r = await _run(args);
    return r.stdout as String;
  }

  /// Reads a working-tree file as text (for File View / editing).
  Future<String> readFileContent(String path) async {
    final f = File('$workingDir${Platform.pathSeparator}$path');
    if (!await f.exists()) return '';
    return f.readAsString();
  }

  /// Unified diff a commit introduced for one file (`git show <hash> -- path`).
  /// Handles the root commit (shown as an addition).
  Future<String> commitFileDiff(String hash, String path,
      {bool ignoreWhitespace = false}) async {
    final r = await _run([
      'show',
      '--format=',
      '--no-color',
      '-M',
      if (ignoreWhitespace) '-w',
      hash,
      '--',
      path,
    ]);
    return r.stdout as String;
  }

  /// The contents of a file as of a specific commit (`git show <hash>:path`).
  Future<String> fileContentAt(String hash, String path) async {
    final r = await _run(['show', '$hash:$path']);
    if (r.exitCode != 0) return '';
    return r.stdout as String;
  }

  /// Overwrites a working-tree file with [content] (used by the editor).
  Future<void> writeFileContent(String path, String content) async {
    final f = File('$workingDir${Platform.pathSeparator}$path');
    await f.writeAsString(content);
  }

  /// Applies a patch (single hunk or whole file) via `git apply`.
  /// [cached] stages it; [reverse] reverts it (e.g. discard a working hunk).
  Future<void> applyPatch(String patch,
      {bool cached = false, bool reverse = false}) async {
    final tmp = await File(
            '${Directory.systemTemp.path}${Platform.pathSeparator}lgm_${DateTime.now().microsecondsSinceEpoch}.patch')
        .create();
    try {
      await tmp.writeAsString(patch);
      final r = await _run([
        'apply',
        if (cached) '--cached',
        if (reverse) '--reverse',
        '--whitespace=nowarn',
        tmp.path,
      ]);
      if (r.exitCode != 0) {
        final err = (r.stderr as String).trim();
        throw GitException(err.isEmpty ? 'Failed to apply patch' : err);
      }
    } finally {
      try {
        await tmp.delete();
      } catch (_) {}
    }
  }

  // -------------------------------------------------------------- actions ---
  Future<void> stage(String path) => _runOrThrow(['add', '--', path]);
  Future<void> stageAll() => _runOrThrow(['add', '-A']);
  Future<void> unstage(String path) =>
      _runOrThrow(['restore', '--staged', '--', path]);
  Future<void> unstageAll() => _runOrThrow(['reset']);
  Future<void> discard(String path) =>
      _runOrThrow(['checkout', '--', path]);

  /// Discards all unstaged changes to tracked files (leaves untracked files).
  Future<void> discardAllChanges() => _runOrThrow(['checkout', '--', '.']);

  // ---------------------------------------------- commit-level operations ---
  /// Editor-suppressing environment so non-interactive rebases never hang.
  static const _noEditorEnv = {
    'GIT_EDITOR': 'true',
    'GIT_SEQUENCE_EDITOR': 'true',
  };

  Future<void> checkoutCommit(String sha) => _runOrThrow(['checkout', sha]);

  Future<void> createBranchAt(String name, String sha) =>
      _runOrThrow(['checkout', '-b', name, sha]);

  /// mode is 'soft', 'mixed' or 'hard'.
  Future<void> resetTo(String sha, String mode) =>
      _runOrThrow(['reset', '--$mode', sha]);

  Future<void> revertCommit(String sha, {bool noCommit = false}) => _runOrThrow(
      ['revert', if (noCommit) '--no-commit' else '--no-edit', sha],
      env: _noEditorEnv);

  Future<String> commitMessage(String sha) async {
    final r = await _run(['log', '-1', '--format=%B', sha]);
    return (r.stdout as String).trimRight();
  }

  /// Amends the current commit keeping its message (used for the rebase `edit`
  /// stop: fold newly-staged changes into the paused commit).
  Future<void> amendNoEdit() =>
      _runOrThrow(['commit', '--amend', '--no-edit', '--allow-empty'],
          env: _noEditorEnv);

  Future<void> amendMessage(String message) =>
      _runOrThrow(['commit', '--amend', '-m', message]);

  /// Writes [message] to a temp file so multi-line subjects/bodies are passed
  /// safely to git (avoids shell newline/quoting issues). Returns the path.
  Future<String> _writeMessageFile(String message) async {
    final f = File('${Directory.systemTemp.path}${Platform.pathSeparator}'
        'cm_msg_${DateTime.now().microsecondsSinceEpoch}.txt');
    await f.writeAsString(message);
    return f.path;
  }

  void _deleteQuiet(String path) {
    try {
      File(path).deleteSync();
    } catch (_) {}
  }

  /// Amends the HEAD commit's message (subject + body) from a temp file.
  Future<void> amendHeadMessage(String message) async {
    final path = await _writeMessageFile(message);
    try {
      await _runOrThrow(['commit', '--amend', '-F', path], env: _noEditorEnv);
    } finally {
      _deleteQuiet(path);
    }
  }

  /// Rewords an arbitrary commit's message by rebuilding [branch] onto the
  /// reworded commit. The tree is unchanged, so children replay cleanly (no
  /// conflicts); on any failure the branch is restored. Requires [sha] to be an
  /// ancestor of [branch].
  Future<void> rewordCommit(String sha, String message, String branch) async {
    final ancestor =
        await _run(['merge-base', '--is-ancestor', sha, branch]);
    if (ancestor.exitCode != 0) {
      throw GitException(
          'This commit is not on the current branch, so its message '
          "can't be edited here.");
    }
    final path = await _writeMessageFile(message);
    final parentRes = await _run(['rev-parse', '$sha^']);
    final hasParent = parentRes.exitCode == 0;
    final childrenOut =
        await _runOrThrow(['rev-list', '--reverse', '$sha..$branch']);
    final children = childrenOut
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    try {
      if (hasParent) {
        await _runOrThrow(
            ['checkout', '--detach', (parentRes.stdout as String).trim()]);
        await _runOrThrow(['cherry-pick', sha], env: _noEditorEnv);
      } else {
        await _runOrThrow(['checkout', '--detach', sha]);
      }
      await _runOrThrow(['commit', '--amend', '-F', path], env: _noEditorEnv);
      for (final c in children) {
        await _runOrThrow(['cherry-pick', c], env: _noEditorEnv);
      }
      final head =
          (await _run(['rev-parse', 'HEAD'])).stdout.toString().trim();
      await _runOrThrow(['checkout', '-B', branch, head]);
    } catch (e) {
      await _run(['cherry-pick', '--abort']);
      await _run(['checkout', '-f', branch]);
      throw GitException('Could not update the message. Repository restored. $e');
    } finally {
      _deleteQuiet(path);
    }
  }

  /// Drops [sha] from history by rebasing its children onto its parent.
  Future<void> dropCommit(String sha) =>
      _runOrThrow(['rebase', '--onto', '$sha^', sha], env: _noEditorEnv);

  Future<void> setUpstream(String branch, String upstream) =>
      _runOrThrow(['branch', '--set-upstream-to=$upstream', branch]);

  Future<void> renameBranch(String oldName, String newName) =>
      _runOrThrow(['branch', '-m', oldName, newName]);

  Future<void> deleteBranch(String name, {bool force = false}) =>
      _runOrThrow(['branch', force ? '-D' : '-d', name]);

  Future<void> deleteRemoteBranch(String remote, String name) =>
      _runOrThrow(['push', remote, '--delete', name]);

  Future<void> createTag(String name, String sha) =>
      _runOrThrow(['tag', name, sha]);

  Future<void> createAnnotatedTag(String name, String message, String sha) =>
      _runOrThrow(['tag', '-a', name, '-m', message, sha]);

  Future<void> deleteTag(String name) => _runOrThrow(['tag', '-d', name]);

  Future<void> pushTag(String remote, String name, {String? authHeader}) =>
      _runOrThrow([..._netArgs(authHeader), 'push', remote, 'refs/tags/$name'],
          env: _netEnv(authHeader));

  Future<void> deleteRemoteTag(String remote, String name,
          {String? authHeader}) =>
      _runOrThrow(
          [..._netArgs(authHeader), 'push', remote, '--delete', 'refs/tags/$name'],
          env: _netEnv(authHeader));

  /// Writes a `0001-*.patch` for [sha] into the repo root; returns its path.
  Future<String> formatPatch(String sha) async {
    final out = await _runOrThrow(['format-patch', '-1', sha, '-o', '.']);
    return out.trim();
  }

  Future<void> applyPatchFile(String path) =>
      _runOrThrow(['apply', '--whitespace=nowarn', path]);

  Future<String> remoteUrl([String remote = 'origin']) async {
    final r = await _run(['remote', 'get-url', remote]);
    if (r.exitCode != 0) return '';
    return (r.stdout as String).trim();
  }

  // ------------------------------------------------------------- remotes ----
  Future<List<GitRemote>> remotes() async {
    final r = await _run(['remote', '-v']);
    if (r.exitCode != 0) return const [];
    final fetch = <String, String>{};
    final push = <String, String>{};
    for (final line in (r.stdout as String).split('\n')) {
      final m = RegExp(r'^(\S+)\s+(\S+)\s+\((fetch|push)\)$').firstMatch(line.trim());
      if (m == null) continue;
      if (m.group(3) == 'fetch') {
        fetch[m.group(1)!] = m.group(2)!;
      } else {
        push[m.group(1)!] = m.group(2)!;
      }
    }
    final names = {...fetch.keys, ...push.keys}.toList()..sort();
    return [
      for (final n in names)
        GitRemote(name: n, fetchUrl: fetch[n] ?? '', pushUrl: push[n] ?? fetch[n] ?? ''),
    ];
  }

  Future<void> addRemote(String name, String url) =>
      _runOrThrow(['remote', 'add', name, url]);
  Future<void> removeRemote(String name) =>
      _runOrThrow(['remote', 'remove', name]);
  Future<void> renameRemote(String oldName, String newName) =>
      _runOrThrow(['remote', 'rename', oldName, newName]);
  Future<void> setRemoteUrl(String name, String url) =>
      _runOrThrow(['remote', 'set-url', name, url]);

  // ---------------------------------------------------------- submodules ----
  Future<List<GitSubmodule>> submodules() async {
    final r = await _run(['submodule', 'status']);
    if (r.exitCode != 0) return const [];
    final out = <GitSubmodule>[];
    for (final raw in (r.stdout as String).split('\n')) {
      if (raw.trim().isEmpty) continue;
      // Format: "<flag><sha> <path> (<describe>)" — flag is one of ' +-U'.
      final flag = raw[0];
      final rest = raw.substring(1);
      final m = RegExp(r'^(\S+)\s+(\S+)(?:\s+\((.*)\))?').firstMatch(rest);
      if (m == null) continue;
      out.add(GitSubmodule(
        status: flag == ' ' ? '' : flag,
        sha: m.group(1)!,
        path: m.group(2)!,
        describe: m.group(3) ?? '',
      ));
    }
    return out;
  }

  Future<void> submoduleUpdate({bool init = true}) => _runOrThrow([
        'submodule',
        'update',
        if (init) '--init',
        '--recursive',
      ]);
  Future<void> submoduleSync() =>
      _runOrThrow(['submodule', 'sync', '--recursive']);

  // -------------------------------------------------------------- reflog ----
  Future<List<ReflogEntry>> reflog({int limit = 200}) async {
    final r = await _run([
      'reflog',
      '-n',
      '$limit',
      '--format=%H$_us%gd$_us%gs$_rs',
    ]);
    if (r.exitCode != 0) return const [];
    final out = <ReflogEntry>[];
    for (final rec in (r.stdout as String).split(_rs)) {
      final t = rec.trim();
      if (t.isEmpty) continue;
      final f = t.split(_us);
      if (f.length < 3) continue;
      out.add(ReflogEntry(sha: f[0], selector: f[1], subject: f[2]));
    }
    return out;
  }

  /// Signature status of [sha] via `%G?`: G(ood), B(ad), U(unknown validity),
  /// X/Y/R(expired/etc), E(cannot check), N(one).
  Future<String> signatureStatus(String sha) async {
    final r = await _run(['log', '-1', '--format=%G?', sha]);
    if (r.exitCode != 0) return 'N';
    final v = (r.stdout as String).trim();
    return v.isEmpty ? 'N' : v[0];
  }

  // ----------------------------------------------- branch-level operations ---
  Future<void> merge(String branch) =>
      _runOrThrow(['merge', '--no-edit', branch], env: _noEditorEnv);

  Future<void> rebaseOnto(String branch) =>
      _runOrThrow(['rebase', branch], env: _noEditorEnv);

  /// Interactive rebase, auto-accepting the default todo (non-interactive env).
  Future<void> interactiveRebase(String branch) =>
      _runOrThrow(['rebase', '-i', branch], env: _noEditorEnv);

  /// The commits eligible for an interactive rebase: everything from [base]
  /// (exclusive) up to HEAD, oldest first. When [base] is null the whole
  /// history to HEAD is returned (rebasing from the root).
  Future<List<GitCommit>> rebaseRange(String? base) async {
    final range = base == null ? 'HEAD' : '$base..HEAD';
    final r = await _run([
      'log',
      '--reverse',
      '--pretty=format:$_commitFmt$_rs',
      range,
    ]);
    if (r.exitCode != 0) return [];
    return _parseCommitRecords(r.stdout as String);
  }

  /// Realizes an interactive-rebase [plan] (ordered oldest→newest) onto [base]
  /// (null = root). Builds a todo of `pick`/`fixup` lines plus
  /// `exec git commit --amend -F <file>` steps so messages are set without ever
  /// opening an editor. Conflicts pause the rebase (operation == rebase) for
  /// the normal conflict UI to resolve/continue/abort.
  Future<void> runInteractiveRebase(
      String? base, List<RebaseStep> plan) async {
    final steps = plan.where((s) => s.action != RebaseAction.drop).toList();
    if (steps.isEmpty) {
      throw GitException('An interactive rebase must keep at least one commit.');
    }
    final tmp = await Directory.systemTemp.createTemp('cm_irebase_');
    String unix(String p) => p.replaceAll('\\', '/');

    final todo = StringBuffer();
    var msgIndex = 0;

    // Current group (a kept commit plus any squash/fixup folded into it).
    String? groupBaseMsg;
    var groupIsReword = false;
    final groupSquashMsgs = <String>[];
    var groupOpen = false;

    Future<void> flush() async {
      if (!groupOpen) return;
      if (groupIsReword || groupSquashMsgs.isNotEmpty) {
        final parts = <String>[
          if ((groupBaseMsg ?? '').trim().isNotEmpty) groupBaseMsg!.trim(),
          for (final m in groupSquashMsgs)
            if (m.trim().isNotEmpty) m.trim(),
        ];
        final file = '${tmp.path}${Platform.pathSeparator}msg_${msgIndex++}.txt';
        await File(file).writeAsString('${parts.join('\n\n')}\n');
        todo.writeln(
            'exec git commit --amend --allow-empty -F "${unix(file)}"');
      }
      groupOpen = false;
      groupBaseMsg = null;
      groupIsReword = false;
      groupSquashMsgs.clear();
    }

    for (final step in steps) {
      switch (step.action) {
        case RebaseAction.drop:
          break; // filtered out above
        case RebaseAction.pick:
          await flush();
          todo.writeln('pick ${step.sha}');
          groupOpen = true;
          groupBaseMsg = await commitMessage(step.sha);
          groupIsReword = false;
          break;
        case RebaseAction.reword:
          await flush();
          todo.writeln('pick ${step.sha}');
          groupOpen = true;
          groupBaseMsg = step.newMessage ?? await commitMessage(step.sha);
          groupIsReword = true;
          break;
        case RebaseAction.edit:
          // git pauses after applying this commit so the user can amend it.
          await flush();
          todo.writeln('edit ${step.sha}');
          groupOpen = true;
          groupBaseMsg = await commitMessage(step.sha);
          groupIsReword = false;
          break;
        case RebaseAction.squash:
        case RebaseAction.fixup:
          if (!groupOpen) {
            // Nothing to fold into (first step) — keep it as a plain pick.
            todo.writeln('pick ${step.sha}');
            groupOpen = true;
            groupBaseMsg = await commitMessage(step.sha);
            groupIsReword = false;
            break;
          }
          todo.writeln('fixup ${step.sha}');
          if (step.action == RebaseAction.squash) {
            groupSquashMsgs.add(await commitMessage(step.sha));
          }
          break;
      }
    }
    await flush();

    final todoPath = '${tmp.path}${Platform.pathSeparator}todo.txt';
    await File(todoPath).writeAsString(todo.toString());

    // Install our todo by overriding the sequence editor with a copy command
    // (git's bundled shell provides `cp` on all platforms).
    final env = {
      ..._noEditorEnv,
      'GIT_SEQUENCE_EDITOR': 'cp "${unix(todoPath)}"',
    };
    await _runOrThrow(['rebase', '-i', base ?? '--root'], env: env);
    // Reached only when the rebase completed without pausing; safe to clean up.
    try {
      await tmp.delete(recursive: true);
    } catch (_) {}
  }

  Future<void> cherryPick(String sha, {bool noCommit = false}) => _runOrThrow(
      ['cherry-pick', if (noCommit) '-n', sha],
      env: _noEditorEnv);

  // ----------------------------------------------- conflict / in-progress ---
  /// Detects a paused multi-step operation (merge/rebase/cherry-pick/revert)
  /// by inspecting the git directory's in-progress marker files.
  Future<GitOperation> currentOperation() async {
    final r = await _run(['rev-parse', '--absolute-git-dir']);
    if (r.exitCode != 0) return GitOperation.none;
    final g = (r.stdout as String).trim();
    bool has(String rel) =>
        File('$g/$rel').existsSync() || Directory('$g/$rel').existsSync();
    if (has('rebase-merge') || has('rebase-apply')) return GitOperation.rebase;
    if (has('CHERRY_PICK_HEAD')) return GitOperation.cherryPick;
    if (has('REVERT_HEAD')) return GitOperation.revert;
    if (has('MERGE_HEAD')) return GitOperation.merge;
    return GitOperation.none;
  }

  /// Paths with unresolved merge conflicts.
  Future<List<String>> conflictedPaths() async {
    final r = await _run(['diff', '--name-only', '--diff-filter=U']);
    if (r.exitCode != 0) return const [];
    return (r.stdout as String)
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
  }

  /// Resolve a conflict by taking our side (current branch) and staging it.
  Future<void> resolveUsingOurs(String path) async {
    await _runOrThrow(['checkout', '--ours', '--', path]);
    await _runOrThrow(['add', '--', path]);
  }

  /// Resolve a conflict by taking their side (incoming) and staging it.
  Future<void> resolveUsingTheirs(String path) async {
    await _runOrThrow(['checkout', '--theirs', '--', path]);
    await _runOrThrow(['add', '--', path]);
  }

  /// Mark a manually-edited file as resolved (stage it).
  Future<void> markResolved(String path) =>
      _runOrThrow(['add', '--', path]);

  /// Continue the paused operation after all conflicts are resolved.
  Future<void> continueOperation(GitOperation op) {
    switch (op) {
      case GitOperation.merge:
        return _runOrThrow(['merge', '--continue'], env: _noEditorEnv);
      case GitOperation.rebase:
        return _runOrThrow(['rebase', '--continue'], env: _noEditorEnv);
      case GitOperation.cherryPick:
        return _runOrThrow(['cherry-pick', '--continue'], env: _noEditorEnv);
      case GitOperation.revert:
        return _runOrThrow(['revert', '--continue'], env: _noEditorEnv);
      case GitOperation.none:
        return Future.value();
    }
  }

  /// Abort the paused operation, restoring the pre-operation state.
  Future<void> abortOperation(GitOperation op) {
    switch (op) {
      case GitOperation.merge:
        return _runOrThrow(['merge', '--abort']);
      case GitOperation.rebase:
        return _runOrThrow(['rebase', '--abort']);
      case GitOperation.cherryPick:
        return _runOrThrow(['cherry-pick', '--abort']);
      case GitOperation.revert:
        return _runOrThrow(['revert', '--abort']);
      case GitOperation.none:
        return Future.value();
    }
  }

  // ------------------------------------------------------- stash operations ---
  Future<void> stashApply(int index) =>
      _runOrThrow(['stash', 'apply', 'stash@{$index}']);
  Future<void> stashPopAt(int index) =>
      _runOrThrow(['stash', 'pop', 'stash@{$index}']);
  Future<void> stashDrop(int index) =>
      _runOrThrow(['stash', 'drop', 'stash@{$index}']);

  /// The patch text for a stash (for "Share as Cloud Patch").
  Future<String> stashPatch(int index) async {
    final r = await _run(['stash', 'show', '-p', 'stash@{$index}']);
    return r.stdout as String;
  }

  /// Combined patch of all working-tree changes vs HEAD (staged + unstaged
  /// tracked files) — used for "Cloud Patch".
  Future<String> workingPatch() async {
    final r = await _run(['diff', 'HEAD']);
    return r.stdout as String;
  }

  /// Git has no native stash-reword, so re-store the stash commit under a new
  /// message (it moves to the top of the stash list).
  Future<void> editStashMessage(int index, String message) async {
    final shaRes = await _run(['rev-parse', 'stash@{$index}']);
    if (shaRes.exitCode != 0) {
      throw GitException('Could not resolve stash.');
    }
    final sha = (shaRes.stdout as String).trim();
    await _runOrThrow(['stash', 'drop', 'stash@{$index}']);
    await _runOrThrow(['stash', 'store', '-m', message, sha]);
  }

  /// Stashes working changes with options. [includeUntracked] also stashes
  /// untracked files; [keepIndex] leaves staged changes in the index.
  Future<void> stashPushWith(
      {String? message,
      bool includeUntracked = false,
      bool keepIndex = false}) {
    final args = ['stash', 'push'];
    if (keepIndex) args.add('--keep-index');
    if (includeUntracked) args.add('--include-untracked');
    final m = message?.trim() ?? '';
    if (m.isNotEmpty) args.addAll(['-m', m]);
    return _runOrThrow(args);
  }

  /// Untracked files/dirs that `clean -fd` would remove (dry run).
  Future<List<String>> cleanPreview() async {
    final r = await _run(['clean', '-fdn']);
    if (r.exitCode != 0) return const [];
    return (r.stdout as String)
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.startsWith('Would remove '))
        .map((l) => l.substring('Would remove '.length))
        .toList();
  }

  /// Removes untracked files and directories (`git clean -fd`).
  Future<void> cleanUntracked() => _runOrThrow(['clean', '-fd']);

  /// Adds a new worktree at [path] checked out to [ref] (branch name or sha).
  Future<void> worktreeAdd(String path, String ref) =>
      _runOrThrow(['worktree', 'add', path, ref]);

  /// Lists the repository's worktrees (`git worktree list --porcelain`).
  Future<List<GitWorktree>> worktreeList() async {
    final r = await _run(['worktree', 'list', '--porcelain']);
    if (r.exitCode != 0) return const [];
    final out = <GitWorktree>[];
    String? path, sha, branch;
    var bare = false, detached = false;
    void flush() {
      if (path == null) return;
      out.add(GitWorktree(
        path: path!,
        branch: branch,
        sha: sha ?? '',
        // The first entry git reports is the main worktree.
        isMain: out.isEmpty,
        bare: bare,
        detached: detached,
      ));
      path = sha = branch = null;
      bare = detached = false;
    }

    for (final raw in (r.stdout as String).split('\n')) {
      final line = raw.trimRight();
      if (line.isEmpty) {
        flush();
        continue;
      }
      if (line.startsWith('worktree ')) {
        path = line.substring('worktree '.length);
      } else if (line.startsWith('HEAD ')) {
        sha = line.substring('HEAD '.length);
      } else if (line.startsWith('branch ')) {
        branch = line
            .substring('branch '.length)
            .replaceFirst('refs/heads/', '');
      } else if (line == 'bare') {
        bare = true;
      } else if (line == 'detached') {
        detached = true;
      }
    }
    flush();
    return out;
  }

  /// Removes the worktree registered at [path].
  Future<void> worktreeRemove(String path, {bool force = false}) =>
      _runOrThrow(['worktree', 'remove', if (force) '--force', path]);

  /// Prunes stale worktree administrative entries.
  Future<void> worktreePrune() => _runOrThrow(['worktree', 'prune']);

  /// The full patch text for a commit (`git format-patch -1 --stdout`).
  Future<String> commitPatchText(String sha) async {
    final r = await _run(['format-patch', '-1', '--stdout', sha]);
    return r.stdout as String;
  }

  /// Reorders [sha] one position older (swaps it with its parent) on [branch].
  /// Rewinds safely (aborts cherry-pick, restores branch) on any failure.
  Future<void> moveCommitDown(String sha, String branch) async {
    final parent = await _run(['rev-parse', '$sha^']);
    if (parent.exitCode != 0) {
      throw GitException('This commit has no parent to move past.');
    }
    final grand = await _run(['rev-parse', '$sha^^']);
    if (grand.exitCode != 0) {
      throw GitException('Cannot move past the root commit.');
    }
    final p = (parent.stdout as String).trim();
    final g = (grand.stdout as String).trim();
    final childrenOut = await _runOrThrow(['rev-list', '--reverse', '$sha..$branch']);
    final children = childrenOut
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    try {
      await _runOrThrow(['checkout', '--detach', g]);
      await _runOrThrow(['cherry-pick', sha], env: _noEditorEnv);
      await _runOrThrow(['cherry-pick', p], env: _noEditorEnv);
      for (final c in children) {
        await _runOrThrow(['cherry-pick', c], env: _noEditorEnv);
      }
      final head = (await _run(['rev-parse', 'HEAD']).then(
          (r) => (r.stdout as String).trim()));
      await _runOrThrow(['checkout', '-B', branch, head]);
    } catch (e) {
      await _run(['cherry-pick', '--abort']);
      await _run(['checkout', '-f', branch]);
      throw GitException(
          'Could not reorder (likely a conflict). Repository restored. $e');
    }
  }

  /// Opens [url] in the default browser.
  static Future<void> openUrl(String url) async {
    if (Platform.isWindows) {
      await Process.run('cmd', ['/c', 'start', '', url], runInShell: true);
    } else if (Platform.isMacOS) {
      await Process.run('open', [url]);
    } else {
      await Process.run('xdg-open', [url]);
    }
  }

  Future<void> commit(String summary,
      {String description = '', bool amend = false, bool signoff = false}) async {
    final args = ['commit'];
    if (amend) args.add('--amend');
    if (signoff) args.add('--signoff');
    args.addAll(['-m', summary]);
    if (description.trim().isNotEmpty) args.addAll(['-m', description]);
    await _runOrThrow(args);
  }

  /// The configured commit message template (`commit.template`), if any.
  Future<String?> commitTemplate() async {
    final r = await _run(['config', '--get', 'commit.template']);
    if (r.exitCode != 0) return null;
    var path = (r.stdout as String).trim();
    if (path.isEmpty) return null;
    if (path.startsWith('~')) {
      final home = Platform.environment['USERPROFILE'] ??
          Platform.environment['HOME'] ??
          '';
      path = '$home${path.substring(1)}';
    }
    final f = File(path.contains(RegExp(r'^[a-zA-Z]:|^[/\\]'))
        ? path
        : '$workingDir${Platform.pathSeparator}$path');
    if (!await f.exists()) return null;
    return f.readAsString();
  }

  /// Appends [pattern] to the repository's `.gitignore` (creating it if needed).
  Future<void> appendGitignore(String pattern) async {
    final f = File('$workingDir${Platform.pathSeparator}.gitignore');
    final existing = await f.exists() ? await f.readAsString() : '';
    final lines = existing.split('\n').map((l) => l.trim()).toSet();
    if (lines.contains(pattern.trim())) return; // already ignored
    final prefix = existing.isEmpty || existing.endsWith('\n') ? '' : '\n';
    await f.writeAsString('$prefix${pattern.trim()}\n', mode: FileMode.append);
  }

  /// Suppresses interactive credential prompts (the Git Credential Manager
  /// GUI) for network ops when we are supplying our own auth.
  static const _noPromptEnv = {
    'GIT_TERMINAL_PROMPT': '0',
    'GCM_INTERACTIVE': 'never',
  };

  /// `-c` overrides that inject an Azure DevOps PAT as an HTTP auth header so
  /// git authenticates non-interactively instead of invoking the credential
  /// manager. Returns no overrides when [authHeader] is null (other remotes
  /// keep using whatever credential helper the user has configured).
  List<String> _authArgs(String? authHeader) => authHeader == null
      ? const []
      : ['-c', 'credential.interactive=false', '-c', 'http.extraHeader=$authHeader'];

  /// Combines the per-call auth header overrides with the app-wide SSH /
  /// credential runtime config.
  List<String> _netArgs(String? authHeader) =>
      [...GitRuntimeConfig.configArgs(), ..._authArgs(authHeader)];

  /// Whether to suppress the credential-manager GUI for this network call.
  Map<String, String>? _netEnv(String? authHeader) =>
      (authHeader != null || !GitRuntimeConfig.useCredentialManager)
          ? _noPromptEnv
          : null;

  Future<String> pull({String? authHeader}) => _runOrThrow(
      [..._netArgs(authHeader), 'pull'],
      env: _netEnv(authHeader));
  /// Whether the current branch has a configured upstream (tracking) branch.
  Future<bool> _hasUpstream() async {
    final r = await _run(
        ['rev-parse', '--abbrev-ref', '--symbolic-full-name', '@{u}']);
    return r.exitCode == 0;
  }

  /// Pushes the current branch. When it has no upstream yet (e.g. a freshly
  /// created local branch), this creates a matching remote branch and sets it
  /// as the upstream (`git push --set-upstream origin <branch>`).
  Future<String> push({String? authHeader}) async {
    final args = [..._netArgs(authHeader), 'push'];
    if (!await _hasUpstream()) {
      final branch = await currentBranch();
      if (branch.isNotEmpty && branch != 'HEAD') {
        args.addAll(['--set-upstream', 'origin', branch]);
      }
    }
    return _runOrThrow(args, env: _netEnv(authHeader));
  }
  Future<String> fetch({String? authHeader}) => _runOrThrow(
      [..._netArgs(authHeader), 'fetch', '--all', '--prune'],
      env: _netEnv(authHeader));
  Future<void> checkout(String branch) => _runOrThrow(['checkout', branch]);
  Future<void> createBranch(String name) =>
      _runOrThrow(['checkout', '-b', name]);
  Future<void> stashPush() => _runOrThrow(['stash', 'push']);
  Future<void> stashPop() => _runOrThrow(['stash', 'pop']);

  /// Clones [url] into [destination]; returns the created repo directory.
  /// [userInfo] is a pre-encoded `user:secret` injected into the HTTPS URL for
  /// non-interactive auth (provider-specific — see IntegrationService).
  static Future<String> clone(String url, String destination,
      {String? userInfo}) async {
    final args = [...GitRuntimeConfig.configArgs(), 'clone'];
    if (userInfo != null && userInfo.isNotEmpty && url.startsWith('https://')) {
      // Replace any existing userinfo with ours.
      final authed = url.replaceFirst(
          RegExp(r'^https://([^@/]*@)?'), 'https://$userInfo@');
      args.add(authed);
    } else {
      args.add(url);
    }
    args.add(destination);
    final r = await Process.run('git', args,
        runInShell: Platform.isWindows,
        environment: _noPromptEnv,
        includeParentEnvironment: true,
        stderrEncoding: SystemEncoding(),
        stdoutEncoding: SystemEncoding());
    if (r.exitCode != 0) {
      throw GitException((r.stderr as String).trim());
    }
    return destination;
  }
}
