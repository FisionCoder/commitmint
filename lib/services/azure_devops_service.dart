import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/integration.dart';
import '../models/pull_request.dart';

/// Parsed Azure DevOps coordinates from a git remote URL.
class AzureRemote {
  final String org;
  final String project;
  final String repo;
  const AzureRemote(this.org, this.project, this.repo);

  /// Parses https://dev.azure.com/{org}/{project}/_git/{repo} (and the
  /// org.visualstudio.com variant, with optional credentials).
  static AzureRemote? parse(String remote) {
    var r = remote.trim();
    if (r.isEmpty) return null;
    r = r.replaceFirst(RegExp(r'^https?://[^@/]*@'), 'https://');
    final azure = RegExp(r'dev\.azure\.com/([^/]+)/([^/]+)/_git/([^/?#]+)')
        .firstMatch(r);
    if (azure != null) {
      return AzureRemote(azure.group(1)!, azure.group(2)!,
          azure.group(3)!.replaceFirst(RegExp(r'\.git$'), ''));
    }
    final vsts =
        RegExp(r'https?://([^.]+)\.visualstudio\.com/([^/]+)/_git/([^/?#]+)')
            .firstMatch(r);
    if (vsts != null) {
      return AzureRemote(vsts.group(1)!, vsts.group(2)!,
          vsts.group(3)!.replaceFirst(RegExp(r'\.git$'), ''));
    }
    return null;
  }

  String get hostDomain => 'dev.azure.com/$org';
}

class AzureException implements Exception {
  final String message;
  AzureException(this.message);
  @override
  String toString() => message;
}

class AzureConnectionResult {
  final String displayName;

  /// The normalized host domain that actually connected (e.g. the user may
  /// paste a full project URL; we store `dev.azure.com/{org}`).
  final String hostDomain;
  AzureConnectionResult(this.displayName, this.hostDomain);
}

/// Talks to the Azure DevOps REST API using a Personal Access Token.
class AzureDevOpsService {
  static const _apiVersion = '7.1';

  /// Reduces any pasted Azure DevOps URL to its organization root, since the
  /// `_apis/projects` (and most org-level) endpoints live there:
  ///   https://dev.azure.com/{org}/{project}/_git/{repo}  ->  dev.azure.com/{org}
  ///   {org}.visualstudio.com/{project}/...               ->  {org}.visualstudio.com
  ///   dev.azure.com/{org}                                ->  dev.azure.com/{org}
  static String normalizeHostDomain(String input) {
    var s = input.trim();
    s = s.replaceFirst(RegExp(r'^https?://'), '');
    s = s.replaceFirst(RegExp(r'^[^@/]*@'), ''); // strip embedded credentials
    s = s.replaceAll(RegExp(r'/+$'), '');
    final azure = RegExp(r'^(dev\.azure\.com)/([^/]+)').firstMatch(s);
    if (azure != null) return '${azure.group(1)}/${azure.group(2)}';
    final vsts = RegExp(r'^([^./]+\.visualstudio\.com)').firstMatch(s);
    if (vsts != null) return vsts.group(1)!;
    return s;
  }

  /// Builds `https://dev.azure.com/org` from a (possibly full-URL) host domain.
  static String _baseUrl(String hostDomain) =>
      'https://${normalizeHostDomain(hostDomain)}';

  static Map<String, String> _headers(String pat) {
    final token = base64.encode(utf8.encode(':$pat'));
    return {
      'Authorization': 'Basic $token',
      'Accept': 'application/json',
    };
  }

  /// Validates the PAT against the org and returns the connected display name.
  static Future<AzureConnectionResult> connect(
      String hostDomain, String pat) async {
    if (pat.trim().isEmpty) {
      throw AzureException('A Personal Access Token is required.');
    }
    final base = _baseUrl(hostDomain);
    final uri = Uri.parse('$base/_apis/projects?api-version=$_apiVersion');

    http.Response res;
    try {
      res = await http
          .get(uri, headers: _headers(pat))
          .timeout(const Duration(seconds: 20));
    } catch (e) {
      throw AzureException('Could not reach $base — check the host domain.');
    }

    if (res.statusCode == 401 || res.statusCode == 203) {
      throw AzureException(
          'Authentication failed. Check the token and its scopes (Code: Read).');
    }
    if (res.statusCode == 404) {
      throw AzureException('Organization not found at $base.');
    }
    if (res.statusCode != 200) {
      throw AzureException('Azure DevOps returned HTTP ${res.statusCode}.');
    }

    // Best-effort: resolve the signed-in user's display name.
    var name = '';
    try {
      final profileUri = Uri.parse(
          'https://app.vssps.visualstudio.com/_apis/profile/profiles/me?api-version=$_apiVersion');
      final p = await http
          .get(profileUri, headers: _headers(pat))
          .timeout(const Duration(seconds: 10));
      if (p.statusCode == 200) {
        final body = jsonDecode(p.body) as Map<String, dynamic>;
        name = (body['displayName'] as String?) ??
            (body['emailAddress'] as String?) ??
            '';
      }
    } catch (_) {/* non-fatal */}

    if (name.isEmpty) {
      final org = base.split('/').last;
      name = 'Connected ($org)';
    }
    return AzureConnectionResult(name, normalizeHostDomain(hostDomain));
  }

