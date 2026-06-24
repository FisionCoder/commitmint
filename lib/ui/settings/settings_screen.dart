import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/layout_state.dart';
import '../../state/settings_state.dart';
import '../../theme/app_theme.dart';
import '../integrations/integrations_view.dart';
import '../widgets/notifier.dart';
import '../widgets/profile_avatar.dart';
import 'settings_controls.dart';

/// Opens the full-screen Settings takeover, optionally on a specific tab.
void openSettings(BuildContext context, {int initialTab = 0}) {
  Navigator.of(context, rootNavigator: true).push(
    PageRouteBuilder(
      opaque: true,
      pageBuilder: (_, _, _) => SettingsScreen(initialTab: initialTab),
      transitionsBuilder: (_, anim, _, child) =>
          FadeTransition(opacity: anim, child: child),
      transitionDuration: const Duration(milliseconds: 120),
    ),
  );
}

class _NavItem {
  final String label;
  final IconData icon;
  final Widget Function() page;

  /// When true the page fills the content area itself (no title scroll/padding),
  /// for pages that manage their own layout — e.g. Integrations.
  final bool fills;
  const _NavItem(this.label, this.icon, this.page, {this.fills = false});
}

class SettingsScreen extends StatefulWidget {
  final int initialTab;
  const SettingsScreen({super.key, this.initialTab = 0});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late int _index = widget.initialTab.clamp(0, 5);

