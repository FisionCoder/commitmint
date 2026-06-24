import 'package:flutter/material.dart';

/// Pixel-art mint leaf used as the Commit Mint logo. Each character is one
/// pixel: '.' transparent, 'd' dark green, 'g' green, 'l' light mint.
const List<String> _mintLeafGrid = [
  '.......d.......',
  '......ldg......',
  '.....gldgg.....',
  '....ggldggg....',
  '...dggldgggd...',
  '..dgggldggggd..',
  '..dgggldggggd..',
  '.dggggldgggggd.',
  '..dgggldggggd..',
  '..dgggldggggd..',
  '...dggldgggd...',
  '....ggldggg....',
  '.....gldgg.....',
  '.......d.......',
  '.......d.......',
];

const Map<String, Color> _mintColors = {
  'd': Color(0xFF15803D),
  'g': Color(0xFF22C55E),
  'l': Color(0xFF86EFAC),
};

/// Renders the pixelated mint-leaf logo at [size].
///
/// By default the leaf is set in a modern dark, mint-tinted gradient circular
/// badge with a faint mint rim. Pass [background] = false for a bare,
/// transparent leaf (e.g. when it sits inside its own decorated container).
class MintLeafLogo extends StatelessWidget {
  final double size;
  final bool background;
  const MintLeafLogo({super.key, this.size = 24, this.background = true});

  @override
  Widget build(BuildContext context) {
    final bareLeaf = SizedBox.expand(
      child: CustomPaint(painter: _MintLeafPainter()),
    );

    if (!background) {
      return SizedBox(width: size, height: size, child: bareLeaf);
    }

    final pad = size * 0.22; // breathing room between leaf and rim
    final rim = (size * 0.045).clamp(0.8, 2.0);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        // Modern dark, faintly mint-tinted depth (light at top-left).
        gradient: const RadialGradient(
          center: Alignment(-0.4, -0.5),
          radius: 1.15,
          colors: [Color(0xFF24332E), Color(0xFF0C1411)],
        ),
        border: Border.all(
          color: const Color(0xFF2DD4BF).withValues(alpha: 0.30),
          width: rim,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF000000).withValues(alpha: 0.35),
            blurRadius: size * 0.16,
            offset: Offset(0, size * 0.04),
          ),
        ],
      ),
      child: Padding(padding: EdgeInsets.all(pad), child: bareLeaf),
    );
  }
}

class _MintLeafPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final n = _mintLeafGrid.length;
    final cell = size.width / n;
    final paint = Paint()
      ..isAntiAlias = false
      ..style = PaintingStyle.fill;
    for (var y = 0; y < n; y++) {
      final row = _mintLeafGrid[y];
      for (var x = 0; x < row.length; x++) {
        final c = _mintColors[row[x]];
        if (c == null) continue;
        paint.color = c;
        // +0.6 overdraw avoids hairline gaps between cells at fractional sizes.
        canvas.drawRect(
            Rect.fromLTWH(x * cell, y * cell, cell + 0.6, cell + 0.6), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _MintLeafPainter oldDelegate) => false;
}
