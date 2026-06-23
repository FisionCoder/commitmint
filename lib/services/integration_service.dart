import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/integration.dart';
import 'azure_devops_service.dart';

class IntegrationException implements Exception {
  final String message;
  IntegrationException(this.message);
  @override
  String toString() => message;
}

/// Result of a successful connect: the resolved display name and the
/// normalized host to persist.
class ConnectionResult {
  final String displayName;
  final String host;
  ConnectionResult(this.displayName, this.host);
}

/// Provider-agnostic façade over each integration's REST API. Handles
/// connecting (credential validation + display-name resolution), listing
/// repositories, and building the userinfo used for HTTPS clone auth.
class IntegrationService {
  static const _timeout = Duration(seconds: 25);

  /// Strips scheme, embedded credentials and trailing slashes from a host.
  static String normalizeHost(ProviderType p, String input) {
    if (p == ProviderType.azureDevOps) {
      return AzureDevOpsService.normalizeHostDomain(input);
    }
    if (!p.needsHost) return p.defaultHost;
    var s = input.trim();
    s = s.replaceFirst(RegExp(r'^https?://'), '');
    s = s.replaceFirst(RegExp(r'^[^@/]*@'), '');
    s = s.replaceAll(RegExp(r'/+$'), '');
    return s;
  }

  // ----------------------------------------------------------- connect ----
  static Future<ConnectionResult> connect(
    ProviderType provider,
    String hostInput,
    String? principal,
    String secret,
  ) async {
    if (secret.trim().isEmpty) {
      throw IntegrationException('A ${provider.secretLabel} is required.');
    }
    if (provider.authMode == AuthMode.principalSecret &&
        (principal == null || principal.trim().isEmpty)) {
      throw IntegrationException('A ${provider.principalLabel} is required.');
    }
    final host = normalizeHost(provider, hostInput);
    if (provider.needsHost && host.isEmpty) {
      throw IntegrationException('A ${provider.hostLabel} is required.');
    }

    switch (provider) {
      case ProviderType.azureDevOps:
        final r = await AzureDevOpsService.connect(hostInput, secret);
        return ConnectionResult(r.displayName, r.hostDomain);
      case ProviderType.github:
      case ProviderType.githubEnterprise:
        return _connectGitHub(provider, host, secret);
      case ProviderType.gitlab:
      case ProviderType.gitlabSelfManaged:
        return _connectGitLab(host, secret);
      case ProviderType.bitbucket:
        return _connectBitbucketCloud(host, principal!, secret);
      case ProviderType.bitbucketDataCenter:
        return _connectBitbucketServer(host, secret);
      case ProviderType.jiraCloud:
        return _connectJiraCloud(host, principal!, secret);
      case ProviderType.jiraDataCenter:
        return _connectJiraServer(host, secret);
      case ProviderType.trello:
        return _connectTrello(principal!, secret);
    }
  }

  // -------------------------------------------------------- list repos ----
  static Future<List<RemoteRepo>> listRepositories(
      Integration inst, String secret) async {
    switch (inst.provider) {
      case ProviderType.azureDevOps:
        return AzureDevOpsService.listRepositories(inst.host, secret);
      case ProviderType.github:
      case ProviderType.githubEnterprise:
        return _reposGitHub(inst.provider, inst.host, secret);
      case ProviderType.gitlab:
      case ProviderType.gitlabSelfManaged:
        return _reposGitLab(inst.host, secret);
      case ProviderType.bitbucket:
        return _reposBitbucketCloud(inst.host, inst.principal!, secret);
      case ProviderType.bitbucketDataCenter:
        return _reposBitbucketServer(inst.host, secret);
      default:
        return const [];
    }
  }

  /// The `user:pass` userinfo to inject into an HTTPS clone URL for [inst].
  static String cloneUserInfo(Integration inst, String secret) {
    switch (inst.provider) {
      case ProviderType.azureDevOps:
        return 'pat:${Uri.encodeComponent(secret)}';
      case ProviderType.github:
      case ProviderType.githubEnterprise:
        return 'x-access-token:${Uri.encodeComponent(secret)}';
      case ProviderType.gitlab:
      case ProviderType.gitlabSelfManaged:
        return 'oauth2:${Uri.encodeComponent(secret)}';
      case ProviderType.bitbucket:
        return '${Uri.encodeComponent(inst.principal ?? '')}:'
            '${Uri.encodeComponent(secret)}';
      case ProviderType.bitbucketDataCenter:
        return Uri.encodeComponent(secret);
      default:
        return Uri.encodeComponent(secret);
    }
  }

  // ============================================================ GitHub ====
  static String _githubBase(ProviderType p, String host) =>
      p == ProviderType.github
          ? 'https://api.github.com'
          : 'https://$host/api/v3';

