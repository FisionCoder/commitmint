import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_pty/flutter_pty.dart';
import 'package:provider/provider.dart';
import 'package:xterm/xterm.dart';

import '../../state/repo_state.dart';
import '../../theme/app_theme.dart';

/// Terminal colour scheme matching the app's dark palette.
const _termTheme = TerminalTheme(
  cursor: Color(0xFF2DD4BF),
  selection: Color(0x552DD4BF),
  foreground: Color(0xFFE8EDEA),
  background: Color(0xFF11151B),
  black: Color(0xFF11151B),
  red: Color(0xFFF87171),
  green: Color(0xFF4ADE80),
  yellow: Color(0xFFFBBF24),
  blue: Color(0xFF60A5FA),
  magenta: Color(0xFFA78BFA),
  cyan: Color(0xFF22D3EE),
  white: Color(0xFFE6EAF0),
  brightBlack: Color(0xFF697483),
  brightRed: Color(0xFFFB7185),
  brightGreen: Color(0xFF86EFAC),
  brightYellow: Color(0xFFFDE68A),
  brightBlue: Color(0xFF93C5FD),
  brightMagenta: Color(0xFFC4B5FD),
  brightCyan: Color(0xFF67E8F9),
  brightWhite: Color(0xFFFFFFFF),
  searchHitBackground: Color(0xFFFBBF24),
  searchHitBackgroundCurrent: Color(0xFFF59E0B),
  searchHitForeground: Color(0xFF11151B),
);

/// An embedded terminal running a real shell (ConPTY on Windows) rooted at the
/// repository's working directory.
class TerminalPanel extends StatefulWidget {
  final String workingDirectory;
  const TerminalPanel({super.key, required this.workingDirectory});

  @override
  State<TerminalPanel> createState() => _TerminalPanelState();
}

class _TerminalPanelState extends State<TerminalPanel> {
  final Terminal terminal = Terminal(maxLines: 10000);
  final TerminalController _controller = TerminalController();
  Pty? _pty;

  @override
  void initState() {
    super.initState();
    // Spawn after first frame so the terminal has real view dimensions.
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  String _shell() {
    if (Platform.isWindows) {
      // PowerShell is friendlier for git; fall back to cmd.
      return Platform.environment['COMSPEC']?.toLowerCase().contains('cmd') ??
              true
          ? 'powershell.exe'
          : (Platform.environment['COMSPEC'] ?? 'cmd.exe');
    }
    return Platform.environment['SHELL'] ?? 'bash';
  }

  void _start() {
    try {
      final pty = Pty.start(
        _shell(),
        columns: terminal.viewWidth,
        rows: terminal.viewHeight,
        workingDirectory: widget.workingDirectory,
        environment: Map<String, String>.from(Platform.environment),
      );
      _pty = pty;
      pty.output
          .cast<List<int>>()
          .transform(const Utf8Decoder(allowMalformed: true))
          .listen(terminal.write);
      pty.exitCode.then((code) {
        if (mounted) {
          terminal.write('\r\n\x1b[90m[process exited: $code]\x1b[0m\r\n');
        }
      });
      terminal.onOutput = (data) {
        pty.write(const Utf8Encoder().convert(data));
      };
      terminal.onResize = (w, h, pw, ph) {
        pty.resize(h, w);
      };
    } catch (e) {
      terminal.write('\r\n\x1b[31mFailed to start terminal: $e\x1b[0m\r\n');
    }
  }

  @override
  void dispose() {
    try {
      _pty?.kill();
    } catch (_) {}
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF11151B),
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        children: [
          _Header(workingDirectory: widget.workingDirectory),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
              child: TerminalView(
                terminal,
                controller: _controller,
                autofocus: true,
                backgroundOpacity: 0,
                theme: _termTheme,
                textStyle: const TerminalStyle(fontSize: 13),
                padding: EdgeInsets.zero,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final String workingDirectory;
  const _Header({required this.workingDirectory});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 32,
      padding: const EdgeInsets.only(left: 12, right: 4),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          const Icon(Icons.terminal, size: 14, color: AppColors.textSecondary),
          const SizedBox(width: 8),
          const Text('TERMINAL',
              style: TextStyle(
                  fontSize: 11,
                  letterSpacing: 0.8,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(workingDirectory,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    const TextStyle(fontSize: 11, color: AppColors.textMuted)),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 15),
            color: AppColors.textSecondary,
            splashRadius: 16,
            tooltip: 'Close terminal',
            onPressed: () => context.read<RepoState>().toggleTerminal(),
          ),
        ],
      ),
    );
  }
}
