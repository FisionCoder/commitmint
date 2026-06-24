import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/git_repository.dart';
import '../models/integration.dart';

/// Persists saved repositories and Azure DevOps instances. Tokens are kept in
/// the OS secure store (DPAPI on Windows), everything else in shared prefs.
class StorageService {
  static const _kRepos = 'repositories';
  static const _kAzure = 'azure_instances'; // legacy key (migrated forward)
  static const _kIntegrations = 'integrations';
  static const _kLayout = 'layout';
  static const _kSettings = 'settings';
  static const _kTabs = 'open_tabs';
  static const _kAuthorColors = 'author_colors';
  // Secret key prefix kept as the legacy name so existing Azure tokens resolve.
  static const _patPrefix = 'azure_pat_';

  Future<Map<String, dynamic>> loadTabs() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kTabs);
    if (raw == null) return {};
    return jsonDecode(raw) as Map<String, dynamic>;
  }

  Future<void> saveTabs(Map<String, dynamic> data) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kTabs, jsonEncode(data));
  }

  Future<Map<String, int>> loadAuthorColors() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kAuthorColors);
    if (raw == null) return {};
    final m = jsonDecode(raw) as Map<String, dynamic>;
    return m.map((k, v) => MapEntry(k, (v as num).toInt()));
  }

  Future<void> saveAuthorColors(Map<String, int> slots) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kAuthorColors, jsonEncode(slots));
  }

  Future<Map<String, dynamic>> loadLayout() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kLayout);
    if (raw == null) return {};
    return jsonDecode(raw) as Map<String, dynamic>;
  }

  Future<void> saveLayout(Map<String, dynamic> layout) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kLayout, jsonEncode(layout));
  }

  Future<Map<String, dynamic>> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kSettings);
    if (raw == null) return {};
    return jsonDecode(raw) as Map<String, dynamic>;
  }

  Future<void> saveSettings(Map<String, dynamic> settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kSettings, jsonEncode(settings));
  }

  final _secure = const FlutterSecureStorage(
    wOptions: WindowsOptions(),
  );

  Future<List<GitRepository>> loadRepositories() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kRepos);
    if (raw == null) return [];
    final list = jsonDecode(raw) as List;
    return list
        .map((e) => GitRepository.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> saveRepositories(List<GitRepository> repos) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _kRepos, jsonEncode(repos.map((e) => e.toJson()).toList()));
  }

  Future<List<Integration>> loadIntegrations() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kIntegrations);
    if (raw != null) {
      final list = jsonDecode(raw) as List;
      return list
          .map((e) => Integration.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    // Migrate legacy Azure-only connections forward (one-time).
    final legacy = prefs.getString(_kAzure);
    if (legacy != null) {
      final list = (jsonDecode(legacy) as List)
          .map((e) => Integration.fromLegacyAzure(e as Map<String, dynamic>))
          .toList();
      await saveIntegrations(list);
      return list;
    }
    return [];
  }

  Future<void> saveIntegrations(List<Integration> integrations) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _kIntegrations, jsonEncode(integrations.map((e) => e.toJson()).toList()));
  }

  Future<void> savePat(String instanceId, String pat) =>
      _secure.write(key: '$_patPrefix$instanceId', value: pat);

  Future<String?> readPat(String instanceId) =>
      _secure.read(key: '$_patPrefix$instanceId');

  Future<void> deletePat(String instanceId) =>
      _secure.delete(key: '$_patPrefix$instanceId');
}
