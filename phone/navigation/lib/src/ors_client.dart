import 'dart:convert';

import 'package:http/http.dart' as http;

import 'geo.dart';
import 'route.dart';

/// OpenRouteService directions client (provider chosen in N1, see
/// docs/navigation.md).
///
/// The API key must not be committed: pass it in from a build-time define,
/// e.g. `flutter run --dart-define=ORS_API_KEY=...`, read with
/// `const String.fromEnvironment('ORS_API_KEY')`.
class OrsClient {
  final String apiKey;
  final String profile;
  final http.Client _http;

  OrsClient({required this.apiKey, this.profile = 'cycling-regular', http.Client? client})
      : _http = client ?? http.Client();

  /// Requests a cycling route. Usable directly as a [RouteProvider].
  Future<NavRoute> route(LatLng from, LatLng to) async {
    final uri = Uri.parse('https://api.openrouteservice.org/v2/directions/$profile/geojson');
    final res = await _http.post(
      uri,
      headers: {
        'Authorization': apiKey,
        'Content-Type': 'application/json',
        'Accept': 'application/geo+json, application/json',
      },
      body: jsonEncode({
        'coordinates': [
          [from.lng, from.lat],
          [to.lng, to.lat],
        ],
        'instructions': true,
        'language': 'en',
        'units': 'm',
      }),
    );
    if (res.statusCode != 200) {
      throw OrsException(res.statusCode, res.body);
    }
    return parseOrsGeoJson(jsonDecode(res.body) as Map<String, dynamic>);
  }
}

class OrsException implements Exception {
  final int statusCode;
  final String body;
  OrsException(this.statusCode, this.body);
  @override
  String toString() => 'OpenRouteService error $statusCode: $body';
}

/// ORS step "type" codes -> our manoeuvre kinds. Null means the step is not
/// shown to the rider (depart, and the separate "exit roundabout" step,
/// because the exit number is already on the "enter roundabout" step).
ManoeuvreKind? orsKind(int type) => switch (type) {
      0 => ManoeuvreKind.left,
      1 => ManoeuvreKind.right,
      2 => ManoeuvreKind.sharpLeft,
      3 => ManoeuvreKind.sharpRight,
      4 => ManoeuvreKind.slightLeft,
      5 => ManoeuvreKind.slightRight,
      6 => ManoeuvreKind.straight,
      7 => ManoeuvreKind.roundabout,
      8 => null, // exit roundabout
      9 => ManoeuvreKind.uTurn,
      10 => ManoeuvreKind.arrive,
      11 => null, // depart
      12 => ManoeuvreKind.slightLeft, // keep left
      13 => ManoeuvreKind.slightRight, // keep right
      _ => null,
    };

/// Parses a response from `/v2/directions/{profile}/geojson`.
NavRoute parseOrsGeoJson(Map<String, dynamic> json) {
  final feature = (json['features'] as List).first as Map<String, dynamic>;
  final coords = (feature['geometry']['coordinates'] as List)
      .map((c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()))
      .toList();
  final line = Polyline(coords);
  final props = feature['properties'] as Map<String, dynamic>;

  final manoeuvres = <Manoeuvre>[];
  for (final segment in props['segments'] as List) {
    for (final step in (segment['steps'] as List? ?? const [])) {
      final kind = orsKind((step['type'] as num).toInt());
      if (kind == null) continue;
      final index = ((step['way_points'] as List).first as num).toInt();
      manoeuvres.add(Manoeuvre(
        kind: kind,
        exitNumber: (step['exit_number'] as num?)?.toInt(),
        instruction: step['instruction'] as String? ?? '',
        pointIndex: index,
        alongM: line.cumulativeM[index],
      ));
    }
  }
  final duration = (props['summary']?['duration'] as num?)?.toDouble() ?? 0;
  return NavRoute(line, manoeuvres, durationS: duration);
}
