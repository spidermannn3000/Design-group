import 'dart:math' as math;
import 'dart:typed_data';

import 'engine.dart';
import 'route.dart';

/// Screen layout for the handlebar display: a 0.96" 128x64 SSD1306 OLED
/// over I2C (task F2, replacing the 8x8 LED matrix).
///
/// ```
///  0 +----------------+---------------------+
///    |                |        120          |
///    |     arrow      |                     |
///    |   (58 x 64)    |         m           |
/// 63 +----------------+---------------------+
/// ```
///
/// The arrow fills the left of the screen; the distance is on the right.
/// The arrow angle shows how sharp the turn is: straight 0 deg, slight 45,
/// normal 90, sharp 135. When the turn is 5 m away the whole screen flashes
/// (the firmware toggles the SSD1306 "invert display" command).
///
/// The phone app uses this to preview the screen, and the front-module
/// firmware draws the same layout (see docs/navigation.md).
class OledFrame {
  static const int width = 128;
  static const int height = 64;

  /// Rows above this are yellow on the yellow/blue version of the module.
  static const int yellowRows = 16;

  final Uint8List _px = Uint8List(width * height);

  bool pixel(int x, int y) => _px[y * width + x] != 0;

  void set(int x, int y, [bool on = true]) {
    if (x < 0 || y < 0 || x >= width || y >= height) return;
    _px[y * width + x] = on ? 1 : 0;
  }

  int get litPixels => _px.where((p) => p != 0).length;

  /// The frame in the SSD1306's memory layout: 8 pages of 128 bytes, each
  /// byte a vertical strip of 8 pixels with the top pixel in bit 0. This is
  /// what `Adafruit_SSD1306::getBuffer()` holds, so it can be sent as is.
  Uint8List toSsd1306() {
    final out = Uint8List(width * height ~/ 8);
    for (var page = 0; page < height ~/ 8; page++) {
      for (var x = 0; x < width; x++) {
        var b = 0;
        for (var bit = 0; bit < 8; bit++) {
          if (pixel(x, page * 8 + bit)) b |= 1 << bit;
        }
        out[page * width + x] = b;
      }
    }
    return out;
  }

  /// Text art for debugging and docs ('#' = lit).
  String toAscii() => [
        for (var y = 0; y < height; y++)
          String.fromCharCodes([
            for (var x = 0; x < width; x++) pixel(x, y) ? 35 : 46,
          ]),
      ].join('\n');

  // ---- drawing primitives -------------------------------------------------

  void fillCircle(double cx, double cy, double r) {
    for (var y = (cy - r).floor(); y <= (cy + r).ceil(); y++) {
      for (var x = (cx - r).floor(); x <= (cx + r).ceil(); x++) {
        final dx = x + 0.5 - cx, dy = y + 0.5 - cy;
        if (dx * dx + dy * dy <= r * r) set(x, y);
      }
    }
  }

  /// A line [r] pixels either side of its centre.
  void thickLine(double x0, double y0, double x1, double y1, double r) {
    final len = math.sqrt((x1 - x0) * (x1 - x0) + (y1 - y0) * (y1 - y0));
    final steps = math.max(1, (len * 2).ceil());
    for (var i = 0; i <= steps; i++) {
      final t = i / steps;
      fillCircle(x0 + (x1 - x0) * t, y0 + (y1 - y0) * t, r);
    }
  }

  void fillTriangle(List<double> a, List<double> b, List<double> c) {
    double edge(List<double> p, List<double> q, double x, double y) =>
        (q[0] - p[0]) * (y - p[1]) - (q[1] - p[1]) * (x - p[0]);
    final minX = [a[0], b[0], c[0]].reduce(math.min).floor();
    final maxX = [a[0], b[0], c[0]].reduce(math.max).ceil();
    final minY = [a[1], b[1], c[1]].reduce(math.min).floor();
    final maxY = [a[1], b[1], c[1]].reduce(math.max).ceil();
    for (var y = minY; y <= maxY; y++) {
      for (var x = minX; x <= maxX; x++) {
        final px = x + 0.5, py = y + 0.5;
        final e0 = edge(a, b, px, py), e1 = edge(b, c, px, py), e2 = edge(c, a, px, py);
        if ((e0 >= 0 && e1 >= 0 && e2 >= 0) || (e0 <= 0 && e1 <= 0 && e2 <= 0)) set(x, y);
      }
    }
  }

