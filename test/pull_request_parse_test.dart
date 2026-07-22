import 'package:commit_mint/services/integration_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseRemoteSlug', () {
    test('github https', () {
      final s = IntegrationService.parseRemoteSlug(
          'https://github.com/octocat/Hello-World.git');
      expect(s?.host, 'github.com');
      expect(s?.owner, 'octocat');
      expect(s?.repo, 'Hello-World');
    });

    test('github ssh', () {
      final s =
          IntegrationService.parseRemoteSlug('git@github.com:octocat/Hello.git');
      expect(s?.host, 'github.com');
      expect(s?.owner, 'octocat');
      expect(s?.repo, 'Hello');
    });

    test('gitlab subgroups', () {
      final s = IntegrationService.parseRemoteSlug(
          'https://gitlab.com/group/sub/project.git');
      expect(s?.host, 'gitlab.com');
      expect(s?.owner, 'group/sub');
      expect(s?.repo, 'project');
    });

    test('bitbucket without .git', () {
      final s = IntegrationService.parseRemoteSlug(
          'https://bitbucket.org/team/repo');
      expect(s?.host, 'bitbucket.org');
      expect(s?.owner, 'team');
      expect(s?.repo, 'repo');
    });

    test('ssh:// form', () {
      final s = IntegrationService.parseRemoteSlug(
          'ssh://git@gitlab.example.com/grp/proj.git');
      expect(s?.host, 'gitlab.example.com');
      expect(s?.owner, 'grp');
      expect(s?.repo, 'proj');
    });

    test('unparseable returns null', () {
      expect(IntegrationService.parseRemoteSlug(''), isNull);
      expect(IntegrationService.parseRemoteSlug('not a url'), isNull);
    });
  });

  group('mapGitHubPRs', () {
    final json = [
      {
        'number': 42,
        'title': 'Add feature',
        'user': {'login': 'alice'},
        'head': {'ref': 'feature/x'},
        'base': {'ref': 'main'},
        'html_url': 'https://github.com/o/r/pull/42',
        'created_at': '2026-07-01T10:00:00Z',
        'updated_at': '2026-07-02T10:00:00Z',
        'requested_reviewers': [
          {'login': 'me'}
        ],
      },
    ];

    test('maps fields and flags mine/awaiting-review', () {
      final prs = IntegrationService.mapGitHubPRs(json, 'me', 'r');
      expect(prs.length, 1);
      final pr = prs.first;
      expect(pr.id, 42);
      expect(pr.title, 'Add feature');
      expect(pr.authorName, 'alice');
      expect(pr.sourceBranch, 'feature/x');
      expect(pr.targetBranch, 'main');
      expect(pr.url, 'https://github.com/o/r/pull/42');
      expect(pr.isMine, false);
      expect(pr.awaitingMyReview, true);
    });

    test('flags mine when the login authored it', () {
      final prs = IntegrationService.mapGitHubPRs(json, 'alice', 'r');
      expect(prs.first.isMine, true);
      expect(prs.first.awaitingMyReview, false);
    });
  });

  group('mapGitLabMRs', () {
    test('maps iid/source/target/web_url', () {
      final json = [
        {
          'iid': 7,
          'title': 'Fix bug',
          'author': {'username': 'bob'},
          'source_branch': 'bugfix',
          'target_branch': 'develop',
          'web_url': 'https://gitlab.com/g/p/-/merge_requests/7',
          'reviewers': [
            {'username': 'me'}
          ],
        },
      ];
      final prs = IntegrationService.mapGitLabMRs(json, 'me', 'p');
      expect(prs.first.id, 7);
      expect(prs.first.sourceBranch, 'bugfix');
      expect(prs.first.targetBranch, 'develop');
      expect(prs.first.url, 'https://gitlab.com/g/p/-/merge_requests/7');
      expect(prs.first.awaitingMyReview, true);
    });
  });

  group('mapBitbucketPRs', () {
    test('maps id/branches/url/author', () {
      final json = [
        {
          'id': 3,
          'title': 'Update',
          'author': {'display_name': 'Carol', 'account_id': 'abc'},
          'source': {
            'branch': {'name': 'feat'}
          },
          'destination': {
            'branch': {'name': 'main'}
          },
          'links': {
            'html': {'href': 'https://bitbucket.org/t/r/pull-requests/3'}
          },
        },
      ];
      final prs = IntegrationService.mapBitbucketPRs(json, 'abc', 'r');
      expect(prs.first.id, 3);
      expect(prs.first.authorName, 'Carol');
      expect(prs.first.sourceBranch, 'feat');
      expect(prs.first.targetBranch, 'main');
      expect(prs.first.url, 'https://bitbucket.org/t/r/pull-requests/3');
      expect(prs.first.isMine, true);
    });
  });
}
