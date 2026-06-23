/// A repository the user has added to the app.
class GitRepository {
  final String id;
  final String name;
  final String path; // local working directory
  final String? remoteUrl;

  /// Id of the integration this repo was cloned from, if any.
  final String? integrationId;

  const GitRepository({
    required this.id,
    required this.name,
    required this.path,
    this.remoteUrl,
    this.integrationId,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'path': path,
        'remoteUrl': remoteUrl,
        'integrationId': integrationId,
      };

  factory GitRepository.fromJson(Map<String, dynamic> json) => GitRepository(
        id: json['id'] as String,
        name: json['name'] as String,
        path: json['path'] as String,
        remoteUrl: json['remoteUrl'] as String?,
        // Accept the legacy `azureInstanceId` key for repos saved earlier.
        integrationId: json['integrationId'] as String? ??
            json['azureInstanceId'] as String?,
      );
}
