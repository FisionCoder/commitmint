import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

/// GitHub repository that hosts Commit Mint releases.
const String _kRepo = 'FisionCoder/commitmint';

/// Details of an available update discovered on GitHub.
class UpdateInfo {
  /// Release tag, e.g. `v1.2.6`.
  final String tag;

  /// Human version without the leading `v`, e.g. `1.2.6`.
  final String version;

  /// The currently running version, e.g. `1.2.5`.
  final String currentVersion;

  /// Release title.
  final String name;

  /// Release notes (markdown body from GitHub).
  final String notes;

  /// Browser page for the release.
  final String htmlUrl;

  /// Download URL of the archive for this platform.
  final String assetUrl;

  /// Archive file name (e.g. `CommitMint-Windows-x64.zip`).
  final String assetName;

  /// Archive size in bytes (0 if unknown).
  final int assetSize;

  const UpdateInfo({
    required this.tag,
    required this.version,
    required this.currentVersion,
    required this.name,
    required this.notes,
    required this.htmlUrl,
    required this.assetUrl,
    required this.assetName,
    required this.assetSize,
  });
}

/// Result of a version check.
class UpdateCheckResult {
  /// The running version.
  final String currentVersion;

  /// The available update, or null if already up to date.
  final UpdateInfo? update;

  const UpdateCheckResult({required this.currentVersion, this.update});

  bool get hasUpdate => update != null;
}

/// Checks GitHub for newer releases and applies them in place.
///
/// The update is downloaded and extracted to a temp staging folder, then a
/// small detached helper script waits for this process to exit, copies the new
/// files over the install directory, and relaunches the app — this is the only
/// way to replace an executable that is currently running (especially on
/// Windows, where a running .exe/.dll is locked).
class UpdateService {
  /// Whether auto-update is supported on this platform.
  static bool get isSupported => Platform.isWindows || Platform.isLinux;

  /// Fetches the running app version from the platform bundle.
  static Future<String> currentVersion() async {
    final info = await PackageInfo.fromPlatform();
    return info.version;
  }

  /// Queries the GitHub "latest release" API and returns whether a newer
  /// version exists for this platform. Throws on network/API errors.
  static Future<UpdateCheckResult> checkForUpdate() async {
    final current = await currentVersion();
    final resp = await http.get(
      Uri.parse('https://api.github.com/repos/$_kRepo/releases/latest'),
      headers: const {
        'Accept': 'application/vnd.github+json',
        'User-Agent': 'CommitMint-Updater',
      },
    );
    if (resp.statusCode != 200) {
      throw Exception('GitHub returned ${resp.statusCode}');
    }
    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    final tag = (json['tag_name'] as String?)?.trim() ?? '';
    final version = _stripV(tag);
    if (version.isEmpty) throw Exception('No release tag found');

    if (_compareVersions(version, current) <= 0) {
      // Already on the latest (or newer, e.g. a local dev build).
      return UpdateCheckResult(currentVersion: current);
    }

    final assetName = _platformAssetName();
    final assets = (json['assets'] as List?) ?? const [];
    Map<String, dynamic>? asset;
    for (final a in assets.cast<Map<String, dynamic>>()) {
      if (a['name'] == assetName) {
        asset = a;
        break;
      }
    }
    if (asset == null) {
      // A release exists but not for this platform — nothing to offer.
      return UpdateCheckResult(currentVersion: current);
    }

    return UpdateCheckResult(
      currentVersion: current,
      update: UpdateInfo(
        tag: tag,
        version: version,
        currentVersion: current,
        name: (json['name'] as String?) ?? tag,
        notes: (json['body'] as String?) ?? '',
        htmlUrl: (json['html_url'] as String?) ?? '',
        assetUrl: asset['browser_download_url'] as String,
        assetName: assetName,
        assetSize: (asset['size'] as num?)?.toInt() ?? 0,
      ),
    );
  }

  /// Downloads [info]'s archive, reporting progress in [0.0, 1.0] via
  /// [onProgress] (or -1 when the total size is unknown). Returns the archive
  /// file path.
  static Future<String> download(
    UpdateInfo info, {
    void Function(double progress)? onProgress,
  }) async {
    final dir = await _stagingDir();
    // Start clean so a previous half-finished attempt can't corrupt this one.
    if (await dir.exists()) await dir.delete(recursive: true);
    await dir.create(recursive: true);

    final archivePath = '${dir.path}${Platform.pathSeparator}${info.assetName}';
    final client = http.Client();
    try {
      final req = http.Request('GET', Uri.parse(info.assetUrl));
      req.headers['User-Agent'] = 'CommitMint-Updater';
      final resp = await client.send(req);
      if (resp.statusCode != 200) {
        throw Exception('Download failed (${resp.statusCode})');
      }
      final total = resp.contentLength ?? info.assetSize;
      final sink = File(archivePath).openWrite();
      var received = 0;
      try {
        await for (final chunk in resp.stream) {
          sink.add(chunk);
          received += chunk.length;
          if (onProgress != null) {
            onProgress(total > 0 ? received / total : -1);
          }
        }
      } finally {
        await sink.close();
      }
      return archivePath;
    } finally {
      client.close();
    }
  }

