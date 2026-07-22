import 'dart:math';

import 'package:flutter/foundation.dart';

import '../services/git_config_service.dart';
import '../services/git_service.dart';
import '../theme/app_theme.dart';
import '../services/storage_service.dart';

/// Pixel avatar grid is 5 columns x 7 rows (row-major) of on/off cells.
const int kAvatarCols = 5;
const int kAvatarRows = 7;

enum AppThemeMode { dark, light }

enum TerminalCursor { block, bar, underline }

enum NotificationLocation { topLeft, topRight, bottomLeft, bottomRight }

/// How much of the branch tree is shown in the commit graph.
enum BranchVisibility { all, current, none }

/// Whether the commit description (body) is shown in the details panel.
enum DescriptionVisibility { always, never }

/// A git identity profile. The active profile's identity is written to the
/// user's global git config.
class GitProfile {
  final String id;
  String name;
  String authorName;
  String authorEmail;

  /// Custom avatar colour (ARGB int) and pixel cells (35-char '0'/'1' string,
  /// row-major 5x7). Both null = use the auto-generated avatar from the email.
  int? avatarColor;
  String? avatarCells;

  GitProfile({
    required this.id,
    required this.name,
    this.authorName = '',
    this.authorEmail = '',
    this.avatarColor,
    this.avatarCells,
  });

  bool get hasCustomAvatar => avatarCells != null;

  /// Decodes [avatarCells] into a 7-row x 5-col grid, or null if unset/invalid.
  List<List<bool>>? get avatarGrid {
    final s = avatarCells;
    if (s == null || s.length != kAvatarCols * kAvatarRows) return null;
    return List.generate(
      kAvatarRows,
      (r) => List.generate(kAvatarCols, (c) => s[r * kAvatarCols + c] == '1'),
    );
  }

  static String encodeGrid(List<List<bool>> grid) {
    final b = StringBuffer();
    for (final row in grid) {
      for (final on in row) {
        b.write(on ? '1' : '0');
      }
    }
    return b.toString();
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'authorName': authorName,
        'authorEmail': authorEmail,
        if (avatarColor != null) 'avatarColor': avatarColor,
        if (avatarCells != null) 'avatarCells': avatarCells,
      };

  static GitProfile fromJson(Map<String, dynamic> j) => GitProfile(
        id: j['id'] as String,
        name: (j['name'] as String?) ?? 'Profile',
        authorName: (j['authorName'] as String?) ?? '',
        authorEmail: (j['authorEmail'] as String?) ?? '',
        avatarColor: (j['avatarColor'] as num?)?.toInt(),
        avatarCells: j['avatarCells'] as String?,
      );
}

/// Application preferences shown on the Settings screen. Every value here is
/// actually applied somewhere: git-backed values go to the global git config;
/// SSH/credential values flow into [GitRuntimeConfig] which every network git
/// command consults; the rest drive the theme, terminal, commit graph,
/// toolbar, notifications, and startup behaviour. Persisted to shared-prefs.
class SettingsState extends ChangeNotifier {
  final StorageService _storage = StorageService();
  final GitConfigService _git = GitConfigService();

  // ----- General (git-backed + startup) ------------------------------------
  String defaultBranchName = '';
  bool longPaths = false;
  bool autoCrlf = false;
  bool rememberTabs = true;

  // ----- Appearance --------------------------------------------------------
  AppThemeMode themeMode = AppThemeMode.dark;
  NotificationLocation notificationLocation = NotificationLocation.bottomRight;

  // ----- Date / time -------------------------------------------------------
  String dateTimeLocale = 'system'; // 'system' or an intl locale code
  String dateTimeFormat = 'MM/dd/yyyy @ h:mm a'; // graph date column
  String dateWordFormat = 'EEE, MMM d yyyy • h:mm a'; // commit details
  String dateVerboseFormat = 'EEEE, MMMM d, y · h:mm a'; // hover tooltip