  void ring(double cx, double cy, double r, double thickness) {
    for (var y = (cy - r - thickness).floor(); y <= (cy + r + thickness).ceil(); y++) {
      for (var x = (cx - r - thickness).floor(); x <= (cx + r + thickness).ceil(); x++) {
        final d = math.sqrt(math.pow(x + 0.5 - cx, 2) + math.pow(y + 0.5 - cy, 2));
        if ((d - r).abs() <= thickness / 2) set(x, y);
      }
    }
  }

  /// Text in the built-in 5x7 font. Each character is 6 x [scale] wide.
  void text(int x, int y, String s, {int scale = 1}) {
    var cx = x;
    for (final ch in s.split('')) {
      final glyph = _font[ch] ?? _font[' ']!;
      for (var row = 0; row < 7; row++) {
        for (var col = 0; col < 5; col++) {
          if (glyph[row][col] == '#') {
            for (var dy = 0; dy < scale; dy++) {
              for (var dx = 0; dx < scale; dx++) {
                set(cx + col * scale + dx, y + row * scale + dy);
              }
            }
          }
        }
      }
      cx += 6 * scale;
    }
  }

  static int textWidth(String s, {int scale = 1}) =>
      s.isEmpty ? 0 : s.length * 6 * scale - scale;

  void centredText(int left, int right, int y, String s, {int scale = 1}) =>
      text(left + (right - left - textWidth(s, scale: scale)) ~/ 2, y, s, scale: scale);
}

// ---- what to draw ----------------------------------------------------------

/// Draws the handlebar screen for one navigation state.
///
/// Flashing is not part of the frame: when [NavState.flash] is true the
/// display alternates between this frame and its inverse about 4 times a
/// second.
OledFrame renderOled(NavState s) {
  final f = OledFrame();

  if (s.arrived) {
    f.centredText(0, 128, 4, 'YOU HAVE ARRIVED');
    _drawFlag(f, 40, 16);
    return f;
  }
  if (s.offRoute) {
    f.centredText(0, 128, 4, 'REROUTING');
    f.centredText(0, 128, 22, '?', scale: 5);
    return f;
  }
  final next = s.next;
  if (next == null) return f;

  final kind = s.showTurn ? next.kind : ManoeuvreKind.straight;
  _drawArrow(f, kind, next.exitNumber);
  _drawDistance(f, s.distanceToNextM);
  return f;
}

/// Turn angle in degrees: 0 = straight ahead, negative = left.
double? turnAngle(ManoeuvreKind k) => switch (k) {
      ManoeuvreKind.straight => 0,
      ManoeuvreKind.slightLeft => -45,
      ManoeuvreKind.slightRight => 45,
      ManoeuvreKind.left => -90,
      ManoeuvreKind.right => 90,
      ManoeuvreKind.sharpLeft => -135,
      ManoeuvreKind.sharpRight => 135,
      _ => null,
    };

// ---- arrows ------------------------------------------------------------------
//
// Each arrow is designed once on a small grid, then measured and scaled up
// to fill the arrow area (the left 57 x 64 pixels) as fully as its shape
// allows: tall arrows use the full height, wide ones the full width.

/// The arrow area: x 0-56, y 0-63, with half a pixel of margin.
const double _areaLeft = 0.5, _areaTop = 0.5, _areaWidth = 56, _areaHeight = 63;

/// Line thickness (half-width) and arrowhead size, in design units.
const double _lineR = 3.0, _headLen = 10.0, _headHalf = 7.5;

/// Draws or measures shapes. Coordinates are in design units.
abstract class _Pen {
  void dot(double x, double y, double r);
  void line(double x0, double y0, double x1, double y1, double r);
  void triangle(List<double> a, List<double> b, List<double> c);
}

