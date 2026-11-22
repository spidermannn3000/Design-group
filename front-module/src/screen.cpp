// Port of renderOled (phone/navigation/lib/src/oled.dart). Keep the two in
// step: test_native/check.sh compares them pixel for pixel.
#include "screen.h"

#include <math.h>
#include <stdio.h>
#include <string.h>

namespace screen {
namespace {

constexpr double kPi = 3.14159265358979323846;

// ---- 5x7 font --------------------------------------------------------------

struct Glyph {
  char ch;
  const char* rows[7];
};

const Glyph kFont[] = {
    {' ', {".....", ".....", ".....", ".....", ".....", ".....", "....."}},
    {'-', {".....", ".....", ".....", "#####", ".....", ".....", "....."}},
    {'.', {".....", ".....", ".....", ".....", ".....", ".##..", ".##.."}},
    {'>', {"#....", ".#...", "..#..", "...#.", "..#..", ".#...", "#...."}},
    {'?', {".###.", "#...#", "....#", "...#.", "..#..", ".....", "..#.."}},
    {'%', {"##...", "##..#", "...#.", "..#..", ".#...", "#..##", "...##"}},
    {'0', {".###.", "#...#", "#..##", "#.#.#", "##..#", "#...#", ".###."}},
    {'1', {"..#..", ".##..", "..#..", "..#..", "..#..", "..#..", ".###."}},
    {'2', {".###.", "#...#", "....#", "...#.", "..#..", ".#...", "#####"}},
    {'3', {"####.", "....#", "....#", ".###.", "....#", "....#", "####."}},
    {'4', {"...#.", "..##.", ".#.#.", "#..#.", "#####", "...#.", "...#."}},
    {'5', {"#####", "#....", "####.", "....#", "....#", "#...#", ".###."}},
    {'6', {"..##.", ".#...", "#....", "####.", "#...#", "#...#", ".###."}},
    {'7', {"#####", "....#", "...#.", "..#..", ".#...", ".#...", ".#..."}},
    {'8', {".###.", "#...#", "#...#", ".###.", "#...#", "#...#", ".###."}},
    {'9', {".###.", "#...#", "#...#", ".####", "....#", "...#.", ".##.."}},
    {'A', {".###.", "#...#", "#...#", "#####", "#...#", "#...#", "#...#"}},
    {'B', {"####.", "#...#", "#...#", "####.", "#...#", "#...#", "####."}},
    {'C', {".###.", "#...#", "#....", "#....", "#....", "#...#", ".###."}},
    {'D', {"####.", "#...#", "#...#", "#...#", "#...#", "#...#", "####."}},
    {'E', {"#####", "#....", "#....", "####.", "#....", "#....", "#####"}},
    {'F', {"#####", "#....", "#....", "####.", "#....", "#....", "#...."}},
    {'G', {".###.", "#...#", "#....", "#.###", "#...#", "#...#", ".####"}},
    {'H', {"#...#", "#...#", "#...#", "#####", "#...#", "#...#", "#...#"}},
    {'I', {".###.", "..#..", "..#..", "..#..", "..#..", "..#..", ".###."}},
    {'J', {"..###", "...#.", "...#.", "...#.", "...#.", "#..#.", ".##.."}},
    {'K', {"#...#", "#..#.", "#.#..", "##...", "#.#..", "#..#.", "#...#"}},
    {'L', {"#....", "#....", "#....", "#....", "#....", "#....", "#####"}},
    {'M', {"#...#", "##.##", "#.#.#", "#.#.#", "#...#", "#...#", "#...#"}},
    {'N', {"#...#", "#...#", "##..#", "#.#.#", "#..##", "#...#", "#...#"}},
    {'O', {".###.", "#...#", "#...#", "#...#", "#...#", "#...#", ".###."}},
    {'P', {"####.", "#...#", "#...#", "####.", "#....", "#....", "#...."}},
    {'Q', {".###.", "#...#", "#...#", "#...#", "#.#.#", "#..#.", ".##.#"}},
    {'R', {"####.", "#...#", "#...#", "####.", "#.#..", "#..#.", "#...#"}},
    {'S', {".####", "#....", "#....", ".###.", "....#", "....#", "####."}},
    {'T', {"#####", "..#..", "..#..", "..#..", "..#..", "..#..", "..#.."}},
    {'U', {"#...#", "#...#", "#...#", "#...#", "#...#", "#...#", ".###."}},
    {'V', {"#...#", "#...#", "#...#", "#...#", "#...#", ".#.#.", "..#.."}},
    {'W', {"#...#", "#...#", "#...#", "#.#.#", "#.#.#", "#.#.#", ".#.#."}},
    {'X', {"#...#", "#...#", ".#.#.", "..#..", ".#.#.", "#...#", "#...#"}},
    {'Y', {"#...#", "#...#", ".#.#.", "..#..", "..#..", "..#..", "..#.."}},
    {'Z', {"#####", "....#", "...#.", "..#..", ".#...", "#....", "#####"}},
    {'k', {"#....", "#....", "#..#.", "#.#..", "##...", "#.#..", "#..#."}},
    {'m', {".....", ".....", "##.#.", "#.#.#", "#.#.#", "#.#.#", "#.#.#"}},
};

const Glyph& glyphFor(char ch) {
  for (const Glyph& g : kFont) {
    if (g.ch == ch) return g;
  }
  return kFont[0];
}

// ---- drawing primitives (same maths as the Dart version) ------------------

void set(Canvas& c, int x, int y) {
  if (x < 0 || y < 0 || x >= kWidth || y >= kHeight) return;
  c.set(x, y);
}

void fillCircle(Canvas& c, double cx, double cy, double r) {
  for (int y = (int)floor(cy - r); y <= (int)ceil(cy + r); y++) {
    for (int x = (int)floor(cx - r); x <= (int)ceil(cx + r); x++) {
      const double dx = x + 0.5 - cx, dy = y + 0.5 - cy;
      if (dx * dx + dy * dy <= r * r) set(c, x, y);
    }
  }
}

void thickLine(Canvas& c, double x0, double y0, double x1, double y1, double r) {
  const double len = sqrt((x1 - x0) * (x1 - x0) + (y1 - y0) * (y1 - y0));
  int steps = (int)ceil(len * 2);
  if (steps < 1) steps = 1;
  for (int i = 0; i <= steps; i++) {
    const double t = (double)i / steps;
    fillCircle(c, x0 + (x1 - x0) * t, y0 + (y1 - y0) * t, r);
  }
}

double edge(const double* p, const double* q, double x, double y) {
  return (q[0] - p[0]) * (y - p[1]) - (q[1] - p[1]) * (x - p[0]);
}

void fillTriangle(Canvas& c, const double* a, const double* b, const double* d) {
  const int minX = (int)floor(fmin(a[0], fmin(b[0], d[0])));
  const int maxX = (int)ceil(fmax(a[0], fmax(b[0], d[0])));
  const int minY = (int)floor(fmin(a[1], fmin(b[1], d[1])));
  const int maxY = (int)ceil(fmax(a[1], fmax(b[1], d[1])));
  for (int y = minY; y <= maxY; y++) {
    for (int x = minX; x <= maxX; x++) {
      const double px = x + 0.5, py = y + 0.5;
      const double e0 = edge(a, b, px, py), e1 = edge(b, d, px, py), e2 = edge(d, a, px, py);
      if ((e0 >= 0 && e1 >= 0 && e2 >= 0) || (e0 <= 0 && e1 <= 0 && e2 <= 0)) set(c, x, y);
    }
  }
}

int textWidth(const char* s, int scale) {
  const int n = (int)strlen(s);
  return n == 0 ? 0 : n * 6 * scale - scale;
}

void text(Canvas& c, int x, int y, const char* s, int scale) {
  int cx = x;
  for (const char* p = s; *p; p++) {
    const Glyph& g = glyphFor(*p);
    for (int row = 0; row < 7; row++) {
      for (int col = 0; col < 5; col++) {
        if (g.rows[row][col] != '#') continue;
        for (int dy = 0; dy < scale; dy++) {
          for (int dx = 0; dx < scale; dx++) {
            set(c, cx + col * scale + dx, y + row * scale + dy);
          }
        }
      }
    }
    cx += 6 * scale;
  }
}

void centredText(Canvas& c, int left, int right, int y, const char* s, int scale = 1) {
  text(c, left + (right - left - textWidth(s, scale)) / 2, y, s, scale);
}

// ---- screens ---------------------------------------------------------------

const char* longName(uint8_t k) {
  switch (k) {
    case kStraight: return "STRAIGHT ON";
    case kLeft: return "TURN LEFT";
    case kRight: return "TURN RIGHT";
    case kSlightLeft: return "SLIGHT LEFT";
    case kSlightRight: return "SLIGHT RIGHT";
    case kSharpLeft: return "SHARP LEFT";
    case kSharpRight: return "SHARP RIGHT";
    case kUTurn: return "U-TURN";
    case kRoundabout: return "ROUNDABOUT";
    case kArrive: return "DESTINATION";
    default: return "";
  }
}

const char* shortName(uint8_t k) {
  switch (k) {
    case kStraight: return "AHEAD";
    case kLeft: return "LEFT";
    case kRight: return "RIGHT";
    case kSlightLeft: return "SLIGHT L";
    case kSlightRight: return "SLIGHT R";
    case kSharpLeft: return "SHARP L";
    case kSharpRight: return "SHARP R";
    case kUTurn: return "U-TURN";
    case kRoundabout: return "RNDABT";
    case kArrive: return "DESTINATION";
    default: return "";
  }
}

// Turn angle in degrees (0 = straight, negative = left), or false if the
// symbol is not a simple turn.
bool turnAngle(uint8_t k, double& angle) {
  switch (k) {
    case kStraight: angle = 0; return true;
    case kSlightLeft: angle = -45; return true;
    case kSlightRight: angle = 45; return true;
    case kLeft: angle = -90; return true;
    case kRight: angle = 90; return true;
    case kSharpLeft: angle = -135; return true;
    case kSharpRight: angle = 135; return true;
    default: return false;
  }
}

void drawFlag(Canvas& c, int x, int y) {
  thickLine(c, x + 12.0, y + 4.0, x + 12.0, y + 46.0, 1.5);
  for (int row = 0; row < 3; row++) {
    for (int col = 0; col < 5; col++) {
      if ((row + col) % 2 != 0) continue;
      for (int dy = 0; dy < 5; dy++) {
        for (int dx = 0; dx < 5; dx++) set(c, x + 14 + col * 5 + dx, y + 4 + row * 5 + dy);
      }
    }
  }
  for (int col = 0; col < 25; col++) {
    set(c, x + 14 + col, y + 4);
    set(c, x + 14 + col, y + 18);
  }
}

struct ArrowBox {
  Canvas& c;
  double bx, by;