  // ----- UI / graph --------------------------------------------------------
  bool showToolbarLabels = true;
  bool enableSpellChecking = true;
  bool useInitialsAvatars = false;
  bool showGhostHover = true;
  bool highlightAssociatedRows = true;
  BranchVisibility branchVisibility = BranchVisibility.all;
  DescriptionVisibility commitDescriptionVisibility =
      DescriptionVisibility.always;

  // ----- SSH / credentials -------------------------------------------------
  bool useLocalSshAgent = false;
  String sshPrivateKeyPath = '';
  String sshPublicKeyPath = '';
  bool useGitCredentialManager = true;

  // ----- Commit signing (git-backed: commit.gpgsign / user.signingkey /
  // gpg.format) --------------------------------------------------------------
  bool signCommits = false;
  String signingKey = '';
  bool signWithSsh = false; // false = OpenPGP (default), true = SSH

  // ----- In-App Terminal ---------------------------------------------------
  String terminalFont = 'Consolas';
  double terminalFontSize = 13;
  double terminalLineHeight = 1.2;
  TerminalCursor terminalCursor = TerminalCursor.bar;
  bool dimTerminalWhenUnfocused = true;
  String defaultShell = 'powershell';

  // ----- Profiles ----------------------------------------------------------
  List<GitProfile> profiles = [];
  String? activeProfileId;

  /// The profile whose author email matches [email] (case-insensitive), or
  /// null. Used to show a profile's custom avatar on its own commits.
  GitProfile? profileForEmail(String email) {
    final e = email.trim().toLowerCase();
    if (e.isEmpty) return null;
    for (final p in profiles) {
      if (p.authorEmail.trim().toLowerCase() == e) return p;
    }
    return null;
  }

  GitProfile get activeProfile {
    if (profiles.isEmpty) {
      final p = GitProfile(id: 'default', name: 'Default Profile');
      profiles = [p];
      activeProfileId = p.id;
    }
    return profiles.firstWhere((p) => p.id == activeProfileId,
        orElse: () => profiles.first);
  }

  /// The intl locale to pass to DateFormat (null = system default).
  String? get effectiveLocale =>
      dateTimeLocale == 'system' ? null : dateTimeLocale;

  Palette get palette =>
      themeMode == AppThemeMode.light ? lightPalette : darkPalette;

  bool _loaded = false;
  bool get loaded => _loaded;

  Future<void> init() async {
    final m = await _storage.loadSettings();
    _readFrom(m);
    AppColors.apply(palette);
    _applyRuntime();
    final cfg = await _git.read();
    if (profiles.isEmpty) {
      profiles = [
        GitProfile(
          id: 'default',
          name: 'Default Profile',
          authorName: cfg.userName,
          authorEmail: cfg.userEmail,
        )
      ];
      activeProfileId = 'default';
    }
    if (defaultBranchName.isEmpty) defaultBranchName = cfg.defaultBranch;
    autoCrlf = cfg.autoCrlf;
    longPaths = cfg.longPaths;
    // Signing config is read straight from git (not persisted to prefs).
    signCommits = (await _git.get('commit.gpgsign'))?.toLowerCase() == 'true';
    signingKey = await _git.get('user.signingkey') ?? '';
    signWithSsh = (await _git.get('gpg.format'))?.toLowerCase() == 'ssh';
    _loaded = true;
    notifyListeners();
  }

