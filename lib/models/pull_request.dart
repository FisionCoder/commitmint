/// A pull request (or merge request) fetched from a hosting provider.
class PullRequest {
  final int id;
  final String title;
  final String authorName;
  final String sourceBranch; // short, e.g. feature/foo
  final String targetBranch;
  final String repoName;

  /// Web URL of the PR/MR on the provider (for "open in browser").
  final String url;
  final List<String> assignees;
  final DateTime? created;
  final DateTime? updated;
  final bool isMine;
  final bool awaitingMyReview;

  const PullRequest({
    required this.id,
    required this.title,
    required this.authorName,
    required this.sourceBranch,
    required this.targetBranch,
    required this.repoName,
    this.url = '',
    this.assignees = const [],
    this.created,
    this.updated,
    this.isMine = false,
    this.awaitingMyReview = false,
  });
}