  static Map<String, String> _bearer(String token) => {
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
      };

  static Future<ConnectionResult> _connectGitHub(
      ProviderType p, String host, String token) async {
    final base = _githubBase(p, host);
    final body = await _getJson('$base/user', _githubHeaders(token));
    final name = (body['name'] as String?)?.trim();
    final login = body['login'] as String?;
    return ConnectionResult(
        name?.isNotEmpty == true ? name! : (login ?? 'Connected'), host);
  }

  static Map<String, String> _githubHeaders(String token) => {
        'Authorization': 'Bearer $token',
        'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
      };

  static Future<List<RemoteRepo>> _reposGitHub(
      ProviderType p, String host, String token) async {
    final base = _githubBase(p, host);
    final repos = <RemoteRepo>[];
    for (var page = 1; page <= 3; page++) {
      final list = await _getJsonList(
          '$base/user/repos?per_page=100&sort=updated&page=$page',
          _githubHeaders(token));
      if (list.isEmpty) break;
      for (final item in list.cast<Map<String, dynamic>>()) {
        repos.add(RemoteRepo(
          id: '${item['id']}',
          name: item['name'] as String? ?? '',
          group: (item['owner'] as Map<String, dynamic>?)?['login']
                  as String? ??
              '',
          cloneUrl: item['clone_url'] as String? ?? '',
          defaultBranch: item['default_branch'] as String?,
        ));
      }
      if (list.length < 100) break;
    }
    return _sorted(repos);
  }

  // ============================================================ GitLab ====
  static Future<ConnectionResult> _connectGitLab(
      String host, String token) async {
    final body = await _getJson(
        'https://$host/api/v4/user', {'PRIVATE-TOKEN': token});
    final name = (body['name'] as String?)?.trim();
    final username = body['username'] as String?;
    return ConnectionResult(
        name?.isNotEmpty == true ? name! : (username ?? 'Connected'), host);
  }

  static Future<List<RemoteRepo>> _reposGitLab(
      String host, String token) async {
    final repos = <RemoteRepo>[];
    for (var page = 1; page <= 3; page++) {
      final list = await _getJsonList(
          'https://$host/api/v4/projects?membership=true&simple=true'
          '&per_page=100&order_by=last_activity_at&page=$page',
          {'PRIVATE-TOKEN': token});
      if (list.isEmpty) break;
      for (final item in list.cast<Map<String, dynamic>>()) {
        final ns = (item['namespace'] as Map<String, dynamic>?)?['full_path']
            as String?;
        repos.add(RemoteRepo(
          id: '${item['id']}',
          name: item['name'] as String? ?? item['path'] as String? ?? '',
          group: ns ?? '',
          cloneUrl: item['http_url_to_repo'] as String? ?? '',
          defaultBranch: item['default_branch'] as String?,
        ));
      }
      if (list.length < 100) break;
    }
    return _sorted(repos);
  }

  // ==================================================== Bitbucket Cloud ====
  static Future<ConnectionResult> _connectBitbucketCloud(
      String host, String username, String appPassword) async {
    final body = await _getJson(
        'https://api.bitbucket.org/2.0/user', _basic(username, appPassword));
    final name = (body['display_name'] as String?)?.trim();
    return ConnectionResult(
        name?.isNotEmpty == true ? name! : username, host);
  }

  static Future<List<RemoteRepo>> _reposBitbucketCloud(
      String host, String username, String appPassword) async {
    final repos = <RemoteRepo>[];
    var url =
        'https://api.bitbucket.org/2.0/repositories?role=member&pagelen=100';
    for (var i = 0; i < 5 && url.isNotEmpty; i++) {
      final body = await _getJson(url, _basic(username, appPassword));
      final values = (body['values'] as List?) ?? const [];
      for (final item in values.cast<Map<String, dynamic>>()) {
        final clones = ((item['links'] as Map<String, dynamic>?)?['clone']
                as List?) ??
            const [];
        String href = '';
        for (final c in clones.cast<Map<String, dynamic>>()) {
          if (c['name'] == 'https') href = c['href'] as String? ?? '';
        }
        // Strip any embedded username so our own creds inject cleanly.
        href = href.replaceFirst(RegExp(r'^https://[^@/]*@'), 'https://');
        final full = item['full_name'] as String? ?? '';
        repos.add(RemoteRepo(
          id: item['uuid'] as String? ?? full,
          name: item['name'] as String? ?? '',
          group: full.contains('/') ? full.split('/').first : '',
          cloneUrl: href,
          defaultBranch:
              (item['mainbranch'] as Map<String, dynamic>?)?['name'] as String?,
        ));
      }
      url = body['next'] as String? ?? '';
    }
    return _sorted(repos);
  }

