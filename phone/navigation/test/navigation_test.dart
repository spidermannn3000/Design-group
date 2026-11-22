import 'dart:convert';
import 'dart:io';

import 'package:bike_navigation/bike_navigation.dart';
import 'package:test/test.dart';

NavRoute loadSample() => parseOrsGeoJson(jsonDecode(
        File('test/fixtures/ors_sample.json').readAsStringSync())
    as Map<String, dynamic>);

/// The point [metres] along the route.
LatLng pointAlong(NavRoute route, double metres) {
  final line = route.line;
  var i = 0;
  while (i < line.segmentCount - 1 && line.cumulativeM[i + 1] < metres) {
    i++;
  }
  final a = line.points[i], b = line.points[i + 1];
  final t = (metres - line.cumulativeM[i]) / (line.cumulativeM[i + 1] - line.cumulativeM[i]);
  return LatLng(a.lat + (b.lat - a.lat) * t, a.lng + (b.lng - a.lng) * t);
}

void main() {
  group('N1/N6 parsing and symbols', () {
    test('parses ORS steps into manoeuvres, skipping depart', () {
      final route = loadSample();
      expect(route.manoeuvres.map((m) => m.kind), [
        ManoeuvreKind.right,
        ManoeuvreKind.roundabout,
        ManoeuvreKind.arrive,
      ]);
      expect(route.manoeuvres[1].exitNumber, 2);
      expect(route.manoeuvres[0].alongM, closeTo(400, 1));
      expect(route.distanceM, closeTo(900, 1));
    });

    test('roundabout shows symbol then exit number', () {
      final m = loadSample().manoeuvres[1];
      expect(displaySequence(m), [LedSymbol.roundabout, 22]);
    });

    test('every manoeuvre kind has a symbol', () {
      for (final k in ManoeuvreKind.values) {
        expect(symbolFor(k), greaterThan(0));
      }
    });
  });

  group('N2 level 1', () {
    test('shows the next manoeuvre straight away', () {
      final route = loadSample();
      final engine = NavigationEngine(route, config: const NavConfig(mode: TriggerMode.always));
      final s = engine.update(pointAlong(route, 10));
      expect(s.next!.kind, ManoeuvreKind.right);
      expect(s.showTurn, isTrue);
      expect(s.symbols, [LedSymbol.right]);
      expect(s.distanceToNextM, closeTo(390, 1));
    });
  });

  group('N3 level 2 (distance along route)', () {
    test('hidden at 200 m, shown at 105 m, then moves on after the turn', () {
      final route = loadSample();
      final engine = NavigationEngine(route);
      expect(engine.update(pointAlong(route, 200)).symbols, [LedSymbol.straight]);
      expect(engine.update(pointAlong(route, 295)).symbols, [LedSymbol.right]);
      // Past the turn: next is the roundabout, 500 m from the start.
      final after = engine.update(pointAlong(route, 430));
      expect(after.next!.kind, ManoeuvreKind.roundabout);
      expect(after.symbols, [LedSymbol.straight]);
    });

    test('uses distance along the route, not straight-line distance', () {
      // 60 m before the roundabout the rider is on East Road. The straight
      // line to it is the same, but the route distance check must hold too.
      final route = loadSample();
      final engine = NavigationEngine(route);
      engine.update(pointAlong(route, 420));
      final s = engine.update(pointAlong(route, 640));
      expect(s.distanceToNextM, closeTo(60, 1));
      expect(s.symbols, [LedSymbol.roundabout, 22]);
    });

    test('turn stays shown despite GPS jitter backwards', () {
      final route = loadSample();
      final engine = NavigationEngine(route);
      engine.update(pointAlong(route, 300));
      final s = engine.update(pointAlong(route, 285));
      expect(s.showTurn, isTrue);
    });

    test('arrives at the end', () {
      final route = loadSample();
      final engine = NavigationEngine(route);
      for (final d in <double>[100, 300, 450, 600, 750, 895]) {
        engine.update(pointAlong(route, d));
      }
      final s = engine.update(pointAlong(route, 899));
      expect(s.arrived, isTrue);
      expect(s.symbols, [LedSymbol.arrive]);
    });
  });

  group('N4 level 3 (junctions)', () {
    test('reads junctions (3+ arms) from Overpass data', () {
      final json = {
        'elements': [
          {'type': 'way', 'id': 1, 'nodes': [1, 2, 3]},
          {'type': 'way', 'id': 2, 'nodes': [2, 4]},
          {'type': 'way', 'id': 3, 'nodes': [3, 5]}, // just a continuation
          for (final id in [1, 2, 3, 4, 5])
            {'type': 'node', 'id': id, 'lat': 53.0 + id / 1000, 'lon': -6.0},
        ],
      };
      final j = junctionsFromOverpass(json);
      expect(j.length, 1);
      expect(j.single.lat, closeTo(53.002, 1e-9));
    });

    test('shows the turn once the last junction before it is passed', () {
      final route = loadSample();
      // Side roads at 150 m and 330 m before the right turn at 400 m, and
      // one at the turn itself which must be ignored.
      attachJunctions(route, [
        pointAlong(route, 150),
        pointAlong(route, 330),
        pointAlong(route, 400),
      ]);
      expect(route.manoeuvres[0].junctionAlongM, closeTo(330, 1));

      final engine = NavigationEngine(route,
          config: const NavConfig(mode: TriggerMode.junction));
      expect(engine.update(pointAlong(route, 300)).showTurn, isFalse,
          reason: 'within 100 m but junction not reached');
      expect(engine.update(pointAlong(route, 320)).showTurn, isTrue);
    });

    test('falls back to distance when there is no junction', () {
      final route = loadSample();
      final engine = NavigationEngine(route,
          config: const NavConfig(mode: TriggerMode.junction));
      expect(engine.update(pointAlong(route, 200)).showTurn, isFalse);
      expect(engine.update(pointAlong(route, 300)).showTurn, isTrue);
    });

    test('Overpass query covers the route', () {
      final q = overpassQuery(loadSample().line);
      expect(q, contains('residential'));
      expect(q, isNot(contains('service')));
    });
  });

  group('N5 off-route and rerouting', () {
    test('needs 3 fixes over 30 m away before going off-route', () {
      final route = loadSample();
      final engine = NavigationEngine(route);
      engine.update(pointAlong(route, 200));
      final away = offsetM(pointAlong(route, 210), eastM: -80);
      expect(engine.update(away).offRoute, isFalse);
      expect(engine.update(away).offRoute, isFalse);
      final s = engine.update(away);
      expect(s.offRoute, isTrue);
      expect(s.symbols, [LedSymbol.rerouting]);
      // Back on the route clears it.
      expect(engine.update(pointAlong(route, 220)).offRoute, isFalse);
    });

    test('a single GPS spike does not trigger rerouting', () {
      final route = loadSample();
      final engine = NavigationEngine(route);
      engine.update(pointAlong(route, 100));
      engine.update(offsetM(pointAlong(route, 105), eastM: 60));
      expect(engine.update(pointAlong(route, 110)).offRoute, isFalse);
    });

    test('session reroutes from the current position, with a cooldown', () async {
      final sample = loadSample();
      final requests = <LatLng>[];
      Future<NavRoute> provider(LatLng from, LatLng to) async {
        requests.add(from);
        // The new route starts where the rider is now.
        return NavRoute(
            Polyline([from, offsetM(from, northM: 300)]),
            [Manoeuvre(kind: ManoeuvreKind.arrive, instruction: 'Arrive', pointIndex: 1, alongM: 300)]);
      }

      final session = NavigationSession(
          routeProvider: provider, destination: sample.line.points.last);
      final start = sample.line.points.first;
      await session.start(start);
      expect(requests.length, 1);

      final away = offsetM(start, eastM: 500);
      final t0 = DateTime.utc(2026);
      for (var i = 0; i < 3; i++) {
        await session.onPosition(away, at: t0.add(Duration(seconds: i)));
      }
      expect(session.rerouteCount, 1);
      expect(requests.last.lng, closeTo(away.lng, 1e-9));
      final s = await session.onPosition(away, at: t0.add(const Duration(seconds: 4)));
      expect(s.offRoute, isFalse);
    });
  });

  group('N7 replay', () {
    test('a simulated noisy ride shows each turn and arrives', () {
      final route = loadSample();
      final engine = NavigationEngine(route);
      final seen = <int>{};
      var arrived = false;
      var offRoute = false;
      for (final fix in simulateRide(route.line.points, noiseM: 8, seed: 7)) {
        final s = engine.update(fix.position, accuracyM: fix.accuracyM);
        seen.addAll(s.symbols);
        offRoute |= s.offRoute;
        if (s.arrived) {
          arrived = true;
          break;
        }
      }
      expect(seen, containsAll([LedSymbol.right, LedSymbol.roundabout, 22]));
      expect(offRoute, isFalse, reason: '8 m GPS noise must not cause rerouting');
      expect(arrived, isTrue);
    });

    test('parses GPX track points', () {
      const gpx = '''<gpx><trk><trkseg>
        <trkpt lat="53.34" lon="-6.26"><time>2026-01-01T09:00:00Z</time></trkpt>
        <trkpt lon="-6.2601" lat="53.3401"><time>2026-01-01T09:00:02Z</time></trkpt>
      </trkseg></trk></gpx>''';
      final fixes = parseGpx(gpx);
      expect(fixes.length, 2);
      expect(fixes[1].position.lng, -6.2601);
      expect(fixes[1].time.difference(fixes[0].time).inSeconds, 2);
    });
  });
}