/// Measures the extent of an arrow in design units.
class _BoundsPen implements _Pen {
  double minX = double.infinity, minY = double.infinity;
  double maxX = -double.infinity, maxY = -double.infinity;
  void _add(double x, double y, double r) {
    minX = math.min(minX, x - r);
    maxX = math.max(maxX, x + r);
    minY = math.min(minY, y - r);
    maxY = math.max(maxY, y + r);
  }

  @override
  void dot(double x, double y, double r) => _add(x, y, r);
  @override
  void line(double x0, double y0, double x1, double y1, double r) {
    _add(x0, y0, r);
    _add(x1, y1, r);
  }

  @override
  void triangle(List<double> a, List<double> b, List<double> c) {
    _add(a[0], a[1], 0);
    _add(b[0], b[1], 0);
    _add(c[0], c[1], 0);
  }
}

/// Draws onto the frame, scaled and shifted to fill the arrow area.
class _FramePen implements _Pen {
  final OledFrame f;
  final double scale, left, top;
  _FramePen(this.f, this.scale, this.left, this.top);
  double x(double v) => left + v * scale;
  double y(double v) => top + v * scale;

  @override
  void dot(double px, double py, double r) => f.fillCircle(x(px), y(py), r * scale);
  @override
  void line(double x0, double y0, double x1, double y1, double r) =>
      f.thickLine(x(x0), y(y0), x(x1), y(y1), r * scale);
  @override
  void triangle(List<double> a, List<double> b, List<double> c) =>
      f.fillTriangle([x(a[0]), y(a[1])], [x(b[0]), y(b[1])], [x(c[0]), y(c[1])]);
}

/// The arrow shape for [kind] in design units. Returns false if there is none.
bool _arrowShape(_Pen pen, ManoeuvreKind kind) {
  void head(double tipX, double tipY, double angleDeg) {
    final a = angleDeg * math.pi / 180;
    final dx = math.sin(a), dy = -math.cos(a); // direction of travel
    final baseX = tipX - dx * _headLen, baseY = tipY - dy * _headLen;
    pen.triangle([tipX, tipY], [baseX - dy * _headHalf, baseY + dx * _headHalf],
        [baseX + dy * _headHalf, baseY - dx * _headHalf]);
  }

  final angle = turnAngle(kind);
  if (angle != null) {
    if (angle == 0) {
      pen.line(24, 46, 24, 12, _lineR);
      head(24, 2, 0);
      return true;
    }
    // Stem up from the bottom to the junction, then off at the turn angle.
    // Sharp turns bend back down, so their junction sits higher.
    const pivotX = 24.0, arm = 14.0;
    final pivotY = angle.abs() > 100 ? 14.0 : angle.abs() > 60 ? 24.0 : 28.0;
    final a = angle * math.pi / 180;
    final endX = pivotX + math.sin(a) * arm, endY = pivotY - math.cos(a) * arm;
    pen.line(pivotX, 46, pivotX, pivotY, _lineR);
    pen.line(pivotX, pivotY, endX, endY, _lineR);
    head(endX + math.sin(a) * 9, endY - math.cos(a) * 9, angle);
    return true;
  }
  switch (kind) {
    case ManoeuvreKind.uTurn:
      // Up the left side, over the top and back down the right side
      // (traffic keeps left in Ireland, so U-turns go round to the right).
      pen.line(14, 46, 14, 20, _lineR);
      for (var i = 0; i <= 24; i++) {
        final t = math.pi - math.pi * i / 24;
        pen.dot(24 + math.cos(t) * 10, 20 - math.sin(t) * 10, _lineR);
      }
      pen.line(34, 20, 34, 28, _lineR);
      head(34, 40, 180);
      return true;
    case ManoeuvreKind.roundabout:
      // A clockwise circular arrow (traffic goes clockwise round Irish
      // roundabouts) with the entry from below.
      for (var deg = 200; deg <= 470; deg += 4) {
        final phi = deg * math.pi / 180; // clockwise from the top
        pen.dot(_rbX + _rbR * math.sin(phi), _rbY - _rbR * math.cos(phi), _lineR * 0.8);
      }
      const endDeg = 470.0;
      final endPhi = endDeg * math.pi / 180;
      final tangent = endDeg + 90; // direction of travel at the end of the arc
      final ta = tangent * math.pi / 180;
      head(_rbX + _rbR * math.sin(endPhi) + math.sin(ta) * 8,
          _rbY - _rbR * math.cos(endPhi) - math.cos(ta) * 8, tangent);
      pen.line(_rbX, 46, _rbX, _rbY + _rbR, _lineR);
      return true;
    default:
      return false;
  }
}

