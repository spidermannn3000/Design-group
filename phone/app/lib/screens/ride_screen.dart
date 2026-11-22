import 'dart:async';

import 'package:bike_navigation/bike_navigation.dart';
import 'package:material_ui/material_ui.dart';

import '../config.dart';
import '../services/front_module.dart';
import '../services/location.dart';
import '../widgets/oled_display.dart';
import '../widgets/route_map.dart';

/// The ride screen: runs navigation from GPS (or a simulated ride), shows
/// what the handlebar matrix shows, and sends it to the front module.
class RideScreen extends StatefulWidget {
  final LatLng start;
  final LatLng destination;
  final String destinationLabel;
  final NavConfig config;
  final RouteProvider routeProvider;
  final Future<void> Function(NavRoute route)? prepareRoute;
  final FrontModule frontModule;

  /// Ride along the route automatically instead of using GPS.
  final bool simulate;
  final Duration simulationInterval;

  /// GPS source; replaced in tests.
  final Stream<Fix> Function() gps;

  /// The Google map needs a device, so tests turn it off.
  final bool showMap;

  const RideScreen({
    super.key,
    required this.start,
    required this.destination,
    required this.destinationLabel,
    required this.routeProvider,
    required this.frontModule,
    this.config = const NavConfig(),
    this.prepareRoute,
    this.simulate = false,
    this.simulationInterval = const Duration(milliseconds: 1000 ~/ simulationSpeedUp),
    this.gps = gpsFixes,
    this.showMap = true,
  });

  @override
  State<RideScreen> createState() => _RideScreenState();
}

class _RideScreenState extends State<RideScreen> {
  late final NavigationSession _session;
  StreamSubscription<NavState>? _sub;
  NavState? _state;
  LatLng? _rider;
  Object? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _session = NavigationSession(
      routeProvider: widget.routeProvider,
      destination: widget.destination,
      config: widget.config,
      prepareRoute: widget.prepareRoute,
    );
    _start();
  }

  Future<void> _start() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await _session.start(widget.start);
    } catch (e) {
      if (mounted) setState(() => _error = e);
      return;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
    final fixes = widget.simulate ? _simulated(_session.route!) : widget.gps();
    _sub = fixes.asyncMap((f) async {
      _rider = f.position;
      return _session.onPosition(f.position, accuracyM: f.accuracyM, at: f.time);
    }).listen(_onState);
  }

  Stream<Fix> _simulated(NavRoute route) async* {
    for (final fix in simulateRide(route.line.points, noiseM: 5)) {
      await Future<void>.delayed(widget.simulationInterval);
      yield fix;
    }
  }

  void _onState(NavState s) {
    if (!mounted) return;
    setState(() => _state = s);
    widget.frontModule.showNavigation(s);
    if (s.arrived) _sub?.cancel();
  }

  @override
  void dispose() {
    _sub?.cancel();
    widget.frontModule.showNavigation(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = _state;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.destinationLabel, overflow: TextOverflow.ellipsis),
        actions: [
          if (widget.simulate)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: Chip(label: Text('Simulated')),
            ),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            color: theme.colorScheme.surfaceContainerHighest,
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: OledDisplay(state: s, width: 256),
                  ),
                ),
                const SizedBox(height: 12),
                _instruction(theme, s),
              ],
            ),
          ),
          if (s != null && s.offRoute)
            MaterialBanner(
              content: const Text('Off route, finding a new route…'),
              leading: const Icon(Icons.alt_route),
              actions: const [SizedBox.shrink()],
            ),
          Expanded(
            child: widget.showMap
                ? RouteMap(
                    center: widget.start,
                    route: _session.route,
                    destination: widget.destination,
                    rider: _rider,
                    follow: true,
                  )
                : const SizedBox.expand(),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      switch (_session.rerouteCount) {
                        0 => '',
                        1 => 'Rerouted once',
                        final n => 'Rerouted $n times',
                      },
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.stop),
                    label: Text(s?.arrived ?? false ? 'Done' : 'End ride'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _instruction(ThemeData theme, NavState? s) {
    if (_error != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Couldn't get a route", style: theme.textTheme.titleMedium),
          Text('$_error', maxLines: 3, overflow: TextOverflow.ellipsis),
          TextButton(onPressed: _start, child: const Text('Try again')),
        ],
      );
    }
    if (_loading || s == null) {
      return Text(_loading ? 'Getting route…' : 'Waiting for GPS…',
          style: theme.textTheme.titleMedium);
    }
    if (s.arrived) {
      return Text('You have arrived', style: theme.textTheme.headlineSmall);
    }
    final next = s.next!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(next.instruction, style: theme.textTheme.titleMedium, maxLines: 2),
        if (s.then != null)
          Text('then ${s.then!.instruction}', style: theme.textTheme.bodyMedium, maxLines: 1),
      ],
    );
  }
}
