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

/// Renders the pixelated mint-leaf logo at [size] (transparent background).
class MintLeafLogo extends StatelessWidget {
  final double size;
  const MintLeafLogo({super.key, this.size = 24});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _MintLeafPainter()),
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
