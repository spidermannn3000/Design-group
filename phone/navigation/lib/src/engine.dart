import 'dart:math' as math;

import 'geo.dart';
import 'route.dart';
import 'symbols.dart';

/// When to show the next turn on the LED matrix.
enum TriggerMode {
  /// Level 1 (N2): always show the next manoeuvre.
  always,

  /// Level 2 (N3): show it once the rider is within [NavConfig.triggerDistanceM].
  distance,

  /// Level 3 (N4): show it once the rider passes the last junction before the
  /// turn. Falls back to [distance] when no junction is known.
  junction,
}

class NavConfig {
  final TriggerMode mode;

  /// Level 2 trigger distance, measured along the route.
  final double triggerDistanceM;

  /// Phone GPS error allowance (5-10 m). Turns are shown this much earlier
  /// so GPS error makes them early rather than late.
  final double gpsMarginM;

  /// How far past a manoeuvre the rider must be before moving on to the next
  /// one, so GPS jitter near the junction does not skip it early.
  final double passMarginM;

  /// Distance from the route that counts as off-route (N5), on top of the
  /// fix's reported accuracy (capped at 20 m).
  final double offRouteM;

  /// Consecutive off-route fixes needed before declaring off-route.
  final int offRouteFixes;

  /// Level 3: show the turn this far before reaching the junction itself.
  final double junctionLeadM;

  /// How far ahead along the route to search when snapping a fix. Stops the
  /// rider being snapped onto a later part of the route that passes nearby.
  final double searchAheadM;

  const NavConfig({
    this.mode = TriggerMode.distance,
    this.triggerDistanceM = 100,
    this.gpsMarginM = 10,
    this.passMarginM = 10,
    this.offRouteM = 30,
    this.offRouteFixes = 3,
    this.junctionLeadM = 5,
    this.searchAheadM = 400,
  });
}

/// What the phone should do after one GPS fix.
class NavState {
  /// The manoeuvre coming up, or null once arrived.
  final Manoeuvre? next;

  /// Distance along the route to [next] (metres, never negative).
  final double distanceToNextM;

  /// Whether the turn is shown yet (false = show "straight" for now).
  final bool showTurn;

  /// LED symbol IDs to send to the front module, in display order.
  final List<int> symbols;

  final bool offRoute;
  final bool arrived;

  /// Rider's progress along the route and distance from it (metres).
  final double alongM;
  final double offsetM;

  const NavState({
    required this.next,
    required this.distanceToNextM,
    required this.showTurn,
    required this.symbols,
    required this.offRoute,
    required this.arrived,
    required this.alongM,
    required this.offsetM,
  });

  @override
  String toString() => arrived
      ? 'ARRIVED'
      : offRoute
          ? 'OFF ROUTE (${offsetM.round()} m away)'
          : '${showTurn ? next!.kind.name.toUpperCase() : 'straight'}'
              '${next?.exitNumber != null && showTurn ? ' exit ${next!.exitNumber}' : ''}'
              ' - ${next?.kind.name} in ${distanceToNextM.round()} m, symbols $symbols';
}

/// Turns GPS fixes into the next manoeuvre and LED symbols (N2, N3, N4, and
/// off-route detection for N5). Create a new engine for each new route.
class NavigationEngine {
  final NavRoute route;
  final NavConfig config;

  int _nextIndex = 0;
  int _segment = 0;
  bool _locked = false;
  double _alongM = 0;
  int _offRouteCount = 0;
  bool _shown = false;
  bool _arrived = false;

  NavigationEngine(this.route, {this.config = const NavConfig()});

  Manoeuvre? get nextManoeuvre =>
      _nextIndex < route.manoeuvres.length ? route.manoeuvres[_nextIndex] : null;

  NavState update(LatLng position, {double accuracyM = 0}) {
    final line = route.line;
    final threshold = config.offRouteM + math.min(accuracyM, 20);

    // Snap near where the rider was last; if that fails (e.g. after a GPS
    // jump or a shortcut), try the whole route before calling it off-route.
    var p = _locked
        ? line.project(position,
            fromSegment: math.max(0, _segment - 2),
            toSegment: line.segmentAhead(_segment, config.searchAheadM))
        : line.project(position);
    if (p.offsetM > threshold && _locked) {
      final global = line.project(position);
      if (global.offsetM <= threshold) p = global;
    }

    if (p.offsetM > threshold) {
      _offRouteCount++;
    } else {
      _offRouteCount = 0;
      _locked = true;
      _segment = p.segment;
      _alongM = p.alongM;
    }
    final offRoute = _offRouteCount >= config.offRouteFixes;

    // Move past manoeuvres the rider has completed.
    while (_nextIndex < route.manoeuvres.length) {
      final m = route.manoeuvres[_nextIndex];
      if (m.kind == ManoeuvreKind.arrive) break;
      if (_alongM < m.alongM + config.passMarginM) break;
      _nextIndex++;
      _shown = false;
    }

    final next = nextManoeuvre;
    final distance = next == null ? 0.0 : math.max(0.0, next.alongM - _alongM);
    if (next != null &&
        next.kind == ManoeuvreKind.arrive &&
        distance <= config.gpsMarginM * 2) {
      _arrived = true;
    }

    if (next != null && !_shown) _shown = _shouldShow(next, distance);

    final List<int> symbols;
    if (_arrived) {
      symbols = const [LedSymbol.arrive];
    } else if (offRoute) {
      symbols = const [LedSymbol.rerouting];
    } else if (next != null && _shown) {
      symbols = displaySequence(next);
    } else {
      symbols = const [LedSymbol.straight];
    }

    return NavState(
      next: _arrived ? null : next,
      distanceToNextM: distance,
      showTurn: _shown && !_arrived,
      symbols: symbols,
      offRoute: offRoute && !_arrived,
      arrived: _arrived,
      alongM: _alongM,
      offsetM: p.offsetM,
    );
  }

  bool _shouldShow(Manoeuvre m, double distance) {
    final byDistance = distance <= config.triggerDistanceM + config.gpsMarginM;
    switch (config.mode) {
      case TriggerMode.always:
        return true;
      case TriggerMode.distance:
        return byDistance;
      case TriggerMode.junction:
        final j = m.junctionAlongM;
        if (j == null) return byDistance;
        return _alongM >= j - config.junctionLeadM - config.gpsMarginM;
    }
  }
}