/// Roundabout ring centre and radius, in design units.
const double _rbX = 24, _rbY = 25, _rbR = 13;

void _drawArrow(OledFrame f, ManoeuvreKind kind, int? exit) {
  if (kind == ManoeuvreKind.arrive) {
    _drawFlag(f, 6, 6);
    return;
  }
  final bounds = _BoundsPen();
  if (!_arrowShape(bounds, kind)) return;
  final w = bounds.maxX - bounds.minX, h = bounds.maxY - bounds.minY;
  final scale = math.min(_areaWidth / w, _areaHeight / h);
  final left = _areaLeft + (_areaWidth - w * scale) / 2 - bounds.minX * scale;
  final top = _areaTop + (_areaHeight - h * scale) / 2 - bounds.minY * scale;
  final pen = _FramePen(f, scale, left, top);
  _arrowShape(pen, kind);

  if (kind == ManoeuvreKind.roundabout && exit != null) {
    // Exit number in the middle of the ring, as large as fits.
    final digitScale = scale >= 1.5 ? 3 : 2;
    final cx = pen.x(_rbX).round(), cy = pen.y(_rbY).round();
    f.text(cx - (5 * digitScale) ~/ 2, cy - (7 * digitScale) ~/ 2, '$exit', scale: digitScale);
  }
}

void _drawFlag(OledFrame f, int x, int y) {
  f.thickLine(x + 12.0, y + 4.0, x + 12.0, y + 46.0, 1.5);
  for (var row = 0; row < 3; row++) {
    for (var col = 0; col < 5; col++) {
      if ((row + col).isEven) {
        for (var dy = 0; dy < 5; dy++) {
          for (var dx = 0; dx < 5; dx++) {
            f.set(x + 14 + col * 5 + dx, y + 4 + row * 5 + dy);
          }
        }
      }
    }
  }
  for (var col = 0; col < 25; col++) {
    f.set(x + 14 + col, y + 4);
    f.set(x + 14 + col, y + 18);
  }
}

/// Distance to the turn on the right: "120" over "m", or "1.2" over "km".
void _drawDistance(OledFrame f, double metres) {
  final (number, unit) = formatDistance(metres);
  const left = 58, right = 128;
  final scale = OledFrame.textWidth(number, scale: 4) <= right - left ? 4 : 3;
  // Below row 16, so the text is one colour on the yellow/blue module.
  f.centredText(left, right, 18, number, scale: scale);
  f.centredText(left, right, 49, unit, scale: 2);
}

/// Rounds the way bike computers do: to 10 m above 100 m, to 0.1 km from 1 km.
/// Works from whole metres, as sent to the front module, so the phone
/// preview and the handlebar always agree.
(String, String) formatDistance(double metres) {
  final m = metres.round();
  if (m >= 9950) return ('${(m / 1000).round()}', 'km');
  if (m >= 995) return ((m / 1000).toStringAsFixed(1), 'km');
  if (m >= 100) return ('${(m / 10).round() * 10}', 'm');
  return ('$m', 'm');
}