  // --------------------------------------------------------------- IO ------
  void _readFrom(Map<String, dynamic> m) {
    double readD(String k, double d) =>
        (m[k] is num) ? (m[k] as num).toDouble() : d;
    bool readB(String k, bool d) => (m[k] is bool) ? m[k] as bool : d;
    String readS(String k, String d) => (m[k] is String) ? m[k] as String : d;
    T readE<T>(String k, List<T> values, T d) {
      final i = m[k];
      if (i is num && i.toInt() >= 0 && i.toInt() < values.length) {
        return values[i.toInt()];
      }
      return d;
    }

    defaultBranchName = readS('defaultBranchName', defaultBranchName);
    rememberTabs = readB('rememberTabs', rememberTabs);

    themeMode = readE('themeMode', AppThemeMode.values, themeMode);
    notificationLocation = readE(
        'notificationLocation', NotificationLocation.values, notificationLocation);

    dateTimeLocale = readS('dateTimeLocale', dateTimeLocale);
    dateTimeFormat = readS('dateTimeFormat', dateTimeFormat);
    dateWordFormat = readS('dateWordFormat', dateWordFormat);
    dateVerboseFormat = readS('dateVerboseFormat', dateVerboseFormat);

    showToolbarLabels = readB('showToolbarLabels', showToolbarLabels);
    enableSpellChecking = readB('enableSpellChecking', enableSpellChecking);
    useInitialsAvatars = readB('useInitialsAvatars', useInitialsAvatars);
    showGhostHover = readB('showGhostHover', showGhostHover);
    highlightAssociatedRows =
        readB('highlightAssociatedRows', highlightAssociatedRows);
    branchVisibility =
        readE('branchVisibility', BranchVisibility.values, branchVisibility);
    commitDescriptionVisibility = readE('commitDescriptionVisibility',
        DescriptionVisibility.values, commitDescriptionVisibility);

    useLocalSshAgent = readB('useLocalSshAgent', useLocalSshAgent);
    sshPrivateKeyPath = readS('sshPrivateKeyPath', sshPrivateKeyPath);
    sshPublicKeyPath = readS('sshPublicKeyPath', sshPublicKeyPath);
    useGitCredentialManager =
        readB('useGitCredentialManager', useGitCredentialManager);

    terminalFont = readS('terminalFont', terminalFont);
    terminalFontSize = readD('terminalFontSize', terminalFontSize);
    terminalLineHeight = readD('terminalLineHeight', terminalLineHeight);
    terminalCursor =
        readE('terminalCursor', TerminalCursor.values, terminalCursor);
    dimTerminalWhenUnfocused =
        readB('dimTerminalWhenUnfocused', dimTerminalWhenUnfocused);
    defaultShell = readS('defaultShell', defaultShell);

    final ps = m['profiles'];
    if (ps is List) {
      profiles = ps
          .map((e) => GitProfile.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    activeProfileId = m['activeProfileId'] as String? ?? activeProfileId;
  }

  Map<String, dynamic> _toJson() => {
        'defaultBranchName': defaultBranchName,
        'rememberTabs': rememberTabs,
        'themeMode': themeMode.index,
        'notificationLocation': notificationLocation.index,
        'dateTimeLocale': dateTimeLocale,
        'dateTimeFormat': dateTimeFormat,
        'dateWordFormat': dateWordFormat,
        'dateVerboseFormat': dateVerboseFormat,
        'showToolbarLabels': showToolbarLabels,
        'enableSpellChecking': enableSpellChecking,
        'useInitialsAvatars': useInitialsAvatars,
        'showGhostHover': showGhostHover,
        'highlightAssociatedRows': highlightAssociatedRows,
        'branchVisibility': branchVisibility.index,
        'commitDescriptionVisibility': commitDescriptionVisibility.index,
        'useLocalSshAgent': useLocalSshAgent,
        'sshPrivateKeyPath': sshPrivateKeyPath,
        'sshPublicKeyPath': sshPublicKeyPath,
        'useGitCredentialManager': useGitCredentialManager,
        'terminalFont': terminalFont,
        'terminalFontSize': terminalFontSize,
        'terminalLineHeight': terminalLineHeight,
        'terminalCursor': terminalCursor.index,
        'dimTerminalWhenUnfocused': dimTerminalWhenUnfocused,
        'defaultShell': defaultShell,
        'profiles': profiles.map((p) => p.toJson()).toList(),
        'activeProfileId': activeProfileId,
      };

  void _save() {
    _storage.saveSettings(_toJson());
    notifyListeners();
  }

  /// Pushes SSH / credential settings into the runtime config consulted by
  /// every network git command.
  void _applyRuntime() {
    GitRuntimeConfig.useLocalAgent = useLocalSshAgent;
    GitRuntimeConfig.sshKeyPath =
        sshPrivateKeyPath.trim().isEmpty ? null : sshPrivateKeyPath.trim();
    GitRuntimeConfig.useCredentialManager = useGitCredentialManager;
  }

  /// Generic mutator: applies [change], persists, refreshes runtime, notifies.
  void update(VoidCallback change) {
    change();
    _applyRuntime();
    _save();
  }

  void setThemeMode(AppThemeMode mode) {
    themeMode = mode;
    AppColors.apply(palette);
    _save();
  }

  // ---------------------------------------------------- git-backed writes ---
  Future<void> applyToGitConfig() async {
    final p = activeProfile;
    await _git.set('user.name', p.authorName);
    await _git.set('user.email', p.authorEmail);
    await _git.set('init.defaultBranch', defaultBranchName);
    await _git.set('core.autocrlf', autoCrlf ? 'true' : 'false');
    await _git.set('core.longpaths', longPaths ? 'true' : 'false');
  }

  /// Writes the commit-signing settings to the global git config. Enabling
  /// requires a signing key; the format selects OpenPGP (GPG) vs SSH.
  Future<void> applySigningConfig() async {
    await _git.set('commit.gpgsign', signCommits ? 'true' : 'false');
    await _git.set('user.signingkey', signingKey);
    await _git.set('gpg.format', signWithSsh ? 'ssh' : 'openpgp');
  }

  Future<bool> forgetCredentials() => _git.forgetCredentials();

  String defaultSshKeyPath() => _git.defaultKeyPath();

  Future<String> generateSshKey(String path) =>
      _git.generateKey(path, comment: activeProfile.authorEmail);

  // ------------------------------------------------------------- profiles ---
  void addProfile() {
    final id =
        'p${profiles.length}_${profiles.fold<int>(0, (a, p) => a + p.id.length)}';
    profiles = [...profiles, GitProfile(id: id, name: 'New Profile')];
    _save();
  }

  void removeProfile(String id) {
    if (profiles.length <= 1) return;
    profiles = profiles.where((p) => p.id != id).toList();
    if (activeProfileId == id) activeProfileId = profiles.first.id;
    _save();
  }

  void setActiveProfile(String id) {
    activeProfileId = id;
    _save();
    applyToGitConfig();
  }

  // ------------------------------------------------------ profile avatar ---
  GitProfile? _profileById(String id) {
    for (final p in profiles) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// Saves a custom avatar (colour + cells) for a profile.
  void setProfileAvatar(String id, int color, List<List<bool>> grid) {
    final p = _profileById(id);
    if (p == null) return;
    p.avatarColor = color;
    p.avatarCells = GitProfile.encodeGrid(grid);
    _save();
  }

  /// Generates a fresh random, horizontally-symmetric avatar for a profile.
  void regenerateProfileAvatar(String id) {
    final p = _profileById(id);
    if (p == null) return;
    final rnd = Random();
    final grid = List.generate(
      kAvatarRows,
      (_) => List<bool>.filled(kAvatarCols, false),
    );
    for (var r = 0; r < kAvatarRows; r++) {
      for (var c = 0; c < (kAvatarCols / 2).ceil(); c++) {
        final on = rnd.nextBool();
        grid[r][c] = on;
        grid[r][kAvatarCols - 1 - c] = on; // mirror
      }
    }
    final palette = AppColors.lanes;
    p.avatarColor = palette[rnd.nextInt(palette.length)].toARGB32();
    p.avatarCells = GitProfile.encodeGrid(grid);
    _save();
  }

  /// Clears the custom avatar, reverting to the auto-generated one.
  void resetProfileAvatar(String id) {
    final p = _profileById(id);
    if (p == null) return;
    p.avatarColor = null;
    p.avatarCells = null;
    _save();
  }
}
