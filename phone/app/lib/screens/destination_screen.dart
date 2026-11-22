import 'dart:async';

import 'package:bike_navigation/bike_navigation.dart';
import 'package:material_ui/material_ui.dart';

import '../config.dart';
import '../services/front_module.dart';
import '../services/location.dart';
import '../services/place_search.dart';
import '../widgets/route_map.dart';
import 'ride_screen.dart';

/// Destination entry (P3): search for a place or long-press the map, preview
/// the cycling route and start the ride.
class DestinationScreen extends StatefulWidget {
  final FrontModule frontModule;
  const DestinationScreen({super.key, required this.frontModule});

  @override
  State<DestinationScreen> createState() => _DestinationScreenState();
}

class _DestinationScreenState extends State<DestinationScreen> {
  final _ors = OrsClient(apiKey: orsApiKey);
  final _places = PlaceSearch(orsApiKey);
  final _query = TextEditingController();
  Timer? _debounce;

  LatLng _here = trinityCollege;
  bool _haveGps = false;
  List<Place> _results = const [];
  Place? _destination;
  NavRoute? _preview;
  bool _loadingRoute = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _locate();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  Future<void> _locate() async {
    try {
      final p = await currentLocation();
      if (!mounted) return;
      setState(() {
        if (p != null) _here = p;
        _haveGps = p != null;
        if (p == null) {
          _message = 'Location is off or not allowed. Starting from Trinity College.';
        }
      });
    } catch (_) {}
  }

  void _onQuery(String text) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () async {
      try {
        final r = await _places.search(text, near: _here);
        if (mounted) setState(() => _results = r);
      } catch (e) {
        if (mounted) setState(() => _message = 'Search failed: $e');
      }
    });
  }

  Future<void> _choose(Place place) async {
    FocusScope.of(context).unfocus();
    setState(() {
      _destination = place;
      _results = const [];
      _query.text = place.label;
      _preview = null;
      _loadingRoute = true;
      _message = null;
    });
    try {
      final r = await _ors.route(_here, place.position);
      if (mounted) setState(() => _preview = r);
    } catch (e) {
      if (mounted) setState(() => _message = 'No route: $e');
    } finally {
      if (mounted) setState(() => _loadingRoute = false);
    }
  }

  void _ride({required bool simulate}) {
    final dest = _destination!;
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => RideScreen(
        start: _here,
        destination: dest.position,
        destinationLabel: dest.label,
        // Always show the next turn and how far away it is.
        config: const NavConfig(mode: TriggerMode.always),
        routeProvider: _ors.route,
        frontModule: widget.frontModule,
        simulate: simulate,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: RouteMap(
              center: _here,
              route: _preview,
              destination: _destination?.position,
              onLongPress: (p) => _choose(Place('Dropped pin', p)),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  if (orsApiKey.isEmpty)
                    const Card(
                      child: ListTile(
                        leading: Icon(Icons.key_off),
                        title: Text('No OpenRouteService key'),
                        subtitle: Text('Run with --dart-define=ORS_API_KEY=your_key'),
                      ),
                    ),
                  Card(
                    child: Column(
                      children: [
                        TextField(
                          controller: _query,
                          onChanged: _onQuery,
                          textInputAction: TextInputAction.search,
                          decoration: InputDecoration(
                            hintText: 'Where to?',
                            prefixIcon: const Icon(Icons.search),
                            border: InputBorder.none,
                            suffixIcon: Icon(_haveGps ? Icons.gps_fixed : Icons.gps_off),
                          ),
                        ),
                        for (final p in _results.take(5))
                          ListTile(
                            dense: true,
                            leading: const Icon(Icons.place_outlined),
                            title: Text(p.label),
                            onTap: () => _choose(p),
                          ),
                      ],
                    ),
                  ),
                  if (_message != null)
                    Card(
                      child: ListTile(dense: true, title: Text(_message!)),
                    ),
                ],
              ),
            ),
          ),
          if (_destination != null)
            Align(
              alignment: Alignment.bottomCenter,
              child: SafeArea(
                child: Card(
                  margin: const EdgeInsets.all(12),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          _loadingRoute
                              ? 'Finding a cycling route…'
                              : _preview == null
                                  ? 'No route yet'
                                  : '${(_preview!.distanceM / 1000).toStringAsFixed(1)} km · '
                                      '${(_preview!.durationS / 60).round()} min · '
                                      '${_preview!.manoeuvres.length} turns',
                          style: theme.textTheme.titleMedium,
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _preview == null ? null : () => _ride(simulate: true),
                                icon: const Icon(Icons.play_circle_outline),
                                label: const Text('Simulate'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: _preview == null ? null : () => _ride(simulate: false),
                                icon: const Icon(Icons.directions_bike),
                                label: const Text('Start ride'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
