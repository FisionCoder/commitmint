enum ChangeType { added, modified, deleted, renamed, untracked, conflicted }

/// A changed file from `git status --porcelain`.
class FileChange {
  final String path;
  final ChangeType type;
  final bool staged;

  const FileChange({
    required this.path,
    required this.type,
    required this.staged,
  });

  String get fileName {
    final parts = path.replaceAll('\\', '/').split('/');
    return parts.isEmpty ? path : parts.last;
  }

  String get directory {
    final norm = path.replaceAll('\\', '/');
    final i = norm.lastIndexOf('/');
    return i < 0 ? '' : norm.substring(0, i);
  }

  String get statusLetter {
    switch (type) {
      case ChangeType.added:
        return 'A';
      case ChangeType.modified:
        return 'M';
      case ChangeType.deleted:
        return 'D';
      case ChangeType.renamed:
        return 'R';
      case ChangeType.untracked:
        return 'U';
      case ChangeType.conflicted:
        return '!';
    }
  }
}