  /// Extracts [archivePath] into a `staging` folder, writes the platform
  /// updater script, launches it detached, and terminates this process so the
  /// script can replace the running files and relaunch the app.
  ///
  /// Does not return on success (the process exits).
  static Future<void> applyAndRestart(String archivePath) async {
    final base = await _stagingDir();
    final staging = Directory('${base.path}${Platform.pathSeparator}staging');
    if (await staging.exists()) await staging.delete(recursive: true);
    await staging.create(recursive: true);

    await _extract(archivePath, staging.path);

    final installDir = File(Platform.resolvedExecutable).parent.path;
    final exePath = Platform.resolvedExecutable;
    final myPid = pid;

    if (Platform.isWindows) {
      await _launchWindowsUpdater(
          base.path, staging.path, installDir, exePath, myPid);
    } else {
      await _launchLinuxUpdater(
          base.path, staging.path, installDir, exePath, myPid);
    }

    // Give the helper a moment to start, then hard-exit so the files unlock.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    exit(0);
  }

  // ------------------------------------------------------------- internals ---

  static Future<Directory> _stagingDir() async {
    final tmp = Directory.systemTemp;
    return Directory('${tmp.path}${Platform.pathSeparator}commitmint_update');
  }

  static String _platformAssetName() {
    if (Platform.isWindows) return 'CommitMint-Windows-x64.zip';
    if (Platform.isLinux) return 'CommitMint-Linux-x64.tar.gz';
    throw UnsupportedError('Auto-update is not supported on this platform');
  }

  static Future<void> _extract(String archivePath, String destDir) async {
    if (Platform.isWindows) {
      // Expand-Archive ships with every Windows 10+ PowerShell.
      final r = await Process.run('powershell', [
        '-NoProfile',
        '-Command',
        'Expand-Archive -LiteralPath ${_ps(archivePath)} '
            '-DestinationPath ${_ps(destDir)} -Force',
      ]);
      if (r.exitCode != 0) {
        throw Exception('Extraction failed: ${r.stderr}');
      }
    } else {
      final r = await Process.run('tar', ['-xzf', archivePath, '-C', destDir]);
      if (r.exitCode != 0) {
        throw Exception('Extraction failed: ${r.stderr}');
      }
    }
  }

  static Future<void> _launchWindowsUpdater(String baseDir, String staging,
      String installDir, String exePath, int pid) async {
    final script = '$baseDir\\apply_update.bat';
    // robocopy exit codes 0-7 are success; treat >=8 as failure but we relaunch
    // regardless. /MIR would delete extra files but that risks user data next
    // to the exe, so we mirror the bundle with /E (add/overwrite only).
    final content = '''
@echo off
setlocal
echo Waiting for Commit Mint to close...
:waitloop
tasklist /fi "PID eq $pid" 2>nul | find "$pid" >nul
if not errorlevel 1 (
  timeout /t 1 /nobreak >nul
  goto waitloop
)
robocopy "$staging" "$installDir" /E /NFL /NDL /NJH /NJS /NC /NS /NP >nul
start "" "$exePath"
rmdir /s /q "$baseDir" 2>nul
endlocal
''';
    await File(script).writeAsString(content);
    await Process.start('cmd', ['/c', script],
        mode: ProcessStartMode.detached, runInShell: false);
  }

  static Future<void> _launchLinuxUpdater(String baseDir, String staging,
      String installDir, String exePath, int pid) async {
    final script = '$baseDir/apply_update.sh';
    final content = '''
#!/bin/sh
while kill -0 $pid 2>/dev/null; do
  sleep 0.5
done
cp -rf "$staging/." "$installDir/"
chmod +x "$exePath" 2>/dev/null
"$exePath" &
rm -rf "$baseDir"
''';
    await File(script).writeAsString(content);
    await Process.run('chmod', ['+x', script]);
    await Process.start('sh', [script],
        mode: ProcessStartMode.detached, runInShell: false);
  }

  /// Single-quotes a path for a PowerShell argument.
  static String _ps(String path) => "'${path.replaceAll("'", "''")}'";

  static String _stripV(String tag) =>
      tag.startsWith('v') ? tag.substring(1) : tag;

  /// Compares dotted numeric versions. Returns >0 if [a] > [b], <0 if a<b,
  /// 0 if equal. Non-numeric suffixes are ignored.
  static int _compareVersions(String a, String b) {
    final pa = _parts(a);
    final pb = _parts(b);
    final len = pa.length > pb.length ? pa.length : pb.length;
    for (var i = 0; i < len; i++) {
      final x = i < pa.length ? pa[i] : 0;
      final y = i < pb.length ? pb[i] : 0;
      if (x != y) return x - y;
    }
    return 0;
  }

  static List<int> _parts(String v) {
    // Keep only the numeric core (drop any build/pre-release suffix).
    final core = v.split(RegExp(r'[-+]')).first;
    return core
        .split('.')
        .map((s) => int.tryParse(s.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0)
        .toList();
  }
}
