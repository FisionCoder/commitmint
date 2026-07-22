/// An issue fetched from a hosting provider's tracker (GitHub / GitLab).
class Issue {
  /// Provider-native number (GitHub issue number / GitLab iid).
  final int number;
  final String title;
  final String url;
  final String author;
  final DateTime? updated;

  const Issue({
    required this.number,
    required this.title,
    required this.url,
    this.author = '',
    this.updated,
  });
}
