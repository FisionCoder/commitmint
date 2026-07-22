// Helpers for turning a git remote URL into browser links.

String? gitHttpBase(String remote) {
  var r = remote.trim();
  if (r.isEmpty) return null;
  final ssh = RegExp(r'^git@([^:]+):(.+)$').firstMatch(r);
  if (ssh != null) {
    r = 'https://${ssh.group(1)}/${ssh.group(2)}';
  } else if (r.startsWith('ssh://')) {
    r = r
        .replaceFirst('ssh://git@', 'https://')
        .replaceFirst('ssh://', 'https://');
  }
  r = r.replaceFirst(RegExp(r'\.git$'), '');
  return r.startsWith('http') ? r : null;
}

bool _isAzure(String base) =>
    base.contains('dev.azure.com') || base.contains('visualstudio.com');

String? gitCommitUrl(String remote, String sha) {
  final base = gitHttpBase(remote);
  return base == null ? null : '$base/commit/$sha';
}

String? gitBranchUrl(String remote, String branch) {
  final base = gitHttpBase(remote);
  if (base == null) return null;
  if (_isAzure(base)) {
    return '$base?version=GB${Uri.encodeComponent(branch)}';
  }
  return '$base/tree/${Uri.encodeComponent(branch)}';
}

/// URL to open the "create pull request" page for a branch.
String? gitPrCreateUrl(String remote, String branch) {
  final base = gitHttpBase(remote);
  if (base == null) return null;
  if (_isAzure(base)) {
    return '$base/pullrequestcreate?sourceRef=${Uri.encodeComponent(branch)}';
  }
  return '$base/compare/${Uri.encodeComponent(branch)}?expand=1';
}

/// URL to open the "create pull request" page for merging [head] into [base]
/// (e.g. right-clicking another branch and opening a PR from the current
/// branch into it).
String? gitPrCreateUrlInto(String remote, String base, String head) {
  final b = gitHttpBase(remote);
  if (b == null) return null;
  if (_isAzure(b)) {
    return '$b/pullrequestcreate?sourceRef=${Uri.encodeComponent(head)}'
        '&targetRef=${Uri.encodeComponent(base)}';
  }
  return '$b/compare/${Uri.encodeComponent(base)}...'
      '${Uri.encodeComponent(head)}?expand=1';
}

/// Splits [text] into runs, tagging `#123` issue references. Each token is
/// either plain text (`issue == null`) or an issue reference with its number.
List<({String text, int? issue})> tokenizeIssueRefs(String text) {
  final re = RegExp(r'#(\d+)');
  final out = <({String text, int? issue})>[];
  var last = 0;
  for (final m in re.allMatches(text)) {
    if (m.start > last) {
      out.add((text: text.substring(last, m.start), issue: null));
    }
    out.add((text: m.group(0)!, issue: int.parse(m.group(1)!)));
    last = m.end;
  }
  if (last < text.length) out.add((text: text.substring(last), issue: null));
  if (out.isEmpty) out.add((text: text, issue: null));
  return out;
}

/// URL to a repository issue by number (GitLab uses `/-/issues/`).
String? gitIssueUrl(String remote, int number) {
  final base = gitHttpBase(remote);
  if (base == null) return null;
  return base.contains('gitlab')
      ? '$base/-/issues/$number'
      : '$base/issues/$number';
}

/// URL to view a specific pull request by id.
String? gitPrViewUrl(String remote, int prId) {
  final base = gitHttpBase(remote);
  if (base == null) return null;
  if (_isAzure(base)) return '$base/pullrequest/$prId';
  return '$base/pull/$prId';
}
