import 'dart:async';

import 'package:bike_navigation/bike_navigation.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:material_ui/material_ui.dart';

/// Draft 8x8 bitmaps for every LED symbol ID (a starting point for F2).
/// '#' = LED on. Row 0 is the top row. The front module firmware should use
/// the same pictures so the on-screen preview matches the handlebar.
const Map<int, List<String>> ledBitmaps = {
  LedSymbol.blank: ['........', '........', '........', '........', '........', '........', '........', '........'],
  LedSymbol.straight: ['...##...', '..####..', '.######.', '...##...', '...##...', '...##...', '...##...', '...##...'],
  LedSymbol.left: ['..#.....', '.##.....', '######..', '.##..#..', '..#..#..', '.....#..', '.....#..', '.....#..'],
  LedSymbol.right: ['.....#..', '.....##.', '..######', '..#..##.', '..#..#..', '..#.....', '..#.....', '..#.....'],
  LedSymbol.slightLeft: ['####....', '##......', '#.#.....', '#..#....', '....#...', '.....#..', '.....#..', '.....#..'],
  LedSymbol.slightRight: ['....####', '......##', '.....#.#', '....#..#', '...#....', '..#.....', '..#.....', '..#.....'],
  LedSymbol.sharpLeft: ['.....#..', '.....#..', '.....#..', '....#...', '...#....', '#.#.....', '##......', '####....'],
  LedSymbol.sharpRight: ['..#.....', '..#.....', '..#.....', '...#....', '....#...', '.....#.#', '......##', '....####'],
  LedSymbol.uTurn: ['.####...', '#....#..', '#....#..', '#....#..', '#..#####', '#...###.', '#....#..', '#.......'],
  LedSymbol.roundabout: ['..####..', '.#....#.', '#......#', '#......#', '#......#', '#......#', '.#....#.', '..####..'],
  LedSymbol.arrive: ['########', '#......#', '#.####.#', '#.#..#.#', '#.#..#.#', '#.####.#', '#......#', '########'],
  LedSymbol.rerouting: ['..####..', '.##..##.', '.....##.', '....##..', '...##...', '...##...', '........', '...##...'],
  LedSymbol.bluetoothLost: ['##....##', '.##..##.', '..####..', '...##...', '...##...', '..####..', '.##..##.', '##....##'],
  LedSymbol.lowBattery: ['..####..', '.#....#.', '.#....#.', '.#....#.', '.#....#.', '.#....#.', '.######.', '.######.'],
  21: ['........', '...#....', '..##....', '...#....', '...#....', '...#....', '...#....', '..###...'],
  22: ['........', '..###...', '.#...#..', '.....#..', '....#...', '...#....', '..#.....', '.#####..'],
  23: ['........', '.####...', '.....#..', '.....#..', '..###...', '.....#..', '.....#..', '.####...'],
  24: ['........', '....#...', '...##...', '..#.#...', '.#..#...', '.#####..', '....#...', '....#...'],
  25: ['........', '.#####..', '.#......', '.####...', '.....#..', '.....#..', '.#...#..', '..###...'],
  26: ['........', '...##...', '..#.....', '.#......', '.####...', '.#...#..', '.#...#..', '..###...'],
  27: ['........', '.#####..', '.....#..', '....#...', '...#....', '..#.....', '..#.....', '..#.....'],
  28: ['........', '..###...', '.#...#..', '.#...#..', '..###...', '.#...#..', '.#...#..', '..###...'],
  29: ['........', '..###...', '.#...#..', '.#...#..', '..####..', '.....#..', '....#...', '..##....'],
};

/// Shows a symbol sequence the way the handlebar matrix would, cycling
/// through it (e.g. roundabout, then exit number).
class LedMatrix extends StatefulWidget {
  final List<int> symbols;
  final double size;
  final Duration cycle;

  const LedMatrix({
    super.key,
    required this.symbols,
    this.size = 160,
    this.cycle = const Duration(milliseconds: 800),
  });

  @override
  State<LedMatrix> createState() => _LedMatrixState();
}

class _LedMatrixState extends State<LedMatrix> {
  int _index = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _restart();
  }

  @override
  void didUpdateWidget(LedMatrix old) {
    super.didUpdateWidget(old);
    if (!listEquals(old.symbols, widget.symbols)) _restart();
  }

  void _restart() {
    _timer?.cancel();
    _index = 0;
    if (widget.symbols.length > 1) {
      _timer = Timer.periodic(widget.cycle, (_) {
        setState(() => _index = (_index + 1) % widget.symbols.length);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final id = widget.symbols.isEmpty ? LedSymbol.blank : widget.symbols[_index];
    return Semantics(
      label: 'LED symbol $id',
      child: CustomPaint(
        size: Size.square(widget.size),
        painter: _MatrixPainter(ledBitmaps[id] ?? ledBitmaps[LedSymbol.blank]!),
      ),
    );
  }
}

class _MatrixPainter extends CustomPainter {
  final List<String> rows;
  _MatrixPainter(this.rows);

  @override
  void paint(Canvas canvas, Size size) {
    final cell = size.width / 8;
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(cell / 2)),
      Paint()..color = const Color(0xFF111111),
    );
    final on = Paint()..color = const Color(0xFFFFB020);
    final off = Paint()..color = const Color(0xFF2A2A2A);
    for (var y = 0; y < 8; y++) {
      for (var x = 0; x < 8; x++) {
        canvas.drawCircle(
          Offset((x + 0.5) * cell, (y + 0.5) * cell),
          cell * 0.36,
          rows[y][x] == '#' ? on : off,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_MatrixPainter old) => old.rows != rows;
}
