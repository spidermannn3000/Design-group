import 'dart:math' as math;

import 'geo.dart';

/// One GPS fix in a recorded or simulated track (task N7).
class Fix {
  final LatLng position;
  final DateTime time;
  final double accuracyM;
  const Fix(this.position, this.time, {this.accuracyM = 5});
}

/// Reads track points from a GPX file (e.g. exported from Strava, Komoot or
/// any GPS logger app).
List<Fix> parseGpx(String gpx) {
  final pointRe = RegExp(r'<trkpt\b([^>]*)>(.*?)</trkpt>', dotAll: true);
  final latRe = RegExp(r'''lat\s*=\s*["']([-\d.]+)["']''');
  final lonRe = RegExp(r'''lon\s*=\s*["']([-\d.]+)["']''');
  final timeRe = RegExp(r'<time>([^<]+)</time>');
  final start = DateTime.utc(2000);
  final fixes = <Fix>[];
  for (final m in pointRe.allMatches(gpx)) {
    final attrs = m.group(1)!;
    final lat = double.parse(latRe.firstMatch(attrs)!.group(1)!);
    final lon = double.parse(lonRe.firstMatch(attrs)!.group(1)!);
    final t = timeRe.firstMatch(m.group(2)!)?.group(1);
    final time = t != null
        ? DateTime.parse(t)
        : start.add(Duration(seconds: fixes.length));
    fixes.add(Fix(LatLng(lat, lon), time));
  }
  return fixes;
}

/// Simulates riding along [path] at [speedMps] with GPS noise of about
/// [noiseM] metres, so navigation can be tested without riding.
List<Fix> simulateRide(
  List<LatLng> path, {
  double speedMps = 5, // about 18 km/h
  Duration interval = const Duration(seconds: 1),
  double noiseM = 5,
  int seed = 1,
}) {
  final random = math.Random(seed);
  double gaussian() {
    final u1 = 1 - random.nextDouble();
    final u2 = random.nextDouble();
    return math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * u2);
  }

  final step = speedMps * interval.inMilliseconds / 1000;
  final fixes = <Fix>[];
  var time = DateTime.utc(2026, 1, 1, 9);
  var carried = 0.0; // distance already covered into the current segment
  for (var i = 0; i < path.length - 1; i++) {
    final a = path[i], b = path[i + 1];
    final segLen = haversineM(a, b);
    var d = carried;
    while (d < segLen) {
      final t = d / segLen;
      final p = LatLng(a.lat + (b.lat - a.lat) * t, a.lng + (b.lng - a.lng) * t);
      fixes.add(Fix(
        offsetM(p, northM: gaussian() * noiseM, eastM: gaussian() * noiseM),
        time,
        accuracyM: noiseM,
      ));
      time = time.add(interval);
      d += step;
    }
    carried = d - segLen;
  }
  fixes.add(Fix(path.last, time, accuracyM: noiseM));
  return fixes;
}