  /// Lists every git repository the token can see in the organization.
  static Future<List<RemoteRepo>> listRepositories(
      String hostDomain, String pat) async {
    final base = _baseUrl(hostDomain);
    final uri =
        Uri.parse('$base/_apis/git/repositories?api-version=$_apiVersion');
    http.Response res;
    try {
      res = await http
          .get(uri, headers: _headers(pat))
          .timeout(const Duration(seconds: 30));
    } catch (e) {
      throw AzureException('Could not load repositories from $base.');
    }
    if (res.statusCode != 200) {
      throw AzureException(
          'Failed to list repositories (HTTP ${res.statusCode}).');
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final list = (body['value'] as List?) ?? [];
    final repos = <RemoteRepo>[];
    for (final item in list) {
      final m = item as Map<String, dynamic>;
      if (m['isDisabled'] == true) continue;
      repos.add(RemoteRepo(
        id: m['id'] as String,
        name: m['name'] as String,
        group: (m['project'] as Map<String, dynamic>?)?['name'] as String? ??
            '',
        cloneUrl: (m['remoteUrl'] as String?) ?? (m['webUrl'] as String?) ?? '',
        defaultBranch: (m['defaultBranch'] as String?)
            ?.replaceFirst('refs/heads/', ''),
      ));
    }
    repos.sort((a, b) {
      final p = a.group.compareTo(b.group);
      return p != 0 ? p : a.name.compareTo(b.name);
    });
    return repos;
  }

  static String _short(String? ref) =>
      (ref ?? '').replaceFirst('refs/heads/', '');

  /// Lists pull requests for a repository. [currentUser] (display name) flags
  /// "mine" / "awaiting my review".
  static Future<List<PullRequest>> listPullRequests(
      AzureRemote r, String pat, {String? currentUser}) async {
    final base = _baseUrl(r.hostDomain);
    final uri = Uri.parse(
        '$base/${Uri.encodeComponent(r.project)}/_apis/git/repositories/'
        '${Uri.encodeComponent(r.repo)}/pullrequests'
        '?searchCriteria.status=all&\$top=100&api-version=$_apiVersion');
    http.Response res;
    try {
      res = await http
          .get(uri, headers: _headers(pat))
          .timeout(const Duration(seconds: 25));
    } catch (e) {
      throw AzureException('Could not load pull requests.');
    }
    if (res.statusCode != 200) {
      throw AzureException('Failed to load pull requests (HTTP ${res.statusCode}).');
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final list = (body['value'] as List?) ?? [];
    final prs = <PullRequest>[];
    for (final item in list) {
      final m = item as Map<String, dynamic>;
      final createdBy =
          (m['createdBy'] as Map<String, dynamic>?)?['displayName'] as String? ??
              '';
      final reviewers = ((m['reviewers'] as List?) ?? [])
          .map((e) => (e as Map<String, dynamic>)['displayName'] as String? ?? '')
          .where((e) => e.isNotEmpty)
          .toList();
      DateTime? parseDate(String? s) =>
          s == null ? null : DateTime.tryParse(s)?.toLocal();
      final mine = currentUser != null &&
          currentUser.isNotEmpty &&
          createdBy.toLowerCase() == currentUser.toLowerCase();
      prs.add(PullRequest(
        id: (m['pullRequestId'] as num).toInt(),
        title: m['title'] as String? ?? '(untitled)',
        authorName: createdBy,
        sourceBranch: _short(m['sourceRefName'] as String?),
        targetBranch: _short(m['targetRefName'] as String?),
        repoName: (m['repository'] as Map<String, dynamic>?)?['name'] as String? ??
            r.repo,
        assignees: reviewers,
        created: parseDate(m['creationDate'] as String?),
        updated: parseDate(
            (m['lastMergeCommit'] as Map<String, dynamic>?)?['author']
                ?['date'] as String?) ??
            parseDate(m['creationDate'] as String?),
        isMine: mine,
        awaitingMyReview: !mine &&
            currentUser != null &&
            reviewers.any((x) => x.toLowerCase() == currentUser.toLowerCase()),
      ));
    }
    return prs;
  }
}
