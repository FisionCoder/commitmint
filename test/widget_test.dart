import 'package:flutter_test/flutter_test.dart';

import 'package:commit_mint/models/integration.dart';
import 'package:commit_mint/services/azure_devops_service.dart';
import 'package:commit_mint/services/integration_service.dart';

void main() {
  Integration azure(String host) => Integration(
        id: '1',
        provider: ProviderType.azureDevOps,
        host: host,
        addedAt: DateTime(2026, 1, 1),
      );

  test('Integration.organization parses the Azure host', () {
    expect(azure('dev.azure.com/mycompany').organization, 'mycompany');
    expect(azure('https://dev.azure.com/contoso/').organization, 'contoso');
    // A full project URL still yields just the org.
    expect(
        azure('https://dev.azure.com/juliedenichaud/Honeycomb%20v3')
            .organization,
        'juliedenichaud');
    expect(azure('https://myorg.visualstudio.com/Project/_git/Repo').organization,
        'myorg');
  });

  test('IntegrationService.normalizeHost handles fixed and self-managed hosts',
      () {
    // Fixed-host providers ignore input and use their default host.
    expect(IntegrationService.normalizeHost(ProviderType.github, 'whatever'),
        'github.com');
    expect(IntegrationService.normalizeHost(ProviderType.gitlab, ''),
        'gitlab.com');
    // Self-managed strips scheme/credentials/trailing slash.
    expect(
        IntegrationService.normalizeHost(ProviderType.gitlabSelfManaged,
            'https://user@gitlab.acme.com/'),
        'gitlab.acme.com');
  });

  test('provider metadata is consistent', () {
    expect(ProviderType.github.hostsRepositories, true);
    expect(ProviderType.jiraCloud.hostsRepositories, false);
    expect(ProviderType.bitbucket.authMode, AuthMode.principalSecret);
    expect(ProviderType.github.authMode, AuthMode.tokenOnly);
    expect(ProviderType.github.needsHost, false);
    expect(ProviderType.githubEnterprise.needsHost, true);
  });

  test('normalizeHostDomain reduces any URL to the org root', () {
    expect(
        AzureDevOpsService.normalizeHostDomain(
            'https://dev.azure.com/juliedenichaud/Honeycomb%20v3'),
        'dev.azure.com/juliedenichaud');
    expect(
        AzureDevOpsService.normalizeHostDomain(
            'https://dev.azure.com/juliedenichaud/Honeycomb%20v3/_git/honeycomb'),
        'dev.azure.com/juliedenichaud');
    expect(AzureDevOpsService.normalizeHostDomain('dev.azure.com/contoso/'),
        'dev.azure.com/contoso');
    expect(
        AzureDevOpsService.normalizeHostDomain(
            'https://myorg.visualstudio.com/Project/_git/Repo'),
        'myorg.visualstudio.com');
  });

  test('ProviderType labels are non-empty', () {
    for (final p in ProviderType.values) {
      expect(p.label.isNotEmpty, true);
    }
  });
}
