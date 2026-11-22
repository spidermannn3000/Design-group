import 'dart:math' as math;

/// A WGS84 coordinate in degrees.
class LatLng {
  final double lat;
  final double lng;
  const LatLng(this.lat, this.lng);

  @override
  String toString() => '(${lat.toStringAsFixed(6)}, ${lng.toStringAsFixed(6)})';
}

const double _earthRadiusM = 6371000.0;
double _rad(double deg) => deg * math.pi / 180.0;

/// Great-circle distance in metres.
double haversineM(LatLng a, LatLng b) {
  final dLat = _rad(b.lat - a.lat);
  final dLng = _rad(b.lng - a.lng);
  final h = math.pow(math.sin(dLat / 2), 2) +
      math.cos(_rad(a.lat)) * math.cos(_rad(b.lat)) * math.pow(math.sin(dLng / 2), 2);
  return 2 * _earthRadiusM * math.asin(math.min(1.0, math.sqrt(h)));
}

/// Moves [from] by [northM] and [eastM] metres. Used by tests and the simulator.
LatLng offsetM(LatLng from, {double northM = 0, double eastM = 0}) {
  final dLat = northM / _earthRadiusM;
  final dLng = eastM / (_earthRadiusM * math.cos(_rad(from.lat)));
  return LatLng(from.lat + dLat * 180 / math.pi, from.lng + dLng * 180 / math.pi);
}

/// Where a point lands when snapped onto a polyline.
class Projection {
  /// Index of the segment (points[segment] -> points[segment + 1]).
  final int segment;

  /// Distance from the start of the route, measured along the route (metres).
  final double alongM;

  /// Straight-line distance from the point to the route (metres).
  final double offsetM;

  /// The snapped point on the route.
  final LatLng snapped;

  const Projection(this.segment, this.alongM, this.offsetM, this.snapped);
}

/// A route line with cumulative distances, so "distance along the route"
/// (task N3) is a lookup rather than a straight-line guess.
class Polyline {
  final List<LatLng> points;
  late final List<double> cumulativeM;

  Polyline(this.points) {
    if (points.length < 2) {
      throw ArgumentError('A route needs at least two points');
    }
    final cum = <double>[0];
    for (var i = 1; i < points.length; i++) {
      cum.add(cum.last + haversineM(points[i - 1], points[i]));
    }
    cumulativeM = cum;
  }

  double get lengthM => cumulativeM.last;
  int get segmentCount => points.length - 1;

  /// Snaps [p] onto segments [fromSegment]..[toSegment] (inclusive) and
  /// returns the closest match.
  Projection project(LatLng p, {int fromSegment = 0, int? toSegment}) {
    final last = math.min(toSegment ?? segmentCount - 1, segmentCount - 1);
    final first = fromSegment.clamp(0, last);
    Projection? best;
    for (var i = first; i <= last; i++) {
      final candidate = _projectOnSegment(p, i);
      if (best == null || candidate.offsetM < best.offsetM) best = candidate;
    }
    return best!;
  }

  /// Index of the segment containing the point [alongM] metres from the
  /// start (the last segment if past the end).
  int segmentAtM(double alongM) {
    var lo = 0, hi = segmentCount - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) ~/ 2;
      if (cumulativeM[mid] <= alongM) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return lo;
  }

  Projection _projectOnSegment(LatLng p, int i) {
    final a = points[i];
    final b = points[i + 1];
    // Local flat-earth frame centred on a. Accurate to centimetres over the
    // short segment lengths a route polyline uses.
    final cosLat = math.cos(_rad(a.lat));
    double x(LatLng q) => _rad(q.lng - a.lng) * cosLat * _earthRadiusM;
    double y(LatLng q) => _rad(q.lat - a.lat) * _earthRadiusM;
    final bx = x(b), by = y(b), px = x(p), py = y(p);
    final len2 = bx * bx + by * by;
    var t = len2 == 0 ? 0.0 : (px * bx + py * by) / len2;
    t = t.clamp(0.0, 1.0);
    final sx = bx * t, sy = by * t;
    final offset = math.sqrt((px - sx) * (px - sx) + (py - sy) * (py - sy));
    final snapped = LatLng(a.lat + (b.lat - a.lat) * t, a.lng + (b.lng - a.lng) * t);
    final along = cumulativeM[i] + (cumulativeM[i + 1] - cumulativeM[i]) * t;
    return Projection(i, along, offset, snapped);
  }
}
