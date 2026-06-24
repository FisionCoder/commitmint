/// Supported integration providers (left rail of the Integrations screen).
enum ProviderType {
  github,
  githubEnterprise,
  gitlab,
  gitlabSelfManaged,
  bitbucket,
  bitbucketDataCenter,
  azureDevOps,
  jiraCloud,
  jiraDataCenter,
  trello,
}

/// How a provider authenticates:
/// - [tokenOnly]: a single Personal Access Token.
/// - [principalSecret]: an identity (email / username / key) plus a secret
///   (API token / app password / token).
enum AuthMode { tokenOnly, principalSecret }

extension ProviderTypeX on ProviderType {
  String get label {
    switch (this) {
      case ProviderType.github:
        return 'GitHub';
      case ProviderType.githubEnterprise:
        return 'GitHub Enterprise Server';
      case ProviderType.gitlab:
        return 'GitLab';
      case ProviderType.gitlabSelfManaged:
        return 'GitLab Self-Managed';
      case ProviderType.bitbucket:
        return 'Bitbucket';
      case ProviderType.bitbucketDataCenter:
        return 'Bitbucket Data Center';
      case ProviderType.azureDevOps:
        return 'Azure DevOps';
      case ProviderType.jiraCloud:
        return 'Jira Cloud';
      case ProviderType.jiraDataCenter:
        return 'Jira Data Center';
      case ProviderType.trello:
        return 'Trello';
    }
  }

  /// All providers are now wired up.
  bool get isImplemented => true;

  /// Whether this provider hosts git repositories that can be browsed/cloned.
  /// Issue/board trackers (Jira, Trello) do not.
  bool get hostsRepositories {
    switch (this) {
      case ProviderType.jiraCloud:
      case ProviderType.jiraDataCenter:
      case ProviderType.trello:
        return false;
      default:
        return true;
    }
  }

  /// Whether the connect form shows a host/URL field. Cloud providers with a
  /// fixed endpoint don't; self-managed / enterprise / Azure / Jira do.
  bool get needsHost {
    switch (this) {
      case ProviderType.github:
      case ProviderType.gitlab:
      case ProviderType.bitbucket:
      case ProviderType.trello:
        return false;
      default:
        return true;
    }
  }

  /// Fixed host for cloud providers (used when [needsHost] is false).
  String get defaultHost {
    switch (this) {
      case ProviderType.github:
        return 'github.com';
      case ProviderType.gitlab:
        return 'gitlab.com';
      case ProviderType.bitbucket:
        return 'bitbucket.org';
      case ProviderType.trello:
        return 'trello.com';
      default:
        return '';
    }
  }

  AuthMode get authMode {
    switch (this) {
      case ProviderType.bitbucket:
      case ProviderType.jiraCloud:
      case ProviderType.trello:
        return AuthMode.principalSecret;
      default:
        return AuthMode.tokenOnly;
    }
  }

  /// Label for the host/URL field.
  String get hostLabel {
    switch (this) {
      case ProviderType.azureDevOps:
        return 'Host Domain';
      case ProviderType.jiraCloud:
        return 'Site URL';
      default:
        return 'Server URL';
    }
  }

  String get hostHint {
    switch (this) {
      case ProviderType.azureDevOps:
        return 'e.g., dev.azure.com/mycompany';
      case ProviderType.githubEnterprise:
        return 'e.g., github.mycompany.com';
      case ProviderType.gitlabSelfManaged:
        return 'e.g., gitlab.mycompany.com';
      case ProviderType.bitbucketDataCenter:
        return 'e.g., bitbucket.mycompany.com';
      case ProviderType.jiraCloud:
        return 'e.g., mycompany.atlassian.net';
      case ProviderType.jiraDataCenter:
        return 'e.g., jira.mycompany.com';
      default:
        return '';
    }
  }

  /// Label for the identity field (only used in [AuthMode.principalSecret]).
  String get principalLabel {
    switch (this) {
      case ProviderType.bitbucket:
        return 'Username';
      case ProviderType.jiraCloud:
        return 'Email';
      case ProviderType.trello:
        return 'API Key';
      default:
        return 'Username';
    }
  }

  /// Label for the secret field.
  String get secretLabel {
    switch (this) {
      case ProviderType.bitbucket:
        return 'App Password';
      case ProviderType.jiraCloud:
        return 'API Token';
      case ProviderType.trello:
        return 'Token';
      default:
        return 'Personal Access Token';
    }
  }

  /// The provider page to open in the browser so the user can sign in and
  /// create the token/secret to paste back. Host-aware for self-managed /
  /// enterprise / Azure / Jira instances; [host] may be empty for those (then a
  /// sensible fallback is used). Scopes/description are pre-filled where the
  /// provider supports it.
  String tokenCreateUrl(String host) {
    final h = host.trim().replaceAll(RegExp(r'/+$'), '');
    switch (this) {
      case ProviderType.github:
        return 'https://github.com/settings/tokens/new'
            '?scopes=repo&description=Commit%20Mint';
      case ProviderType.githubEnterprise:
        return h.isEmpty
            ? 'https://docs.github.com/en/enterprise-server/authentication'
            : 'https://$h/settings/tokens/new?scopes=repo&description=Commit%20Mint';
      case ProviderType.gitlab:
        return 'https://gitlab.com/-/user_settings/personal_access_tokens'
            '?name=Commit+Mint&scopes=read_api,read_repository,write_repository';
      case ProviderType.gitlabSelfManaged:
        return h.isEmpty
            ? 'https://docs.gitlab.com/ee/user/profile/personal_access_tokens.html'
            : 'https://$h/-/user_settings/personal_access_tokens'
                '?name=Commit+Mint&scopes=read_api,read_repository,write_repository';
      case ProviderType.bitbucket:
        return 'https://bitbucket.org/account/settings/app-passwords/';
      case ProviderType.bitbucketDataCenter:
        return h.isEmpty
            ? 'https://confluence.atlassian.com/bitbucketserver/personal-access-tokens-939515499.html'
            : 'https://$h/plugins/servlet/access-tokens/manage';
      case ProviderType.azureDevOps:
        return h.isEmpty
            ? 'https://dev.azure.com'
            : 'https://$h/_usersSettings/tokens';
      case ProviderType.jiraCloud:
        return 'https://id.atlassian.com/manage-profile/security/api-tokens';
      case ProviderType.jiraDataCenter:
        return h.isEmpty
            ? 'https://confluence.atlassian.com/enterprise/using-personal-access-tokens-1026032365.html'
            : 'https://$h/secure/ViewProfile.jspa';
      case ProviderType.trello:
        return 'https://trello.com/app-key';
    }
  }