  late final List<_NavItem> _items = [
    _NavItem('General', Icons.settings_outlined, () => const GeneralPage()),
    _NavItem('Profiles', Icons.people_alt_outlined, () => const ProfilesPage()),
    _NavItem('SSH', Icons.vpn_key_outlined, () => const SshPage()),
    _NavItem('Integrations', Icons.extension_outlined,
        () => const IntegrationsView(),
        fills: true),
    _NavItem('UI Customization', Icons.palette_outlined, () => const UiPage()),
    _NavItem('In-App Terminal', Icons.terminal,
        () => const TerminalSettingsPage()),
  ];

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsState>();
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Row(
          children: [
            _buildNav(settings),
            VerticalDivider(width: 1, color: AppColors.border),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(32, 24, 32, 8),
                    child: Text(_items[_index].label,
                        style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary)),
                  ),
                  Expanded(
                    child: _items[_index].fills
                        ? _items[_index].page()
                        : SingleChildScrollView(
                            padding: const EdgeInsets.fromLTRB(32, 8, 40, 40),
                            child: _items[_index].page(),
                          ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNav(SettingsState settings) {
    return Container(
      width: 250,
      color: AppColors.surfaceAlt,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => Navigator.of(context).maybePop(),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              child: Row(
                children: [
                  Transform.flip(
                    flipX: true,
                    child: Icon(Icons.logout,
                        size: 16, color: AppColors.textSecondary),
                  ),
                  const SizedBox(width: 8),
                  Text('Exit Settings',
                      style: TextStyle(
                          fontSize: 13, color: AppColors.textSecondary)),
                ],
              ),
            ),
          ),
          Divider(height: 1, color: AppColors.border),
          _railHeader('Current profile'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                ProfileAvatar(profile: settings.activeProfile, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(settings.activeProfile.name,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 13, color: AppColors.textPrimary)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          _railHeader('Preferences'),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                for (var i = 0; i < _items.length; i++)
                  _navTile(i, _items[i]),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _railHeader(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Text(t.toUpperCase(),
            style: TextStyle(
                fontSize: 10.5,
                letterSpacing: 0.8,
                fontWeight: FontWeight.w600,
                color: AppColors.textMuted)),
      );

  Widget _navTile(int i, _NavItem item) {
    final selected = i == _index;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => setState(() => _index = i),
        child: Container(
          color: selected ? AppColors.selection : Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          child: Row(
            children: [
              Icon(item.icon,
                  size: 16,
                  color:
                      selected ? AppColors.accentTeal : AppColors.textSecondary),
              const SizedBox(width: 12),
              Text(item.label,
                  style: TextStyle(
                      fontSize: 13,
                      color: selected
                          ? AppColors.textPrimary
                          : AppColors.textSecondary,
                      fontWeight:
                          selected ? FontWeight.w600 : FontWeight.w400)),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================ General ======
class GeneralPage extends StatelessWidget {
  const GeneralPage({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsState>();
    return Column(
      children: [
        SettingRow(
          label: 'Default Branch Name',
          hint: 'Sets the default branch name when initializing new repositories '
              '(git init.defaultBranch).',
          child: TextFieldControl(
            value: s.defaultBranchName,
            hintText: 'main',
            onChanged: (v) => s.update(() => s.defaultBranchName = v),
            onSubmit: s.applyToGitConfig,
          ),
        ),
        SettingRow(
          label: 'Remember tabs',
          hint: 'Reopen the tabs you had open when the app restarts.',
          child: CheckControl(
              value: s.rememberTabs,
              onChanged: (v) => s.update(() => s.rememberTabs = v)),
        ),
        SettingRow(
          label: 'Longpaths',
          hint:
              'Sets core.longpaths in your global Git config. Enable support for '
              'file paths longer than 260 characters on Windows.',
          child: CheckControl(
              value: s.longPaths,
              onChanged: (v) {
                s.update(() => s.longPaths = v);
                s.applyToGitConfig();
              }),
        ),
        SettingRow(
          label: 'AutoCRLF',
          hint: 'Sets core.autocrlf in your global Git config.',
          child: CheckControl(
              value: s.autoCrlf,
              onChanged: (v) {
                s.update(() => s.autoCrlf = v);
                s.applyToGitConfig();
              }),
        ),
        SettingRow(
          label: 'Forget all Usernames and Passwords',
          hint: 'Clears stored credentials from the OS credential manager.',
          child: OutlinedButtonControl(
            label: 'Forget All',
            onPressed: () async {
              final ok = await s.forgetCredentials();
              if (context.mounted) {
                notify(
                    context,
                    ok
                        ? 'Cleared stored credentials.'
                        : 'No stored credentials to remove.');
              }
            },
          ),
        ),
      ],
    );
  }
}

// ============================================================ Profiles =====
class ProfilesPage extends StatelessWidget {
  const ProfilesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsState>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Profiles store your git identity. The active profile is applied to '
          'your global git config (name and email).',
          style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButtonControl(
            label: '+ Add a Profile',
            onPressed: s.addProfile,
          ),
        ),
        const SizedBox(height: 16),
        for (final p in s.profiles) _ProfileCard(profile: p),
      ],
    );
  }
}

class _ProfileCard extends StatelessWidget {
  final GitProfile profile;
  const _ProfileCard({required this.profile});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsState>();
    final active = s.activeProfileId == profile.id;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
            color: active ? AppColors.accent : AppColors.border,
            width: active ? 1.4 : 1),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Tooltip(
                message: 'Customize icon',
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: () => showAvatarEditor(context, profile),
                    child: ProfileAvatar(profile: profile, size: 30),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(profile.name,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600)),
              ),
              IconButton(
                icon: const Icon(Icons.brush_outlined, size: 18),
                color: AppColors.textSecondary,
                tooltip: 'Customize icon',
                onPressed: () => showAvatarEditor(context, profile),
              ),
              IconButton(
                icon: const Icon(Icons.casino_outlined, size: 18),
                color: AppColors.textSecondary,
                tooltip: 'Regenerate icon',
                onPressed: () => s.regenerateProfileAvatar(profile.id),
              ),
              if (active)
                Padding(
                  padding: EdgeInsets.only(right: 8),
                  child: Text('Active',
                      style: TextStyle(fontSize: 11.5, color: AppColors.accentTeal)),
                )
              else
                TextButton(
                  onPressed: () => s.setActiveProfile(profile.id),
                  child: const Text('Set active', style: TextStyle(fontSize: 12.5)),
                ),
              if (s.profiles.length > 1)
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 18),
                  color: AppColors.textMuted,
                  tooltip: 'Remove profile',
                  onPressed: () => s.removeProfile(profile.id),
                ),
            ],
          ),
          const SizedBox(height: 8),
          SettingRow(
            label: 'Profile Name',
            child: TextFieldControl(
              value: profile.name,
              onChanged: (v) => s.update(() => profile.name = v),
            ),
          ),
          SettingRow(
            label: 'Author Name',
            child: TextFieldControl(
              value: profile.authorName,
              onChanged: (v) => s.update(() => profile.authorName = v),
              onSubmit: active ? s.applyToGitConfig : null,
            ),
          ),
          SettingRow(
            label: 'Author Email',
            child: TextFieldControl(
              value: profile.authorEmail,
              onChanged: (v) => s.update(() => profile.authorEmail = v),
              onSubmit: active ? s.applyToGitConfig : null,
            ),
          ),
        ],
      ),
    );
  }
}

