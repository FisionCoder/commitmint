import 'dart:io';

/// Reads and writes the user's **global** git configuration (`git config
/// --global`). Used by the Settings screen for the values that are genuinely
/// backed by git itself (identity, default branch, line endings, long paths).
class GitConfigService {
  Future<ProcessResult> _run(List<String> args) async {
    try {
      return await Process.run('git', args,
          runInShell: Platform.isWindows,
          stdoutEncoding: SystemEncoding(),
          stderrEncoding: SystemEncoding());
    } on ProcessException catch (e) {
      return ProcessResult(0, 1, '', 'Failed to run git: ${e.message}');
    }
  }

  /// Reads a single global config value, or null if unset.
  Future<String?> get(String key) async {
    final r = await _run(['config', '--global', '--get', key]);
    if (r.exitCode != 0) return null;
    final v = (r.stdout as String).trim();
    return v.isEmpty ? null : v;
  }

  /// Sets a global config value (or unsets it when [value] is null/empty).
  Future<void> set(String key, String? value) async {
    if (value == null || value.trim().isEmpty) {
      await _run(['config', '--global', '--unset', key]);
      return;
    }
    await _run(['config', '--global', key, value.trim()]);
  }

  /// Reads the common identity + behaviour values in one shot.
  Future<GlobalGitConfig> read() async {
    final results = await Future.wait([
      get('user.name'),
      get('user.email'),
      get('init.defaultBranch'),
      get('core.autocrlf'),
      get('core.longpaths'),
    ]);
    return GlobalGitConfig(
      userName: results[0] ?? '',
      userEmail: results[1] ?? '',
      defaultBranch: results[2] ?? '',
      autoCrlf: (results[3] ?? '').toLowerCase() == 'true',
      longPaths: (results[4] ?? '').toLowerCase() == 'true',
    );
  }

  /// Clears all stored credentials known to the OS credential helper (best
  /// effort — the helper may be `manager`, `wincred`, or unset).
  Future<bool> forgetCredentials() async {
    final helper = await get('credential.helper') ?? '';
    // `git credential-manager erase` clears GCM's store; fall back to clearing
    // the Windows generic credentials that git uses.
    if (helper.contains('manager')) {
      final r = await _run(['credential-manager', 'erase']);
      if (r.exitCode == 0) return true;
    }
    // Generic: reject any github/azure/gitlab host via the credential subsystem.
    final r = await _run(['credential', 'reject']);
    return r.exitCode == 0;
  }

  /// Generates a new ed25519 SSH key pair (no passphrase) at a fresh,
  /// non-clobbering path derived from [path]. Returns the **private** key path
  /// on success (the public key is the same path + ".pub"); throws with the
  /// captured error on failure.
  Future<String> generateKey(String path, {String comment = ''}) async {
    final target = _freePath(path);
    final dir = Directory(target).parent;
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final ProcessResult k;
    try {
      // NOTE: do NOT run in a shell — on Windows runInShell drops the empty
      // `-N ""` passphrase argument, which makes ssh-keygen prompt and fail.
      k = await Process.run(
        'ssh-keygen',
        [
          '-t', 'ed25519',
          '-f', target,
          '-N', '', // empty passphrase
          '-C', comment.isEmpty ? 'commit-mint' : comment,
        ],
        runInShell: false,
        stdoutEncoding: SystemEncoding(),
        stderrEncoding: SystemEncoding(),
      );
    } on ProcessException catch (e) {
      throw Exception(
          'Could not run ssh-keygen (is OpenSSH installed and on PATH?): ${e.message}');
    }
    if (k.exitCode != 0) {
      final err = (k.stderr as String).trim();
      final out = (k.stdout as String).trim();
      throw Exception(err.isNotEmpty
          ? err
          : (out.isNotEmpty ? out : 'ssh-keygen exited with ${k.exitCode}'));
    }
    return target;
  }

  /// Returns [path] if free, else appends `_1`, `_2`, … so we never overwrite
  /// an existing key (e.g. the user's working id_ed25519).
  String _freePath(String path) {
    if (!File(path).existsSync() && !File('$path.pub').existsSync()) {
      return path;
    }
    for (var i = 1; i < 1000; i++) {
      final p = '${path}_$i';
      if (!File(p).existsSync() && !File('$p.pub').existsSync()) return p;
    }
    return path;
  }

  /// A sensible default location for a new SSH key (~/.ssh/id_ed25519).
  String defaultKeyPath() {
    final home = Platform.environment['USERPROFILE'] ??
        Platform.environment['HOME'] ??
        '.';
    return '$home${Platform.pathSeparator}.ssh${Platform.pathSeparator}id_ed25519';
  }
}

class GlobalGitConfig {
  final String userName;
  final String userEmail;
  final String defaultBranch;
  final bool autoCrlf;
  final bool longPaths;
  const GlobalGitConfig({
    required this.userName,
    required this.userEmail,
    required this.defaultBranch,
    required this.autoCrlf,
    required this.longPaths,
  });
}
