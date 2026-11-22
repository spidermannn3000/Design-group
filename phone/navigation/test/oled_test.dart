import 'package:bike_navigation/bike_navigation.dart';
import 'package:test/test.dart';

NavState turn(ManoeuvreKind kind, double distance, {int? exit}) => NavState(
      next: Manoeuvre(
          kind: kind,
          instruction: '',
          pointIndex: 0,
          alongM: 0,
          exitNumber: exit),
      distanceToNextM: distance,
      showTurn: true,
      symbols: const [],
      offRoute: false,
      arrived: false,
      alongM: 0,
      offsetM: 0,
    );

/// Lit pixels in the arrow area (the left 57 columns).
Set<(int, int)> arrowPixels(OledFrame f) => {
      for (var y = 0; y < 64; y++)
        for (var x = 0; x < 57; x++)
          if (f.pixel(x, y)) (x, y),
    };

void main() {
  test('each kind of turn has its own arrow', () {
    final kinds = [
      ManoeuvreKind.straight,
      ManoeuvreKind.slightLeft,
      ManoeuvreKind.left,
      ManoeuvreKind.sharpLeft,
      ManoeuvreKind.slightRight,
      ManoeuvreKind.right,
      ManoeuvreKind.sharpRight,
      ManoeuvreKind.uTurn,
      ManoeuvreKind.roundabout,
    ];
    final arrows = {
      for (final k in kinds) k: arrowPixels(renderOled(turn(k, 50)))
    };
    for (final a in arrows.values) {
      expect(a.length, greaterThan(100));
    }
    expect(arrows.values.map((a) => a.toString()).toSet().length, kinds.length);
  });

  test('right arrows mirror left arrows', () {
    for (final (l, r) in [
      (ManoeuvreKind.slightLeft, ManoeuvreKind.slightRight),
      (ManoeuvreKind.left, ManoeuvreKind.right),
      (ManoeuvreKind.sharpLeft, ManoeuvreKind.sharpRight),
    ]) {
      final left = arrowPixels(renderOled(turn(l, 50)));
      final mirrored = {
        for (final (x, y) in arrowPixels(renderOled(turn(r, 50)))) (56 - x, y)
      };
      final diff =
          left.difference(mirrored).length + mirrored.difference(left).length;
      expect(diff, lessThan(left.length ~/ 10), reason: '$l vs $r');
    }
  });

  test('sharper turns point further back', () {
    // Average height of the arrow tip (the far left): a slight left reaches up,
    // a sharp left reaches down.
    double leftHalfY(ManoeuvreKind k) {
      final px =
          arrowPixels(renderOled(turn(k, 50))).where((p) => p.$1 < 15).toList();
      return px.map((p) => p.$2).reduce((a, b) => a + b) / px.length;
    }

    expect(leftHalfY(ManoeuvreKind.slightLeft),
        lessThan(leftHalfY(ManoeuvreKind.left)));
    expect(leftHalfY(ManoeuvreKind.left),
        lessThan(leftHalfY(ManoeuvreKind.sharpLeft)));
  });

  test('distance formatting', () {
    expect(formatDistance(4), ('4', 'm'));
    expect(formatDistance(87), ('87', 'm'));
    expect(formatDistance(123), ('120', 'm'));
    expect(formatDistance(996), ('1.0', 'km'));
    expect(formatDistance(2340), ('2.3', 'km'));
    expect(formatDistance(12400), ('12', 'km'));
  });

  test('arrow and distance never touch', () {
    for (final d in <double>[3, 99, 850, 2340, 12400]) {
      for (final k in ManoeuvreKind.values) {
        final f = renderOled(turn(k, d, exit: 3));
        // A clear gap between the arrow and the distance.
        final overlap = [
          for (var y = 0; y < 64; y++)
            for (var x = 57; x < 59; x++)
              if (f.pixel(x, y)) 1,
        ];
        expect(overlap, isEmpty, reason: '$k at $d m');
      }
    }
  });

  test('SSD1306 buffer layout', () {
    final f = OledFrame()
      ..set(0, 0)
      ..set(5, 9)
      ..set(127, 63);
    final b = f.toSsd1306();
    expect(b.length, 1024);
    expect(b[0], 1); // page 0, column 0, bit 0
    expect(b[128 + 5], 1 << 1); // page 1, column 5, bit 1
    expect(b[7 * 128 + 127], 1 << 7);
  });

  test('Bluetooth packet (draft protocol v1)', () {
    final s = NavState(
      next: Manoeuvre(
          kind: ManoeuvreKind.roundabout,
          instruction: '',
          pointIndex: 0,
          alongM: 0,
          exitNumber: 2),
      distanceToNextM: 300.4,
      showTurn: true,
      symbols: const [9, 22],
      offRoute: false,
      arrived: false,
      flash: true,
      alongM: 0,
      offsetM: 0,
    );
    expect(encodeNavPacket(s), [1, 1, 0x2C, 0x01, 2, 9, 22]); // 300 m = 0x012C
    expect(encodeNavPacket(null), [1, 0, 0xFF, 0xFF, 0]);
  });

  group('flash at 5 m', () {
    final start = LatLng(53.34, -6.26);
    final line = Polyline([
      start,
      offsetM(start, northM: 200),
      offsetM(start, northM: 200, eastM: 100)
    ]);
    NavRoute route() => NavRoute(line, [
          Manoeuvre(
              kind: ManoeuvreKind.right,
              instruction: '',
              pointIndex: 1,
              alongM: line.cumulativeM[1]),
          Manoeuvre(
              kind: ManoeuvreKind.arrive,
              instruction: '',
              pointIndex: 2,
              alongM: line.cumulativeM[2]),
        ]);

    test('not at 50 m or 8 m, yes at 4 m', () {
      final e = NavigationEngine(route());
      expect(e.update(offsetM(start, northM: 150)).flash, isFalse);
      expect(e.update(offsetM(start, northM: 192)).flash, isFalse);
      expect(e.update(offsetM(start, northM: 196)).flash, isTrue);
    });

    test('not for the destination', () {
      final e = NavigationEngine(route());
      for (final n in <double>[100, 199, 220]) {
        e.update(offsetM(start,
            northM: n.clamp(0, 200).toDouble(), eastM: n > 200 ? n - 200 : 0));
      }
      final s = e.update(offsetM(start, northM: 200, eastM: 97));
      expect(s.flash, isFalse);
    });
  });
}