// ================================================================= SSH =====
class SshPage extends StatelessWidget {
  const SshPage({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsState>();
    final agent = s.useLocalSshAgent;
    return Column(
      children: [
        SettingRow(
          label: 'Use local SSH agent',
          hint: 'Use the keys loaded in your system SSH agent instead of a '
              'specific key file. When on, the key paths below are ignored.',
          child: CheckControl(
              value: agent,
              onChanged: (v) => s.update(() => s.useLocalSshAgent = v)),
        ),
        SettingRow(
          label: 'SSH Private Key',
          hint: 'Used as core.sshCommand (ssh -i …) for SSH remotes on pull, '
              'push, fetch and clone.',
          child: BrowseField(
            value: s.sshPrivateKeyPath,
            enabled: !agent,
            onPick: () async {
              final r = await FilePicker.platform.pickFiles(
                  dialogTitle: 'Select your SSH private key');
              if (r != null && r.files.single.path != null) {
                s.update(() => s.sshPrivateKeyPath = r.files.single.path!);
              }
            },
          ),
        ),
        SettingRow(
          label: 'SSH Public Key',
          child: BrowseField(
            value: s.sshPublicKeyPath,
            enabled: !agent,
            onPick: () async {
              final r = await FilePicker.platform.pickFiles(
                  dialogTitle: 'Select your SSH public key');
              if (r != null && r.files.single.path != null) {
                s.update(() => s.sshPublicKeyPath = r.files.single.path!);
              }
            },
          ),
        ),
        SettingRow(
          label: 'Generate new Private/Public key',
          hint: 'Creates a new ed25519 key pair (no passphrase) under ~/.ssh '
              'without overwriting any existing key, and selects it above.',
          child: OutlinedButtonControl(
            label: 'Generate',
            onPressed: () => _generate(context, s),
          ),
        ),
        SettingRow(
          label: 'Use default Git Credential Manager',
          hint: 'Let Git use the OS credential manager for HTTPS access. When '
              'off, the credential helper is disabled for network operations.',
          child: CheckControl(
              value: s.useGitCredentialManager,
              onChanged: (v) => s.update(() => s.useGitCredentialManager = v)),
        ),
      ],
    );
  }

  Future<void> _generate(BuildContext context, SettingsState s) async {
    final path = s.defaultSshKeyPath();
    try {
      final priv = await s.generateSshKey(path);
      s.update(() {
        s.sshPrivateKeyPath = priv;
        s.sshPublicKeyPath = '$priv.pub';
      });
      if (context.mounted) {
        notify(context, 'Generated SSH key at $priv',
            icon: Icons.vpn_key, iconColor: AppColors.green);
      }
    } catch (e) {
      if (context.mounted) {
        notify(context, 'Key generation failed: $e',
            icon: Icons.error, iconColor: AppColors.red);
      }
    }
  }
}

// ====================================================== UI Customization ===
class UiPage extends StatelessWidget {
  const UiPage({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsState>();
    final layout = context.watch<LayoutState>();
    return Column(
      children: [
        const SectionHeader('Appearance'),
        SettingRow(
          label: 'Theme',
          child: DropdownControl<AppThemeMode>(
            value: s.themeMode,
            items: const {
              AppThemeMode.dark: 'Commit Mint Dark',
              AppThemeMode.light: 'Commit Mint Light',
            },
            onChanged: s.setThemeMode,
          ),
        ),
        SettingRow(
          label: 'Notification Location',
          hint: 'Where transient notifications (e.g. "Push complete") appear.',
          child: DropdownControl<NotificationLocation>(
            value: s.notificationLocation,
            items: const {
              NotificationLocation.topLeft: 'Top Left',
              NotificationLocation.topRight: 'Top Right',
              NotificationLocation.bottomLeft: 'Bottom Left',
              NotificationLocation.bottomRight: 'Bottom Right',
            },
            onChanged: (v) => s.update(() => s.notificationLocation = v),
          ),
        ),
        const SectionHeader('Date / Time'),
        SettingRow(
          label: 'Date/Time Locale',
          hint: 'Locale used to format dates in the graph and commit details.',
          child: DropdownControl<String>(
            value: s.dateTimeLocale,
            items: const {
              'system': 'System',
              'en_US': 'English (US)',
              'en_GB': 'English (UK)',
              'de_DE': 'German',
              'fr_FR': 'French',
              'ja_JP': 'Japanese',
            },
            onChanged: (v) => s.update(() => s.dateTimeLocale = v),
          ),
        ),
        SettingRow(
          label: 'Date/Time Format',
          hint: 'Used for the commit Date/Time column in the graph. '
              'Uses ICU/intl date patterns (e.g. MM/dd/yyyy @ h:mm a).',
          child: TextFieldControl(
            value: s.dateTimeFormat,
            onChanged: (v) => s.update(() => s.dateTimeFormat = v),
          ),
        ),
        SettingRow(
          label: 'Date word Format',
          hint: 'Used for the date shown in the commit details panel.',
          child: TextFieldControl(
            value: s.dateWordFormat,
            onChanged: (v) => s.update(() => s.dateWordFormat = v),
          ),
        ),
        SettingRow(
          label: 'Date verbose Format',
          hint: 'Used for the full date hover tooltip in the graph.',
          child: TextFieldControl(
            value: s.dateVerboseFormat,
            onChanged: (v) => s.update(() => s.dateVerboseFormat = v),
          ),
        ),
        const SectionHeader('Graph & Layout'),
        SettingRow(
          label: 'Show toolbar icon labels',
          child: CheckControl(
              value: s.showToolbarLabels,
              onChanged: (v) => s.update(() => s.showToolbarLabels = v)),
        ),
        SettingRow(
          label: 'Enable spell checking',
          hint: 'Spell-check the commit summary and description fields.',
          child: CheckControl(
              value: s.enableSpellChecking,
              onChanged: (v) => s.update(() => s.enableSpellChecking = v)),
        ),
        SettingRow(
          label: 'Display author initials instead of avatars',
          child: CheckControl(
              value: s.useInitialsAvatars,
              onChanged: (v) => s.update(() => s.useInitialsAvatars = v)),
        ),
        SettingRow(
          label: 'Show ghost branch/tag when hovering over a commit',
          hint: 'Shows the full commit details popover on hover.',
          child: CheckControl(
              value: s.showGhostHover,
              onChanged: (v) => s.update(() => s.showGhostHover = v)),
        ),
        SettingRow(
          label: 'Highlight associated rows when hovering over a branch',
          child: CheckControl(
              value: s.highlightAssociatedRows,
              onChanged: (v) => s.update(() => s.highlightAssociatedRows = v)),
        ),
        SettingRow(
          label: 'Show commit description in details panel',
          child: DropdownControl<DescriptionVisibility>(
            value: s.commitDescriptionVisibility,
            items: const {
              DescriptionVisibility.always: 'Always',
              DescriptionVisibility.never: 'Never',
            },
            onChanged: (v) => s.update(() => s.commitDescriptionVisibility = v),
          ),
        ),
        SettingRow(
          label: 'Branch visibility in commit graph',
          hint: 'Limiting to the current branch hides remote-tracking labels.',
          child: DropdownControl<BranchVisibility>(
            value: s.branchVisibility,
            items: const {
              BranchVisibility.all: 'All',
              BranchVisibility.current: 'Current branch only',
              BranchVisibility.none: 'None',
            },
            onChanged: (v) {
              s.update(() => s.branchVisibility = v);
              layout.setSmartBranch(v != BranchVisibility.all);
            },
          ),
        ),
        SettingRow(
          label: 'Show branches and tags in graph',
          child: CheckControl(
              value: layout.showBranch,
              onChanged: (_) => layout.toggleColumn(GraphColumn.branch)),
        ),
        SettingRow(
          label: 'Show commit author in graph',
          child: CheckControl(
              value: layout.showAuthor,
              onChanged: (_) => layout.toggleColumn(GraphColumn.author)),
        ),
        SettingRow(
          label: 'Show commit date/time in graph',
          child: CheckControl(
              value: layout.showDate,
              onChanged: (_) => layout.toggleColumn(GraphColumn.date)),
        ),
        SettingRow(
          label: 'Show commit message in graph',
          child: CheckControl(
              value: layout.showMessage,
              onChanged: (_) => layout.toggleColumn(GraphColumn.message)),
        ),
        SettingRow(
          label: 'Show commit sha in graph',
          child: CheckControl(
              value: layout.showSha,
              onChanged: (_) => layout.toggleColumn(GraphColumn.sha)),
        ),
        SettingRow(
          label: 'Show commit tree (graph lanes)',
          child: CheckControl(
              value: layout.showGraph,
              onChanged: (_) => layout.toggleColumn(GraphColumn.graph)),
        ),
      ],
    );
  }
}

// ====================================================== In-App Terminal =====
class TerminalSettingsPage extends StatelessWidget {
  const TerminalSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsState>();
    return Column(
      children: [
        SettingRow(
          label: 'Font',
          child: DropdownControl<String>(
            value: s.terminalFont,
            items: const {
              'Consolas': 'Consolas',
              'Cascadia Mono': 'Cascadia Mono',
              'Courier New': 'Courier New',
              'monospace': 'monospace',
            },
            onChanged: (v) => s.update(() => s.terminalFont = v),
          ),
        ),
        SettingRow(
          label: 'Font Size',
          child: NumberField(
            value: s.terminalFontSize.round(),
            min: 8,
            max: 32,
            onChanged: (v) => s.update(() => s.terminalFontSize = v.toDouble()),
          ),
        ),
        SettingRow(
          label: 'Line Height',
          child: TextFieldControl(
            value: s.terminalLineHeight.toString(),
            onChanged: (v) {
              final d = double.tryParse(v);
              if (d != null && d >= 1.0 && d <= 2.5) {
                s.update(() => s.terminalLineHeight = d);
              }
            },
          ),
        ),
        SettingRow(
          label: 'Cursor Style',
          child: DropdownControl<TerminalCursor>(
            value: s.terminalCursor,
            items: const {
              TerminalCursor.bar: 'Bar',
              TerminalCursor.block: 'Block',
              TerminalCursor.underline: 'Underline',
            },
            onChanged: (v) => s.update(() => s.terminalCursor = v),
          ),
        ),
        SettingRow(
          label: 'Dim terminal when unfocused',
          child: CheckControl(
              value: s.dimTerminalWhenUnfocused,
              onChanged: (v) =>
                  s.update(() => s.dimTerminalWhenUnfocused = v)),
        ),
        SettingRow(
          label: 'Default In-App Terminal',
          hint:
              'Changes to this setting will only apply to new terminal sessions.',
          child: DropdownControl<String>(
            value: s.defaultShell,
            items: const {
              'powershell': 'PowerShell',
              'cmd': 'Command Prompt',
              'bash': 'Git Bash',
            },
            onChanged: (v) => s.update(() => s.defaultShell = v),
          ),
        ),
      ],
    );
  }
}
