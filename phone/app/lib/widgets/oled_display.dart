import 'dart:async';

import 'package:bike_navigation/bike_navigation.dart';
import 'package:material_ui/material_ui.dart';

/// The colour versions of the 0.96" SSD1306 module. Buy the blue or white
/// one: on the yellow/blue one the top 16 rows can only ever be yellow.
enum OledColours { blue, white, yellowBlue }

/// Pixel-exact preview of the handlebar OLED (128x64). Uses the same
/// [renderOled] as the module, and flashes the same way: inverting the
/// screen 4 times a second when [NavState.flash] is set.
class OledDisplay extends StatefulWidget {
  final NavState? state;
  final double width;
  final OledColours colours;

  const OledDisplay({
    super.key,
    required this.state,
    this.width = 256,
    this.colours = OledColours.blue,
  });

  @override
  State<OledDisplay> createState() => _OledDisplayState();
}

class _OledDisplayState extends State<OledDisplay> {
  Timer? _flashTimer;
  bool _inverted = false;

  @override
  void didUpdateWidget(OledDisplay old) {
    super.didUpdateWidget(old);
    final flash = widget.state?.flash ?? false;
    if (flash && _flashTimer == null) {
      _flashTimer = Timer.periodic(const Duration(milliseconds: 125), (_) {
        setState(() => _inverted = !_inverted);
      });
    } else if (!flash && _flashTimer != null) {
      _flashTimer!.cancel();
      _flashTimer = null;
      _inverted = false;
    }
  }

  @override
  void dispose() {
    _flashTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    return Semantics(
      label: 'Handlebar display preview',
      child: CustomPaint(
        size: Size(widget.width, widget.width / 2),
        painter: _OledPainter(
          s == null ? OledFrame() : renderOled(s),
          inverted: _inverted,
          colours: widget.colours,
        ),
      ),
    );
  }
}

class _OledPainter extends CustomPainter {
  final OledFrame frame;
  final bool inverted;
  final OledColours colours;

  _OledPainter(this.frame, {required this.inverted, required this.colours});

  @override
  void paint(Canvas canvas, Size size) {
    final px = size.width / OledFrame.width;
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF07080C));
    const blue = Color(0xFF5ABEFF), white = Color(0xFFF2F4FF), yellow = Color(0xFFFFC828);
    final top = Paint()
      ..color = switch (colours) {
        OledColours.blue => blue,
        OledColours.white => white,
        OledColours.yellowBlue => yellow,
      };
    final bottom = Paint()..color = colours == OledColours.white ? white : blue;
    for (var y = 0; y < OledFrame.height; y++) {
      final paint = y < OledFrame.yellowRows ? top : bottom;
      for (var x = 0; x < OledFrame.width; x++) {
        if (frame.pixel(x, y) != inverted) {
          canvas.drawRect(Rect.fromLTWH(x * px, y * px, px * 0.9, px * 0.9), paint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(_OledPainter old) =>
      old.frame != frame || old.inverted != inverted || old.colours != colours;
}
