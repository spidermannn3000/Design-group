import 'dart:math' as math;
import 'dart:typed_data';

import 'engine.dart';
import 'route.dart';

/// Screen layout for the handlebar display: a 0.96" 128x64 SSD1306 OLED
/// over I2C (task F2, replacing the 8x8 LED matrix).
///
/// ```
///  0 +--------------------------------------+
///    |        TURN LEFT  (label)            |  rows 0-15: yellow on the
/// 16 +-------------+------------------------+  yellow/blue version
///    |   arrow     |        120             |
///    |  (48x48)    |         m              |  rows 16-63: blue
/// 63 +-------------+------------------------+
/// ```
///
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
  const box = 8, boxTop = 16; // arrow area: x 8-55, y 16-63

  if (s.arrived) {
    f.centredText(0, 128, 4, 'YOU HAVE ARRIVED');
    _drawFlag(f, 40, boxTop);
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
  final then = s.showTurn ? s.then : null;
  f.centredText(0, 128, 4, _label(kind, next.exitNumber, then?.kind));
  _drawArrow(f, box.toDouble(), boxTop.toDouble(), kind, next.exitNumber);
  _drawDistance(f, s.distanceToNextM);
  return f;
}

String _label(ManoeuvreKind k, int? exit, ManoeuvreKind? then) {
  String name(ManoeuvreKind k) => switch (k) {
        ManoeuvreKind.straight => 'STRAIGHT ON',
        ManoeuvreKind.left => 'TURN LEFT',
        ManoeuvreKind.right => 'TURN RIGHT',
        ManoeuvreKind.slightLeft => 'SLIGHT LEFT',
        ManoeuvreKind.slightRight => 'SLIGHT RIGHT',
        ManoeuvreKind.sharpLeft => 'SHARP LEFT',
        ManoeuvreKind.sharpRight => 'SHARP RIGHT',
        ManoeuvreKind.uTurn => 'U-TURN',
        ManoeuvreKind.roundabout => exit == null ? 'ROUNDABOUT' : 'ROUNDABOUT EXIT $exit',
        ManoeuvreKind.arrive => 'DESTINATION',
      };
  String short(ManoeuvreKind k) => switch (k) {
        ManoeuvreKind.straight => 'AHEAD',
        ManoeuvreKind.slightLeft => 'SLIGHT L',
        ManoeuvreKind.slightRight => 'SLIGHT R',
        ManoeuvreKind.sharpLeft => 'SHARP L',
        ManoeuvreKind.sharpRight => 'SHARP R',
        ManoeuvreKind.roundabout => 'RNDABT',
        _ => name(k).replaceAll('TURN ', ''),
      };
  if (then != null) {
    final long = '${short(k)} THEN ${short(then)}';
    return OledFrame.textWidth(long) <= OledFrame.width ? long : '${short(k)} > ${short(then)}';
  }
  return name(k);
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

void _drawArrow(OledFrame f, double bx, double by, ManoeuvreKind kind, int? exit) {
  const r = 2.5; // half the line thickness
  List<double> p(double x, double y) => [bx + x, by + y];

  void head(double tipX, double tipY, double angleDeg) {
    final a = angleDeg * math.pi / 180;
    final dx = math.sin(a), dy = -math.cos(a); // direction of travel
    const len = 9.0, half = 6.5;
    final baseX = tipX - dx * len, baseY = tipY - dy * len;
    f.fillTriangle(p(tipX, tipY), p(baseX - dy * half, baseY + dx * half),
        p(baseX + dy * half, baseY - dx * half));
  }

  final angle = turnAngle(kind);
  if (angle != null) {
    if (angle == 0) {
      f.thickLine(bx + 24, by + 46, bx + 24, by + 14, r);
      head(24, 3, 0);
      return;
    }
    // Stem up from the bottom to the junction, then off at the turn angle.
    // Sharp turns bend back down, so their junction sits higher.
    const pivotX = 24.0, arm = 14.0;
    final pivotY = angle.abs() > 100 ? 14.0 : angle.abs() > 60 ? 24.0 : 28.0;
    final a = angle * math.pi / 180;
    final endX = pivotX + math.sin(a) * arm, endY = pivotY - math.cos(a) * arm;
    f.thickLine(bx + pivotX, by + 46, bx + pivotX, by + pivotY, r);
    f.thickLine(bx + pivotX, by + pivotY, bx + endX, by + endY, r);
    head(endX + math.sin(a) * 8, endY - math.cos(a) * 8, angle);
    return;
  }
  switch (kind) {
    case ManoeuvreKind.uTurn:
      // Up the left side, over the top and back down the right side
      // (traffic keeps left in Ireland, so U-turns go round to the right).
      f.thickLine(bx + 14, by + 46, bx + 14, by + 20, r);
      for (var i = 0; i <= 24; i++) {
        final t = math.pi - math.pi * i / 24;
        f.fillCircle(bx + 24 + math.cos(t) * 10, by + 20 - math.sin(t) * 10, r);
      }
      f.thickLine(bx + 34, by + 20, bx + 34, by + 28, r);
      head(34, 40, 180);
    case ManoeuvreKind.roundabout:
      // A clockwise circular arrow (traffic goes clockwise round Irish
      // roundabouts), like a roundabout road sign, with the
      // entry from below.
      const cx = 24.0, cy = 25.0, rr = 12.0;
      for (var deg = 200; deg <= 470; deg += 4) {
        final phi = deg * math.pi / 180; // clockwise from the top
        f.fillCircle(bx + cx + rr * math.sin(phi), by + cy - rr * math.cos(phi), 2);
      }
      const endDeg = 470.0;
      final endPhi = endDeg * math.pi / 180;
      final tangent = endDeg + 90; // direction of travel at the end of the arc
      final ta = tangent * math.pi / 180;
      head(cx + rr * math.sin(endPhi) + math.sin(ta) * 7,
          cy - rr * math.cos(endPhi) - math.cos(ta) * 7, tangent);
      f.thickLine(bx + cx, by + 46, bx + cx, by + cy + rr, r);
      if (exit != null) f.centredText((bx + 13).round(), (bx + 35).round(), (by + 18).round(), '$exit', scale: 2);
    case ManoeuvreKind.arrive:
      _drawFlag(f, bx.round(), by.round());
    default:
      break;
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
  f.centredText(left, right, 20, number, scale: scale);
  f.centredText(left, right, 50, unit, scale: 2);
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