  /// Hint shown under the secret field describing how to create the token.
  String get tokenHelp {
    switch (this) {
      case ProviderType.github:
      case ProviderType.githubEnterprise:
        return 'GitHub → Settings → Developer settings → Personal access '
            'tokens, with "repo" scope.';
      case ProviderType.gitlab:
      case ProviderType.gitlabSelfManaged:
        return 'GitLab → Preferences → Access Tokens, with read_api and '
            'read_repository scopes.';
      case ProviderType.bitbucket:
        return 'Bitbucket → Personal settings → App passwords, with '
            'Repositories: Read.';
      case ProviderType.bitbucketDataCenter:
        return 'Bitbucket → Manage account → HTTP access tokens, with '
            'Repository read.';
      case ProviderType.azureDevOps:
        return 'Azure DevOps → User settings → Personal access tokens, with '
            'Code (Read).';
      case ProviderType.jiraCloud:
        return 'Atlassian → Account → Security → Create and manage API tokens.';
      case ProviderType.jiraDataCenter:
        return 'Jira → Profile → Personal Access Tokens.';
      case ProviderType.trello:
        return 'Get your API key and token at trello.com/app-key.';
    }
  }
}

/// A saved connection to an integration provider.
class Integration {
  final String id;
  final ProviderType provider;

  /// Normalized host/URL/site without scheme (e.g. `github.com`,
  /// `dev.azure.com/org`, `mysite.atlassian.net`).
  final String host;

  /// Identity for [AuthMode.principalSecret] providers (email / username /
  /// key). The secret itself lives in secure storage. Null for token-only.
  final String? principal;

  /// Resolved display name after connecting.
  final String? userName;

  final DateTime addedAt;

  const Integration({
    required this.id,
    required this.provider,
    required this.host,
    this.principal,
    this.userName,
    required this.addedAt,
  });

  /// A short title for the saved-instance card (org for Azure, else the host
  /// or the provider name for fixed-host providers).
  String get title {
    if (provider == ProviderType.azureDevOps) return organization;
    if (!provider.needsHost) return userName ?? provider.label;
    return host.isNotEmpty ? host : provider.label;
  }

  /// Organization name (Azure DevOps), parsed from the host. Robust to a full
  /// project URL slipping in (only the first path segment is the org).
  String get organization {
    final cleaned = host
        .replaceFirst(RegExp(r'^https?://'), '')
        .replaceAll(RegExp(r'/+$'), '');
    final vsts = RegExp(r'^([^./]+)\.visualstudio\.com').firstMatch(cleaned);
    if (vsts != null) return vsts.group(1)!;
    final parts = cleaned.split('/');
    return parts.length > 1 ? parts[1] : cleaned;
  }

  Integration copyWith({String? userName, String? principal}) => Integration(
        id: id,
        provider: provider,
        host: host,
        principal: principal ?? this.principal,
        userName: userName ?? this.userName,
        addedAt: addedAt,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'provider': provider.name,
        'host': host,
        'principal': principal,
        'userName': userName,
        'addedAt': addedAt.toIso8601String(),
      };

  factory Integration.fromJson(Map<String, dynamic> json) => Integration(
        id: json['id'] as String,
        provider: ProviderType.values.firstWhere(
          (p) => p.name == json['provider'],
          orElse: () => ProviderType.azureDevOps,
        ),
        host: json['host'] as String? ?? '',
        principal: json['principal'] as String?,
        userName: json['userName'] as String?,
        addedAt: DateTime.tryParse(json['addedAt'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
      );

  /// Builds an [Integration] from the legacy `azure_instances` JSON shape
  /// (`hostDomain`/`userName`/`addedAt`), so existing Azure connections and
  /// their stored tokens keep working after the upgrade.
  factory Integration.fromLegacyAzure(Map<String, dynamic> json) => Integration(
        id: json['id'] as String,
        provider: ProviderType.azureDevOps,
        host: json['hostDomain'] as String? ?? '',
        userName: json['userName'] as String?,
        addedAt: DateTime.tryParse(json['addedAt'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
      );
}

/// A repository discovered on a provider, ready to clone.
class RemoteRepo {
  final String id;
  final String name;

  /// Owner / namespace / project the repo belongs to.
  final String group;

  /// HTTPS clone URL.
  final String cloneUrl;
  final String? defaultBranch;

  const RemoteRepo({
    required this.id,
    required this.name,
    required this.group,
    required this.cloneUrl,
    this.defaultBranch,
  });
}