  // Filled arrowhead with its tip at (tipX, tipY), pointing along angleDeg.
  void head(double tipX, double tipY, double angleDeg) {
    const double a = angleDeg * kPi / 180;
    const double dx = sin(a), dy = -cos(a);
    const double len = 9.0, half = 6.5;
    const double baseX = tipX - dx * len, baseY = tipY - dy * len;
    const double p0[2] = {bx + tipX, by + tipY};
    const double p1[2] = {bx + baseX - dy * half, by + baseY + dx * half};
    const double p2[2] = {bx + baseX + dy * half, by + baseY - dx * half};
    fillTriangle(c, p0, p1, p2);
  }

  void draw(uint8_t kind, int exitNumber) {
    const double r = 2.5;  // half the line thickness
    double angle;
    if (turnAngle(kind, angle)) {
      if (angle == 0) {
        thickLine(c, bx + 24, by + 46, bx + 24, by + 14, r);
        head(24, 3, 0);
        return;
      }
      // Stem up to the junction, then off at the turn angle. Sharp turns
      // bend back down, so their junction sits higher.
      const double pivotX = 24.0, arm = 14.0;
      const double pivotY = fabs(angle) > 100 ? 14.0 : fabs(angle) > 60 ? 24.0 : 28.0;
      const double a = angle * kPi / 180;
      const double endX = pivotX + sin(a) * arm, endY = pivotY - cos(a) * arm;
      thickLine(c, bx + pivotX, by + 46, bx + pivotX, by + pivotY, r);
      thickLine(c, bx + pivotX, by + pivotY, bx + endX, by + endY, r);
      head(endX + sin(a) * 8, endY - cos(a) * 8, angle);
      return;
    }
    switch (kind) {
      case kUTurn:
        // Traffic keeps left in Ireland, so U-turns go round to the right.
        thickLine(c, bx + 14, by + 46, bx + 14, by + 20, r);
        for (int i = 0; i <= 24; i++) {
          const double t = kPi - kPi * i / 24;
          fillCircle(c, bx + 24 + cos(t) * 10, by + 20 - sin(t) * 10, r);
        }
        thickLine(c, bx + 34, by + 20, bx + 34, by + 28, r);
        head(34, 40, 180);
        break;
      case kRoundabout: {
        // Clockwise circular arrow, like a roundabout road sign.
        const double cx = 24.0, cy = 25.0, rr = 12.0;
        for (int deg = 200; deg <= 470; deg += 4) {
          const double phi = deg * kPi / 180;
          fillCircle(c, bx + cx + rr * sin(phi), by + cy - rr * cos(phi), 2);
        }
        const double endDeg = 470.0;
        const double endPhi = endDeg * kPi / 180;
        const double tangent = endDeg + 90;
        const double ta = tangent * kPi / 180;
        head(cx + rr * sin(endPhi) + sin(ta) * 7, cy - rr * cos(endPhi) - cos(ta) * 7, tangent);
        thickLine(c, bx + cx, by + 46, bx + cx, by + cy + rr, r);
        if (exitNumber > 0) {
          char digit[4];
          snprintf(digit, sizeof digit, "%d", exitNumber);
          centredText(c, (int)lround(bx + 13), (int)lround(bx + 35), (int)lround(by + 18), digit, 2);
        }
        break;
      }
      case kArrive:
        drawFlag(c, (int)lround(bx), (int)lround(by));
        break;
      default:
        break;
    }
  }
};

// "120" over "m", or "2.3" over "km". Same rounding as formatDistance.
void drawDistance(Canvas& c, uint16_t m) {
  char number[8];
  const char* unit = "m";
  if (m >= 9950) {
    snprintf(number, sizeof number, "%ld", lround(m / 1000.0));
    unit = "km";
  } else if (m >= 995) {
    snprintf(number, sizeof number, "%.1f", m / 1000.0);
    unit = "km";
  } else if (m >= 100) {
    snprintf(number, sizeof number, "%ld", lround(m / 10.0) * 10);
  } else {
    snprintf(number, sizeof number, "%u", (unsigned)m);
  }
  const int left = 58, right = 128;
  const int scale = textWidth(number, 4) <= right - left ? 4 : 3;
  centredText(c, left, right, 20, number, scale);
  centredText(c, left, right, 50, unit, 2);
}

}  // namespace

bool decode(const uint8_t* data, size_t len, NavMessage& out) {
  if (len < 5 || data[0] != kProtocolVersion) return false;
  const uint8_t count = data[4];
  if (count > 4 || len < 5u + count) return false;
  out.flash = data[1] & 1;
  out.arrived = data[1] & 2;
  out.distanceM = data[2] | (data[3] << 8);
  out.count = count;
  for (int i = 0; i < 4; i++) out.symbols[i] = i < count ? data[5 + i] : 0;
  return true;
}

void draw(Canvas& c, const NavMessage& msg) {
  if (msg.arrived) {
    centredText(c, 0, 128, 4, "YOU HAVE ARRIVED");
    drawFlag(c, 40, 16);
    return;
  }
  if (msg.count == 0 || msg.symbols[0] == kBlank) return;
  const uint8_t kind = msg.symbols[0];
  if (kind == kRerouting) {
    centredText(c, 0, 128, 4, "REROUTING");
    centredText(c, 0, 128, 22, "?", 5);
    return;
  }
  if (kind == kBluetoothLost) {
    drawNoPhone(c);
    return;
  }

  // [9, 22] = roundabout exit 2. Anything after that is the next turn,
  // shown together because it is close.
  int i = 1, exitNumber = 0;
  if (kind == kRoundabout && i < msg.count && msg.symbols[i] > kExitDigitBase &&
      msg.symbols[i] <= kExitDigitBase + 9) {
    exitNumber = msg.symbols[i++] - kExitDigitBase;
  }
  const uint8_t then = i < msg.count ? msg.symbols[i] : (uint8_t)kBlank;

  char label[40];
  if (then != kBlank) {
    snprintf(label, sizeof label, "%s THEN %s", shortName(kind), shortName(then));
    if (textWidth(label, 1) > kWidth) {
      snprintf(label, sizeof label, "%s > %s", shortName(kind), shortName(then));
    }
  } else if (kind == kRoundabout && exitNumber > 0) {
    snprintf(label, sizeof label, "ROUNDABOUT EXIT %d", exitNumber);
  } else {
    snprintf(label, sizeof label, "%s", longName(kind));
  }
  centredText(c, 0, 128, 4, label);

  ArrowBox box{c, 8, 16};
  box.draw(kind, exitNumber);
  if (msg.distanceM != kNoDistance) drawDistance(c, msg.distanceM);
}

void drawNoPhone(Canvas& c) {
  centredText(c, 0, 128, 4, "NO PHONE");
  // A phone outline with a cross through it.
  for (int y = 18; y <= 60; y++) {
    set(c, 48, y);
    set(c, 49, y);
    set(c, 78, y);
    set(c, 79, y);
  }
  for (int x = 48; x <= 79; x++) {
    set(c, x, 18);
    set(c, x, 19);
    set(c, x, 59);
    set(c, x, 60);
  }
  thickLine(c, 40, 22, 88, 56, 2);
  thickLine(c, 88, 22, 40, 56, 2);
}

void drawWaiting(Canvas& c) {
  centredText(c, 0, 128, 4, "BIKE NAV");
  centredText(c, 0, 128, 28, "WAITING FOR");
  centredText(c, 0, 128, 40, "PHONE");
}

void drawLowBattery(Canvas& c, int percent) {
  centredText(c, 0, 128, 4, "LOW BATTERY");
  // Battery outline with a fill level.
  for (int x = 30; x <= 90; x++) {
    set(c, x, 24);
    set(c, x, 25);
    set(c, x, 54);
    set(c, x, 55);
  }
  for (int y = 24; y <= 55; y++) {
    set(c, 30, y);
    set(c, 31, y);
    set(c, 89, y);
    set(c, 90, y);
  }
  for (int y = 32; y <= 47; y++) {
    set(c, 91, y);
    set(c, 92, y);
    set(c, 93, y);
  }
  const int fill = percent < 0 ? 0 : percent > 100 ? 100 : percent;
  for (int y = 28; y <= 51; y++) {
    for (int x = 34; x < 34 + fill * 53 / 100; x++) set(c, x, y);
  }
  char pct[8];
  snprintf(pct, sizeof pct, "%d%%", fill);
  centredText(c, 94, 128, 36, pct);
}

}  // namespace screen
