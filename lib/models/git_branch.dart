/// A git ref shown in the sidebar (local branch, remote branch, tag, stash).
enum RefKind { localBranch, remoteBranch, tag, stash }

class GitRef {
  final String name; // e.g. "UI-Overall" or "origin/main"
  final RefKind kind;
  final bool isCurrent;
  final String? upstream;
  final int ahead;
  final int behind;
  final String? targetHash;

  const GitRef({
    required this.name,
    required this.kind,
    this.isCurrent = false,
    this.upstream,
    this.ahead = 0,
    this.behind = 0,
    this.targetHash,
  });

  /// "origin" for a remote branch like "origin/main".
  String? get remoteName {
    if (kind != RefKind.remoteBranch) return null;
    final i = name.indexOf('/');
    return i < 0 ? null : name.substring(0, i);
  }

  /// Branch name without the remote prefix.
  String get displayName {
    if (kind == RefKind.remoteBranch) {
      final i = name.indexOf('/');
      return i < 0 ? name : name.substring(i + 1);
    }
    return name;
  }
}
