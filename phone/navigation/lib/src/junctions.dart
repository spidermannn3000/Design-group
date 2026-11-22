import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;

import 'geo.dart';
import 'route.dart';

/// Junction positions for Level 3 (task N4).
///
/// Directions APIs only give the turns, not the side roads the rider passes
/// on the way. We get those from OpenStreetMap through the Overpass API: a
/// junction is any road node where three or more road arms meet.

/// Road types that count as a junction arm. Footways, driveways ("service")
/// and paths are left out so car-park entrances do not trigger the turn early.
const defaultJunctionRoadTypes = [
  'trunk', 'trunk_link', 'primary', 'primary_link', 'secondary',
  'secondary_link', 'tertiary', 'tertiary_link', 'unclassified',
  'residential', 'living_street', 'cycleway',
];

/// Overpass query for all roads in the route's bounding box.
String overpassQuery(Polyline line,
    {double paddingM = 50, List<String> roadTypes = defaultJunctionRoadTypes}) {
  var s = line.points.first.lat, n = s, w = line.points.first.lng, e = w;
  for (final p in line.points) {
    s = math.min(s, p.lat);
    n = math.max(n, p.lat);
    w = math.min(w, p.lng);
    e = math.max(e, p.lng);
  }
  final sw = offsetM(LatLng(s, w), northM: -paddingM, eastM: -paddingM);
  final ne = offsetM(LatLng(n, e), northM: paddingM, eastM: paddingM);
  return '[out:json][timeout:25];'
      'way["highway"~"^(${roadTypes.join('|')})\$"]'
      '(${sw.lat},${sw.lng},${ne.lat},${ne.lng});'
      'out body;>;out skel qt;';
}

/// Reads junction positions from an Overpass JSON response.
List<LatLng> junctionsFromOverpass(Map<String, dynamic> json) {
  final nodes = <int, LatLng>{};
  final degree = <int, int>{};
  for (final el in json['elements'] as List) {
    if (el['type'] == 'node') {
      nodes[el['id'] as int] =
          LatLng((el['lat'] as num).toDouble(), (el['lon'] as num).toDouble());
    } else if (el['type'] == 'way') {
      final ids = (el['nodes'] as List).cast<int>();
      for (var i = 0; i < ids.length; i++) {
        // Each node gets one arm towards the previous node and one towards the next.
        final arms = (i > 0 ? 1 : 0) + (i < ids.length - 1 ? 1 : 0);
        degree[ids[i]] = (degree[ids[i]] ?? 0) + arms;
      }
    }
  }
  return [
    for (final entry in degree.entries)
      if (entry.value >= 3 && nodes[entry.key] != null) nodes[entry.key]!,
  ];
}

Future<List<LatLng>> fetchJunctions(Polyline line,
    {http.Client? client,
    String endpoint = 'https://overpass-api.de/api/interpreter'}) async {
  final c = client ?? http.Client();
  final res = await c.post(Uri.parse(endpoint), body: {'data': overpassQuery(line)});
  if (res.statusCode != 200) {
    throw Exception('Overpass error ${res.statusCode}: ${res.body}');
  }
  return junctionsFromOverpass(jsonDecode(res.body) as Map<String, dynamic>);
}

/// Sets [Manoeuvre.junctionAlongM] on each manoeuvre to the last junction
/// on the route before it.
///
/// [maxOffsetM]: how close to the route line a junction must be.
/// [minGapM]: junctions this close to the turn are the turn itself, not the
/// one before it.
void attachJunctions(NavRoute route, List<LatLng> junctions,
    {double maxOffsetM = 15, double minGapM = 15}) {
  final along = <double>[];
  for (final j in junctions) {
    final p = route.line.project(j);
    if (p.offsetM <= maxOffsetM) along.add(p.alongM);
  }
  along.sort();

  var previousTurnM = 0.0;
  for (final m in route.manoeuvres) {
    double? last;
    for (final a in along) {
      if (a <= previousTurnM + minGapM) continue;
      if (a >= m.alongM - minGapM) break;
      last = a;
    }
    m.junctionAlongM = last;
    previousTurnM = m.alongM;
  }
}

/// Fetches and attaches junctions in one step. Pass as
/// [NavigationSession.prepareRoute]. Failure is not fatal: without junctions
/// Level 3 falls back to the Level 2 distance trigger.
Future<void> addJunctions(NavRoute route, {http.Client? client}) async {
  try {
    attachJunctions(route, await fetchJunctions(route.line, client: client));
  } catch (_) {}
}
