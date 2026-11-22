import 'dart:convert';

import 'package:bike_navigation/bike_navigation.dart';
import 'package:http/http.dart' as http;

class Place {
  final String label;
  final LatLng position;
  const Place(this.label, this.position);
}

/// Destination search (P3) using OpenRouteService's place search, so the app
/// needs only one key for search and routing. Results are limited to Ireland
/// and ranked by closeness to the rider.
class PlaceSearch {
  final String apiKey;
  final http.Client _http;

  PlaceSearch(this.apiKey, {http.Client? client}) : _http = client ?? http.Client();

  Future<List<Place>> search(String text, {LatLng? near}) async {
    if (text.trim().length < 3) return const [];
    final uri = Uri.https('api.openrouteservice.org', '/geocode/autocomplete', {
      'api_key': apiKey,
      'text': text,
      'boundary.country': 'IE',
      if (near != null) 'focus.point.lat': '${near.lat}',
      if (near != null) 'focus.point.lon': '${near.lng}',
    });
    final res = await _http.get(uri).timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) {
      throw Exception('Place search failed (${res.statusCode})');
    }
    return parsePlaces(jsonDecode(res.body) as Map<String, dynamic>);
  }
}

List<Place> parsePlaces(Map<String, dynamic> json) => [
      for (final f in json['features'] as List? ?? const [])
        Place(
          f['properties']['label'] as String,
          LatLng((f['geometry']['coordinates'][1] as num).toDouble(),
              (f['geometry']['coordinates'][0] as num).toDouble()),
        ),
    ];
