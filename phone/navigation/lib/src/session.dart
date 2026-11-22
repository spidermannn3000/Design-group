import 'geo.dart';
import 'engine.dart';
import 'route.dart';
import 'symbols.dart';

/// One ride to a destination: requests the route, runs the engine and
/// reroutes automatically when the rider goes off-route (task N5).
class NavigationSession {
  final RouteProvider routeProvider;
  final LatLng destination;
  final NavConfig config;

  /// Minimum time between reroute requests, to protect the API quota when
  /// the rider is wandering (e.g. walking the bike through a park).
  final Duration rerouteCooldown;

  /// Optional hook to attach junctions (N4) to each new route.
  final Future<void> Function(NavRoute route)? prepareRoute;

  NavigationEngine? _engine;
  DateTime? _lastRerouteAt;
  int rerouteCount = 0;

  NavigationSession({
    required this.routeProvider,
    required this.destination,
    this.config = const NavConfig(),
    this.rerouteCooldown = const Duration(seconds: 15),
    this.prepareRoute,
  });

  NavRoute? get route => _engine?.route;

  Future<void> start(LatLng from) => _loadRoute(from);

  /// Call for every GPS fix. [at] defaults to now; tests and the replay tool
  /// pass the recorded time.
  Future<NavState> onPosition(LatLng position, {double accuracyM = 0, DateTime? at}) async {
    final engine = _engine;
    if (engine == null) throw StateError('Call start() first');
    final state = engine.update(position, accuracyM: accuracyM);
    if (!state.offRoute) return state;

    final now = at ?? DateTime.now();
    final last = _lastRerouteAt;
    if (last != null && now.difference(last) < rerouteCooldown) return state;
    _lastRerouteAt = now;

    try {
      await _loadRoute(position);
      rerouteCount++;
      return _engine!.update(position, accuracyM: accuracyM);
    } catch (_) {
      // No signal or API error: keep showing "rerouting" and retry after the
      // cooldown, rather than crashing mid-ride.
      return state;
    }
  }

  Future<void> _loadRoute(LatLng from) async {
    final route = await routeProvider(from, destination);
    await prepareRoute?.call(route);
    _engine = NavigationEngine(route, config: config);
  }
}

/// Convenience for the BLE layer (P5): the symbol to show when a navigation
/// state is unavailable.
const int idleSymbol = LedSymbol.blank;