const Map<String, List<String>> _font = {
  ' ': ['.....', '.....', '.....', '.....', '.....', '.....', '.....'],
  '-': ['.....', '.....', '.....', '#####', '.....', '.....', '.....'],
  '.': ['.....', '.....', '.....', '.....', '.....', '.##..', '.##..'],
  '>': ['#....', '.#...', '..#..', '...#.', '..#..', '.#...', '#....'],
  '?': ['.###.', '#...#', '....#', '...#.', '..#..', '.....', '..#..'],
  '0': ['.###.', '#...#', '#..##', '#.#.#', '##..#', '#...#', '.###.'],
  '1': ['..#..', '.##..', '..#..', '..#..', '..#..', '..#..', '.###.'],
  '2': ['.###.', '#...#', '....#', '...#.', '..#..', '.#...', '#####'],
  '3': ['####.', '....#', '....#', '.###.', '....#', '....#', '####.'],
  '4': ['...#.', '..##.', '.#.#.', '#..#.', '#####', '...#.', '...#.'],
  '5': ['#####', '#....', '####.', '....#', '....#', '#...#', '.###.'],
  '6': ['..##.', '.#...', '#....', '####.', '#...#', '#...#', '.###.'],
  '7': ['#####', '....#', '...#.', '..#..', '.#...', '.#...', '.#...'],
  '8': ['.###.', '#...#', '#...#', '.###.', '#...#', '#...#', '.###.'],
  '9': ['.###.', '#...#', '#...#', '.####', '....#', '...#.', '.##..'],
  'A': ['.###.', '#...#', '#...#', '#####', '#...#', '#...#', '#...#'],
  'B': ['####.', '#...#', '#...#', '####.', '#...#', '#...#', '####.'],
  'C': ['.###.', '#...#', '#....', '#....', '#....', '#...#', '.###.'],
  'D': ['####.', '#...#', '#...#', '#...#', '#...#', '#...#', '####.'],
  'E': ['#####', '#....', '#....', '####.', '#....', '#....', '#####'],
  'F': ['#####', '#....', '#....', '####.', '#....', '#....', '#....'],
  'G': ['.###.', '#...#', '#....', '#.###', '#...#', '#...#', '.####'],
  'H': ['#...#', '#...#', '#...#', '#####', '#...#', '#...#', '#...#'],
  'I': ['.###.', '..#..', '..#..', '..#..', '..#..', '..#..', '.###.'],
  'J': ['..###', '...#.', '...#.', '...#.', '...#.', '#..#.', '.##..'],
  'K': ['#...#', '#..#.', '#.#..', '##...', '#.#..', '#..#.', '#...#'],
  'L': ['#....', '#....', '#....', '#....', '#....', '#....', '#####'],
  'M': ['#...#', '##.##', '#.#.#', '#.#.#', '#...#', '#...#', '#...#'],
  'N': ['#...#', '#...#', '##..#', '#.#.#', '#..##', '#...#', '#...#'],
  'O': ['.###.', '#...#', '#...#', '#...#', '#...#', '#...#', '.###.'],
  'P': ['####.', '#...#', '#...#', '####.', '#....', '#....', '#....'],
  'Q': ['.###.', '#...#', '#...#', '#...#', '#.#.#', '#..#.', '.##.#'],
  'R': ['####.', '#...#', '#...#', '####.', '#.#..', '#..#.', '#...#'],
  'S': ['.####', '#....', '#....', '.###.', '....#', '....#', '####.'],
  'T': ['#####', '..#..', '..#..', '..#..', '..#..', '..#..', '..#..'],
  'U': ['#...#', '#...#', '#...#', '#...#', '#...#', '#...#', '.###.'],
  'V': ['#...#', '#...#', '#...#', '#...#', '#...#', '.#.#.', '..#..'],
  'W': ['#...#', '#...#', '#...#', '#.#.#', '#.#.#', '#.#.#', '.#.#.'],
  'X': ['#...#', '#...#', '.#.#.', '..#..', '.#.#.', '#...#', '#...#'],
  'Y': ['#...#', '#...#', '.#.#.', '..#..', '..#..', '..#..', '..#..'],
  'Z': ['#####', '....#', '...#.', '..#..', '.#...', '#....', '#####'],
  'k': ['#....', '#....', '#..#.', '#.#..', '##...', '#.#..', '#..#.'],
  'm': ['.....', '.....', '##.#.', '#.#.#', '#.#.#', '#.#.#', '#.#.#'],
};
