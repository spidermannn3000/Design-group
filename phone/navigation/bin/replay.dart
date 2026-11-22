// Replays a recorded or simulated ride through the navigation engine and
// prints what the LED matrix would show (task N7).
//
//   dart run bin/replay.dart --route test/fixtures/ors_sample.json
//   dart run bin/replay.dart --route my_route.json --gpx my_ride.gpx --mode junction
//
// --route  a saved OpenRouteService GeoJSON response
// --gpx    a recorded track; without it a ride along the route is simulated
// --mode   always | distance | junction   (default: distance)
// --noise  simulated GPS noise in metres (default 5)
import 'dart:convert';
import 'dart:io';

import 'package:bike_navigation/bike_navigation.dart';

Future<void> main(List<String> args) async {
  String? opt(String name) {
    final i = args.indexOf('--$name');
    return i >= 0 && i + 1 < args.length ? args[i + 1] : null;
  }

  final routePath = opt('route');
  if (routePath == null) {
    stderr.writeln('Usage: dart run bin/replay.dart --route route.json [--gpx ride.gpx] [--mode distance]');
    exit(64);
  }
  final route = parseOrsGeoJson(
      jsonDecode(File(routePath).readAsStringSync()) as Map<String, dynamic>);
  final mode = TriggerMode.values.byName(opt('mode') ?? 'distance');
  if (mode == TriggerMode.junction) await addJunctions(route);

  final gpx = opt('gpx');
  final fixes = gpx != null
      ? parseGpx(File(gpx).readAsStringSync())
      : simulateRide(route.line.points,
          noiseM: double.parse(opt('noise') ?? '5'));

  print('Route: ${route.distanceM.round()} m, ${route.manoeuvres.length} manoeuvres');
  for (final m in route.manoeuvres) {
    print('  $m${m.junctionAlongM != null ? ' (last junction at ${m.junctionAlongM!.round()} m)' : ''}');
  }
  print('Replaying ${fixes.length} fixes, mode ${mode.name}:');

  final engine = NavigationEngine(route, config: NavConfig(mode: mode));
  final start = fixes.first.time;
  String? lastShown;
  for (final fix in fixes) {
    final state = engine.update(fix.position, accuracyM: fix.accuracyM);
    final shown = '${state.symbols}${state.offRoute}${state.next?.alongM}';
    if (shown != lastShown) {
      final t = fix.time.difference(start).inSeconds;
      print('  t=${t.toString().padLeft(4)} s  at ${state.alongM.round().toString().padLeft(5)} m  $state');
      lastShown = shown;
    }
    if (state.arrived) break;
  }
}
