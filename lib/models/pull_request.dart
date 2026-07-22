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

  /// Head commit sha (used to fetch CI status); may be empty.
  final String headSha;

  /// Normalized CI status: 'success', 'failed', 'pending', or '' (unknown).
  final String ciStatus;
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
    this.headSha = '',
    this.ciStatus = '',
    this.assignees = const [],
    this.created,
    this.updated,
    this.isMine = false,
    this.awaitingMyReview = false,
  });

  PullRequest withCi(String status) => PullRequest(
        id: id,
        title: title,
        authorName: authorName,
        sourceBranch: sourceBranch,
        targetBranch: targetBranch,
        repoName: repoName,
        url: url,
        headSha: headSha,
        ciStatus: status,
        assignees: assignees,
        created: created,
        updated: updated,
        isMine: isMine,
        awaitingMyReview: awaitingMyReview,
      );
}