  // =================================================== Bitbucket Server ====
  static Future<ConnectionResult> _connectBitbucketServer(
      String host, String token) async {
    // No "current user" endpoint for HTTP tokens; validate via projects.
    await _getJson(
        'https://$host/rest/api/1.0/projects?limit=1', _bearer(token));
    return ConnectionResult('Connected', host);
  }

  static Future<List<RemoteRepo>> _reposBitbucketServer(
      String host, String token) async {
    final repos = <RemoteRepo>[];
    var start = 0;
    for (var i = 0; i < 5; i++) {
      final body = await _getJson(
          'https://$host/rest/api/1.0/repos?limit=100&start=$start',
          _bearer(token));
      final values = (body['values'] as List?) ?? const [];
      for (final item in values.cast<Map<String, dynamic>>()) {
        final clones = ((item['links'] as Map<String, dynamic>?)?['clone']
                as List?) ??
            const [];
        String href = '';
        for (final c in clones.cast<Map<String, dynamic>>()) {
          if (c['name'] == 'http' || c['name'] == 'https') {
            href = c['href'] as String? ?? '';
          }
        }
        href = href.replaceFirst(RegExp(r'^https://[^@/]*@'), 'https://');
        repos.add(RemoteRepo(
          id: '${item['id']}',
          name: item['name'] as String? ?? item['slug'] as String? ?? '',
          group:
              (item['project'] as Map<String, dynamic>?)?['key'] as String? ??
                  '',
          cloneUrl: href,
          defaultBranch: null,
        ));
      }
      if (body['isLastPage'] == true || values.isEmpty) break;
      start = (body['nextPageStart'] as num?)?.toInt() ?? (start + 100);
    }
    return _sorted(repos);
  }

  // ============================================================= Jira ====
  static Future<ConnectionResult> _connectJiraCloud(
      String host, String email, String apiToken) async {
    final body =
        await _getJson('https://$host/rest/api/3/myself', _basic(email, apiToken));
    final name = (body['displayName'] as String?)?.trim();
    return ConnectionResult(name?.isNotEmpty == true ? name! : email, host);
  }

  static Future<ConnectionResult> _connectJiraServer(
      String host, String token) async {
    final body =
        await _getJson('https://$host/rest/api/2/myself', _bearer(token));
    final name = (body['displayName'] as String?)?.trim();
    return ConnectionResult(name?.isNotEmpty == true ? name! : 'Connected', host);
  }

  // =========================================================== Trello ====
  static Future<ConnectionResult> _connectTrello(
      String key, String token) async {
    final body = await _getJson(
        'https://api.trello.com/1/members/me?key=$key&token=$token', const {});
    final name = (body['fullName'] as String?)?.trim();
    final username = body['username'] as String?;
    return ConnectionResult(
        name?.isNotEmpty == true ? name! : (username ?? 'Connected'),
        'trello.com');
  }

  // ----------------------------------------------------------- helpers ----
  static Map<String, String> _basic(String user, String secret) {
    final token = base64.encode(utf8.encode('$user:$secret'));
    return {'Authorization': 'Basic $token', 'Accept': 'application/json'};
  }

  static List<RemoteRepo> _sorted(List<RemoteRepo> repos) {
    repos.sort((a, b) {
      final g = a.group.toLowerCase().compareTo(b.group.toLowerCase());
      return g != 0 ? g : a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return repos;
  }

  static Future<Map<String, dynamic>> _getJson(
      String url, Map<String, String> headers) async {
    http.Response res;
    try {
      res = await http.get(Uri.parse(url), headers: headers).timeout(_timeout);
    } catch (e) {
      throw IntegrationException('Could not reach $url.');
    }
    _checkStatus(res.statusCode);
    final decoded = jsonDecode(res.body);
    return decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
  }

  static Future<List<dynamic>> _getJsonList(
      String url, Map<String, String> headers) async {
    http.Response res;
    try {
      res = await http.get(Uri.parse(url), headers: headers).timeout(_timeout);
    } catch (e) {
      throw IntegrationException('Could not reach $url.');
    }
    _checkStatus(res.statusCode);
    final decoded = jsonDecode(res.body);
    return decoded is List ? decoded : const [];
  }

  static void _checkStatus(int code) {
    if (code == 200) return;
    if (code == 401 || code == 403) {
      throw IntegrationException(
          'Authentication failed — check the token and its scopes.');
    }
    if (code == 404) {
      throw IntegrationException('Not found — check the host/URL.');
    }
    throw IntegrationException('Server returned HTTP $code.');
  }
}
