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

/// URL to view a specific pull request by id.
String? gitPrViewUrl(String remote, int prId) {
  final base = gitHttpBase(remote);
  if (base == null) return null;
  if (_isAzure(base)) return '$base/pullrequest/$prId';
  return '$base/pull/$prId';
}
